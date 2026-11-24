extends Node
## Autoload "Ballistics": simulates every bullet in flight.
##
## Flight: point-mass trajectory with gravity and G1 drag (Cd from the G1
## standard table scaled by sectional density / BC), integrated each physics tick.
##
## Impact, per surface:
##  1. Frangible on a hard surface -> turns to dust.
##  2. Shallow angle on a material that allows it -> ricochet (keeps 55-85% speed).
##  3. Otherwise measure the thickness it must cross (ray back from the far side),
##     convert to gel-equivalent millimetres, and compare with what the bullet can
##     still penetrate at its current speed. It either stops inside (all energy
##     delivered) or exits slower, possibly deflected, expanded, plugged or crushed.
## Rifle bullets (AmmoType.yaws()) go in nose-first for a few inches of tissue,
## losing little, then yaw: fragmenting if still above frag_min_fps (big wound,
## stops sooner, the biggest piece keeps frag_retained of the mass), otherwise
## tumbling. Too little tissue to reach the yaw = a small hole straight through.
## Barriers destabilize them (they arrive at the next thing already tumbling).
## On hard materials they punch nose-first (hard_ref_in), scaled by
## hard_barrier_factor (M855's steel penetrator: 0.65).
## Tracers (AmmoType.tracer) draw a glowing streak until tracer_range_m, always.
## Every impact emits `impact(info)` with speeds, energies (J and ft-lbs) and outcome.

signal impact(info: Dictionary)
signal melee_impact(info: Dictionary)
signal gunshot(origin: Vector3, shooter: RID, loudness: float)   ## Every shot fired, for AI hearing (1 = unsuppressed).   ## Blade contacts (Melee.strike), for the HUD and sounds.

const GRAVITY := 9.81
const AIR_DENSITY := 1.225
const SPEED_OF_SOUND := 343.0
const V_MIN := 55.0          ## m/s: below this a pistol bullet no longer penetrates tissue.
const MAX_LIFE := 5.0
const MAX_THICKNESS := 2.0   ## m: anything thicker stops the bullet.
const RAY_MASK := 1 | 4 | 32  ## world, hitboxes, doors (character capsules are not bullet stoppers: hitboxes are)
const MAX_EVENTS_PER_TICK := 6
const TRAIL_LIFE := 4.0
const G1 := [
	[0.0, 0.263], [0.5, 0.203], [0.7, 0.203], [0.8, 0.217], [0.9, 0.255], [0.95, 0.297],
	[1.0, 0.380], [1.05, 0.444], [1.1, 0.489], [1.2, 0.520], [1.5, 0.505], [2.0, 0.437],
	[2.5, 0.380], [3.0, 0.341],
]


class Bullet:
	var ammo: AmmoType
	var pos: Vector3
	var vel: Vector3
	var shooter: RID
	var exclude: Array[RID] = []    ## Shooter plus their own hitboxes.
	var expanded := false
	var clogged := false
	var deformed := false
	var yawed := false              ## Rifle bullet already turned sideways (tumbling).
	var fragmented := false
	var split := false              ## Broke in two rather than fragmenting.
	var mass_frac := 1.0            ## What's left of it after fragmenting.
	var alive := true
	var time := 0.0
	var distance := 0.0
	var trail := PackedVector3Array()
	var trail_colors := PackedColorArray()
	var color := Color(1, 1, 1, 0.8)


var debug_enabled := false  ## Off in real levels; the shooting range turns it on.
var bullets: Array[Bullet] = []
var _trails: Array[Dictionary] = []
var _trail_mesh: ImmediateMesh
var _trail_instance: MeshInstance3D
var _tracer_mesh: ImmediateMesh
var fx: ImpactFX
var blood: BloodFX


func _ready() -> void:
	fx = ImpactFX.new()
	add_child(fx)
	blood = BloodFX.new()
	add_child(blood)
	_trail_mesh = ImmediateMesh.new()
	_trail_instance = MeshInstance3D.new()
	_trail_instance.mesh = _trail_mesh
	_trail_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_instance.material_override = m
	add_child(_trail_instance)
	_tracer_mesh = ImmediateMesh.new()
	var ti := MeshInstance3D.new()
	ti.mesh = _tracer_mesh
	ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ti.extra_cull_margin = 16384.0
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.no_depth_test = false
	ti.material_override = tm
	add_child(ti)


## Fire one bullet. `velocity_factor` scales muzzle velocity for barrels shorter/longer than the reference.
func fire(origin: Vector3, direction: Vector3, ammo: AmmoType, shooter: RID, velocity_factor := 1.0, exclude: Array[RID] = [], loudness := 1.0) -> Bullet:
	var b := Bullet.new()
	b.exclude.append(shooter)
	b.exclude.append_array(exclude)
	gunshot.emit(origin, shooter, loudness)
	b.ammo = ammo
	b.pos = origin
	b.vel = direction.normalized() * ammo.muzzle_ms() * velocity_factor
	b.shooter = shooter
	b.trail.append(origin)
	b.trail_colors.append(b.color)
	bullets.append(b)
	return b


## Drag deceleration constant k (a = -k * |v| * v) for this ammo at this speed.
static func drag_k(ammo: AmmoType, speed: float) -> float:
	var cd := g1_cd(speed / SPEED_OF_SOUND) * ammo.sectional_density() / ammo.bc_g1
	return 0.5 * AIR_DENSITY * cd * ammo.area_m2() / ammo.mass_kg()


static func g1_cd(mach: float) -> float:
	for i in range(1, G1.size()):
		var hi: Array = G1[i]
		if mach <= hi[0]:
			var lo: Array = G1[i - 1]
			return lerpf(lo[1], hi[1], (mach - lo[0]) / (hi[0] - lo[0]))
	return G1.back()[1]


func _physics_process(delta: float) -> void:
	for b in bullets:
		if b.alive:
			_step(b, delta)
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		if not b.alive:
			_trails.append({points = b.trail, colors = b.trail_colors, t = 0.0})
			bullets.remove_at(i)
	_draw_trails(delta)
	_draw_tracers()


func _step(b: Bullet, dt: float) -> void:
	b.time += dt
	var speed := b.vel.length()
	if speed < 25.0 or b.time > MAX_LIFE or b.pos.y < -30.0:
		b.alive = false
		return
	var k := drag_k(b.ammo, speed) / b.mass_frac * (2.5 if b.yawed else 1.0)   # tumbling = much more drag
	var acc := -k * speed * b.vel + Vector3.DOWN * GRAVITY
	var new_vel := b.vel + acc * dt
	var to := b.pos + (b.vel + new_vel) * 0.5 * dt
	b.vel = new_vel
	_trace(b, b.pos, to)


func _trace(b: Bullet, from: Vector3, to: Vector3) -> void:
	var space := get_viewport().get_world_3d().direct_space_state
	for _i in MAX_EVENTS_PER_TICK:
		var q := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK, b.exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			b.distance += from.distance_to(to)
			b.pos = to
			_trail_point(b, to)
			return
		var travelled := from.distance_to(hit.position)
		var remaining := maxf(0.0, from.distance_to(to) - travelled)
		b.distance += travelled
		_trail_point(b, hit.position)
		var r := _interact(b, hit)
		if not b.alive:
			if r.has("stop_pos"):
				_trail_point(b, r.stop_pos)
			return
		var dir: Vector3 = b.vel.normalized()
		from = r.exit_pos + dir * 0.002
		to = from + dir * remaining
		_trail_point(b, r.exit_pos)
	b.pos = to


func _interact(b: Bullet, hit: Dictionary) -> Dictionary:
	var ammo := b.ammo
	var collider: Object = hit.collider
	var normal: Vector3 = hit.normal
	var p: Vector3 = hit.position
	var dir := b.vel.normalized()
	var speed := b.vel.length()
	var hitbox := collider as Hitbox
	var mat := BallisticMaterials.of(collider)
	var props := BallisticMaterials.get_props(mat)
	var soft_tissue: bool = props.fx == "flesh" or props.fx == "dummy"
	var e_in := ammo.energy_j(speed) * b.mass_frac
	var info := {
		position = p, normal = normal, material = mat, collider = collider, ammo = ammo,
		speed_in = speed, energy_in = e_in, energy_out = 0.0, deposited = 0.0,
		distance = b.distance, result = "", zone = "", thickness_mm = 0.0, depth_mm = 0.0,
		expanded = false, clogged = b.clogged, deformed = b.deformed, damage = 0.0,
		exit_pos = null, fx = props.fx, direction = dir, bone = "", momentum = 0.0,
		yaw = "", fragmented = b.fragmented,
	}
	if hitbox:
		info.zone = hitbox.zone
		info.bone = hitbox.bone_name

	var out := {}
	var incidence := rad_to_deg(asin(clampf(-dir.dot(normal), 0.0, 1.0)))  # 0 = grazing, 90 = square
	var crit: float = props.ricochet * ammo.ricochet_factor

	if props.hard and ammo.disintegrates_on_hard:
		info.result = "disintegrated"
		b.alive = false
	elif crit > 0.0 and incidence < crit and randf() < (1.0 - incidence / crit) * 1.3:
		# Ricochet: skim off with a flatter angle and some scatter.
		var t := incidence / crit
		var tangent := (dir - normal * dir.dot(normal)).normalized()
		var out_deg := incidence * randf_range(0.2, 0.7)
		var new_dir := (tangent * cos(deg_to_rad(out_deg)) + normal * sin(deg_to_rad(out_deg))).normalized()
		new_dir = _scatter(new_dir, 6.0)
		b.vel = new_dir * speed * lerpf(0.85, 0.55, t)
		if props.hard and ammo.construction != AmmoType.Construction.FMJ and ammo.construction != AmmoType.Construction.SOLID_COPPER:
			b.deformed = true
		b.color = Color(1.0, 0.9, 0.2, 0.9)
		info.result = "ricochet"
		out.exit_pos = p + normal * 0.003
	else:
		# Penetration.
		if soft_tissue and ammo.expands() and not (b.clogged or b.deformed or b.expanded) \
				and AmmoType.ms_to_fps(speed) >= ammo.expand_min_fps:
			b.expanded = true
		var gel_factor: float = props.gel_per_mm
		if hitbox:
			gel_factor *= hitbox.gel_factor
		if props.hard:
			gel_factor *= ammo.hard_barrier_factor
		var ref_in := ammo.gel_expanded_in if b.expanded else ammo.gel_unexpanded_in
		var p_ref := ref_in * 25.4
		var v_ref := ammo.muzzle_ms()
		var capacity := p_ref * maxf(0.0, (speed - V_MIN) / (v_ref - V_MIN))
		var thickness := _thickness(p, dir, collider, b)
		var needed := INF if thickness < 0.0 else thickness * 1000.0 * gel_factor
		info.thickness_mm = maxf(thickness, 0.0) * 1000.0
		if ammo.yaws():
			var r := _rifle_path(b, speed, needed, gel_factor, soft_tissue, props.hard)
			capacity = r.capacity
			p_ref = r.p_ref
			info.yaw = r.yaw
		if capacity <= needed:
			info.result = "stopped"
			info.depth_mm = capacity / gel_factor
			out.stop_pos = p + dir * (info.depth_mm / 1000.0)
			b.alive = false
		else:
			var new_speed := V_MIN + (capacity - needed) / p_ref * (v_ref - V_MIN)
			if ammo.yaws() and not soft_tissue and needed > 20.0:
				b.yawed = true   # knocked off balance by the barrier
			if props.hard and ammo.construction in [AmmoType.Construction.JHP, AmmoType.Construction.LEAD]:
				b.deformed = true
			if props.clogs and ammo.expands() and not b.expanded and randf() < ammo.clog_chance:
				b.clogged = true
			var new_dir := _scatter(dir, props.deflect * randf())
			b.vel = new_dir * new_speed
			b.color = Color(1.0, 0.45, 0.1, 0.9)
			info.result = "penetrated"
			out.exit_pos = p + dir * thickness
			info.exit_pos = out.exit_pos

	var e_out := ammo.energy_j(b.vel.length()) * b.mass_frac if b.alive else 0.0
	info.energy_out = e_out
	info.deposited = maxf(0.0, e_in - e_out)
	info.expanded = b.expanded
	info.clogged = b.clogged
	info.deformed = b.deformed
	info.fragmented = b.fragmented
	info.speed_out = b.vel.length() if b.alive else 0.0
	# Momentum handed to what was hit (kg·m/s): what the bullet lost, along its path.
	info.momentum = ammo.mass_kg() * b.mass_frac * maxf(0.0, speed - info.speed_out)
	info.wound_ratio = _wound_ratio(b) if info.result != "ricochet" else 1.0
	if hitbox and hitbox.receiver and info.result != "ricochet":
		info.damage = DamageModel.damage_for(info.deposited, info.wound_ratio)
		hitbox.receiver.take_hit(info)
	fx.spawn(info)
	impact.emit(info)
	return out


## A rifle bullet's penetration through `needed` gel-mm, phase by phase. Speed is
## the state carried between phases; each phase has its own reference depth:
##  nose-first (gel_nose_in) -> yaw at the neck -> fragmenting (gel_frag_in) or
##  tumbling (gel_unexpanded_in), or in between if it splits. Returns {capacity, p_ref} in the units of the
##  phase it ends in (so the caller's stop/exit maths works unchanged) and `yaw`.
func _rifle_path(b: Bullet, speed: float, needed: float, gel_factor: float, tissue: bool, hard: bool) -> Dictionary:
	var a := b.ammo
	var v_ref := a.muzzle_ms()
	var span := v_ref - V_MIN
	var p_nose := a.gel_nose_in * 25.4
	var p_tumble := a.gel_unexpanded_in * 25.4
	if hard and not b.yawed:
		var p_hard := a.hard_ref_in * 25.4
		return {capacity = p_hard * maxf(0.0, (speed - V_MIN) / span), p_ref = p_hard, yaw = "nose"}
	if b.yawed or not tissue:
		var p := a.gel_frag_in * 25.4 if b.fragmented else p_tumble
		return {capacity = p * maxf(0.0, (speed - V_MIN) / span), p_ref = p, yaw = "tumbling" if b.yawed else "nose"}
	var neck := a.yaw_neck_in * 25.4 * gel_factor   # gel-mm the neck is worth in this tissue
	var cap_nose := p_nose * maxf(0.0, (speed - V_MIN) / span)
	if needed <= neck or cap_nose <= neck:
		# Through before it turns (or stops nose-first, if it's that slow).
		return {capacity = cap_nose, p_ref = p_nose, yaw = "icepick"}
	# It turns at the neck. Speed there:
	var v_neck := V_MIN + (cap_nose - neck) / p_nose * span
	b.yawed = true
	var p_after := p_tumble
	var yaw := "tumbled"
	# What it does when it turns depends on how fast it hit (the published thresholds
	# are impact velocities).
	var impact_fps := AmmoType.ms_to_fps(speed)
	if a.frag_min_fps > 0.0 and impact_fps >= a.frag_min_fps:
		b.fragmented = true
		b.mass_frac = a.frag_retained
		p_after = a.gel_frag_in * 25.4
		yaw = "fragmented"
	elif a.split_min_fps > 0.0 and impact_fps >= a.split_min_fps:
		# Breaks in two at the cannelure: less violent than full fragmentation.
		b.fragmented = true
		b.mass_frac = (a.frag_retained + 1.0) / 2.0
		p_after = (a.gel_frag_in + a.gel_unexpanded_in) / 2.0 * 25.4
		b.split = true
		yaw = "split"
	# Express the whole path in after-yaw units: neck already crossed + what's left.
	var cap_after := p_after * maxf(0.0, (v_neck - V_MIN) / span)
	return {capacity = neck + cap_after, p_ref = p_after, yaw = yaw}


## Diameter of the wound channel relative to bore diameter.
func _wound_ratio(b: Bullet) -> float:
	var a := b.ammo
	if b.split:
		return (a.frag_wound_ratio + a.tumble_wound_ratio) / 2.0
	if b.fragmented:
		return a.frag_wound_ratio
	if b.yawed:
		return a.tumble_wound_ratio
	if b.expanded:
		return a.expanded_in / a.diameter_in
	if a.construction == AmmoType.Construction.LEAD:
		return 1.25 if b.deformed else 1.1
	if b.deformed:
		return 1.15
	return 1.0


## Distance through `collider` along `dir` from the entry point, or -1 if it's thicker than MAX_THICKNESS.
func _thickness(entry: Vector3, dir: Vector3, collider: Object, b: Bullet) -> float:
	var space := get_viewport().get_world_3d().direct_space_state
	var far := entry + dir * MAX_THICKNESS
	var exclude: Array[RID] = [b.shooter]
	for _i in 8:
		var q := PhysicsRayQueryParameters3D.create(far, entry + dir * 0.0005, RAY_MASK, exclude)
		var r := space.intersect_ray(q)
		if r.is_empty():
			return -1.0
		if r.collider == collider:
			return entry.distance_to(r.position)
		exclude.append(r.rid)
	return -1.0


func _scatter(dir: Vector3, max_deg: float) -> Vector3:
	if max_deg <= 0.0:
		return dir
	var axis := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	axis = axis.rotated(dir, randf() * TAU)
	return dir.rotated(axis, deg_to_rad(randf() * max_deg)).normalized()


# ------------------------------------------------------------------ tracers

const TRACER_IGNITE := 12.0   ## m: the trace lights a little way out of the muzzle.
const TRACER_STREAK := 9.0    ## m of glowing streak behind the bullet (what the eye sees).
const TRACER_WIDTH := 0.035


## Glowing streaks for tracer rounds in flight (always visible, not a debug view).
## A camera-facing ribbon back along the bullet's actual path, bright at the head.
func _draw_tracers() -> void:
	_tracer_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var began := false
	for b in bullets:
		if not b.alive or not b.ammo.tracer or b.distance < TRACER_IGNITE or b.distance > b.ammo.tracer_range_m:
			continue
		# Walk back along the trail for the streak.
		var pts: Array[Vector3] = [b.pos]
		var left := minf(TRACER_STREAK, b.distance - TRACER_IGNITE * 0.5)
		var j := b.trail.size() - 1
		while j >= 0 and left > 0.0:
			var q := b.trail[j]
			var d: float = (pts.back() as Vector3).distance_to(q)
			if d < 0.0001:
				j -= 1
				continue
			if d >= left:
				pts.append((pts.back() as Vector3).lerp(q, left / d))
				break
			pts.append(q)
			left -= d
			j -= 1
		if pts.size() < 2:
			continue
		if not began:
			_tracer_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			began = true
		var burn := 1.0 - smoothstep(b.ammo.tracer_range_m * 0.85, b.ammo.tracer_range_m, b.distance)
		var n := pts.size()
		for i in range(n - 1):
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var seg := (p1 - p0).normalized()
			var side0 := seg.cross(eye - p0).normalized()
			var side1 := seg.cross(eye - p1).normalized()
			var k0 := 1.0 - float(i) / float(n - 1)
			var k1 := 1.0 - float(i + 1) / float(n - 1)
			var w0 := TRACER_WIDTH * (0.4 + 0.6 * k0) * maxf(1.0, eye.distance_to(p0) / 30.0)
			var w1 := TRACER_WIDTH * (0.4 + 0.6 * k1) * maxf(1.0, eye.distance_to(p1) / 30.0)
			var c0 := Color(1.0, 0.45 + 0.35 * k0, 0.25 * k0, k0 * burn)
			var c1 := Color(1.0, 0.45 + 0.35 * k1, 0.25 * k1, k1 * burn)
			var v := [p0 + side0 * w0, p0 - side0 * w0, p1 - side1 * w1, p1 + side1 * w1]
			var cs := [c0, c0, c1, c1]
			for idx in [0, 1, 2, 0, 2, 3]:
				_tracer_mesh.surface_set_color(cs[idx])
				_tracer_mesh.surface_add_vertex(v[idx])
		# The burning base: a glowing dot that stays a few pixels wide however far away
		# (seen from behind the gun the streak is end-on, so this is most of what you see).
		var to_eye := (eye - b.pos).normalized()
		var right := to_eye.cross(Vector3.UP if absf(to_eye.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := right.cross(to_eye)
		var hs := maxf(0.03, eye.distance_to(b.pos) * 0.0035)
		var head := Color(1.0, 0.55, 0.25, burn)
		var q := [b.pos - right * hs, b.pos - up * hs, b.pos + right * hs, b.pos + up * hs]   # a diamond
		for idx in [0, 1, 2, 0, 2, 3]:
			_tracer_mesh.surface_set_color(head)
			_tracer_mesh.surface_add_vertex(q[idx])
	if began:
		_tracer_mesh.surface_end()


## How many tracer streaks are being drawn right now (for tests).
func tracers_visible() -> int:
	var n := 0
	for b in bullets:
		if b.alive and b.ammo.tracer and b.distance >= TRACER_IGNITE and b.distance <= b.ammo.tracer_range_m:
			n += 1
	return n


# ------------------------------------------------------------------ debug trails

func _trail_point(b: Bullet, p: Vector3) -> void:
	b.trail.append(p)
	b.trail_colors.append(b.color)


func _draw_trails(delta: float) -> void:
	_trail_mesh.clear_surfaces()
	if not debug_enabled:
		_trails.clear()
		return
	for i in range(_trails.size() - 1, -1, -1):
		_trails[i].t += delta
		if _trails[i].t > TRAIL_LIFE:
			_trails.remove_at(i)
	var sets: Array = []
	for tr in _trails:
		sets.append([tr.points, tr.colors, 1.0 - tr.t / TRAIL_LIFE])
	for b in bullets:
		sets.append([b.trail, b.trail_colors, 1.0])
	var any := false
	for s in sets:
		if (s[0] as PackedVector3Array).size() >= 2:
			any = true
			break
	if not any:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for s in sets:
		var pts: PackedVector3Array = s[0]
		var cols: PackedColorArray = s[1]
		var fade: float = s[2]
		for j in range(1, pts.size()):
			var c := cols[j]
			c.a *= fade
			_trail_mesh.surface_set_color(c)
			_trail_mesh.surface_add_vertex(pts[j - 1])
			_trail_mesh.surface_set_color(c)
			_trail_mesh.surface_add_vertex(pts[j])
	_trail_mesh.surface_end()
