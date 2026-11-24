class_name Knife
extends Node
## The player's Ka-Bar: draw, slash (R2, alternating forehand/backhand) and
## stab (hold L2 + R2). Each attack has a wind-up, a short window where the
## blade can connect, and a recovery. While the blade is moving, rays sweep the
## arc it covers (slash) or the line it drives along (stab); the first thing
## touched gets Melee.strike. Flesh hits leave blood on the blade.
##
## First person: the shared FP arms (left arm tucked away) holding the knife,
## posed procedurally per attack. Third person: a knife in the body's right hand.

enum Attack { NONE, SLASH_F, SLASH_B, STAB }
enum Phase { IDLE, WINDUP, STRIKE, RECOVER, DRAW }

## Seconds: wind-up, strike (blade live), recovery.
const TIMING := {
	Attack.SLASH_F: [0.09, 0.13, 0.26],
	Attack.SLASH_B: [0.09, 0.13, 0.26],
	Attack.STAB: [0.13, 0.09, 0.36],
}
const DRAW_TIME := 0.4
## FP arms space -> grip centre (where the hand closes on the handle).
const GRIP := Vector3(0.0, -0.063, 0.0565)
var base_pos := Vector3(0.16, -0.19, -0.30)
var base_rot := Vector3(-40.0, 20.0, -15.0)
## The arm swings from the shoulder (behind and below the camera, right side);
## the wrist turns the blade. Per attack: [start, end] of the strike, each
## [arm yaw deg (+ = to the left), arm pitch deg (+ = up), reach m (+ = out), wrist rotation deg].
const SHOULDER := Vector3(0.20, -0.30, 0.12)
const POSES := {
	Attack.SLASH_F: [[-30.0, 12.0, 0.04, Vector3(0.0, -20.0, 30.0)], [38.0, -10.0, 0.16, Vector3(5.0, 30.0, -40.0)]],
	Attack.SLASH_B: [[40.0, 8.0, 0.06, Vector3(0.0, 35.0, -45.0)], [-30.0, -10.0, 0.14, Vector3(0.0, -30.0, 35.0)]],
	Attack.STAB: [[3.0, 0.0, -0.08, Vector3(10.0, 0.0, 0.0)], [8.0, 3.0, 0.24, Vector3(-15.0, 0.0, 0.0)]],
}
const REST := [0.0, 0.0, 0.0, Vector3.ZERO]

var player: Player
var blade := BladeDef.kabar()
var view: Node3D               ## First-person rig (child of the FP camera).
var tp: Node3D                 ## Third-person knife (child of the head).
var active := false
var attack := Attack.NONE
var phase := Phase.IDLE
var blood := 0.0               ## 0 clean .. 1 dripping.
var last_hit: Dictionary = {}

var _t := 0.0
var _next_back := false
var _queued := Attack.NONE
var _connected := false
var _prev_dir := Vector3.ZERO
var _pivot: Node3D
var _tp_pivot: Node3D
var _blood_mats: Array[StandardMaterial3D] = []
var _audio: AudioStreamPlayer
var _streams := {}
var _rng := RandomNumberGenerator.new()
var _bob := 0.0


func _ready() -> void:
	_rng.randomize()
	for key in ["knife_swish", "knife_thrust", "knife_stab_flesh", "knife_slash_flesh", "knife_hit_hard", "knife_draw"]:
		var path := "res://assets/audio/%s.wav" % key
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	_audio = AudioStreamPlayer.new()
	_audio.max_polyphony = 3
	add_child(_audio)


## Build the FP rig under `camera` and the TP knife under `head`; returns the TP grip marker.
func build(camera: Node3D, head: Node3D, fp_layer: int, tp_layer: int) -> Node3D:
	view = Node3D.new()
	view.name = "KnifeView"
	camera.add_child(view)
	_pivot = Node3D.new()
	view.add_child(_pivot)
	var holder := Node3D.new()
	holder.position = -GRIP
	_pivot.add_child(holder)
	var arms: Node3D = (load("res://assets/viewmodels/arms/arms.glb") as PackedScene).instantiate()
	holder.add_child(arms)
	var knife: Node3D = (load(blade.scene_path) as PackedScene).instantiate()
	holder.add_child(knife)
	_pose_arms(arms)
	_set_layers(view, fp_layer)
	_add_blood_overlay(knife)
	view.visible = false

	_tp_pivot = Node3D.new()
	head.add_child(_tp_pivot)
	var tp_holder := Node3D.new()
	tp_holder.position = -GRIP
	_tp_pivot.add_child(tp_holder)
	tp = (load(blade.scene_path) as PackedScene).instantiate()
	tp_holder.add_child(tp)
	_set_layers(_tp_pivot, tp_layer)
	_add_blood_overlay(tp)
	_tp_pivot.visible = false
	var grip := Node3D.new()
	_tp_pivot.add_child(grip)       # at the pivot = the grip centre
	return grip


## Left arm out of view, right fingers closed round the handle.
func _pose_arms(arms: Node3D) -> void:
	var sk: Skeleton3D = arms.find_children("*", "Skeleton3D", true, false)[0]
	var fl := sk.find_bone("Forearm.L")
	if fl >= 0:
		sk.set_bone_pose_position(fl, sk.get_bone_rest(fl).origin + Vector3(0.0, -2.0, 1.0))
	for n in ["Index1.R", "Index2.R", "Index3.R"]:
		var b := sk.find_bone(n)
		if b >= 0:
			sk.set_bone_pose_rotation(b, sk.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, deg_to_rad(-28.0)))


func _set_layers(node: Node, layer: int) -> void:
	if node is GeometryInstance3D:
		node.layers = layer
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_set_layers(c, layer)


## A blood smear over the blade that fills in as it's used.
func _add_blood_overlay(knife: Node3D) -> void:
	var tex := _blood_texture()
	for mi: MeshInstance3D in knife.find_children("*", "MeshInstance3D", true, false):
		if not mi.name.begins_with("Blade"):
			continue
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.albedo_color = Color(0.45, 0.02, 0.02, 0.0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.25
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(18, 18, 18)
		mi.material_overlay = m
		_blood_mats.append(m)


func _blood_texture() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var v := clampf(0.55 + r.randf_range(-0.45, 0.45) + sin(x * 0.4 + y * 0.15) * 0.2, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	return ImageTexture.create_from_image(img)


func set_active(on: bool) -> void:
	active = on
	view.visible = on
	_tp_pivot.visible = on
	attack = Attack.NONE
	_queued = Attack.NONE
	if on:
		phase = Phase.DRAW
		_t = 0.0
		_play("knife_draw")
	else:
		phase = Phase.IDLE


func busy() -> bool:
	return phase != Phase.IDLE


func _process(delta: float) -> void:
	if not active:
		return
	if not player.ui_locked and Input.is_action_just_pressed("fire"):
		var want := Attack.STAB if Input.is_action_pressed("aim") else (Attack.SLASH_B if _next_back else Attack.SLASH_F)
		if phase == Phase.IDLE:
			_begin(want)
		elif phase == Phase.RECOVER and _t > TIMING[attack][2] * 0.4:
			_queued = want
	_advance(delta)
	_animate(delta)
	for m in _blood_mats:
		m.albedo_color.a = clampf(blood, 0.0, 1.0) * 0.9


func _physics_process(_delta: float) -> void:
	if active and phase == Phase.STRIKE and not _connected:
		_sweep()


func _begin(a: Attack) -> void:
	attack = a
	phase = Phase.WINDUP
	_t = 0.0
	_connected = false
	_prev_dir = Vector3.ZERO
	if a != Attack.STAB:
		_next_back = not _next_back
	player.sprinting = false


func _advance(delta: float) -> void:
	_t += delta
	match phase:
		Phase.DRAW:
			if _t >= DRAW_TIME:
				phase = Phase.IDLE
		Phase.WINDUP:
			if _t >= TIMING[attack][0]:
				phase = Phase.STRIKE
				_t = 0.0
				_play("knife_thrust" if attack == Attack.STAB else "knife_swish")
		Phase.STRIKE:
			if _t >= TIMING[attack][1]:
				phase = Phase.RECOVER
				_t = 0.0
		Phase.RECOVER:
			if _t >= TIMING[attack][2]:
				phase = Phase.IDLE
				var q := _queued
				_queued = Attack.NONE
				attack = Attack.NONE
				if q != Attack.NONE:
					_begin(q)


## 0..1 progress through the strike.
func _strike_k() -> float:
	return clampf(_t / TIMING[attack][1], 0.0, 1.0) if phase == Phase.STRIKE else 0.0


## Where the blade is aimed right now (world), for the hit sweep.
func blade_dir(k: float) -> Vector3:
	var cam := player.fp_camera.global_transform.basis
	var yaw := 0.0
	var pitch := 0.0
	match attack:
		Attack.SLASH_F:
			yaw = lerpf(45.0, -45.0, k)        # right to left across the body
			pitch = lerpf(12.0, -12.0, k)
		Attack.SLASH_B:
			yaw = lerpf(-45.0, 40.0, k)
			pitch = lerpf(8.0, -14.0, k)
		Attack.STAB:
			pitch = -2.0
	var d := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Vector3.FORWARD
	return (cam * d).normalized()


func _sweep() -> void:
	var from := player.fp_camera.global_position
	var k := _strike_k()
	var d := blade_dir(k)
	var reach := blade.reach if attack == Attack.STAB else blade.reach * 0.92
	var rays: Array = []
	if _prev_dir == Vector3.ZERO:
		_prev_dir = blade_dir(0.0)
	for i in 4:   # fill the arc swept since last frame
		var dd := _prev_dir.slerp(d, (i + 1) / 4.0)
		rays.append([from, from + dd * reach])
	if attack == Attack.STAB:
		var up := player.fp_camera.global_transform.basis.y * 0.035
		rays.append([from + up, from + up + d * reach])
		rays.append([from - up, from - up + d * reach])
	var travel := (d - _prev_dir).normalized() if attack != Attack.STAB else d
	_prev_dir = d
	var hit := Melee.sweep(player.get_world_3d().direct_space_state, rays, [player.get_rid()])
	if hit.is_empty():
		return
	_connected = true
	var kind := "stab" if attack == Attack.STAB else "slash"
	var cut := travel if kind == "slash" else player.fp_camera.global_transform.basis.y
	var strength := 0.9 if player.crouching else 1.0
	last_hit = Melee.strike(hit, kind, blade, strength, travel if kind == "slash" else d, cut, _rng)
	if last_hit.zone != "":
		blood = minf(1.0, blood + (0.45 if kind == "stab" else 0.25))
		_play("knife_stab_flesh" if kind == "stab" else "knife_slash_flesh")
	else:
		_play("knife_hit_hard")
		if phase == Phase.STRIKE:   # bounce off: cut the swing short
			phase = Phase.RECOVER
			_t = TIMING[attack][2] * 0.3


func _animate(delta: float) -> void:
	var from: Array = REST
	var to: Array = REST
	var k := 0.0
	match phase:
		Phase.DRAW:
			from = [-10.0, -40.0, -0.1, Vector3(30.0, 0.0, 20.0)]
			k = smoothstep(0.0, 1.0, _t / DRAW_TIME)
		Phase.WINDUP:
			to = POSES[attack][0]
			k = smoothstep(0.0, 1.0, _t / TIMING[attack][0])
		Phase.STRIKE:
			from = POSES[attack][0]
			to = POSES[attack][1]
			k = _ease_out(_strike_k())
		Phase.RECOVER:
			from = POSES[attack][1]
			k = smoothstep(0.0, 1.0, _t / TIMING[attack][2])
	var pose := _mix(from, to, k)
	# Idle bob, a guard stance while holding L2, knife low while sprinting.
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if player.is_on_floor() and speed > 0.3:
		_bob += delta * speed * 2.4
	var bob := Vector3(sin(_bob * 0.5) * 0.008, -absf(cos(_bob * 0.5)) * 0.007, 0.0) * clampf(speed / 3.2, 0.0, 1.5)
	if phase == Phase.IDLE:
		if player.aiming:
			pose = _mix(pose, [12.0, 6.0, 0.03, Vector3(-15.0, 0.0, 0.0)], 1.0)
		elif player.sprinting:
			pose = _mix(pose, [-10.0, -25.0, -0.05, Vector3(25.0, 0.0, 15.0)], 1.0)
	var t := _arm_transform(base_pos + bob, base_rot, pose, SHOULDER)
	_pivot.transform = _pivot.transform.interpolate_with(t, minf(1.0, delta * 25.0)) if phase == Phase.IDLE else t
	# Third person: the same swing from the body's shoulder.
	_tp_pivot.transform = _arm_transform(Vector3(0.22, -0.42, -0.36), base_rot, pose, Vector3(0.2, -0.25, 0.0))


static func _mix(a: Array, b: Array, k: float) -> Array:
	return [lerpf(a[0], b[0], k), lerpf(a[1], b[1], k), lerpf(a[2], b[2], k), (a[3] as Vector3).lerp(b[3], k)]


## Hand transform: base pose, wrist turned, reached out along the arm, then the arm swung about the shoulder.
static func _arm_transform(pos: Vector3, rot_deg: Vector3, pose: Array, shoulder: Vector3) -> Transform3D:
	var r := rot_deg * (PI / 180.0)
	var w: Vector3 = (pose[3] as Vector3) * (PI / 180.0)
	var t := Transform3D(Basis.from_euler(r) * Basis.from_euler(w), pos)
	t.origin += (pos - shoulder).normalized() * float(pose[2])
	var swing := Basis(Vector3.UP, deg_to_rad(pose[0])) * Basis(Vector3.RIGHT, deg_to_rad(pose[1]))
	return Transform3D(swing, shoulder) * Transform3D(Basis(), -shoulder) * t


static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 2.2)


func _play(key: String) -> void:
	if not _streams.has(key):
		return
	_audio.stream = _streams[key]
	_audio.pitch_scale = _rng.randf_range(0.94, 1.06)
	_audio.play()
