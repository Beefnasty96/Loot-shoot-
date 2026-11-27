class_name LevelKit
extends Node3D
## Building blocks for code-built levels: procedural early-2000s-style textures,
## boxes with ballistic materials, walls with door/window openings (real wall
## build-ups so bullets go through drywall but not brick), hinged doors,
## breakable windows, gable roofs, room lights and simple furniture.
## Designed in feet like a floor plan (ft() converts), built in metres.

const FT := 0.3048
const IN := 0.0254
const CEILING := 8.0 * FT
const INT_WALL := 4.5 * IN          ## 2x4 studs + 1/2 in drywall both sides.
const EXT_WALL := 6.0 * IN          ## Siding, OSB, batts, drywall.
const DOOR_H := 80.0 * IN           ## 6 ft 8 in.

var _mats := {}
var _rng := RandomNumberGenerator.new()
## Height of the storey being built: box(), cylinder(), wall() and room() add it to their y, so a second
## floor is built with the same calls as the first. Parented boxes are local to their parent and don't.
var floor_y := 0.0


static func ft(v: float) -> float:
	return v * FT


# ------------------------------------------------------------------ textures & materials

## Cached material by name; `make` builds it the first time.
func mat(name: String, make: Callable) -> StandardMaterial3D:
	if not _mats.has(name):
		_mats[name] = make.call()
	return _mats[name]


func flat(name: String, c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	return mat(name, func():
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		return m)


## Textured material, world-space triplanar so any box size tiles evenly. `metres` = one texture repeat.
func textured(name: String, img: Image, metres: float, rough := 0.85) -> StandardMaterial3D:
	return mat(name, func():
		img.generate_mipmaps()
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / metres
		m.roughness = rough
		return m)


func img_noise(c: Color, amount: float, size := 32, seed_v := 1) -> Image:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var k := r.randf_range(-amount, amount)
			img.set_pixel(x, y, Color(c.r + k, c.g + k, c.b + k))
	return img


## Horizontal boards (vinyl siding, wood paneling has vertical grooves: set vertical).
func img_boards(c: Color, groove: Color, boards: int, vertical := false, size := 64, grain := 0.03) -> Image:
	var r := RandomNumberGenerator.new()
	r.seed = boards * 7 + (1 if vertical else 0)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var bh := size / boards
	for y in size:
		for x in size:
			var a := x if vertical else y
			var b := y if vertical else x
			var col := c
			var shade := r.randf_range(-grain, grain) + sin(b * 0.35 + a * 0.05) * grain * 0.5
			col = Color(col.r + shade, col.g + shade, col.b + shade)
			if a % bh == 0:
				col = groove
			elif a % bh == bh - 1 and not vertical:
				col = c.darkened(0.12)        # shadow under each siding lap
			img.set_pixel(x, y, col)
	return img


func img_checker(a: Color, b: Color, size := 32, cells := 4) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var cs := size / cells
	for y in size:
		for x in size:
			var c := a if ((x / cs) + (y / cs)) % 2 == 0 else b
			if x % cs == 0 or y % cs == 0:
				c = c.darkened(0.15)
			img.set_pixel(x, y, c)
	return img


func img_brick(brick: Color, mortar: Color, size := 64) -> Image:
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rows := 8
	var rh := size / rows
	for y in size:
		var row := y / rh
		var off := (rh * 2) if row % 2 == 0 else 0
		for x in size:
			var bx := (x + off) % (size / 2)
			var c := brick
			if y % rh == 0 or bx == 0:
				c = mortar
			else:
				var k := r.randf_range(-0.05, 0.05)
				c = Color(c.r + k, c.g + k * 0.6, c.b + k * 0.5)
			img.set_pixel(x, y, c)
	return img


## Small repeating flower print on a ground colour (1995 sofas and wallpaper).
func img_floral(ground: Color, petal: Color, leaf: Color, size := 32) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(ground)
	var centres := [Vector2(8, 8), Vector2(24, 24), Vector2(24, 6), Vector2(8, 26)]
	for c: Vector2 in centres:
		for y in size:
			for x in size:
				var d := Vector2(x, y).distance_to(c)
				if d < 2.0:
					img.set_pixel(x, y, petal.darkened(0.3))
				elif d < 4.2 and fmod(atan2(y - c.y, x - c.x) * 5.0 / TAU + 10.0, 1.0) < 0.6:
					img.set_pixel(x, y, petal)
				elif d < 5.5 and absf(x - c.x - 3.0) < 1.0:
					img.set_pixel(x, y, leaf)
	return img


# ------------------------------------------------------------------ geometry

## Box with collision and a ballistic material. collide=false -> just the mesh (trim, paint, rugs).
func box(size: Vector3, pos: Vector3, m: Material, ballistic := "concrete", rot_y_deg := 0.0, collide := true, parent: Node = null) -> Node3D:
	var host: Node = parent if parent else self
	if parent == null:
		pos.y += floor_y
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	if not collide:
		mi.position = pos
		mi.rotation_degrees.y = rot_y_deg
		host.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.set_meta("material", ballistic)
	body.position = pos
	body.rotation_degrees.y = rot_y_deg
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	host.add_child(body)
	return body


func cylinder(radius: float, height: float, pos: Vector3, m: Material, ballistic := "wood", collide := true) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	pos.y += floor_y
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	if not collide:
		mi.position = pos
		add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.set_meta("material", ballistic)
	body.position = pos
	body.add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


## A wall between two points on the floor plan (axis-aligned), with openings.
## layers: [[thickness, ballistic, material], ...] from the `inside` face outward. inside = +1/-1 along the
## wall's normal (+Z for walls along X, +X for walls along Z). Openings (distances from `a` along the wall):
##   {at, w, kind = "door"|"window"|"open", sill, head, door = {...Door properties}}
func wall(a: Vector2, b: Vector2, layers: Array, inside := 1.0, openings: Array = [], height := CEILING) -> void:
	var along_x := absf(b.y - a.y) < 0.001
	var length := absf((b.x - a.x) if along_x else (b.y - a.y))
	var start := minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var total_t := 0.0
	for l: Array in layers:
		total_t += l[0]
	# Spans of solid wall between openings, plus the bits above/below each opening.
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return p.at < q.at)
	var cursor := 0.0
	var pieces: Array = []   # [from, to, y0, y1]
	for o: Dictionary in ops:
		var o0: float = o.at - o.w / 2.0
		var o1: float = o.at + o.w / 2.0
		if o0 > cursor:
			pieces.append([cursor, o0, 0.0, height])
		var head: float = o.get("head", DOOR_H if o.kind != "window" else 82.0 * IN)
		var sill: float = o.get("sill", 0.0 if o.kind != "window" else 36.0 * IN)
		if head < height:
			pieces.append([o0, o1, head, height])
		if sill > 0.0:
			pieces.append([o0, o1, 0.0, sill])
		cursor = o1
		var mid := start + float(o.at)
		var centre := Vector3(mid, 0.0, a.y) if along_x else Vector3(a.x, 0.0, mid)
		match o.kind:
			"window":
				_window(centre, o.w, sill, head, along_x, total_t)
			"door":
				var d := Door.new()
				d.width = o.w - 0.02
				d.height = head - 0.01
				for k in o.get("door", {}):
					d.set(k, o.door[k])
				d.position = centre + Vector3(0, floor_y, 0)
				d.rotation.y = 0.0 if along_x else PI / 2.0
				add_child(d)
				_trim_frame(centre, o.w, head, along_x, total_t)
			"open":
				_trim_frame(centre, o.w, head, along_x, total_t)
	if cursor < length:
		pieces.append([cursor, length, 0.0, height])
	for p: Array in pieces:
		var acc := 0.0
		for l: Array in layers:
			var t: float = l[0]
			var normal_off: float = (total_t / 2.0 - acc - t / 2.0) * inside
			acc += t
			var size: Vector3 = Vector3(p[1] - p[0], p[3] - p[2], t) if along_x else Vector3(t, p[3] - p[2], p[1] - p[0])
			var c: float = start + (p[0] + p[1]) / 2.0
			var pos: Vector3 = Vector3(c, (p[2] + p[3]) / 2.0, a.y + normal_off) if along_x else Vector3(a.x + normal_off, (p[2] + p[3]) / 2.0, c)
			box(size, pos, l[2], l[1])


## Glass pane (breaks and stays broken) with a white frame and a sill.
func _window(centre: Vector3, w: float, sill: float, head: float, along_x: bool, wall_t: float) -> void:
	var glass := mat("glass", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.82, 0.9, 0.28)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.3
		return m)
	var h := head - sill
	var pane := box(Vector3(w - 0.06, h - 0.06, 0.006) if along_x else Vector3(0.006, h - 0.06, w - 0.06), centre + Vector3(0, sill + h / 2.0, 0), glass, "glass")
	pane.set_meta("stay_broken", true)
	var trim := flat("trim", Color(0.95, 0.94, 0.9), 0.5)
	# Muntin cross (a 1995 builder-grade colonial grid).
	box(Vector3(w, 0.025, 0.02) if along_x else Vector3(0.02, 0.025, w), centre + Vector3(0, sill + h / 2.0, 0), trim, "wood", 0.0, false)
	box(Vector3(0.025, h, 0.02) if along_x else Vector3(0.02, h, 0.025), centre + Vector3(0, sill + h / 2.0, 0), trim, "wood", 0.0, false)
	_trim_frame(centre, w, head, along_x, wall_t, sill)
	box(Vector3(w + 0.1, 0.03, wall_t + 0.06) if along_x else Vector3(wall_t + 0.06, 0.03, w + 0.1), centre + Vector3(0, sill, 0), trim, "wood", 0.0, false)


## Casing around an opening, both faces of the wall.
func _trim_frame(centre: Vector3, w: float, head: float, along_x: bool, wall_t: float, sill := 0.0) -> void:
	var trim := flat("trim", Color(0.95, 0.94, 0.9), 0.5)
	var depth := wall_t + 0.02
	var h := head - sill
	for side in [-1.0, 1.0]:
		var off := Vector3(side * (w / 2.0 + 0.03), sill + h / 2.0, 0.0) if along_x else Vector3(0.0, sill + h / 2.0, side * (w / 2.0 + 0.03))
		box(Vector3(0.06, h, depth) if along_x else Vector3(depth, h, 0.06), centre + off, trim, "wood", 0.0, false)
	box(Vector3(w + 0.12, 0.07, depth) if along_x else Vector3(depth, 0.07, w + 0.12), centre + Vector3(0, head + 0.035, 0), trim, "wood", 0.0, false)


## Floor finish (no collision; the slab underneath has it) and ceiling for a rectangular room.
func room(x0: float, z0: float, x1: float, z1: float, floor_m: Material, ceiling := true, light := 1.0) -> void:
	if floor_m != null:
		box(Vector3(x1 - x0, 0.02, z1 - z0), Vector3((x0 + x1) / 2.0, 0.01, (z0 + z1) / 2.0), floor_m, "concrete", 0.0, false)
	if ceiling:
		var popcorn := textured("popcorn", img_noise(Color(0.9, 0.89, 0.86), 0.05, 32, 4), 0.5, 1.0)
		box(Vector3(x1 - x0, 0.02, z1 - z0), Vector3((x0 + x1) / 2.0, CEILING + 0.01, (z0 + z1) / 2.0), popcorn, "drywall", 0.0, false)
	if light > 0.0:
		var l := OmniLight3D.new()
		l.position = Vector3((x0 + x1) / 2.0, floor_y + CEILING - 0.25, (z0 + z1) / 2.0)
		l.light_color = Color(1.0, 0.9, 0.75)      # incandescent bulbs
		l.light_energy = light
		l.omni_range = maxf(x1 - x0, z1 - z0) * 0.9 + 1.5
		l.omni_attenuation = 1.2
		add_child(l)
		# The fixture: a frosted dome.
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.12
		dome.mesh = sm
		dome.material_override = mat("fixture", func():
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1, 0.97, 0.9)
			m.emission_enabled = true
			m.emission = Color(1, 0.92, 0.8)
			m.emission_energy_multiplier = 0.8
			return m)
		dome.position = Vector3(l.position.x, floor_y + CEILING - 0.03, l.position.z)
		add_child(dome)


## Simple gable roof over a rectangle, ridge along X.
func gable_roof(x0: float, z0: float, x1: float, z1: float, base_y: float, pitch_deg: float, m: Material, overhang := 0.45) -> void:
	var depth := (z1 - z0) / 2.0 + overhang
	var rise := tan(deg_to_rad(pitch_deg)) * ((z1 - z0) / 2.0)
	var slope_len := depth / cos(deg_to_rad(pitch_deg))
	var mid_z := (z0 + z1) / 2.0
	for side in [-1.0, 1.0]:
		var body := box(Vector3(x1 - x0 + overhang * 2.0, 0.12, slope_len), Vector3((x0 + x1) / 2.0, base_y + rise / 2.0, mid_z + side * depth / 2.0), m, "exterior_sheathing")
		body.rotation_degrees.x = side * pitch_deg
	# Gable ends: triangles approximated with stacked boxes of siding.
	var siding: Material = _mats["siding"] if _mats.has("siding") else flat("siding_flat", Color(0.85, 0.83, 0.75))
	var steps := 6
	for i in steps:
		var y := base_y + rise * (i + 0.5) / steps
		var half := (z1 - z0) / 2.0 * (1.0 - (i + 0.5) / steps)
		for x in [x0, x1]:
			box(Vector3(0.15, rise / steps, half * 2.0), Vector3(x, y, mid_z), siding, "exterior_sheathing", 0.0, false)


func label3d(text: String, pos: Vector3, size := 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	add_child(l)


## Merge every static mesh (not doors, glass that can break, or anything that moves) into one mesh per
## material per `cell` metres of floor plan. Hundreds of boxes become a few dozen draw calls, while each
## chunk stays small enough to only be lit by the nearby room lights (mobile: 8 lights per mesh).
func batch_meshes(cell := 5.0) -> int:
	var groups := {}   # key -> [material, SurfaceTool]
	var merged := 0
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not _batchable(mi):
			continue
		var m := mi.material_override
		var p := mi.global_position
		# Storeys batch apart, so a chunk is only lit by the lights of its own floor (mobile: 8 per mesh).
		var key := "%d|%d|%d|%d" % [m.get_instance_id(), floori(p.x / cell), floori(p.z / cell), floori((p.y + 0.2) / 2.7)]
		if not groups.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = [m, st]
		var xf := global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			(groups[key][1] as SurfaceTool).append_from(mi.mesh, s, xf)
		mi.queue_free()
		merged += 1
	for key: String in groups:
		var g: Array = groups[key]
		var out := MeshInstance3D.new()
		out.mesh = (g[1] as SurfaceTool).commit()
		out.material_override = g[0]
		add_child(out)
	return merged


func _batchable(mi: MeshInstance3D) -> bool:
	if mi.material_override == null or mi.mesh == null or not (mi.mesh is PrimitiveMesh):
		return false
	var n: Node = mi.get_parent()
	while n and n != self:
		if n is Door or n is AnimatableBody3D or n is RigidBody3D or n.has_meta("stay_broken") or n is CharacterBody3D:
			return false
		n = n.get_parent()
	return true
