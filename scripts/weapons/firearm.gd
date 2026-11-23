class_name Firearm
extends Node
## The M1911: one round in the chamber plus a 7-round single-stack magazine.
##
## - Semi-auto: one shot per trigger press. Last shot locks the slide back.
## - Magazines hold one ammo type. D-pad left/right picks the load for your NEXT
##   magazine; the round already chambered stays what it was (like the real thing).
## - X: tap = reload (tactical keeps the chambered round; empty = slide release).
##   Hold = mag check (shows how many rounds are left).
## - Sights are zeroed at 25 yd for 230gr ball: aimed shots cross the sight line
##   there and drop beyond it. Hip fire converges on whatever the crosshair is on.

signal changed
signal shot_fired(ammo: AmmoType)

const CALIBER := ".45 ACP"
const CAPACITY := 7
const MECH_ACCURACY_MOA := 3.0      ## Typical service 1911 from a rest.
const ZERO_DISTANCE := 22.86        ## 25 yards.
const ZERO_AMMO := "45_1_fmj230"
const VELOCITY_FACTOR := 1.0        ## 5" barrel = the ammo data's reference barrel.
const MIN_SHOT_INTERVAL := 0.09
const RELOAD_TIME := 1.7
const RELOAD_EMPTY_TIME := 2.2
const MAG_CHECK_HOLD := 0.35
const SLIDE_TRAVEL := 0.032
const CYCLE_TIME := 0.075
const GRIP_AXIS := Vector3(0.0, -0.951, 0.309)  ## Down the magazine well (18° grip angle).
const MAX_CASINGS := 15

var player: Player
var ammo_types: Array[AmmoType] = []
var selected := 0
var chambered: AmmoType
var mag_ammo: AmmoType
var mag_count := CAPACITY
var has_mag := true
var slide_locked := false
var hammer_down := false
var reloading := false
var reload_progress := 0.0
var mag_check_text := ""
var mag_check_time := 0.0
var bloom := 0.0

var _reload_len := RELOAD_TIME
var _reload_empty := false
var _reload_stage := 0
var _reload_hold := -1.0
var _last_shot := -10.0
var _clock := 0.0  ## Game time (pauses with the game).
var _cycle := 1.0
var _flash_time := 0.0
var _streams := {}
var _audio: AudioStreamPlayer
var _casings: Array[Node] = []
var _parts: Array[Dictionary] = []   ## Per weapon instance (viewmodel + third person).
var _flash_tex: ImageTexture


func _ready() -> void:
	ammo_types = AmmoDB.all_for(CALIBER)
	mag_ammo = ammo_types[0]
	chambered = ammo_types[0]
	for key in ["shot_45", "dry_fire", "mag_out", "mag_in", "slide_release", "casing"]:
		var path := "res://assets/audio/%s.wav" % key
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	_audio = AudioStreamPlayer.new()
	_audio.max_polyphony = 4
	add_child(_audio)
	_flash_tex = _make_flash_texture()


## Called by the player once both weapon models exist.
func register_weapon(root: Node3D, layer: int) -> void:
	var d := {
		root = root,
		slide = root.find_child("Slide", true, false),
		hammer = root.find_child("Hammer", true, false),
		trigger = root.find_child("Trigger", true, false),
		magazine = root.find_child("Magazine", true, false),
		muzzle = root.find_child("Muzzle", true, false),
		port = root.find_child("EjectionPort", true, false),
	}
	d.slide_rest = d.slide.position if d.slide else Vector3.ZERO
	d.trigger_rest = d.trigger.position if d.trigger else Vector3.ZERO
	d.mag_rest = d.magazine.position if d.magazine else Vector3.ZERO
	d.hammer_rest = d.hammer.rotation if d.hammer else Vector3.ZERO
	# Muzzle flash: a star sprite + a brief light.
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _flash_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = m
	flash.mesh = quad
	flash.layers = layer
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.visible = false
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 2.5
	light.omni_range = 5.0
	light.visible = false
	if d.muzzle:
		d.muzzle.add_child(flash)
		d.muzzle.add_child(light)
		flash.position = Vector3(0, 0, -0.03)
	d.flash = flash
	d.light = light
	_parts.append(d)


func current_ammo_name() -> String:
	return chambered.display_name if chambered else "empty"


func next_ammo() -> AmmoType:
	return ammo_types[selected]


func _process(delta: float) -> void:
	if player == null:
		return
	_clock += delta
	var now := _clock
	bloom = maxf(0.0, bloom - delta * 2.5)
	if mag_check_time > 0.0:
		mag_check_time -= delta

	if player.ui_locked:
		_animate(delta)
		return
	if Input.is_action_just_pressed("fire"):
		_try_fire(now)
	if Input.is_action_just_pressed("ammo_next"):
		selected = (selected + 1) % ammo_types.size()
		changed.emit()
	if Input.is_action_just_pressed("ammo_prev"):
		selected = (selected - 1 + ammo_types.size()) % ammo_types.size()
		changed.emit()

	# Tap X to reload, hold to check the magazine.
	if Input.is_action_just_pressed("reload"):
		_reload_hold = 0.0
	if _reload_hold >= 0.0:
		if Input.is_action_pressed("reload"):
			_reload_hold += delta
			if _reload_hold >= MAG_CHECK_HOLD:
				_mag_check()
				_reload_hold = -1.0
		else:
			_reload_hold = -1.0
			_start_reload()

	if reloading:
		_update_reload(delta)
	_animate(delta)


# ------------------------------------------------------------------ firing

func _try_fire(now: float) -> void:
	if reloading or now - _last_shot < MIN_SHOT_INTERVAL:
		return
	if not player.viewmodel.can_fire() and player.effective_view() == Player.View.FIRST:
		return
	if player.sprinting:
		return
	if chambered == null or slide_locked or hammer_down:
		_play("dry_fire")
		hammer_down = true
		return
	_last_shot = now
	var ammo := chambered
	_shoot(ammo)
	if has_mag and mag_count > 0:
		chambered = mag_ammo
		mag_count -= 1
	else:
		chambered = null
		slide_locked = true
	_cycle = 0.0
	_flash_time = 0.045
	_eject_casing()
	shot_fired.emit(ammo)
	changed.emit()


func _shoot(ammo: AmmoType) -> void:
	var fp := player.effective_view() == Player.View.FIRST
	var cam: Camera3D = player.fp_camera if fp else player.tp_camera
	var muzzle := _active_part().muzzle as Node3D
	var origin := muzzle.global_position if muzzle else cam.global_position
	var cam_pos := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var dir: Vector3
	if fp and player.aiming:
		# Real sight geometry: aim at the sight line at the zero distance, then add
		# the barrel's upward angle that makes the zero load cross there.
		var target := cam_pos + fwd * ZERO_DISTANCE
		dir = (target - origin).normalized()
		var zero_v := AmmoDB.get_ammo(ZERO_AMMO).muzzle_ms() * VELOCITY_FACTOR
		var zero_angle := 0.5 * Ballistics.GRAVITY * ZERO_DISTANCE / (zero_v * zero_v)
		dir = dir.rotated(cam.global_transform.basis.x, zero_angle)
	else:
		var space := player.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(cam_pos, cam_pos + fwd * 300.0, 1 | 4, [player.get_rid()])
		var hit := space.intersect_ray(q)
		var target: Vector3 = hit.position if not hit.is_empty() else cam_pos + fwd * 300.0
		dir = (target - origin).normalized()
	dir = _apply_spread(dir)
	Ballistics.fire(origin, dir, ammo, player.get_rid(), VELOCITY_FACTOR)

	# Recoil from the bullet's momentum (+P loads kick harder).
	var momentum := ammo.mass_kg() * ammo.muzzle_ms() * VELOCITY_FACTOR
	var kick := momentum * 0.72 * (1.12 if ammo.plus_p else 1.0)
	player.add_recoil(kick, randf_range(-0.3, 0.3) * kick)
	player.viewmodel.kick(momentum / 3.8)
	bloom = minf(bloom + 0.45, 2.0)
	_play("shot_45")


func spread_degrees() -> float:
	var s := MECH_ACCURACY_MOA / 60.0 * 0.5
	if player.aiming:
		s += 0.12
	else:
		s += 1.6
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	s += clampf(speed / 3.2, 0.0, 1.5) * (0.5 if player.aiming else 1.0)
	if player.crouching:
		s *= 0.8
	return s + bloom


func _apply_spread(dir: Vector3) -> Vector3:
	var max_deg := spread_degrees()
	var axis := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	axis = axis.rotated(dir, randf() * TAU)
	# sqrt for an even spread across the cone's area.
	return dir.rotated(axis, deg_to_rad(sqrt(randf()) * max_deg)).normalized()


# ------------------------------------------------------------------ reloading

func _start_reload() -> void:
	if reloading:
		return
	var same := has_mag and mag_count == CAPACITY and mag_ammo == next_ammo() and chambered != null
	if same:
		return
	reloading = true
	reload_progress = 0.0
	_reload_stage = 0
	_reload_empty = chambered == null
	_reload_len = RELOAD_EMPTY_TIME if _reload_empty else RELOAD_TIME
	player.sprinting = false


func _update_reload(delta: float) -> void:
	reload_progress += delta / _reload_len
	var p := reload_progress
	if _reload_stage == 0 and p >= 0.15:
		_reload_stage = 1
		_play("mag_out")
	if _reload_stage == 1 and p >= 0.32:
		_reload_stage = 2
		has_mag = false
		changed.emit()
	if _reload_stage == 2 and p >= 0.62:
		_reload_stage = 3
		has_mag = true
		mag_ammo = next_ammo()
		mag_count = CAPACITY
		_play("mag_in")
		changed.emit()
	if _reload_stage == 3 and _reload_empty and p >= 0.78:
		_reload_stage = 4
		chambered = mag_ammo
		mag_count -= 1
		slide_locked = false
		hammer_down = false
		_cycle = 0.6
		_play("slide_release")
		changed.emit()
	if p >= 1.0:
		reloading = false
		if chambered == null and mag_count > 0:  # dry-fired with a full mag: rack it
			chambered = mag_ammo
			mag_count -= 1
		hammer_down = false
		changed.emit()


func _mag_check() -> void:
	var ammo_name := mag_ammo.display_name if has_mag else ""
	var desc := "empty"
	if has_mag:
		if mag_count >= CAPACITY:
			desc = "full (7)"
		elif mag_count >= 5:
			desc = "most of it (%d)" % mag_count
		elif mag_count >= 3:
			desc = "about half (%d)" % mag_count
		elif mag_count >= 1:
			desc = "nearly empty (%d)" % mag_count
	mag_check_text = "Mag: %s  %s\nChamber: %s" % [desc, ammo_name, current_ammo_name()]
	mag_check_time = 2.5
	changed.emit()


# ------------------------------------------------------------------ animation + effects

func _active_part() -> Dictionary:
	var fp := player.effective_view() == Player.View.FIRST
	return _parts[0] if fp or _parts.size() < 2 else _parts[1]


func reload_pose() -> float:
	if not reloading:
		return 0.0
	var p := reload_progress
	if p < 0.15:
		return smoothstep(0.0, 0.15, p)
	if p > 0.85:
		return 1.0 - smoothstep(0.85, 1.0, p)
	return 1.0


func _animate(delta: float) -> void:
	_cycle = minf(1.0, _cycle + delta / CYCLE_TIME)
	# Slide: snaps back in the first third of the cycle, returns in the rest; locks back when empty.
	var slide_k := 0.0
	if slide_locked:
		slide_k = 1.0 if _cycle >= 0.33 else _cycle / 0.33
	elif _cycle < 0.33:
		slide_k = _cycle / 0.33
	elif _cycle < 1.0:
		slide_k = 1.0 - (_cycle - 0.33) / 0.67
	var mag_off := 0.0
	var mag_visible := true
	if reloading:
		var p := reload_progress
		if p >= 0.15 and p < 0.32:
			mag_off = smoothstep(0.15, 0.32, p) * 0.14
		elif p >= 0.32 and p < 0.45:
			mag_visible = false
		elif p >= 0.45 and p < 0.62:
			mag_off = (1.0 - smoothstep(0.45, 0.62, p)) * 0.14
	_flash_time -= delta
	var trigger_back := Input.is_action_pressed("fire") and not reloading
	var active := _active_part()
	for d in _parts:
		if d.slide:
			d.slide.position = d.slide_rest + Vector3(0, 0, SLIDE_TRAVEL * slide_k)
		if d.hammer:
			var down := hammer_down or (_cycle < 0.15 and not slide_locked)
			d.hammer.rotation = d.hammer_rest + Vector3(deg_to_rad(-38.0) if down else 0.0, 0, 0)
		if d.trigger:
			d.trigger.position = d.trigger_rest + Vector3(0, 0, 0.003 if trigger_back else 0.0)
		if d.magazine:
			d.magazine.position = d.mag_rest + GRIP_AXIS * mag_off
			d.magazine.visible = mag_visible and (has_mag or mag_off > 0.0)
		var flashing := _flash_time > 0.0 and d == active
		d.flash.visible = flashing
		d.light.visible = flashing
		if d.flash.visible:
			d.flash.rotation.z = randf() * TAU
			d.flash.scale = Vector3.ONE * randf_range(0.8, 1.3)


func _play(key: String) -> void:
	if not _streams.has(key):
		return
	_audio.stream = _streams[key]
	_audio.pitch_scale = randf_range(0.96, 1.04)
	_audio.play()


func _eject_casing() -> void:
	var port := _active_part().port as Node3D
	if port == null:
		return
	var body := RigidBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 1
	body.mass = 0.012
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 1
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.006
	shape.height = 0.023
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.006
	mesh.bottom_radius = 0.006
	mesh.height = 0.023
	mesh.radial_segments = 6
	mesh.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.85, 0.65, 0.25)
	brass.metallic = 0.6
	brass.roughness = 0.35
	mesh.material = brass
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	host.add_child(body)
	var cam_basis := player.fp_camera.global_transform.basis
	body.global_transform = Transform3D(Basis(cam_basis.z, PI / 2.0) * cam_basis, port.global_position)
	body.linear_velocity = cam_basis.x * randf_range(1.8, 2.6) + cam_basis.y * randf_range(1.4, 2.0) \
		+ cam_basis.z * 0.4 + player.velocity
	body.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	var tinkled := [false]
	body.body_entered.connect(func(_b):
		if not tinkled[0] and _streams.has("casing"):
			tinkled[0] = true
			var s := AudioStreamPlayer3D.new()
			s.stream = _streams["casing"]
			s.unit_size = 3.0
			s.pitch_scale = randf_range(0.9, 1.15)
			body.add_child(s)
			s.play())
	_casings.append(body)
	if _casings.size() > MAX_CASINGS:
		var old: Node = _casings.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	get_tree().create_timer(8.0).timeout.connect(func():
		if is_instance_valid(body):
			_casings.erase(body)
			body.queue_free())


func _make_flash_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var v := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5) / (s / 2.0)
			var r := v.length()
			var ang := atan2(v.y, v.x)
			var spikes := pow(absf(cos(ang * 3.0)), 6.0)  # six-point star
			var a := clampf((1.0 - r) * 1.6, 0.0, 1.0) * (0.35 + 0.65 * spikes) + clampf(1.0 - r * 3.0, 0.0, 1.0)
			a = clampf(a, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.8 + 0.2 * (1.0 - r), 0.45 + 0.4 * (1.0 - r), a))
	return ImageTexture.create_from_image(img)
