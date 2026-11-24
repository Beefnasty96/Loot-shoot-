class_name Firearm
extends Node
## Runs the gun in one weapon slot (one Firearm for the holster, one for the
## primary): an InvItem (WeaponDB weapon) carrying its own chambered round,
## magazine and attachment tree. Calibre, accuracy, recoil, muzzle velocity
## (barrel length x each load's fps-per-inch), loudness (suppressor), muzzle flash,
## gunshot sound and the weapon light come from WeaponDB.stats(); handling and
## animation (slide or bolt carrier, reload times, zero, poses) from WeaponDB.rig().
## bind() swaps guns (rebuilding the models if it's a different gun); refresh()
## re-reads stats and rebuilds the part models after modding. The Firearm builds
## its own first-person viewmodel and third-person model (attach()).
##
## - Semi: one shot per trigger press. Auto: fires at the gun's rpm while held.
##   Hold Y to flip the selector (guns with more than one mode).
##   Last shot locks the slide / bolt back.
## - Magazines hold one ammo type. D-pad left/right picks the load for your NEXT
##   magazine; the round already chambered stays what it was (like the real thing).
## - X: tap = reload (tactical keeps the chambered round; empty = slide release).
##   Hold = mag check (shows how many rounds are left).
## - Sights are zeroed for the rig's zero load and distance (1911: 25 yd, 230gr ball;
##   M4: 50 yd, M193 - which crosses again near 200 yd). Aimed shots follow real
##   sight geometry; hip fire converges on whatever the crosshair is on.

signal changed
signal shot_fired(ammo: AmmoType)

const MIN_SHOT_INTERVAL := 0.09     ## Fastest you can work a semi-auto trigger.
const MAG_CHECK_HOLD := 0.35
const CHARGE_TIME := 0.4            ## Pulling the charging handle / racking.
const MAX_CASINGS := 30

var player: Player
var slot := "sidearm"                ## Equipment weapon slot this runs.
var serves := "pistol"               ## Player.active_weapon value that draws it.
var rig: Dictionary = WeaponDB.RIG_DEFAULTS
var mode := "semi"                   ## Fire selector.
var viewmodel: Viewmodel             ## First-person arms + gun (built by attach()).
var tp_model: Node3D                 ## Third-person gun.
var tp_grips: Array[Node3D] = []     ## [grip centre, right hand, left hand] on tp_model.
var dust_open := false               ## AR dust cover: opens on the first shot or charge.
var ammo_types: Array[AmmoType] = []
var selected := 0                    ## Preferred load: reloads pick a magazine of this type first.
var gun: InvItem                     ## The weapon item in your holster (null = none).
var stats := {}                      ## WeaponDB.stats(gun)
var light_on := false
var chambered: AmmoType:
	get: return gun.wpn_chamber if gun else null
	set(v):
		if gun:
			gun.wpn_chamber = v
## The magazine in the gun is a real inventory item: reloads swap it with one from
## your rig or pockets (never the backpack), and the old one goes back where the new one was.
var mag_item: InvItem:
	get: return gun.wpn_mag if gun else null
	set(v):
		if gun:
			gun.wpn_mag = v
var mag_ammo: AmmoType:
	get: return mag_item.mag_ammo if mag_item else null
	set(v):
		if mag_item:
			mag_item.mag_ammo = v
var mag_count: int:
	get: return mag_item.mag_count if mag_item else 0
	set(v):
		if mag_item:
			mag_item.mag_count = v
var has_mag: bool:
	get: return mag_item != null
var notice := ""
var notice_time := 0.0
var _incoming: Dictionary = {}       ## {item, grid, pos} chosen when the reload starts
var _outgoing: InvItem
var slide_locked := false
var hammer_down := false
var reloading := false
var reload_progress := 0.0
var mag_check_text := ""
var mag_check_time := 0.0
var bloom := 0.0

var _reload_len := 1.7
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
var _scene_path := ""
var _fp_parent: Node3D
var _tp_parent: Node3D
var _next_shot := 0.0
var _charge := 1.0                   ## 0..1 through a charging-handle pull (1 = done).
var _shots_in_burst := 0


func _ready() -> void:
	ammo_types = AmmoDB.all_for(".45 ACP")
	for key in ["shot_45", "shot_45_supp", "shot_556", "dry_fire", "mag_out", "mag_in", "slide_release", "casing",
			"charge", "selector", "mag_out_rifle", "mag_in_rifle", "bolt_release"]:
		var path := "res://assets/audio/%s.wav" % key
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	_audio = AudioStreamPlayer.new()
	_audio.max_polyphony = 6
	add_child(_audio)
	_flash_tex = _make_flash_texture()


## Hook this Firearm up to a weapon slot. Models are built for whatever gun is
## bound (and rebuilt when a different gun goes in).
func attach(p: Player, weapon_slot: String, draws_as: String, fp_parent: Node3D, tp_parent: Node3D) -> void:
	player = p
	slot = weapon_slot
	serves = draws_as
	_fp_parent = fp_parent
	_tp_parent = tp_parent


func _build_models() -> void:
	var path: String = String(gun.def.scene_path) if gun else ""
	if path == _scene_path:
		return
	_scene_path = path
	for d in _parts:
		if is_instance_valid(d.flash):
			d.flash.queue_free()
	_parts.clear()
	if viewmodel:
		viewmodel.queue_free()
		viewmodel = null
	if tp_model:
		tp_model.queue_free()
		tp_model = null
	tp_grips.clear()
	if path == "" or _fp_parent == null:
		return
	var scene := load(path) as PackedScene
	viewmodel = Viewmodel.new()
	viewmodel.player = player
	viewmodel.firearm = self
	viewmodel.weapon_scene = scene
	viewmodel.arms_scene = load(String(rig.view.arms)) as PackedScene
	viewmodel.pose = rig.view
	viewmodel.visible = player != null and player.active_weapon == serves
	_fp_parent.add_child(viewmodel)
	tp_model = scene.instantiate()
	tp_model.position = rig.tp.pos
	tp_model.visible = viewmodel.visible
	_tp_parent.add_child(tp_model)
	_set_layers(tp_model, Player.PLAYER_MODEL_LAYER)
	for key in ["grip", "right", "left"]:
		var m := Node3D.new()
		m.position = rig.tp[key]
		tp_model.add_child(m)
		tp_grips.append(m)
	register_weapon(viewmodel.weapon, Viewmodel.LAYER)
	register_weapon(tp_model, Player.PLAYER_MODEL_LAYER)


func _set_layers(node: Node, layer: int) -> void:
	for child in node.get_children():
		if child is VisualInstance3D:
			child.layers = layer
		_set_layers(child, layer)


## Show/hide this gun's models (drawn or put away).
func set_drawn(on: bool) -> void:
	if viewmodel:
		viewmodel.visible = on
	if tp_model:
		tp_model.visible = on
	if not on:
		_shots_in_burst = 0


## Called for each model of the gun (first-person and third-person).
func register_weapon(root: Node3D, layer: int) -> void:
	var d := {
		root = root,
		slide = _find(root, ["Slide", "Bolt"]),
		charging = root.find_child("ChargingHandle", true, false),
		dust = root.find_child("DustCover", true, false),
		selector = root.find_child("Selector", true, false),
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
	d.charging_rest = d.charging.position if d.charging else Vector3.ZERO
	d.dust_rest = d.dust.rotation if d.dust else Vector3.ZERO
	d.selector_rest = d.selector.rotation if d.selector else Vector3.ZERO
	# Muzzle flash: a star sprite + a brief light.
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(rig.flash)
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
	d.layer = layer
	d.beam = null
	_parts.append(d)
	_assemble(d)


func _find(root: Node, names: Array) -> Node3D:
	for n: String in names:
		var f := root.find_child(n, true, false) as Node3D
		if f:
			return f
	return null


func current_ammo_name() -> String:
	return chambered.display_name if chambered else "empty"


func next_ammo() -> AmmoType:
	return ammo_types[selected]


## Put a gun in your hand (or null). Stops any reload.
func bind(item: InvItem) -> void:
	gun = item
	rig = WeaponDB.rig(gun.def.weapon_id) if gun else WeaponDB.RIG_DEFAULTS
	var modes: Array = WeaponDB.weapon(gun.def.weapon_id).get("modes", ["semi"]) if gun else ["semi"]
	if not (mode in modes):
		mode = modes[0]
	_build_models()
	dust_open = false
	_charge = 1.0
	reloading = false
	slide_locked = gun != null and gun.wpn_chamber == null and (gun.wpn_mag == null or gun.wpn_mag.mag_count == 0)
	hammer_down = false
	refresh()


## Re-read stats and rebuild part models (after modding the gun).
func refresh() -> void:
	stats = WeaponDB.stats(gun) if gun else {}
	if gun and stats.caliber != "":
		ammo_types = AmmoDB.all_for(stats.caliber)
		selected = clampi(selected, 0, ammo_types.size() - 1)
	for d in _parts:
		_assemble(d)
	changed.emit()


func _assemble(d: Dictionary) -> void:
	if gun == null:
		return
	var built := WeaponDB.assemble(gun, d.root, d.layer)
	var muzzle: Node3D = built.muzzle
	if muzzle and muzzle != d.muzzle:
		d.flash.reparent(muzzle, false)
		d.light.reparent(muzzle, false)
		d.muzzle = muzzle
	d.beam = built.light


func velocity_factor(ammo: AmmoType) -> float:
	return ammo.velocity_factor(stats.get("barrel_in", ammo.reference_barrel_in))


func has_light() -> bool:
	return not stats.get("light", {}).is_empty()


func toggle_light() -> void:
	if has_light():
		light_on = not light_on
		_play("dry_fire")


## The gun's weight is counted with your equipment now (Equipment.weapons).
func carried_weight() -> float:
	return 0.0


## Loaded magazines you can reach for (rig and pockets).
func spare_mags() -> Array:
	var out: Array = []
	for grid: InvGrid in player.character.equipment.grids(false):
		for e in grid.entries:
			var it: InvItem = e.item
			if it.def.is_mag() and gun and WeaponDB.accepts(gun, "magazine", it) and it.mag_count > 0:
				out.append({item = it, grid = grid, pos = e.pos})
	return out


func spare_count(ammo: AmmoType) -> int:
	var n := 0
	for m in spare_mags():
		if (m.item as InvItem).mag_ammo == ammo:
			n += 1
	return n


func _best_mag() -> Dictionary:
	var best := {}
	var best_score := -1
	for m in spare_mags():
		var it: InvItem = m.item
		var score := it.mag_count + (100 if it.mag_ammo == next_ammo() else 0)
		if score > best_score:
			best_score = score
			best = m
	return best


func _notify(text: String) -> void:
	notice = text
	notice_time = 2.5


func _process(delta: float) -> void:
	if player == null:
		return
	_clock += delta
	var now := _clock
	bloom = maxf(0.0, bloom - delta * 2.5)
	if mag_check_time > 0.0:
		mag_check_time -= delta

	if not player.can_act() or player.active_weapon != serves:
		_shots_in_burst = 0
		_animate(delta)
		return
	if mode == "auto":
		if Input.is_action_pressed("fire"):
			if Input.is_action_just_pressed("fire"):
				_next_shot = maxf(_next_shot, now)
			# Catch up within the frame so the rate is the gun's, not the frame rate's.
			while now >= _next_shot and Input.is_action_pressed("fire"):
				if not _try_fire(now, true):
					break
				_next_shot += 60.0 / maxf(1.0, float(WeaponDB.weapon(gun.def.weapon_id).get("rpm", 600)))
				if now - _next_shot > 0.2:
					_next_shot = now
		else:
			_shots_in_burst = 0
	elif Input.is_action_just_pressed("fire"):
		_shots_in_burst = 0
		_try_fire(now)
	if notice_time > 0.0:
		notice_time -= delta
	if Input.is_action_just_pressed("ammo_next"):
		_cycle_preferred(1)
	if Input.is_action_just_pressed("ammo_prev"):
		_cycle_preferred(-1)

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

## Returns true if a round went off.
func _try_fire(now: float, auto := false) -> bool:
	if reloading or _charge < 1.0 or (not auto and now - _last_shot < MIN_SHOT_INTERVAL):
		return false
	if viewmodel and not viewmodel.can_fire() and player.effective_view() == Player.View.FIRST:
		return false
	if player.sprinting:
		return false
	if gun == null:
		return false
	if not stats.working:
		if not auto or _shots_in_burst == 0:
			_play("dry_fire")
		_notify("It won't fire: no %s." % ", ".join(stats.missing))
		return false
	if chambered == null or slide_locked or hammer_down:
		if not hammer_down:
			_play("dry_fire")
		hammer_down = true
		return false
	_last_shot = now
	_shots_in_burst += 1
	dust_open = true
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
	return true


## Flip the fire selector (hold Y). Returns the new mode, or "" if the gun has one mode.
func toggle_mode() -> String:
	if gun == null:
		return ""
	var modes: Array = WeaponDB.weapon(gun.def.weapon_id).get("modes", ["semi"])
	if modes.size() < 2:
		return ""
	mode = modes[(modes.find(mode) + 1) % modes.size()]
	_play("selector")
	_notify("Selector: %s" % mode.to_upper())
	changed.emit()
	return mode


func _shoot(ammo: AmmoType) -> void:
	var fp := player.effective_view() == Player.View.FIRST
	var cam: Camera3D = player.fp_camera if fp else player.tp_camera
	var muzzle := _active_part().get("muzzle") as Node3D
	var origin := muzzle.global_position if muzzle else cam.global_position
	var cam_pos := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var dir: Vector3
	if fp and player.aiming:
		# Real sight geometry: aim at the sight line at the zero distance, then add
		# the barrel's upward angle that makes the zero load cross there.
		var zero_m := float(rig.zero_m)
		var zero_ammo := AmmoDB.get_ammo(String(rig.zero_ammo))
		var target := cam_pos + fwd * zero_m
		dir = (target - origin).normalized()
		var zero_v := zero_ammo.muzzle_ms() * velocity_factor(zero_ammo)
		var zero_angle := 0.5 * Ballistics.GRAVITY * zero_m / (zero_v * zero_v)
		dir = dir.rotated(cam.global_transform.basis.x, zero_angle)
	else:
		var space := player.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(cam_pos, cam_pos + fwd * 300.0, 1 | 4, [player.get_rid()])
		var hit := space.intersect_ray(q)
		var target: Vector3 = hit.position if not hit.is_empty() else cam_pos + fwd * 300.0
		dir = (target - origin).normalized()
	dir = _apply_spread(dir)
	# Shot-to-shot velocity spread (vertical stringing at range).
	var vf := velocity_factor(ammo)
	if ammo.vel_sd_fps > 0.0:
		vf *= 1.0 + randfn(0.0, ammo.vel_sd_fps) / ammo.muzzle_fps
	Ballistics.fire(origin, dir, ammo, player.get_rid(), vf, player.hitbox_rids(), stats.loudness)

	# Recoil from the bullet's momentum (+P loads kick harder). A rifle's stock and
	# weight keep each kick small, but in auto it adds up (and drifts right-handed: up and right).
	var momentum := ammo.mass_kg() * ammo.muzzle_ms() * velocity_factor(ammo)
	var kick := momentum * float(rig.recoil_k) * (1.12 if ammo.plus_p else 1.0) * float(stats.recoil)
	var yaw := randf_range(-0.3, 0.3) * kick
	if _shots_in_burst > 1:
		kick *= float(rig.auto_climb)
		yaw += kick * 0.18
	player.add_recoil(kick, -yaw)
	if viewmodel:
		viewmodel.kick(momentum * float(rig.view_kick) * float(stats.recoil))
	bloom = minf(bloom + float(rig.bloom) * float(stats.recoil), 2.5)
	_play(String(stats.sound) if stats.sound != "" else "shot_45")


func spread_degrees() -> float:
	# Mechanical accuracy of the gun combined with the load's own dispersion.
	var ammo_moa := chambered.dispersion_moa if chambered else 0.0
	var moa := sqrt(pow(float(stats.get("moa", 3.0)), 2.0) + ammo_moa * ammo_moa)
	var s := moa / 60.0 * 0.5
	if player.aiming:
		s += float(rig.sight_hold)
	else:
		s += float(rig.get("hip_spread", 1.6))
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	s += clampf(speed / 3.2, 0.0, 1.5) * (0.5 if player.aiming else 1.0)
	if player.crouching:
		s *= 0.8
	if player.vitals:
		s += player.vitals.shake() * 2.5     # hurt arms, pain, blood loss
	return s + bloom


func _apply_spread(dir: Vector3) -> Vector3:
	var max_deg := spread_degrees()
	var axis := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	axis = axis.rotated(dir, randf() * TAU)
	# sqrt for an even spread across the cone's area.
	return dir.rotated(axis, deg_to_rad(sqrt(randf()) * max_deg)).normalized()


# ------------------------------------------------------------------ reloading

## D-pad left/right: step through the loads you're actually carrying in magazines.
func _cycle_preferred(step: int) -> void:
	for i in ammo_types.size():
		selected = (selected + step + ammo_types.size()) % ammo_types.size()
		if spare_count(ammo_types[selected]) > 0:
			break
	changed.emit()


func _start_reload() -> void:
	if reloading or gun == null:
		return
	var best := _best_mag()
	if best.is_empty():
		_notify("No loaded magazines in your rig or pockets.")
		return
	var incoming: InvItem = best.item
	if has_mag and mag_count >= incoming.mag_count and mag_ammo == incoming.mag_ammo and chambered != null:
		return  # nothing better to swap to
	_incoming = best
	reloading = true
	reload_progress = 0.0
	_reload_stage = 0
	_reload_empty = chambered == null
	_reload_len = float(rig.reload_empty) if _reload_empty else float(rig.reload)
	player.sprinting = false


func _update_reload(delta: float) -> void:
	reload_progress += delta / _reload_len
	var p := reload_progress
	if _reload_stage == 0 and p >= 0.15:
		_reload_stage = 1
		_play("mag_out_rifle" if rig.anim == "rifle" and _streams.has("mag_out_rifle") else "mag_out")
	if _reload_stage == 1 and p >= 0.32:
		_reload_stage = 2
		_outgoing = mag_item
		mag_item = null
		changed.emit()
	if _reload_stage == 2 and p >= 0.62:
		_reload_stage = 3
		var grid: InvGrid = _incoming.grid
		var incoming: InvItem = _incoming.item
		grid.remove(incoming)
		mag_item = incoming
		# The old magazine goes back where the new one came from (or anywhere it fits).
		if _outgoing:
			if not grid.place(_outgoing, _incoming.pos):
				var stored := false
				for g: InvGrid in player.character.equipment.grids():
					if g.auto_place(_outgoing):
						stored = true
						break
				if not stored:
					_notify("No room for the empty magazine: dropped it.")
		_outgoing = null
		_incoming = {}
		_play("mag_in_rifle" if rig.anim == "rifle" and _streams.has("mag_in_rifle") else "mag_in")
		changed.emit()
	if _reload_stage == 3 and _reload_empty and p >= 0.78:
		_reload_stage = 4
		chambered = mag_ammo
		mag_count -= 1
		slide_locked = false
		hammer_down = false
		_cycle = 0.6
		_play("bolt_release" if rig.anim == "rifle" and _streams.has("bolt_release") else "slide_release")
		changed.emit()
	if p >= 1.0:
		reloading = false
		if chambered == null and mag_count > 0:  # dry-fired with a full mag: rack it
			charge()
		hammer_down = false
		changed.emit()


## Pull the charging handle (rifle) / rack the slide: chambers a round from the magazine.
func charge() -> void:
	_charge = 0.0
	dust_open = true
	_play("charge" if _streams.has("charge") else "slide_release")
	if chambered == null and has_mag and mag_count > 0:
		chambered = mag_ammo
		mag_count -= 1
		slide_locked = false
	changed.emit()


func _mag_check() -> void:
	var ammo_name := mag_ammo.display_name if has_mag else ""
	var desc := "empty"
	if has_mag:
		var cap := float(mag_item.def.mag_capacity)
		if mag_count >= mag_item.def.mag_capacity:
			desc = "full (%d)" % mag_count
		elif mag_count >= cap * 0.65:
			desc = "most of it (%d)" % mag_count
		elif mag_count >= cap * 0.35:
			desc = "about half (%d)" % mag_count
		elif mag_count >= 1:
			desc = "nearly empty (%d)" % mag_count
	mag_check_text = "Mag: %s  %s\nChamber: %s" % [desc, ammo_name, current_ammo_name()]
	mag_check_time = 2.5
	changed.emit()


# ------------------------------------------------------------------ animation + effects

func _active_part() -> Dictionary:
	if _parts.is_empty():
		return {}
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
	_cycle = minf(1.0, _cycle + delta / float(rig.cycle))
	_charge = minf(1.0, _charge + delta / CHARGE_TIME)
	# Charging handle: pulled back over the first 45%, rides home with the bolt.
	var charge_k := 0.0
	if _charge < 1.0:
		charge_k = smoothstep(0.0, 0.45, _charge) if _charge < 0.45 else 1.0 - smoothstep(0.6, 0.8, _charge)
	# Slide: snaps back in the first third of the cycle, returns in the rest; locks back when empty.
	var slide_k := 0.0
	if slide_locked:
		slide_k = 1.0 if _cycle >= 0.33 else _cycle / 0.33
	elif _cycle < 0.33:
		slide_k = _cycle / 0.33
	elif _cycle < 1.0:
		slide_k = 1.0 - (_cycle - 0.33) / 0.67
	slide_k = maxf(slide_k, charge_k)
	var mag_off := 0.0
	var mag_visible := true
	if reloading:
		var p := reload_progress
		if p >= 0.15 and p < 0.32:
			mag_off = smoothstep(0.15, 0.32, p) * float(rig.mag_drop)
		elif p >= 0.32 and p < 0.45:
			mag_visible = false
		elif p >= 0.45 and p < 0.62:
			mag_off = (1.0 - smoothstep(0.45, 0.62, p)) * float(rig.mag_drop)
	_flash_time -= delta
	var trigger_back := Input.is_action_pressed("fire") and not reloading
	var active := _active_part()
	for d in _parts:
		if d.slide:
			d.slide.position = d.slide_rest + Vector3(0, 0, float(rig.travel) * slide_k)
		if d.charging:
			d.charging.position = d.charging_rest + Vector3(0, 0, float(rig.travel) * 0.85 * charge_k)
		if d.dust:
			var target := deg_to_rad(-105.0) if dust_open else 0.0
			d.dust.rotation.z = move_toward(d.dust.rotation.z, d.dust_rest.z + target, delta * 30.0)
		if d.selector:
			var ang := {"safe": 0.0, "semi": 90.0, "auto": 180.0}.get(mode, 90.0) as float
			d.selector.rotation = d.selector_rest + Vector3(deg_to_rad(ang), 0, 0)
		if d.hammer:
			var down := hammer_down or (_cycle < 0.15 and not slide_locked)
			d.hammer.rotation = d.hammer_rest + Vector3(deg_to_rad(-38.0) if down else 0.0, 0, 0)
		if d.trigger:
			d.trigger.position = d.trigger_rest + Vector3(0, 0, 0.003 if trigger_back else 0.0)
		if d.magazine:
			d.magazine.position = d.mag_rest + (rig.mag_axis as Vector3) * mag_off
			d.magazine.visible = mag_visible and (has_mag or mag_off > 0.0)
		var flashing: bool = _flash_time > 0.0 and d == active and stats.get("flash", true)
		d.flash.visible = flashing
		d.light.visible = flashing
		if d.get("beam"):
			(d.beam as Node3D).visible = light_on and d == active
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
	var port := _active_part().get("port") as Node3D
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
	var csize: Vector2 = rig.casing
	shape.radius = csize.x
	shape.height = csize.y
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = csize.x
	mesh.bottom_radius = csize.x
	mesh.height = csize.y
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
