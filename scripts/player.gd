class_name Player
extends CharacterBody3D
## Player controller: movement, crouch, sprint, lean, aim, and first/third person.
## One character, two cameras. R3 swaps views; aiming (L2) always uses first person.

signal view_changed(view_name: String)

enum View { FIRST, THIRD }

@export var walk_speed := 3.2
@export var sprint_speed := 5.8
@export var crouch_speed := 1.6
@export var acceleration := 14.0
@export var look_speed_deg := 170.0   ## Degrees per second at full right-stick deflection.
@export var aim_look_scale := 0.45    ## Look speed multiplier while aiming.
@export var mouse_sensitivity := 0.12 ## Degrees per pixel (PC testing).
@export var fov_normal := 75.0
@export var fov_aim := 50.0

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_STAND := 1.62
const EYE_CROUCH := 0.95
const RADIUS := 0.32
const LEAN_OFFSET := 0.35     ## Metres the head shifts sideways at full lean.
const LEAN_ROLL_DEG := 14.0
const SHOULDER_OFFSET := 0.5
const SPRING_LENGTH := 2.3
const PLAYER_MODEL_LAYER := 2 ## Render layer 2 (bit value 2): hidden from the first-person camera.

var view: View = View.FIRST
var shoulder := 1.0          ## +1 = right shoulder, -1 = left.
var sprinting := false
var crouching := false
var aiming := false
var lean := 0.0
var pitch := 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _height := STAND_HEIGHT
var _bob_time := 0.0

var _shape: CapsuleShape3D
var _collision: CollisionShape3D
var _model: Node3D
var character: CharacterModel
var ui_locked := false        ## Gear menu open: no moving, shooting or view changes.
var preview := false          ## Camera turned around to look at yourself (gear menu).
var head: Node3D             ## Pitch + lean pivot at eye height.
var fp_camera: Camera3D
var _spring: SpringArm3D
var tp_camera: Camera3D
var viewmodel: Viewmodel
var firearm: Firearm
var _tp_weapon: Node3D
var _recoil_recover := 0.0  ## Degrees of muzzle climb still to settle.


func _ready() -> void:
	_build()
	_apply_view()


# ---------------------------------------------------------------- construction

func _build() -> void:
	collision_layer = 2  # characters; the world stays on layer 1
	collision_mask = 1
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = STAND_HEIGHT
	_collision = CollisionShape3D.new()
	_collision.shape = _shape
	_collision.position.y = STAND_HEIGHT / 2.0
	add_child(_collision)

	# Third-person body: the shared base body + gear, hidden from the first-person camera.
	_model = Node3D.new()
	add_child(_model)
	character = CharacterModel.new()
	_model.add_child(character)
	character.layers = PLAYER_MODEL_LAYER
	character.pose_mode = CharacterModel.PoseMode.PISTOL
	for id in ["tshirt", "pants", "boots", "gloves"]:
		var colour := {"tshirt": 3, "pants": 1, "boots": 0, "gloves": 0}[id] as int
		character.equipment.equip(GearInstance.create(id, colour))

	head = Node3D.new()
	head.position.y = EYE_STAND
	add_child(head)

	fp_camera = Camera3D.new()
	fp_camera.near = 0.05
	fp_camera.fov = fov_normal
	fp_camera.cull_mask = 0xFFFFF & ~PLAYER_MODEL_LAYER
	head.add_child(fp_camera)

	_spring = SpringArm3D.new()
	_spring.spring_length = SPRING_LENGTH
	_spring.margin = 0.15
	_spring.position = Vector3(SHOULDER_OFFSET * shoulder, 0.2, 0.0)
	_spring.add_excluded_object(get_rid())
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	_spring.shape = probe
	head.add_child(_spring)

	tp_camera = Camera3D.new()
	tp_camera.near = 0.05
	tp_camera.fov = fov_normal
	tp_camera.cull_mask = 0xFFFFF & ~Viewmodel.LAYER
	_spring.add_child(tp_camera)

	# First-person arms + gun on the first-person camera.
	viewmodel = Viewmodel.new()
	viewmodel.player = self
	fp_camera.add_child(viewmodel)

	# Third-person stand-in: the same pistol held out in front, following your aim.
	_tp_weapon = (load("res://assets/weapons/m1911/m1911.glb") as PackedScene).instantiate()
	_tp_weapon.position = Vector3(0.1, -0.3, -0.45)
	head.add_child(_tp_weapon)
	_set_layers(_tp_weapon, PLAYER_MODEL_LAYER)
	# Where the third-person body's hands go (pistol space: -Z forward).
	character.grip_point = _marker(_tp_weapon, Vector3(0.0, -0.064, 0.057))
	character.grip_right = _marker(_tp_weapon, Vector3(0.006, -0.085, 0.125))
	character.grip_left = _marker(_tp_weapon, Vector3(-0.035, -0.1, 0.105))

	firearm = Firearm.new()
	firearm.player = self
	add_child(firearm)
	firearm.register_weapon(viewmodel.weapon, Viewmodel.LAYER)
	firearm.register_weapon(_tp_weapon, PLAYER_MODEL_LAYER)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := (aim_look_scale if aiming else 1.0) * Settings.look_sensitivity
		var inv := -1.0 if Settings.invert_look_y else 1.0
		_turn(-event.relative.x * mouse_sensitivity * s, -event.relative.y * mouse_sensitivity * s * inv)
	elif event is InputEventMouseButton and event.pressed and OS.has_feature("pc"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if ui_locked:
		return
	if event.is_action_pressed("toggle_view"):
		view = View.THIRD if view == View.FIRST else View.FIRST
		_apply_view()
	elif event.is_action_pressed("sprint"):
		var moving := _move_input().length() > 0.2
		if view == View.THIRD and not moving:
			shoulder = -shoulder  # L3 while standing still in third person swaps shoulders
		else:
			sprinting = not sprinting
			if sprinting and crouching:
				_set_crouch(false)
	elif event.is_action_pressed("swap_shoulder"):
		shoulder = -shoulder
	elif event.is_action_pressed("crouch"):
		_set_crouch(not crouching)


func _move_input() -> Vector2:
	if ui_locked:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


## Muzzle climb from a shot; about half settles back on its own.
func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	_turn(yaw_deg, pitch_deg)
	_recoil_recover += pitch_deg * 0.5


func _turn(yaw_deg: float, pitch_deg: float) -> void:
	rotate_y(deg_to_rad(yaw_deg))
	pitch = clampf(pitch + pitch_deg, -85.0, 85.0)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	# Right-stick look with a squared response curve for fine aiming.
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.0:
		look = look.normalized() * pow(look.length(), 2.0)
		var speed := look_speed_deg * (aim_look_scale if aiming else 1.0) * Settings.look_sensitivity
		var inv := -1.0 if Settings.invert_look_y else 1.0
		_turn(-look.x * speed * delta, -look.y * speed * delta * inv)

	if _recoil_recover > 0.0:
		var settle := minf(_recoil_recover, delta * 14.0)
		pitch -= settle
		_recoil_recover -= settle

	var was_aiming := aiming
	aiming = Input.is_action_pressed("aim") and not ui_locked
	if aiming != was_aiming:
		if aiming:
			sprinting = false
		_apply_view()

	# Lean (hold L1 / R1).
	var lean_target := 0.0
	if Input.is_action_pressed("lean_left") and not ui_locked:
		lean_target -= 1.0
	if Input.is_action_pressed("lean_right") and not ui_locked:
		lean_target += 1.0
	if sprinting:
		lean_target = 0.0
	lean = move_toward(lean, lean_target, delta * 5.0)

	# Smooth crouch height and eye height.
	var target_eye := EYE_CROUCH if crouching else EYE_STAND
	var eye := lerpf(head.position.y, target_eye, minf(1.0, delta * 10.0))

	# Small head bob in first person while moving on the ground.
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var bob := Vector3.ZERO
	if is_on_floor() and flat_speed > 0.5:
		_bob_time += delta * flat_speed * 2.2
		bob = Vector3(cos(_bob_time * 0.5) * 0.025, absf(sin(_bob_time * 0.5)) * 0.035, 0.0)
	fp_camera.position = bob

	head.position = Vector3(lean * LEAN_OFFSET, eye, 0.0)
	head.rotation = Vector3(deg_to_rad(pitch), 0.0, deg_to_rad(-lean * LEAN_ROLL_DEG))
	# Preview (gear menu): swing the camera round to face the character.
	var spring_x := 0.0 if preview else SHOULDER_OFFSET * shoulder
	_spring.position.x = lerpf(_spring.position.x, spring_x, minf(1.0, delta * 8.0))
	_spring.rotation.y = lerp_angle(_spring.rotation.y, PI if preview else 0.0, minf(1.0, delta * 8.0))
	_spring.spring_length = lerpf(_spring.spring_length, 1.7 if preview else SPRING_LENGTH, minf(1.0, delta * 8.0))
	if preview:
		_spring.rotation.x = lerpf(_spring.rotation.x, deg_to_rad(pitch) + 0.12, minf(1.0, delta * 8.0))  # cancel head pitch: a level look at yourself
	else:
		_spring.rotation.x = lerpf(_spring.rotation.x, 0.0, minf(1.0, delta * 8.0))

	# Drive the third-person body.
	character.aim_pitch = deg_to_rad(pitch)
	character.move_speed = Vector2(velocity.x, velocity.z).length()
	character.crouch = move_toward(character.crouch, 1.0 if crouching else 0.0, delta * 5.0)

	var target_fov := fov_aim * Settings.fov / 75.0 if aiming else Settings.fov
	fp_camera.fov = lerpf(fp_camera.fov, target_fov, minf(1.0, delta * 12.0))
	tp_camera.fov = Settings.fov


func _physics_process(delta: float) -> void:
	var input := _move_input()
	if input.length() < 0.1:
		sprinting = false

	var speed := walk_speed
	if crouching:
		speed = crouch_speed
	elif sprinting and input.y < 0.0:  # sprint only while moving forward
		speed = sprint_speed
	elif aiming:
		speed = walk_speed * 0.6

	var dir := (transform.basis * Vector3(input.x, 0.0, input.y))
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


# ---------------------------------------------------------------- state

func _set_crouch(on: bool) -> void:
	if not on and _blocked_above():
		return  # stay crouched under low ceilings
	crouching = on
	if on:
		sprinting = false
	_height = CROUCH_HEIGHT if on else STAND_HEIGHT
	_shape.height = _height
	_collision.position.y = _height / 2.0


func _blocked_above() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * CROUCH_HEIGHT
	var to := global_position + Vector3.UP * (STAND_HEIGHT + 0.05)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


func _marker(parent: Node3D, pos: Vector3) -> Node3D:
	var m := Node3D.new()
	m.position = pos
	parent.add_child(m)
	return m


func _set_layers(node: Node, layer: int) -> void:
	for child in node.get_children():
		if child is VisualInstance3D:
			child.layers = layer
		_set_layers(child, layer)


func effective_view() -> View:
	if preview:
		return View.THIRD
	return View.FIRST if aiming else view


## Gear menu open/close: lock controls and turn the camera to face you.
func set_preview(on: bool) -> void:
	preview = on
	ui_locked = on
	if on:
		sprinting = false
		aiming = false
	_apply_view()


func view_name() -> String:
	return "First person" if effective_view() == View.FIRST else "Third person"


func _apply_view() -> void:
	var first := effective_view() == View.FIRST
	fp_camera.current = first
	tp_camera.current = not first
	view_changed.emit(view_name())
