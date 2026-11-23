class_name BloodFX
extends Node3D
## Blood: wounds that stay on the body (entry/exit holes and a stain that
## spreads through clothing as the wound bleeds), mist at the entry, spray and a
## splatter on whatever is behind an exit wound, drips while bleeding and
## puddles that grow where someone stands or lies. Puddles darken as they dry.
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


## A bullet hit a person: holes and stain on the body, mist, exit spray, wall splatter.
## Fills `wound.marks` with the decals so the stain can grow as it bleeds.
func hit(info: Dictionary, wound: Dictionary) -> void:
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


## Grow a wound's stain on the clothes/skin with how much it has bled.
func grow_stain(w: Dictionary) -> void:
	var lost: float = w.get("lost", 0.0)
	var s := clampf(0.03 + sqrt(lost) * 0.014, 0.03, 0.34)
	for key in ["stain", "stain_exit"]:
		var d: Decal = w.get(key)
		if d and is_instance_valid(d):
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


func _body_decal(parent: Node3D, pos: Vector3, normal: Vector3, tex: Texture2D, size: float, col: Color) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.modulate = col
	d.cull_mask = DECAL_CULL
	d.size = Vector3(size, 0.08, size)
	parent.add_child(d)          # rides on the hitbox, so it follows the bone and the ragdoll
	d.global_transform = _surface_basis(pos, normal, Vector3.ZERO)
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
	quad.size = Vector2(0.025, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	quad.material = m
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.02, 0.02, 0.95))
	ramp.set_color(1, Color(0.3, 0.01, 0.01, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.global_position = pos + dir * 0.01
	p.emitting = true
	_sprays.append(p)
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(p):
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
