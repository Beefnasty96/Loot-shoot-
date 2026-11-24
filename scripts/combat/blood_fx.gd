class_name BloodFX
extends Node3D
## Blood: wounds that stay on the body (entry/exit holes and a stain that
## spreads through clothing as the wound bleeds), mist at the entry, spray and a
## splatter on whatever is behind an exit wound, drips while bleeding and
## puddles that grow where someone stands or lies. Puddles darken as they dry.
## Blades: a stab leaves a slit and gushes as the blade comes out; a slash leaves
## a long cut, throws blood off along the swing (cast-off on walls and floor).
## Arterial bleeds spurt with the heartbeat (spurt()).
## Owned by Ballistics (Ballistics.blood). Everything is capped for the Thor.

const MAX_SPLATS := 60          ## Wall/floor splatter decals.
const MAX_PUDDLES := 70         ## Drips and pools.
const MAX_SPRAYS := 12
const DECAL_CULL := 0xFFFFF & ~(2 | 4)   ## Not on the player's own model or viewmodel.
const POOL_DEPTH := 0.002       ## m: blood spreads to about 2 mm thick on a floor.
const MERGE_DIST := 0.16        ## m: drips this close to a puddle add to it.
const FRESH := Color(0.40, 0.015, 0.015)
const DRIED := Color(0.16, 0.025, 0.02)
const DRY_TIME := 90.0

var _splat_tex: Array[ImageTexture] = []
var _drop_tex: ImageTexture
var _wound_tex: ImageTexture
var _stain_tex: ImageTexture
var _cut_tex: ImageTexture
var _drop_mat: StandardMaterial3D     ## Round droplet for spray particles (shared).
var _splats: Array[Decal] = []
var _puddles: Array[Dictionary] = []   ## {decal, pos, ml, age}
var _sprays: Array[Node] = []
var _dry_clock := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1911
	for i in 4:
		_splat_tex.append(_make_splat(i * 7 + 3, 9, 0.42))
	_drop_tex = _make_splat(91, 4, 0.7)
	_wound_tex = _make_wound_tex()
	_stain_tex = _make_splat(55, 6, 0.6)
	_cut_tex = _make_cut_tex()
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mat.vertex_color_use_as_albedo = true
	_drop_mat.albedo_texture = _make_droplet()


## A bullet hit a person: holes and stain on the body, mist, exit spray, wall splatter.
## Fills `wound.marks` with the decals so the stain can grow as it bleeds.
func hit(info: Dictionary, wound: Dictionary) -> void:
	if info.get("weapon", "") == "blade":
		_blade_hit(info, wound)
		return
	var hb := info.collider as Node3D
	var pos: Vector3 = info.position
	var normal: Vector3 = info.normal
	var dir: Vector3 = info.get("direction", -normal)
	var ratio: float = info.get("wound_ratio", 1.0)
	var marks: Array = []
	if hb:
		marks.append(_body_decal(hb, pos, normal, _wound_tex, 0.022 * ratio, Color(0.22, 0.02, 0.02)))
		var stain := _body_decal(hb, pos, normal, _stain_tex, 0.03, FRESH)
		marks.append(stain)
		wound.stain = stain
		if info.exit_pos != null:
			var ex: Vector3 = info.exit_pos
			marks.append(_body_decal(hb, ex, dir, _wound_tex, 0.03 * ratio, Color(0.25, 0.02, 0.02)))
			var stain2 := _body_decal(hb, ex, dir, _stain_tex, 0.04, FRESH)
			marks.append(stain2)
			wound.stain_exit = stain2
	wound.marks = marks
	wound.drip_acc = 0.0
	# Back-spatter mist at the entry; a heavier spray out of an exit wound.
	_spray(pos, normal, 6, 1.2, 0.6)
	if info.exit_pos != null:
		var out_j: float = info.get("energy_out", 0.0)
		_spray(info.exit_pos, dir, clampi(int(8 + out_j / 25.0), 8, 26), 2.5 + out_j / 120.0, 1.0)
		_wall_splatter(info.exit_pos, dir, out_j, ratio)


func _blade_hit(info: Dictionary, wound: Dictionary) -> void:
	var hb := info.collider as Node3D
	var pos: Vector3 = info.position
	var normal: Vector3 = info.normal
	var cut: Vector3 = info.get("cut_dir", Vector3.UP)
	var marks: Array = []
	if info.kind == "stab":
		var wmm: float = (info.blade as BladeDef).width_mm if info.has("blade") and info.blade else 38.0
		var width := clampf(wmm * clampf(info.depth_mm / 60.0, 0.3, 1.0), 10.0, wmm) / 1000.0
		if hb:
			marks.append(_body_decal(hb, pos, normal, _cut_tex, width, Color(0.2, 0.01, 0.01), cut, 0.12))
			var stain := _body_decal(hb, pos, normal, _stain_tex, 0.035, FRESH)
			marks.append(stain)
			wound.stain = stain
		# The blade comes out and blood follows it.
		_spray(pos, normal, clampi(int(4 + info.depth_mm / 20.0), 4, 14), 1.2, 0.8)
		drip(pos + normal * 0.06, 4.0 + info.depth_mm * 0.06)
	else:
		var length: float = info.length_mm / 1000.0
		if hb:
			marks.append(_body_decal(hb, pos, normal, _cut_tex, length, Color(0.22, 0.01, 0.01), cut, 0.06))
			var stain := _body_decal(hb, pos, normal, _stain_tex, length * 0.7, FRESH, cut, 0.35)
			marks.append(stain)
			wound.stain = stain
			wound.stain_aspect = 0.35
		# Blood flicks off along the swing: cast-off on whatever is past the cut.
		var swing: Vector3 = info.direction
		_spray(pos, (swing + normal * 0.4).normalized(), clampi(int(6 + info.depth_mm / 3.0), 6, 16), 2.2, 0.8)
		_cast_off(pos, swing, info.depth_mm)
		drip(pos + normal * 0.05, 2.0 + info.length_mm * 0.03)
	wound.marks = marks
	wound.drip_acc = 0.0


## Thrown-off drops in a line along the swing: small splats on walls/floor out to ~2 m.
func _cast_off(from: Vector3, swing: Vector3, depth_mm: float) -> void:
	var space := get_world_3d().direct_space_state
	var n := clampi(int(2 + depth_mm / 6.0), 2, 6)
	for i in n:
		var d := (swing + Vector3(0, -0.15 - 0.2 * i, 0) + Vector3(_rng.randf_range(-0.1, 0.1), 0, _rng.randf_range(-0.1, 0.1))).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + d * (0.8 + 0.4 * i), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var dec := Decal.new()
		dec.texture_albedo = _drop_tex
		dec.cull_mask = DECAL_CULL
		dec.modulate = FRESH
		var s := _rng.randf_range(0.02, 0.05)
		dec.size = Vector3(s, 0.06, s * 2.2)     # elongated along the flight
		add_child(dec)
		dec.global_transform = _surface_basis(hit.position, hit.normal, d)
		_splats.append(dec)
		if _splats.size() > MAX_SPLATS:
			_splats.pop_front().queue_free()


## An arterial bleed pumps: a jet out of the wound that lands a little way off.
func spurt(from: Vector3, normal: Vector3, rate: float) -> void:
	var k := clampf(rate / 20.0, 0.4, 1.5)
	var dir := (normal + Vector3(0, 0.25, 0)).normalized()
	_spray(from, dir, clampi(int(8 * k), 4, 14), 1.6 * k, 0.9)
	var land := from + Vector3(normal.x, 0, normal.z).normalized() * (0.25 + 0.35 * k)
	drip(land + Vector3(0, 0.2, 0), rate * 0.25)


## Grow a wound's stain on the clothes/skin with how much it has bled.
func grow_stain(w: Dictionary) -> void:
	var lost: float = w.get("lost", 0.0)
	var s := clampf(0.03 + sqrt(lost) * 0.014, 0.03, 0.34)
	var aspect: float = w.get("stain_aspect", 1.0)
	for key in ["stain", "stain_exit"]:
		var d: Decal = w.get(key)
		if d and is_instance_valid(d):
			if aspect < 1.0:   # a cut: the stain spreads along the cut and runs down
				d.size = Vector3(maxf(d.size.x, s * 0.8), 0.08, maxf(d.size.x, s * 0.8) / aspect * 0.5 + s * 0.6)
			else:
				d.size = Vector3(s, 0.08, s * 1.25)


## `ml` of blood falls from `from` (world): add it to a puddle below, or start a new one.
func drip(from: Vector3, ml: float) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var at: Vector3 = hit.position
	for p: Dictionary in _puddles:
		var d: Vector3 = p.pos - at
		if absf(d.y) < 0.05 and Vector2(d.x, d.z).length() < MERGE_DIST + _radius(p.ml) * 0.5:
			p.ml += ml
			p.age = 0.0
			_size_puddle(p)
			return
	var dec := Decal.new()
	dec.texture_albedo = _drop_tex if ml < 20.0 else _splat_tex[_rng.randi() % _splat_tex.size()]
	dec.cull_mask = DECAL_CULL
	dec.modulate = FRESH
	add_child(dec)
	dec.global_transform = _surface_basis(at, hit.normal, Vector3.ZERO)
	var p := {decal = dec, pos = at, ml = ml, age = 0.0}
	_size_puddle(p)
	_puddles.append(p)
	if _puddles.size() > MAX_PUDDLES:
		var old: Dictionary = _puddles.pop_front()
		if is_instance_valid(old.decal):
			old.decal.queue_free()


## Total ml in puddles (tests/debug).
func puddle_ml() -> float:
	var t := 0.0
	for p: Dictionary in _puddles:
		t += p.ml
	return t


func _process(delta: float) -> void:
	_dry_clock += delta
	if _dry_clock < 0.5:
		return
	for p: Dictionary in _puddles:
		p.age += _dry_clock
		if is_instance_valid(p.decal):
			p.decal.modulate = FRESH.lerp(DRIED, clampf(p.age / DRY_TIME, 0.0, 1.0))
	_dry_clock = 0.0


# ------------------------------------------------------------------ internals

static func _radius(ml: float) -> float:
	return clampf(sqrt(ml * 1e-6 / (PI * POOL_DEPTH)), 0.018, 0.7)


func _size_puddle(p: Dictionary) -> void:
	var r := _radius(p.ml)
	if is_instance_valid(p.decal):
		p.decal.size = Vector3(r * 2.2, 0.03, r * 2.2)   # thin: stains the floor, barely the shoes


## Decal on a body part. `along` + `aspect` make it long and thin (a cut): size runs along `along`, width = size × aspect.
func _body_decal(parent: Node3D, pos: Vector3, normal: Vector3, tex: Texture2D, size: float, col: Color, along := Vector3.ZERO, aspect := 1.0) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.modulate = col
	d.cull_mask = DECAL_CULL
	d.size = Vector3(size * aspect, 0.08, size) if along != Vector3.ZERO else Vector3(size, 0.08, size)
	parent.add_child(d)          # rides on the hitbox, so it follows the bone and the ragdoll
	d.global_transform = _surface_basis(pos, normal, along)
	return d


func _wall_splatter(from: Vector3, dir: Vector3, energy_out: float, ratio: float) -> void:
	var space := get_world_3d().direct_space_state
	var reach := 1.5 + energy_out / 150.0
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var dist := from.distance_to(hit.position)
	var size := clampf((0.12 + energy_out / 1500.0) * ratio * (0.6 + dist * 0.5), 0.1, 0.6)
	var cosi := absf(dir.dot(hit.normal))
	var d := Decal.new()
	d.texture_albedo = _splat_tex[_rng.randi() % _splat_tex.size()]
	d.cull_mask = DECAL_CULL
	d.modulate = FRESH
	# Glancing hits smear out along the shot.
	d.size = Vector3(size, 0.1, size / maxf(cosi, 0.35))
	add_child(d)
	d.global_transform = _surface_basis(hit.position, hit.normal, dir)
	_splats.append(d)
	if _splats.size() > MAX_SPLATS:
		_splats.pop_front().queue_free()


## Decal transform on a surface: its Y along the normal, Z along `along` (projected), else random spin.
func _surface_basis(pos: Vector3, normal: Vector3, along: Vector3) -> Transform3D:
	var y := normal.normalized()
	var z := along - y * along.dot(y)
	if z.length() < 0.01:
		var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
		z = ref.cross(y).normalized().rotated(y, _rng.randf() * TAU)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), pos)


func _spray(pos: Vector3, dir: Vector3, amount: int, speed: float, size: float) -> void:
	if _sprays.size() >= MAX_SPRAYS:
		var old: Node = _sprays.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.6
	p.direction = dir
	p.spread = 22.0
	p.gravity = Vector3(0, -9.8, 0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.5 * size
	p.scale_amount_max = 1.3 * size
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	quad.material = _drop_mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.02, 0.02, 0.95))
	ramp.set_color(1, Color(0.3, 0.01, 0.01, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.global_position = pos + dir * 0.01
	p.emitting = true
	_sprays.append(p)
	p.finished.connect(func():
		_sprays.erase(p)
		p.queue_free())


## White splat (modulated red): a soft central blob with satellite droplets.
func _make_splat(seed_v: int, satellites: int, core: float) -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var s := 64
	var blobs: Array = [[Vector2(0.5, 0.5), core * 0.5]]
	for i in 5:   # lumpy core
		blobs.append([Vector2(0.5, 0.5) + Vector2.from_angle(r.randf() * TAU) * core * 0.3, core * r.randf_range(0.2, 0.35)])
	for i in satellites:
		var a := r.randf() * TAU
		blobs.append([Vector2(0.5, 0.5) + Vector2.from_angle(a) * r.randf_range(core * 0.55, 0.47), r.randf_range(0.015, 0.05)])
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var uv := Vector2((x + 0.5) / s, (y + 0.5) / s)
			var a := 0.0
			for b: Array in blobs:
				var d: float = uv.distance_to(b[0]) / b[1]
				a = maxf(a, clampf((1.0 - d) * 6.0, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, a * 0.92))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Soft round droplet (white; particles tint it).
func _make_droplet() -> ImageTexture:
	var s := 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length() / (s / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 2.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## A cut: dark, slightly ragged line along V with a red margin (stretched by the decal size).
func _make_cut_tex() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 1219
	var w := 16
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v := (y + 0.5) / h
		var taper := clampf(sin(PI * v) * 1.3, 0.0, 1.0)            # pointed ends
		var jitter := r.randf_range(-0.6, 0.6)
		for x in w:
			var u := absf((x + 0.5 + jitter) / w - 0.5) * 2.0
			var core := clampf((0.35 * taper - u) * 8.0, 0.0, 1.0)
			var rim := clampf((0.9 * taper - u) * 3.0, 0.0, 1.0)
			var c := Color(0.12, 0.12, 0.12, 1.0).lerp(Color(1, 1, 1, rim * 0.8), 1.0 - core)
			if rim <= 0.0 and core <= 0.0:
				c = Color(1, 1, 1, 0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Bullet hole in skin/cloth: dark centre, red-brown ring.
func _make_wound_tex() -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length() / (s / 2.0)
			var c := Color(0.1, 0.1, 0.1, 1.0) if d < 0.3 else Color(1, 1, 1, clampf((1.0 - d) / 0.7, 0.0, 1.0) * 0.85)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
