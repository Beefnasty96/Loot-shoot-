class_name GlassPane
extends Node3D
## A pane of glass that cracks, then breaks into pieces.
##
## The pane is cut into 6-12 shards (Voronoi cells of random points, so they
## tile it exactly). Each shard is its own collider with ballistic material
## "glass". A bullet that goes through leaves a hole with a spider-web crack
## on the shard it hit; after 2-4 holes (rolled per pane) the pane lets go:
## the shards nearest the last hit fall out as loose pieces (rigid bodies that
## land and tinkle), the rest stay in the frame. Hitting a shard still left in
## a broken pane knocks it out.
##
## Until it breaks, the pane draws as one mesh (one draw call, like a plain
## window); the shard meshes only show once it's broken.
##
## Local space: X along the width, Y up, Z through the glass.

const DENSITY := 2500.0          ## kg/m3
const MAX_LOOSE := 72            ## Loose pieces in the whole scene before the oldest are cleared.

static var _loose: Array[Node] = []
static var _crack_mat: StandardMaterial3D
static var _shard_mats := {}

var size := Vector2(1.0, 1.0)
var thickness := 0.006
var material: Material
var respawn := 0.0               ## Seconds until it's whole again (range); 0 = stays broken.
var shard_count := 0             ## 0 = roll 6-12.
var hits_to_break := 0           ## 0 = roll 2-4.
var seed_value := 0              ## 0 = random.

var hits := 0
var shattered := false
var shards: Array[StaticBody3D] = []

var _rng := RandomNumberGenerator.new()
var _whole: MeshInstance3D
var _rolled_shards := 0
var _rolled_hits := 0
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	set_meta("stay_broken", true)       # keeps LevelKit.batch_meshes off it
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_rolled_shards = shard_count if shard_count > 0 else _rng.randi_range(6, 12)
	_rolled_hits = hits_to_break if hits_to_break > 0 else _rng.randi_range(2, 4)
	if material == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.82, 0.9, 0.28)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.3
		material = m
	_build()


## Hits this pane can take before it goes (rolled 2-4).
func breaks_after() -> int:
	return _rolled_hits


func _build() -> void:
	hits = 0
	shattered = false
	shards.clear()
	_whole = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, thickness)
	_whole.mesh = bm
	_whole.material_override = material
	add_child(_whole)
	for poly in _cells(_rolled_shards):
		shards.append(_make_shard(poly))


# ------------------------------------------------------------------ cutting

## Voronoi cells of well-spread random points, clipped to the pane.
func _cells(n: int) -> Array:
	var hw := size.x / 2.0
	var hh := size.y / 2.0
	var pts: Array[Vector2] = []
	var min_d := sqrt(size.x * size.y / n) * 0.55
	var tries := 0
	while pts.size() < n and tries < 2000:
		tries += 1
		var p := Vector2(_rng.randf_range(-hw, hw), _rng.randf_range(-hh, hh))
		var ok := true
		for q in pts:
			if p.distance_to(q) < min_d:
				ok = false
				break
		if ok or tries > 1500:
			pts.append(p)
	var rect := PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
	var out: Array = []
	for i in pts.size():
		var poly := rect
		for j in pts.size():
			if i == j:
				continue
			poly = _clip(poly, (pts[i] + pts[j]) / 2.0, pts[j] - pts[i])
			if poly.size() < 3:
				break
		if poly.size() >= 3:
			out.append(poly)
	return out


## Keep the part of a convex polygon on the side of the line through `m` away from `n`.
static func _clip(poly: PackedVector2Array, m: Vector2, n: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var da := (a - m).dot(n)
		var db := (b - m).dot(n)
		if da <= 0.0:
			out.append(a)
		if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


static func area_of(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) / 2.0


static func centroid_of(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / poly.size()


func _make_shard(poly: PackedVector2Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("material", "glass")
	body.set_meta("glass_pane", self)
	body.set_meta("poly", poly)
	var t := thickness / 2.0
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(p.x, p.y, t))
		pts.append(Vector3(p.x, p.y, -t))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _prism(poly, thickness)
	mi.material_override = _shard_material(material)
	mi.visible = false
	body.add_child(mi)
	add_child(body)
	return body


static func _prism(poly: PackedVector2Array, th: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := th / 2.0
	var n := poly.size()
	for i in range(1, n - 1):
		for v in [poly[0], poly[i], poly[i + 1]]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3(v.x, v.y, t))
		for v in [poly[0], poly[i + 1], poly[i]]:
			st.set_normal(Vector3.FORWARD)
			st.add_vertex(Vector3(v.x, v.y, -t))
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var e := b - a
		var nn := Vector3(e.y, -e.x, 0).normalized()
		for v in [Vector3(a.x, a.y, t), Vector3(b.x, b.y, t), Vector3(b.x, b.y, -t), Vector3(a.x, a.y, t), Vector3(b.x, b.y, -t), Vector3(a.x, a.y, -t)]:
			st.set_normal(nn)
			st.add_vertex(v)
	return st.commit()


## The pane's material with backface culling off (pieces tumble and show both sides).
static func _shard_material(m: Material) -> Material:
	var id := m.get_instance_id()
	if not _shard_mats.has(id):
		var d: Material = m.duplicate()
		if d is BaseMaterial3D:
			(d as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		_shard_mats[id] = d
	return _shard_mats[id]


# ------------------------------------------------------------------ hits

## A bullet went into (or through) `shard`. info: the Ballistics impact dictionary.
func hit(shard: Object, info: Dictionary) -> void:
	var body := shard as StaticBody3D
	if body == null or not is_instance_valid(body) or body.get_parent() != self:
		return
	var p: Vector3 = to_local(info.get("position", body.global_position))
	var dir: Vector3 = info.get("direction", -global_basis.z)
	if shattered:
		_drop(body, dir, 1.0)
		return
	hits += 1
	_mark(body, Vector2(p.x, p.y))
	if hits >= _rolled_hits:
		_shatter(Vector2(p.x, p.y), dir)


func _mark(body: StaticBody3D, at: Vector2) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var s := _rng.randf_range(0.14, 0.24)
	qm.size = Vector2(s, s)
	q.mesh = qm
	q.material_override = _crack_material()
	q.position = Vector3(at.x, at.y, 0.0)
	q.rotation.z = _rng.randf() * TAU
	q.name = "Hole"
	body.add_child(q)


func _shatter(at: Vector2, dir: Vector3) -> void:
	shattered = true
	_whole.visible = false
	for s in shards:
		if is_instance_valid(s):
			s.get_node("Mesh").visible = true
	# Nearest the hit go first; pieces along the frame hang on longer.
	var hw := size.x / 2.0
	var hh := size.y / 2.0
	var scored: Array = []
	var far := 0.01
	for s in shards:
		var poly: PackedVector2Array = s.get_meta("poly")
		var d := centroid_of(poly).distance_to(at)
		far = maxf(far, d)
		var edge := false
		for v in poly:
			if absf(absf(v.x) - hw) < 0.002 or absf(absf(v.y) - hh) < 0.002:
				edge = true
		scored.append([d * _rng.randf_range(0.75, 1.3) + (0.25 * size.length() * 0.3 if edge else 0.0), s, d])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var n := scored.size()
	var falling := clampi(int(round(n * _rng.randf_range(0.5, 0.85))), 1, n - 1)
	for i in falling:
		_drop(scored[i][1], dir, 1.0 - scored[i][2] / (far * 1.2))
	_burst(to_global(Vector3(at.x, at.y, 0)), dir)
	if respawn > 0.0:
		get_tree().create_timer(respawn).timeout.connect(_restore)


## Knock a shard out of the frame as a loose piece.
func _drop(body: StaticBody3D, dir: Vector3, push: float) -> void:
	if not is_instance_valid(body):
		return
	shards.erase(body)
	var poly: PackedVector2Array = body.get_meta("poly")
	var rb := RigidBody3D.new()
	rb.collision_layer = 8          # loose debris: the world, not people or bullets
	rb.collision_mask = 1
	rb.mass = maxf(0.03, area_of(poly) * thickness * DENSITY)
	rb.set_meta("material", "glass")
	rb.set_meta("from_pane", self)
	var host: Node = get_parent() if get_parent() else self
	var xf := body.global_transform
	host.add_child(rb)
	rb.global_transform = xf
	for c in body.get_children():
		c.reparent(rb, false)
	var mesh_node := rb.get_node_or_null("Mesh")
	if mesh_node:
		mesh_node.visible = true
	body.queue_free()
	var flat := dir.normalized()
	rb.linear_velocity = flat * _rng.randf_range(0.4, 2.2) * clampf(push, 0.15, 1.0) + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.1, 0.4), _rng.randf_range(-0.3, 0.3))
	rb.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
	if _rng.randf() < 0.5 and ResourceLoader.exists("res://assets/audio/glass_tinkle.wav"):
		rb.contact_monitor = true
		rb.max_contacts_reported = 1
		var ap := AudioStreamPlayer3D.new()
		ap.stream = load("res://assets/audio/glass_tinkle.wav")
		ap.unit_size = 3.0
		rb.add_child(ap)
		rb.body_entered.connect(func(_b):
			if is_instance_valid(ap) and not rb.has_meta("landed"):
				rb.set_meta("landed", true)
				ap.pitch_scale = randf_range(0.85, 1.25)
				ap.play(), CONNECT_ONE_SHOT)
	_loose.append(rb)
	while _loose.size() > MAX_LOOSE:
		var old: Node = _loose.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _burst(pos: Vector3, dir: Vector3) -> void:
	if _audio == null:
		_audio = AudioStreamPlayer3D.new()
		_audio.unit_size = 8.0
		_audio.max_db = 4.0
		add_child(_audio)
	if ResourceLoader.exists("res://assets/audio/glass_shatter.wav"):
		_audio.stream = load("res://assets/audio/glass_shatter.wav")
		_audio.pitch_scale = _rng.randf_range(0.9, 1.1)
		_audio.global_position = pos
		_audio.play()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 40
	p.lifetime = 0.9
	p.direction = dir
	p.spread = 55.0
	p.gravity = Vector3(0, -9.8, 0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 3.5
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.012)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.93, 1.0, 0.7)
	quad.material = m
	p.mesh = quad
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## Whole again (shooting range panels).
func _restore() -> void:
	if not is_instance_valid(self):
		return
	for c in get_children():
		if c is StaticBody3D or c == _whole:
			c.queue_free()
	for rb in _loose.duplicate():
		if is_instance_valid(rb) and rb.get_meta("from_pane", null) == self:
			_loose.erase(rb)
			rb.queue_free()
	_rolled_hits = hits_to_break if hits_to_break > 0 else _rng.randi_range(2, 4)
	_rolled_shards = shard_count if shard_count > 0 else _rng.randi_range(6, 12)
	_build()


# ------------------------------------------------------------------ crack texture

static func _crack_material() -> StandardMaterial3D:
	if _crack_mat:
		return _crack_mat
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var c := Vector2(s / 2.0, s / 2.0)
	# Radial cracks, a little crooked.
	for i in 11:
		var ang := TAU * i / 11.0 + r.randf_range(-0.2, 0.2)
		var p := c
		var length := r.randf_range(0.6, 1.0) * s / 2.0
		var step := 0.0
		while step < length:
			ang += r.randf_range(-0.12, 0.12)
			p += Vector2(cos(ang), sin(ang))
			step += 1.0
			var a := 0.85 * (1.0 - step / length) + 0.15
			_plot(img, p, Color(0.95, 0.97, 1.0, a))
	# Concentric breaks between the spokes.
	for ring_r in [9.0, 18.0, 30.0]:
		var n := int(ring_r * 4)
		for k in n:
			if r.randf() < 0.35:
				continue
			var ang := TAU * k / n
			var rr: float = ring_r + r.randf_range(-1.5, 1.5)
			_plot(img, c + Vector2(cos(ang), sin(ang)) * rr, Color(0.95, 0.97, 1.0, 0.45 * (1.0 - rr / 40.0) + 0.1))
	# The hole: crushed white rim, dark centre.
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c)
			if d < 3.0:
				img.set_pixel(x, y, Color(0.05, 0.05, 0.06, 0.95))
			elif d < 6.5:
				img.set_pixel(x, y, Color(0.92, 0.95, 1.0, 0.85))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.2
	m.render_priority = 1
	_crack_mat = m
	return m


static func _plot(img: Image, p: Vector2, col: Color) -> void:
	var x := int(p.x)
	var y := int(p.y)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var old := img.get_pixel(x, y)
	if col.a > old.a:
		img.set_pixel(x, y, col)
