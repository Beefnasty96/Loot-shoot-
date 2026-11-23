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
## Every impact emits `impact(info)` with speeds, energies (J and ft-lbs) and outcome.

signal impact(info: Dictionary)

const GRAVITY := 9.81
const AIR_DENSITY := 1.225
const SPEED_OF_SOUND := 343.0
const V_MIN := 55.0          ## m/s: below this a pistol bullet no longer penetrates tissue.
const MAX_LIFE := 5.0
const MAX_THICKNESS := 2.0   ## m: anything thicker stops the bullet.
const RAY_MASK := 1 | 2 | 4  ## world, characters, hitboxes
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
	var expanded := false
	var clogged := false
	var deformed := false
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
var fx: ImpactFX


func _ready() -> void:
	fx = ImpactFX.new()
	add_child(fx)
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


## Fire one bullet. `velocity_factor` scales muzzle velocity for barrels shorter/longer than the reference.
func fire(origin: Vector3, direction: Vector3, ammo: AmmoType, shooter: RID, velocity_factor := 1.0) -> Bullet:
	var b := Bullet.new()
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


func _step(b: Bullet, dt: float) -> void:
	b.time += dt
	var speed := b.vel.length()
	if speed < 25.0 or b.time > MAX_LIFE or b.pos.y < -30.0:
		b.alive = false
		return
	var acc := -drag_k(b.ammo, speed) * speed * b.vel + Vector3.DOWN * GRAVITY
	var new_vel := b.vel + acc * dt
	var to := b.pos + (b.vel + new_vel) * 0.5 * dt
	b.vel = new_vel
	_trace(b, b.pos, to)


func _trace(b: Bullet, from: Vector3, to: Vector3) -> void:
	var space := get_viewport().get_world_3d().direct_space_state
	for _i in MAX_EVENTS_PER_TICK:
		var q := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK, [b.shooter])
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
	var e_in := ammo.energy_j(speed)
	var info := {
		position = p, normal = normal, material = mat, collider = collider, ammo = ammo,
		speed_in = speed, energy_in = e_in, energy_out = 0.0, deposited = 0.0,
		distance = b.distance, result = "", zone = "", thickness_mm = 0.0, depth_mm = 0.0,
		expanded = false, clogged = b.clogged, deformed = b.deformed, damage = 0.0,
		exit_pos = null, fx = props.fx,
	}
	if hitbox:
		info.zone = hitbox.zone

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
		if capacity <= needed:
			info.result = "stopped"
			info.depth_mm = capacity / gel_factor
			out.stop_pos = p + dir * (info.depth_mm / 1000.0)
			b.alive = false
		else:
			var new_speed := V_MIN + (capacity - needed) / p_ref * (v_ref - V_MIN)
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

	var e_out := ammo.energy_j(b.vel.length()) if b.alive else 0.0
	info.energy_out = e_out
	info.deposited = maxf(0.0, e_in - e_out)
	info.expanded = b.expanded
	info.clogged = b.clogged
	info.deformed = b.deformed
	info.speed_out = b.vel.length() if b.alive else 0.0
	if hitbox and hitbox.receiver and info.result != "ricochet":
		info.damage = DamageModel.damage_for(info.deposited, _wound_ratio(b))
		hitbox.receiver.take_hit(info)
	fx.spawn(info)
	impact.emit(info)
	return out


## Diameter of the wound channel relative to bore diameter.
func _wound_ratio(b: Bullet) -> float:
	var a := b.ammo
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
