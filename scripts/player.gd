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
const ADS_ZOOM := 1.5                  ## Aiming down sights magnifies the view 1.5x.
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
var _lean_latch := 0            ## Toggle-lean state: -1 left, 0 upright, 1 right.
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
## The gun you're using: the primary when the rifle is drawn, otherwise the holster's.
var firearm: Firearm:
	get:
		return primary_fa if active_weapon == "rifle" and primary_fa else sidearm_fa
var sidearm_fa: Firearm               ## Holster.
var primary_fa: Firearm               ## Primary (long gun).
var firearms: Array[Firearm] = []
## First-person arms + gun of the current firearm.
var viewmodel: Viewmodel:
	get:
		return firearm.viewmodel if firearm else null
var knife: Knife
var vitals: Vitals
var hitboxes: Array[Hitbox] = []
var model: CharacterModel:     ## Same as `character` (Melee and others look for `model`).
	get:
		return character
var med_notice := ""
var med_notice_time := 0.0
signal player_died(cause: String)
var active_weapon := "pistol"   ## "rifle", "pistol", "knife" or "none"; Y switches, hold Y = fire selector.
var _knife_grip: Node3D
var _y_hold := -1.0
var _recoil_recover := 0.0  ## Degrees of muzzle climb still to settle.


func _ready() -> void:
	add_to_group("player")
	_build()
	_apply_view()


# ---------------------------------------------------------------- construction

func _build() -> void:
	collision_layer = 2  # characters; the world stays on layer 1
	collision_mask = 1 | 2 | 32   # world, people, doors
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
	# Starting kit: two spare magazines and some painkillers in your pants pockets,
	# an M4 on the sling (30 rounds of M193, one chambered).
	var pockets: Array = character.equipment.get_slot("legs").grids
	pockets[0].place(InvItem.magazine(AmmoDB.get_ammo("45_1_fmj230"), 7), Vector2i.ZERO)
	pockets[1].place(InvItem.magazine(AmmoDB.get_ammo("45_2_jhp230"), 7), Vector2i.ZERO)
	pockets[2].place(InvItem.create("painkillers"), Vector2i.ZERO)
	pockets[3].place(InvItem.create("ifak"), Vector2i.ZERO)
	# Weapons are items in their own slots: a stock 1911 (loaded, one chambered) and a Ka-Bar.
	character.equipment.arm(InvItem.pistol(AmmoDB.get_ammo("45_1_fmj230"), 7, true))
	character.equipment.arm(InvItem.create("kabar"))
	character.equipment.arm(InvItem.rifle(AmmoDB.get_ammo("556_1_m193"), 29, true))
	hitboxes = Npc.build_hitboxes(character, self)

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

	# One Firearm per gun slot. Each builds its first-person viewmodel (on the
	# first-person camera) and a third-person gun held out in front, following your aim.
	sidearm_fa = Firearm.new()
	sidearm_fa.name = "Sidearm"
	sidearm_fa.attach(self, "sidearm", "pistol", fp_camera, head)
	add_child(sidearm_fa)
	primary_fa = Firearm.new()
	primary_fa.name = "Primary"
	primary_fa.attach(self, "primary", "rifle", fp_camera, head)
	add_child(primary_fa)
	firearms = [primary_fa, sidearm_fa]

	knife = Knife.new()
	knife.player = self
	add_child(knife)
	_knife_grip = knife.build(fp_camera, head, Viewmodel.LAYER, PLAYER_MODEL_LAYER)
	sidearm_fa.bind(character.equipment.get_weapon("sidearm"))
	primary_fa.bind(character.equipment.get_weapon("primary"))
	character.equipment.weapon_changed.connect(_on_weapon_changed)
	_set_weapon(active_weapon)

	vitals = Vitals.new()
	vitals.player = self
	add_child(vitals)
	vitals.died.connect(_on_died)
	vitals.treated.connect(func(t): _med_note(t))


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := look_scale()
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
	elif event.is_action_pressed("crouch") and Settings.toggle_crouch:
		_set_crouch(not crouching)
	elif event.is_action_pressed("lean_left") and Settings.toggle_lean:
		_lean_latch = 0 if _lean_latch == -1 else -1
	elif event.is_action_pressed("lean_right") and Settings.toggle_lean:
		_lean_latch = 0 if _lean_latch == 1 else 1
	elif event.is_action_pressed("use_meds"):
		_med_note(vitals.use_meds())
	elif event.is_action_pressed("toggle_light"):
		_light_hold = 0.0
	elif event.is_action_pressed("interact"):
		var target := interact_target()
		if target and target.has_method("use"):
			target.use(self)


## Everything you carry: worn gear, what's in it, the pistol and the knife.
func carried_weight() -> float:
	var kg := character.equipment.total_weight()
	return kg


var _light_hold := -1.0


## Something went into or out of a weapon slot (inventory, pickup, swap).
func _on_weapon_changed(slot: String) -> void:
	var eq := character.equipment
	for fa in firearms:
		if fa.slot == slot and fa.gun != eq.get_weapon(slot):
			fa.bind(eq.get_weapon(slot))
	var avail := available_weapons()
	if active_weapon != "none" and not (active_weapon in avail):
		_set_weapon(avail[0] if not avail.is_empty() else "none")
	elif active_weapon == "none" and not avail.is_empty():
		_set_weapon(avail[0])


## Free to shoot/swing: not in a menu, not treating yourself, not dead.
func can_act() -> bool:
	return not ui_locked and vitals != null and vitals.using == "" and not vitals.dead


func hitbox_rids() -> Array[RID]:
	var out: Array[RID] = []
	for hb in hitboxes:
		out.append(hb.get_rid())
	return out


## Hit by a bullet or a blade (hitboxes on your body report here).
func take_hit(info: Dictionary) -> void:
	vitals.take_hit(info)
	# The hit jolts your view.
	var k := clampf(info.damage / 25.0, 0.3, 1.5)
	_turn(randf_range(-2.0, 2.0) * k, randf_range(1.0, 3.0) * k)


func _med_note(text: String) -> void:
	if text == "":
		return
	med_notice = text
	med_notice_time = 2.5


func _on_died(cause: String) -> void:
	ui_locked = true
	sprinting = false
	aiming = false
	for fa in firearms:
		fa.set_drawn(false)
	knife.view.visible = false
	character.start_ragdoll(Vector3.ZERO, Vector3.ZERO, "")
	view = View.THIRD
	pitch = -55.0
	_apply_view()
	player_died.emit(cause)


## Rifle -> pistol -> Ka-Bar (Y). Not mid-reload or mid-swing.
## What you can draw: "rifle" (something in the primary slot), "pistol" (holster),
## "knife" (sheath).
func available_weapons() -> Array[String]:
	var out: Array[String] = []
	var eq := character.equipment
	if eq.get_weapon("primary"):
		out.append("rifle")
	if eq.get_weapon("sidearm"):
		out.append("pistol")
	if eq.get_weapon("melee"):
		out.append("knife")
	return out


func switch_weapon(to := "") -> void:
	var avail := available_weapons()
	if to == "":
		if avail.is_empty():
			to = "none"
		else:
			var i := avail.find(active_weapon)
			to = avail[(i + 1) % avail.size()]
	elif to != "none" and not (to in avail):
		return
	if to == active_weapon or (firearm and firearm.reloading) or (knife and knife.busy() and knife.phase != Knife.Phase.DRAW):
		return
	_set_weapon(to)


func _set_weapon(to: String) -> void:
	active_weapon = to
	for fa in firearms:
		fa.set_drawn(fa.serves == to)
	if knife.active != (to == "knife"):
		knife.set_active(to == "knife")
	var fa := firearm
	if to == "none":
		character.pose_mode = CharacterModel.PoseMode.IDLE
	elif (to == "pistol" or to == "rifle") and fa and fa.tp_grips.size() == 3:
		character.pose_mode = CharacterModel.PoseMode.RIFLE if to == "rifle" else CharacterModel.PoseMode.PISTOL
		character.grip_point = fa.tp_grips[0]
		character.grip_right = fa.tp_grips[1]
		character.grip_left = fa.tp_grips[2]
	elif to != "knife":
		character.pose_mode = CharacterModel.PoseMode.IDLE
	else:
		character.pose_mode = CharacterModel.PoseMode.KNIFE
		character.grip_right = _knife_grip
	_apply_view()


## Nearest thing you can use with A (container or mirror), within reach in front of you.
func interact_target() -> Node3D:
	var best: Node3D = null
	var best_d := 2.2
	var fwd := -global_transform.basis.z
	for n in get_tree().get_nodes_in_group("interactable"):
		var node := n as Node3D
		var at: Vector3 = node.interact_point() if node.has_method("interact_point") else node.global_position
		var d := at - global_position
		d.y = 0.0
		var dist := d.length()
		if dist < best_d and (dist < 0.8 or d.normalized().dot(fwd) > 0.3):
			best = node
			best_d = dist
	return best


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


## Touch-screen look (TouchControls): drag in degrees, scaled like the stick.
func touch_look(drag_deg: Vector2) -> void:
	if ui_locked:
		return
	var s := look_scale()
	var inv := -1.0 if Settings.invert_look_y else 1.0
	_turn(-drag_deg.x * s, -drag_deg.y * s * inv)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	# Right-stick look with a squared response curve for fine aiming.
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.0:
		look = look.normalized() * pow(look.length(), 2.0)
		var speed := look_speed_deg * look_scale()
		var inv := -1.0 if Settings.invert_look_y else 1.0
		_turn(-look.x * speed * delta, -look.y * speed * delta * inv)

	# Pain makes it hard to hold your aim still.
	if vitals and vitals.felt_pain() > 0.2 and not vitals.dead:
		var p := vitals.felt_pain()
		_turn(sin(Time.get_ticks_msec() * 0.011) * p * 3.0 * delta, cos(Time.get_ticks_msec() * 0.007) * p * 2.0 * delta)
	med_notice_time = maxf(0.0, med_notice_time - delta)
	# D-pad down: tap = weapon light, hold = bullet paths + ballistics readout.
	if _light_hold >= 0.0:
		if Input.is_action_pressed("toggle_light"):
			_light_hold += delta
			if _light_hold >= 0.6:
				Ballistics.debug_enabled = not Ballistics.debug_enabled
				_light_hold = -1.0
		else:
			if (active_weapon == "pistol" or active_weapon == "rifle") and not ui_locked:
				if firearm.has_light():
					firearm.toggle_light()
				else:
					_med_note("No light on this gun")
			_light_hold = -1.0

	# Y: tap = next weapon (on release), hold = fire selector.
	if Input.is_action_just_pressed("switch_weapon") and not ui_locked:
		_y_hold = 0.0
	if _y_hold >= 0.0:
		if Input.is_action_pressed("switch_weapon"):
			_y_hold += delta
			if _y_hold >= 0.4:
				_y_hold = -1.0
				if (active_weapon == "rifle" or active_weapon == "pistol") and not ui_locked and firearm.toggle_mode() == "":
					switch_weapon()   # one-mode gun: holding Y just switches
		else:
			_y_hold = -1.0
			if not ui_locked:
				switch_weapon()

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

	# Lean: hold L1 / R1, or tap to toggle (Settings.toggle_lean).
	var lean_target := 0.0
	if Settings.toggle_lean:
		lean_target = float(_lean_latch)
	else:
		_lean_latch = 0
		if Input.is_action_pressed("lean_left") and not ui_locked:
			lean_target -= 1.0
		if Input.is_action_pressed("lean_right") and not ui_locked:
			lean_target += 1.0
	if sprinting:
		lean_target = 0.0
		_lean_latch = 0
	# Crouch: tap B to toggle, or hold it (Settings.toggle_crouch).
	if not Settings.toggle_crouch:
		var want := Input.is_action_pressed("crouch") and not ui_locked and not sprinting
		if want != crouching:
			_set_crouch(want)
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

	var gun_drawn := active_weapon == "pistol" or active_weapon == "rifle"
	var target_fov := ads_fov() if aiming and gun_drawn and firearm else Settings.fov
	fp_camera.fov = lerpf(fp_camera.fov, target_fov, minf(1.0, delta * 12.0))
	tp_camera.fov = Settings.fov


func _physics_process(delta: float) -> void:
	var input := _move_input()
	if input.length() < 0.1:
		sprinting = false

	var kg := carried_weight()
	if sprinting and (not Encumbrance.can_sprint(kg) or not vitals.can_sprint()):
		sprinting = false
	var speed := walk_speed
	if crouching:
		speed = crouch_speed
	elif sprinting and input.y < 0.0:  # sprint only while moving forward
		speed = sprint_speed
	elif aiming:
		speed = walk_speed * 0.6
	speed *= Encumbrance.speed_factor(kg) * vitals.speed_factor()
	if vitals.using != "":
		speed *= 0.5
	if vitals.dead:
		speed = 0.0

	var dir := (transform.basis * Vector3(input.x, 0.0, input.y))
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


# ---------------------------------------------------------------- state

## Look speed multiplier: the look sensitivity, times the aim sensitivity while aiming down sights.
func look_scale() -> float:
	return Settings.look_sensitivity * (Settings.aim_sensitivity if aiming else 1.0)


## Field of view aimed down sights: the normal view magnified ADS_ZOOM times
## (tan of the half-angle divided by 1.5, so things look 1.5x bigger).
func ads_fov() -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(Settings.fov) / 2.0) / ADS_ZOOM))


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
