class_name Furniture
extends RefCounted
## The furniture catalogue for generated houses. Every piece is built around a
## Node3D the generator has already placed: origin on the floor at the centre of
## the piece's footprint, local X along the wall it stands against, back toward
## local -Z, front facing +Z (into the room). w = width along the wall, d = depth.
##
## Sizes are real (US, inches/feet). Ballistic materials match what's in them:
## upholstery and mattresses barely slow a bullet, appliances and porcelain
## stop or deflect, cabinets are particleboard boxes.
##
## Items: [id, w, d, tall] — tall pieces (over a window sill) stay off windows.

const IN := 0.0254
const FT := 0.3048

var k: LevelKit
var rng: RandomNumberGenerator
## Per-house palette: wood finish, fabrics, appliance colour.
var wood: Material
var wood2: Material
var fabrics: Array = []
var sheets: Array = []
var appliance: Material
var porcelain: Material
var black: Material
var metal: Material
var mirror: Material
var marble: Material


func _init(kit: LevelKit, r: RandomNumberGenerator) -> void:
	k = kit
	rng = r
	var woods := [
		["oak", Color(0.66, 0.48, 0.28), Color(0.55, 0.38, 0.2)],
		["cherry", Color(0.5, 0.24, 0.14), Color(0.38, 0.17, 0.1)],
		["pine", Color(0.78, 0.62, 0.4), Color(0.62, 0.47, 0.28)],
		["walnut", Color(0.36, 0.24, 0.15), Color(0.26, 0.17, 0.1)],
		["whitewash", Color(0.88, 0.86, 0.8), Color(0.75, 0.73, 0.68)],
	]
	var a: Array = woods[rng.randi() % woods.size()]
	var b: Array = woods[rng.randi() % woods.size()]
	wood = k.textured("f_" + a[0], k.img_boards(a[1], a[2], 4, false, 64, 0.06), 0.6, 0.6)
	wood2 = k.textured("f_" + b[0], k.img_boards(b[1], b[2], 4, false, 64, 0.06), 0.6, 0.6)
	var cols := [
		[Color(0.25, 0.32, 0.28), Color(0.72, 0.35, 0.4), Color(0.45, 0.55, 0.35)],    # hunter green floral
		[Color(0.85, 0.8, 0.68), Color(0.55, 0.3, 0.35), Color(0.4, 0.5, 0.35)],       # cream rose chintz
		[Color(0.3, 0.3, 0.45), Color(0.75, 0.65, 0.4), Color(0.5, 0.45, 0.55)],       # navy
		[Color(0.55, 0.42, 0.32), Color(0.7, 0.55, 0.4), Color(0.4, 0.3, 0.22)],       # brown tweed
		[Color(0.5, 0.2, 0.22), Color(0.7, 0.5, 0.3), Color(0.35, 0.15, 0.15)],        # burgundy
	]
	for i in 3:
		var c: Array = cols[rng.randi() % cols.size()]
		if rng.randf() < 0.5:
			fabrics.append(k.textured("fab_%d_%s" % [i, c[0].to_html()], k.img_floral(c[0], c[1], c[2]), 0.5, 0.95))
		else:
			fabrics.append(k.textured("plaid_%d_%s" % [i, c[0].to_html()], k.img_checker(c[0], c[2], 32, 6), 0.4, 0.95))
	for c in [Color(0.78, 0.7, 0.85), Color(0.35, 0.45, 0.65), Color(0.85, 0.82, 0.75), Color(0.7, 0.3, 0.3), Color(0.45, 0.6, 0.45)]:
		sheets.append(k.flat("sheets_%s" % c.to_html(), c))
	var appl := [Color(0.88, 0.84, 0.74), Color(0.94, 0.94, 0.92), Color(0.12, 0.12, 0.12)]   # almond, white, black
	var ac: Color = appl[rng.randi() % appl.size()]
	appliance = k.flat("appl_%s" % ac.to_html(), ac, 0.4, 0.1)
	porcelain = k.flat("porcelain", Color(0.95, 0.95, 0.93), 0.2)
	black = k.flat("plastic_black", Color(0.08, 0.08, 0.09), 0.4)
	metal = k.flat("steel_grey", Color(0.45, 0.47, 0.48), 0.45, 0.5)
	mirror = k.flat("mirror", Color(0.75, 0.8, 0.85), 0.05, 0.9)
	marble = k.flat("marble", Color(0.92, 0.9, 0.85), 0.3)


func fabric() -> Material:
	return fabrics[rng.randi() % fabrics.size()]


func _b(n: Node3D, size: Vector3, pos: Vector3, m: Material, ballistic := "wood", collide := true, rot := 0.0) -> Node3D:
	return k.box(size, pos, m, ballistic, rot, collide, n)


## Collision only (round things get a box-shaped hitbox; the mesh is drawn separately).
func _solid(n: Node3D, size: Vector3, pos: Vector3, ballistic: String) -> void:
	var body := StaticBody3D.new()
	body.set_meta("material", ballistic)
	body.position = pos
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	n.add_child(body)


func _cyl(n: Node3D, r: float, h: float, pos: Vector3, m: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	n.add_child(mi)


func _ball(n: Node3D, r: float, h: float, pos: Vector3, m: Material) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = h
	sm.radial_segments = 10
	sm.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	n.add_child(mi)


# ------------------------------------------------------------------ seating

func sofa(n: Node3D, w: float, d := 0.9) -> void:
	var m := fabric()
	_b(n, Vector3(w, 0.42, d), Vector3(0, 0.21, 0), m, "upholstery")
	_b(n, Vector3(w, 0.45, 0.22), Vector3(0, 0.64, -d / 2.0 + 0.11), m, "upholstery")
	for s in [-1.0, 1.0]:
		_b(n, Vector3(0.2, 0.25, d), Vector3(s * (w / 2.0 - 0.1), 0.54, 0), m, "upholstery")
	for i in int(w / 0.7):     # seat cushions
		_b(n, Vector3((w - 0.4) / int(w / 0.7) - 0.02, 0.1, d - 0.3), Vector3(-w / 2.0 + 0.2 + ((w - 0.4) / int(w / 0.7)) * (i + 0.5), 0.47, 0.08), m, "upholstery", false)


func recliner(n: Node3D, _w: float, _d: float) -> void:
	var m := fabric()
	_b(n, Vector3(0.9, 0.45, 0.9), Vector3(0, 0.22, 0), m, "upholstery")
	_b(n, Vector3(0.9, 0.6, 0.25), Vector3(0, 0.75, -0.32), m, "upholstery")
	for s in [-1.0, 1.0]:
		_b(n, Vector3(0.18, 0.2, 0.85), Vector3(s * 0.36, 0.55, 0), m, "upholstery", false)


func chair(n: Node3D, m: Material, at := Vector3.ZERO, rot := 0.0) -> void:
	var c := Node3D.new()
	c.position = at
	c.rotation_degrees.y = rot
	n.add_child(c)
	_b(c, Vector3(0.44, 0.05, 0.44), Vector3(0, 0.45, 0), m, "wood")
	_b(c, Vector3(0.44, 0.5, 0.04), Vector3(0, 0.72, -0.2), m, "wood")
	for lx in [-0.19, 0.19]:
		for lz in [-0.19, 0.19]:
			_b(c, Vector3(0.04, 0.45, 0.04), Vector3(lx, 0.22, lz), m, "wood", false)


func beanbag(n: Node3D, _w: float, _d: float) -> void:
	var c: Color = [Color(0.7, 0.15, 0.15), Color(0.15, 0.3, 0.7), Color(0.1, 0.1, 0.1), Color(0.5, 0.2, 0.6)][rng.randi() % 4]
	_solid(n, Vector3(0.75, 0.5, 0.75), Vector3(0, 0.25, 0), "upholstery")
	_ball(n, 0.42, 0.55, Vector3(0, 0.27, 0), k.flat("beanbag_%s" % c.to_html(), c, 0.8))


# ------------------------------------------------------------------ tables, storage

func coffee_table(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.05, d), Vector3(0, 0.42, 0), wood, "wood")
	_b(n, Vector3(w - 0.1, 0.3, d - 0.1), Vector3(0, 0.2, 0), wood, "wood", false)
	if rng.randf() < 0.6:   # magazines, a remote
		_b(n, Vector3(0.22, 0.02, 0.3), Vector3(w * 0.2, 0.455, 0), k.flat("magazine", Color(0.8, 0.3, 0.2), 0.6), "wood", false, 12.0)


func end_table(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.6, d), Vector3(0, 0.3, 0), wood, "cabinet")
	_cyl(n, 0.08, 0.3, Vector3(0, 0.75, 0), k.flat("lamp_base", Color(0.8, 0.75, 0.6), 0.3, 0.3))
	_cyl(n, 0.18, 0.22, Vector3(0, 1.0, 0), k.flat("shade", Color(0.95, 0.9, 0.78)))


func nightstand(n: Node3D, w: float, d: float) -> void:
	end_table(n, w, d)
	if rng.randf() < 0.5:
		_b(n, Vector3(0.18, 0.08, 0.1), Vector3(-w * 0.25, 0.64, 0.05), k.flat("clock_radio", Color(0.1, 0.1, 0.1), 0.4), "appliance", false)


func bookshelf(n: Node3D, w: float, d: float) -> void:
	var h := 1.8
	_b(n, Vector3(w, h, d), Vector3(0, h / 2.0, 0), wood, "cabinet")
	var shelf := 0.32
	var cols := [Color(0.5, 0.1, 0.1), Color(0.1, 0.2, 0.45), Color(0.15, 0.35, 0.15), Color(0.7, 0.6, 0.3), Color(0.2, 0.2, 0.2)]
	var y := 0.1
	while y + 0.25 < h:
		var x := -w / 2.0 + 0.05
		while x < w / 2.0 - 0.1:
			var bw := rng.randf_range(0.03, 0.06) * 3.0
			var c: Color = cols[rng.randi() % cols.size()]
			_b(n, Vector3(minf(bw, w / 2.0 - 0.05 - x), rng.randf_range(0.18, 0.25), 0.02), Vector3(x + bw / 2.0, y + 0.11, d / 2.0 + 0.005), k.flat("books_%s" % c.to_html(), c, 0.7), "wood", false)
			x += bw + 0.01
		y += shelf


func dresser(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.85, d), Vector3(0, 0.425, 0), wood, "cabinet")
	for i in 3:
		_b(n, Vector3(w - 0.08, 0.005, 0.01), Vector3(0, 0.27 * (i + 1), d / 2.0 + 0.002), black, "wood", false)
	var r := rng.randf()
	if r < 0.4:
		_b(n, Vector3(minf(w - 0.2, 1.1), 0.85, 0.03), Vector3(0, 1.3, -d / 2.0 + 0.05), mirror, "glass", false)
	elif r < 0.7:
		crt(n, 0.4, Vector3(0, 0.85, 0))


func armoire(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 1.9, d), Vector3(0, 0.95, 0), wood, "cabinet")
	_b(n, Vector3(0.01, 1.6, 0.01), Vector3(0, 1.0, d / 2.0 + 0.004), black, "wood", false)


func hutch(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.85, d), Vector3(0, 0.425, 0), wood, "cabinet")
	_b(n, Vector3(w, 1.05, d * 0.6), Vector3(0, 1.4, -d * 0.2), wood, "cabinet")
	_b(n, Vector3(w - 0.15, 0.8, 0.01), Vector3(0, 1.4, d * 0.1 + 0.005), k.mat("glass", func(): return k.flat("glass_flat", Color(0.7, 0.8, 0.9))), "glass", false)


func sideboard(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.85, d), Vector3(0, 0.425, 0), wood, "cabinet")
	_cyl(n, 0.06, 0.25, Vector3(w * 0.3, 0.97, 0), k.flat("vase", Color(0.3, 0.45, 0.6), 0.2))


func toy_chest(n: Node3D, w: float, d: float) -> void:
	var c: Color = [Color(0.75, 0.15, 0.12), Color(0.15, 0.4, 0.75), Color(0.9, 0.75, 0.15)][rng.randi() % 3]
	_b(n, Vector3(w, 0.45, d), Vector3(0, 0.225, 0), k.flat("toy_%s" % c.to_html(), c), "wood")


func closet(n: Node3D, w: float, d: float) -> void:
	## Built-in closet with mirrored bi-pass doors.
	var h := LevelKit.CEILING - 0.02
	_b(n, Vector3(w, h, d), Vector3(0, h / 2.0, 0), k.flat("closet_paint", Color(0.88, 0.86, 0.8), 0.9), "drywall_partition")
	for s in [-1.0, 1.0]:
		_b(n, Vector3(w / 2.0 - 0.04, LevelKit.DOOR_H - 0.05, 0.01), Vector3(s * w / 4.0, LevelKit.DOOR_H / 2.0, d / 2.0 + 0.006 + (0.012 if s > 0 else 0.0)), mirror, "glass", false)


func filing_cabinet(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 1.3, d), Vector3(0, 0.65, 0), metal, "sheet_metal")
	for i in 4:
		_b(n, Vector3(0.12, 0.02, 0.02), Vector3(0, 0.25 + i * 0.3, d / 2.0 + 0.01), black, "sheet_metal", false)


func gun_safe(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 1.5, d), Vector3(0, 0.75, 0), k.flat("safe", Color(0.12, 0.14, 0.13), 0.35, 0.6), "steel")
	_cyl(n, 0.08, 0.03, Vector3(w * 0.2, 0.95, d / 2.0 + 0.02), k.flat("brass", Color(0.78, 0.62, 0.25), 0.35, 0.8))


# ------------------------------------------------------------------ electronics, decor

func crt(n: Node3D, size: float, at: Vector3) -> void:
	var tv := _b(n, Vector3(size, size * 0.85, size * 0.85), at + Vector3(0, size * 0.42, 0), k.flat("tv_case", Color(0.12, 0.12, 0.13), 0.5), "crt")
	k.box(Vector3(size * 0.82, size * 0.62, 0.01), Vector3(0, 0.02, size * 0.43), k.flat("tv_screen", Color(0.16, 0.2, 0.2), 0.1, 0.2), "crt", 0.0, false, tv)


func tv_stand(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.55, d), Vector3(0, 0.275, 0), wood, "cabinet")
	crt(n, rng.randf_range(0.55, 0.72), Vector3(0, 0.55, 0))
	if rng.randf() < 0.5:   # a VCR
		_b(n, Vector3(0.43, 0.09, 0.3), Vector3(0, 0.45, 0.06), black, "appliance", false)


func entertainment_centre(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.5, d), Vector3(0, 0.25, 0), wood, "cabinet")
	for s in [-1.0, 1.0]:
		_b(n, Vector3(0.35, 1.3, d), Vector3(s * (w / 2.0 - 0.175), 1.15, 0), wood, "cabinet")
	_b(n, Vector3(w, 0.08, d), Vector3(0, 1.76, 0), wood, "cabinet")
	crt(n, minf(0.72, w - 0.8), Vector3(0, 0.5, 0))


func desk(n: Node3D, w: float, d: float) -> void:
	## d includes room for the chair pulled out in front.
	var dd := d - 0.35
	var z0 := -d / 2.0 + dd / 2.0
	_b(n, Vector3(w, 0.05, dd), Vector3(0, 0.74, z0), wood, "wood")
	_b(n, Vector3(0.42, 0.72, dd - 0.05), Vector3(w / 2.0 - 0.22, 0.36, z0), wood, "cabinet")
	_b(n, Vector3(0.04, 0.72, dd - 0.05), Vector3(-w / 2.0 + 0.03, 0.36, z0), wood, "wood")
	var beige := k.flat("beige_plastic", Color(0.86, 0.83, 0.74), 0.5)
	if rng.randf() < 0.7:     # a beige PC
		_b(n, Vector3(0.42, 0.38, 0.4), Vector3(-0.1, 0.96 + 0.12, z0 - 0.05), beige, "crt")
		_b(n, Vector3(0.45, 0.02, 0.16), Vector3(-0.1, 0.775, z0 + dd / 2.0 - 0.12), beige, "appliance", false)
		_b(n, Vector3(0.45, 0.12, 0.42), Vector3(-0.1, 0.83, z0 - 0.05), beige, "appliance", false)
	else:
		_cyl(n, 0.06, 0.4, Vector3(-w * 0.35, 0.97, z0 - 0.1), k.flat("brass", Color(0.78, 0.62, 0.25), 0.35, 0.8))
	chair(n, black, Vector3(-0.1, 0, d / 2.0 - 0.23), 180.0)


func floor_lamp(n: Node3D, _w: float, _d: float) -> void:
	var brass := k.flat("brass", Color(0.78, 0.62, 0.25), 0.35, 0.8)
	_solid(n, Vector3(0.3, 1.5, 0.3), Vector3(0, 0.75, 0), "sheet_metal")
	_cyl(n, 0.02, 1.5, Vector3(0, 0.75, 0), brass)
	_cyl(n, 0.2, 0.25, Vector3(0, 1.55, 0), k.flat("shade", Color(0.95, 0.9, 0.78)))


func plant(n: Node3D, _w: float, _d: float) -> void:
	var pot := k.flat("terracotta", Color(0.65, 0.35, 0.22), 0.9)
	k.box(Vector3(0.35, 0.4, 0.35), Vector3(0, 0.2, 0), pot, "porcelain", 0.0, true, n)
	_ball(n, 0.35, 0.9, Vector3(0, 0.8, 0), k.flat("leaves_in", Color(0.18, 0.4, 0.18), 1.0))


func piano(n: Node3D, w: float, d: float) -> void:
	var m := k.flat("piano", Color(0.07, 0.05, 0.04), 0.2) if rng.randf() < 0.5 else wood
	_b(n, Vector3(w, 1.25, d * 0.6), Vector3(0, 0.625, -d * 0.2), m, "wood")
	_b(n, Vector3(w, 0.06, d * 0.4), Vector3(0, 0.72, d * 0.2), m, "wood")
	_b(n, Vector3(w - 0.1, 0.02, 0.15), Vector3(0, 0.76, d * 0.25), k.flat("keys", Color(0.95, 0.95, 0.9)), "wood", false)


func fireplace(n: Node3D, w: float, d: float) -> void:
	var brick := k.textured("brick", k.img_brick(Color(0.55, 0.27, 0.2), Color(0.7, 0.68, 0.62)), 0.9, 0.95)
	_b(n, Vector3(w, LevelKit.CEILING, d), Vector3(0, LevelKit.CEILING / 2.0, 0), brick, "brick")
	_b(n, Vector3(0.8, 0.7, 0.02), Vector3(0, 0.45, d / 2.0 + 0.005), black, "brick", false)
	_b(n, Vector3(w + 0.2, 0.08, 0.3), Vector3(0, 1.3, d / 2.0 + 0.1), wood, "wood", false)


func rug(n: Node3D, w: float, d: float) -> void:
	var c: Color = [Color(0.5, 0.22, 0.2), Color(0.25, 0.3, 0.45), Color(0.55, 0.5, 0.35), Color(0.3, 0.4, 0.3)][rng.randi() % 4]
	_b(n, Vector3(w, 0.01, d), Vector3(0, 0.025, 0), k.flat("rug_%s" % c.to_html(), c, 1.0), "concrete", false)


func poster(n: Node3D, w: float, c: Color) -> void:
	var p := _b(n, Vector3(w, w * 1.45, 0.005), Vector3(0, 1.6, 0), k.flat("poster_%s" % c.to_html(), c, 0.6), "drywall", false)
	k.box(Vector3(w * 0.7, 0.12, 0.004), Vector3(0, w * 0.45, 0.003), k.flat("poster_title", Color(0.95, 0.9, 0.3), 0.6), "drywall", 0.0, false, p)


func picture(n: Node3D, w: float) -> void:
	var c := Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.6), rng.randf_range(0.4, 0.8))
	_b(n, Vector3(w + 0.08, w * 0.8 + 0.08, 0.02), Vector3(0, 1.55, 0), wood, "wood", false)
	_b(n, Vector3(w, w * 0.8, 0.005), Vector3(0, 1.55, 0.012), k.flat("art_%s" % c.to_html(), c, 0.7), "wood", false)


func ceiling_fan(n: Node3D) -> void:
	var brass := k.flat("brass", Color(0.78, 0.62, 0.25), 0.35, 0.8)
	_cyl(n, 0.1, 0.18, Vector3(0, LevelKit.CEILING - 0.2, 0), brass)
	for i in 5:
		var b := _b(n, Vector3(0.6, 0.012, 0.12), Vector3(0, LevelKit.CEILING - 0.26, 0), wood, "wood", false, i * 72.0)
		b.translate_object_local(Vector3(0.38, 0, 0))


# ------------------------------------------------------------------ beds

func bed(n: Node3D, w: float, d: float) -> void:
	var frame := wood if rng.randf() < 0.7 else black
	_b(n, Vector3(w, 0.3, d), Vector3(0, 0.15, 0), frame, "wood")
	_b(n, Vector3(w - 0.04, 0.25, d - 0.04), Vector3(0, 0.42, 0), sheets[rng.randi() % sheets.size()], "mattress")
	_b(n, Vector3(w, 1.0, 0.06), Vector3(0, 0.5, -d / 2.0), frame, "wood")
	var pillows := 2 if w > 1.2 else 1
	for i in pillows:
		var px := 0.0 if pillows == 1 else (i - 0.5) * w * 0.48
		_b(n, Vector3(minf(0.6, w * 0.42), 0.1, 0.35), Vector3(px, 0.59, -d / 2.0 + 0.25), k.flat("pillow", Color(0.95, 0.95, 0.92)), "mattress", false)


func crib(n: Node3D, w: float, d: float) -> void:
	var white := k.flat("crib_white", Color(0.95, 0.95, 0.93), 0.6)
	_b(n, Vector3(w, 0.95, d), Vector3(0, 0.475, 0), white, "wood")
	_b(n, Vector3(w - 0.06, 0.1, d - 0.06), Vector3(0, 0.96, 0), sheets[rng.randi() % sheets.size()], "mattress", false)


# ------------------------------------------------------------------ kitchen

func counter(n: Node3D, w: float, d: float, uppers := true, sink := false) -> void:
	var top := k.flat("laminate_%d" % (rng.randi() % 3), [Color(0.85, 0.8, 0.68), Color(0.9, 0.9, 0.88), Color(0.55, 0.5, 0.45)][rng.randi() % 3], 0.5)
	_b(n, Vector3(w, 0.86, d - 0.04), Vector3(0, 0.43, -0.02), wood, "cabinet")
	_b(n, Vector3(w + 0.02, 0.04, d), Vector3(0, 0.88, 0), top, "wood", false)
	if sink:
		_b(n, Vector3(0.8, 0.02, 0.45), Vector3(0, 0.9, 0), k.flat("sink", Color(0.7, 0.72, 0.74), 0.2, 0.9), "sheet_metal", false)
	if uppers:
		_b(n, Vector3(w, 0.75, 0.33), Vector3(0, 1.85, -d / 2.0 + 0.165), wood, "cabinet")


func fridge(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 1.72, d), Vector3(0, 0.86, 0), appliance, "appliance")
	_b(n, Vector3(w - 0.02, 0.01, 0.01), Vector3(0, 1.15, d / 2.0 + 0.005), black, "appliance", false)
	_b(n, Vector3(0.03, 0.4, 0.04), Vector3(w / 2.0 - 0.07, 1.4, d / 2.0 + 0.02), black, "appliance", false)


func stove(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.92, d), Vector3(0, 0.46, 0), appliance, "appliance")
	_b(n, Vector3(w - 0.1, 0.02, d - 0.1), Vector3(0, 0.93, 0), black, "appliance", false)
	_b(n, Vector3(w, 0.2, 0.08), Vector3(0, 1.0, -d / 2.0 + 0.04), appliance, "appliance", false)
	_b(n, Vector3(w - 0.15, 0.4, 0.02), Vector3(0, 0.45, d / 2.0 + 0.005), black, "appliance", false)


func island(n: Node3D, w: float, d: float) -> void:
	counter(n, w, d, false)


func dining_set(n: Node3D, w: float, d: float) -> void:
	## Table in the middle of a w x d footprint with chairs on the long sides (and ends if room).
	var tw := w - 0.9 if w > 2.0 else w - 0.2
	var td := d - 1.1
	_b(n, Vector3(tw, 0.05, td), Vector3(0, 0.74, 0), wood, "wood")
	for lx in [-tw / 2.0 + 0.08, tw / 2.0 - 0.08]:
		for lz in [-td / 2.0 + 0.08, td / 2.0 - 0.08]:
			_b(n, Vector3(0.06, 0.72, 0.06), Vector3(lx, 0.36, lz), wood, "wood", false)
	var per_side := maxi(1, int(tw / 0.6))
	for i in per_side:
		var x := -tw / 2.0 + tw * (i + 0.5) / per_side
		chair(n, wood, Vector3(x, 0, -td / 2.0 - 0.25), 0.0)
		chair(n, wood, Vector3(x, 0, td / 2.0 + 0.25), 180.0)
	if w > 2.0:
		chair(n, wood, Vector3(-tw / 2.0 - 0.25, 0, 0), 90.0)
		chair(n, wood, Vector3(tw / 2.0 + 0.25, 0, 0), 270.0)


# ------------------------------------------------------------------ bath, laundry

func toilet(n: Node3D, _w: float, _d: float) -> void:
	_b(n, Vector3(0.4, 0.4, 0.5), Vector3(0, 0.2, 0.06), porcelain, "porcelain")
	_b(n, Vector3(0.45, 0.4, 0.2), Vector3(0, 0.55, -0.22), porcelain, "porcelain")


func tub(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.5, d), Vector3(0, 0.25, 0), porcelain, "porcelain")
	_b(n, Vector3(w - 0.12, 0.02, d - 0.12), Vector3(0, 0.505, 0), k.flat("tub_in", Color(0.85, 0.88, 0.9), 0.1), "porcelain", false)


func shower(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.1, d), Vector3(0, 0.05, 0), porcelain, "porcelain")
	for side in [[Vector2(w, 1.9), Vector3(0, 1.05, d / 2.0), 0.0], [Vector2(d, 1.9), Vector3(w / 2.0, 1.05, 0), PI / 2.0]]:
		var g := GlassPane.new()
		g.size = side[0]
		g.thickness = 0.008
		g.material = k.mat("glass", func(): return k.flat("glass_flat", Color(0.7, 0.8, 0.9)))
		g.seed_value = rng.randi() | 1
		g.position = side[1]
		g.rotation.y = side[2]
		n.add_child(g)


func vanity(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.8, d - 0.03), Vector3(0, 0.4, -0.015), wood, "cabinet")
	_b(n, Vector3(w + 0.02, 0.03, d), Vector3(0, 0.815, 0), marble, "porcelain", false)
	_b(n, Vector3(minf(w, 1.4) - 0.1, 0.8, 0.02), Vector3(0, 1.45, -d / 2.0 + 0.01), mirror, "glass", false)


func washer(n: Node3D, w: float, d: float) -> void:
	var white := k.flat("white_appl", Color(0.94, 0.94, 0.92), 0.3)
	_b(n, Vector3(w, 0.92, d), Vector3(0, 0.46, 0), white, "appliance")
	_b(n, Vector3(w, 0.15, 0.1), Vector3(0, 0.99, -d / 2.0 + 0.05), white, "appliance", false)


func utility_sink(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.88, d), Vector3(0, 0.44, 0), k.flat("utility_white", Color(0.9, 0.9, 0.88), 0.5), "porcelain")


func water_heater(n: Node3D, _w: float, _d: float) -> void:
	_solid(n, Vector3(0.55, 1.5, 0.55), Vector3(0, 0.75, 0), "sheet_metal")
	_cyl(n, 0.27, 1.5, Vector3(0, 0.75, 0), k.flat("heater", Color(0.85, 0.85, 0.8), 0.4, 0.2))


func shelving(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 1.8, d), Vector3(0, 0.9, 0), metal, "sheet_metal")
	var card := k.flat("cardboard", Color(0.62, 0.48, 0.3), 0.9)
	for y in [0.45, 0.95, 1.45]:
		if rng.randf() < 0.75:
			_b(n, Vector3(w * rng.randf_range(0.3, 0.45), 0.3, d * 0.8), Vector3(rng.randf_range(-0.2, 0.2) * w, y + 0.15, 0.01), card, "wood", false)


# ------------------------------------------------------------------ garage

func car(n: Node3D, _w: float, _d: float) -> void:
	## A '90s sedan, nose toward +Z (the garage door).
	var c: Color = [Color(0.38, 0.06, 0.1), Color(0.12, 0.2, 0.35), Color(0.75, 0.75, 0.72), Color(0.15, 0.3, 0.2), Color(0.05, 0.05, 0.06)][rng.randi() % 5]
	var paint := k.flat("car_%s" % c.to_html(), c, 0.35, 0.4)
	var body := _b(n, Vector3(1.78, 0.75, 4.7), Vector3(0, 0.55, 0), paint, "car")
	var glass: Material = k.mat("glass", func(): return k.flat("glass_flat", Color(0.7, 0.8, 0.9)))
	k.box(Vector3(1.5, 0.5, 2.4), Vector3(0, 0.62, -0.2), glass, "car", 0.0, true, body)
	var tyre := k.flat("tyre", Color(0.06, 0.06, 0.06))
	for wx in [-0.85, 0.85]:
		for wz in [-1.5, 1.5]:
			var t := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.32
			cm.bottom_radius = 0.32
			cm.height = 0.2
			cm.radial_segments = 10
			t.mesh = cm
			t.material_override = tyre
			t.position = Vector3(wx, 0.32, wz)
			t.rotation_degrees.z = 90.0
			n.add_child(t)


func workbench(n: Node3D, w: float, d: float) -> void:
	var pine := k.textured("pine", k.img_boards(Color(0.75, 0.6, 0.38), Color(0.6, 0.45, 0.28), 4), 0.6)
	_b(n, Vector3(w, 0.9, d), Vector3(0, 0.45, 0), pine, "wood")
	_b(n, Vector3(w, 0.9, 0.02), Vector3(0, 1.4, -d / 2.0 + 0.01), k.flat("pegboard", Color(0.6, 0.48, 0.32), 0.9), "wood", false)
	_b(n, Vector3(0.45, 0.2, 0.25), Vector3(w * 0.25, 1.0, 0), k.flat("toolbox_red", Color(0.7, 0.1, 0.08), 0.4, 0.3), "sheet_metal", false)


func tool_chest(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 1.0, d), Vector3(0, 0.5, 0), k.flat("toolbox_red", Color(0.7, 0.1, 0.08), 0.4, 0.3), "sheet_metal")


func mower(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.4, d), Vector3(0, 0.2, 0), k.flat("mower", Color(0.75, 0.15, 0.1), 0.4), "sheet_metal")
	_b(n, Vector3(0.45, 0.04, 0.04), Vector3(0, 0.95, -d / 2.0 - 0.2), black, "sheet_metal", false)


func chest_freezer(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.85, d), Vector3(0, 0.425, 0), k.flat("white_appl", Color(0.94, 0.94, 0.92), 0.3), "appliance")


func boxes(n: Node3D, w: float, d: float) -> void:
	var card := k.flat("cardboard", Color(0.62, 0.48, 0.3), 0.9)
	var y := 0.0
	for i in rng.randi_range(1, 3):
		var s := Vector3(w * rng.randf_range(0.7, 1.0), rng.randf_range(0.3, 0.45), d * rng.randf_range(0.7, 1.0))
		_b(n, s, Vector3(rng.randf_range(-0.05, 0.05), y + s.y / 2.0, 0), card, "wood_crate", true, rng.randf_range(-12, 12))
		y += s.y


func bench(n: Node3D, w: float, d: float) -> void:
	_b(n, Vector3(w, 0.45, d), Vector3(0, 0.225, 0), wood, "wood")


func coat_rack(n: Node3D, _w: float, _d: float) -> void:
	_solid(n, Vector3(0.4, 1.75, 0.4), Vector3(0, 0.875, 0), "wood")
	_cyl(n, 0.025, 1.75, Vector3(0, 0.875, 0), wood)
	_ball(n, 0.2, 0.6, Vector3(0, 1.45, 0), k.flat("coats", Color(0.25, 0.22, 0.3), 1.0))
