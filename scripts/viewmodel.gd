class_name Viewmodel
extends Node3D
## First-person arms + weapon, parented to the first-person camera.
## Handles hip/aim/sprint poses, look sway, walk bob, and pulling the gun back
## when you stand close to a wall (so it never pokes through geometry).

const LAYER := 4                      ## Render layer 3: seen only by the first-person camera.
const HIP_POS := Vector3(0.072, -0.06, -0.215)
const HIP_ROT := Vector3(2.0, 4.0, -3.0)    ## Degrees: angled slightly toward the crosshair.
const AIM_POS := Vector3(0.0, -0.0202, -0.40)  ## Puts the sight line on the eye.
const SPRINT_POS := Vector3(0.05, -0.15, -0.21)
const SPRINT_ROT := Vector3(-38.0, 22.0, 12.0) ## Degrees: muzzle down and inward.
const WALL_CHECK := 0.6               ## Metres ahead of the eye to look for walls.

@export var weapon_scene: PackedScene = preload("res://assets/weapons/m1911/m1911.glb")
@export var arms_scene: PackedScene = preload("res://assets/viewmodels/arms/arms.glb")

var player: Player
var weapon: Node3D
var arms: Node3D

var _aim := 0.0
var _sprint := 0.0
var _wall := 0.0
var _sway_rot := Vector2.ZERO
var _last_yaw := 0.0
var _last_pitch := 0.0
var _bob_t := 0.0
var _kick := 0.0         ## Recoil impulse, decays quickly.
var _kick_vel := 0.0


func _ready() -> void:
	weapon = weapon_scene.instantiate()
	arms = arms_scene.instantiate()
	add_child(weapon)
	add_child(arms)
	_prepare(self)
	position = HIP_POS
	if player:
		_last_yaw = player.rotation.y
		_last_pitch = player.pitch


func _prepare(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			child.layers = LAYER
		_prepare(child)


func _process(delta: float) -> void:
	if player == null:
		return

	# Smoothly blend between poses.
	# Aim speed from the gun's ergonomics (grips, sights, a heavy can on the front).
	var st: Dictionary = player.firearm.stats if player.firearm else {}
	var aim_rate := 6.0 * (0.6 + float(st.get("ergo", 60.0)) / 100.0 * 0.7) * float(st.get("ads", 1.0))
	_aim = move_toward(_aim, 1.0 if player.aiming else 0.0, delta * aim_rate)
	_sprint = move_toward(_sprint, 1.0 if (player.sprinting and not player.aiming) else 0.0, delta * 5.0)
	var aim_k := smoothstep(0.0, 1.0, _aim)
	var sprint_k := smoothstep(0.0, 1.0, _sprint)

	# Look sway: the gun lags behind camera turns, then settles.
	var yaw := player.rotation.y
	var dyaw := wrapf(yaw - _last_yaw, -PI, PI)
	var dpitch := deg_to_rad(player.pitch - _last_pitch)
	_last_yaw = yaw
	_last_pitch = player.pitch
	var sway_gain := lerpf(1.0, 0.25, aim_k)
	_sway_rot += Vector2(dyaw, dpitch) * 0.9 * sway_gain
	_sway_rot = _sway_rot.limit_length(0.12)
	_sway_rot = _sway_rot.lerp(Vector2.ZERO, minf(1.0, delta * 9.0))

	# Walk bob (much smaller while aiming).
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var bob := Vector3.ZERO
	if player.is_on_floor() and speed > 0.3:
		_bob_t += delta * speed * 2.4
		var amount := lerpf(1.0, 0.2, aim_k) * clampf(speed / 3.2, 0.0, 1.6)
		bob = Vector3(sin(_bob_t * 0.5) * 0.006, -absf(cos(_bob_t * 0.5)) * 0.005, 0.0) * amount

	# Pull back when a wall is closer than the muzzle.
	var target_wall := 0.0
	var space := get_world_3d().direct_space_state
	var cam := get_parent() as Node3D
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * WALL_CHECK
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)  # level geometry only (not casings or dummies)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		target_wall = clampf((WALL_CHECK - from.distance_to(hit.position)) / 0.3, 0.0, 1.0)
	_wall = move_toward(_wall, target_wall, delta * 6.0)
	var wall_k := smoothstep(0.0, 1.0, _wall)

	var pos := HIP_POS.lerp(AIM_POS, aim_k)
	pos = pos.lerp(SPRINT_POS, sprint_k)
	pos += bob
	pos += Vector3(_sway_rot.x * 0.05, -_sway_rot.y * 0.04, 0.0)  # lag behind the turn
	pos += Vector3(0.0, -0.06, 0.12) * wall_k

	# Recoil: a damped spring so the gun snaps up and settles.
	_kick_vel += (-_kick * 260.0 - _kick_vel * 22.0) * delta
	_kick += _kick_vel * delta
	var kick_k := _kick * lerpf(1.0, 0.6, aim_k)
	pos += Vector3(0.0, 0.01, 0.05) * kick_k

	# Reload pose: tilt the gun to show the magazine well.
	var reload_k := 0.0
	if player.firearm:
		reload_k = smoothstep(0.0, 1.0, player.firearm.reload_pose())
	pos += Vector3(-0.02, 0.025, 0.03) * reload_k
	position = pos

	var rot := (HIP_ROT * (1.0 - aim_k)).lerp(SPRINT_ROT, sprint_k)
	rot += Vector3(14.0, 0.0, 0.0) * kick_k
	rot += Vector3(18.0, -10.0, 32.0) * reload_k
	rot += Vector3(-rad_to_deg(_sway_rot.y) * 0.6, -rad_to_deg(_sway_rot.x) * 0.8, rad_to_deg(_sway_rot.x) * 0.5)
	rot += Vector3(-45.0, 15.0, 0.0) * wall_k
	rotation_degrees = rot


## Fire impulse; 1.0 is a 230gr ball round.
func kick(strength: float) -> void:
	_kick_vel += 7.0 * strength


## True when the gun is clear to shoot (not sprinting, not jammed against a wall).
func can_fire() -> bool:
	return _sprint < 0.3 and _wall < 0.5 and not (player.firearm and player.firearm.reloading)
