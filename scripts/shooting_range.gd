extends Node3D
## Grey-box shooting range, built in code: open yard with cover, a 100 yd range
## (five lanes: 25 ft, 25 / 50 / 75 / 100 yd) running out of the yard's north-west
## corner, a two-room building with a roof, and stairs to a platform.
## Everything sits on a 1 m checker grid so distances are easy to judge.

const WALL_T := 0.3

var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_cover: StandardMaterial3D
var _mat_accent: StandardMaterial3D
var player: Player
var _wall_ballistic := "concrete"  ## Ballistic material used by _wall_x / _wall_z.


func _ready() -> void:
	DisplayServer.screen_set_keep_on(true)
	Ballistics.debug_enabled = Settings.show_bullet_paths  # bullet paths + readout (Settings, default on)
	_mat_floor = _checker_material(Color(0.42, 0.42, 0.40), Color(0.36, 0.36, 0.34), 1.0)
	_mat_wall = _checker_material(Color(0.62, 0.60, 0.55), Color(0.56, 0.54, 0.50), 1.0)
	_mat_cover = _checker_material(Color(0.55, 0.42, 0.26), Color(0.48, 0.36, 0.22), 0.5)
	_mat_accent = _checker_material(Color(0.70, 0.55, 0.20), Color(0.62, 0.48, 0.16), 0.5)

	_build_environment()
	_build_yard()
	_build_lane()
	_build_house()
	_build_platform()
	_build_barriers()
	_build_dummies()
	_build_civilians()
	_build_supply()

	player = Player.new()
	player.name = "Player"
	player.position = Vector3(0, 0.05, 18)
	add_child(player)

	var hud: Node = load("res://scripts/hud.gd").new()
	hud.player = player
	add_child(hud)


# ---------------------------------------------------------------- helpers

func _checker_material(a: Color, b: Color, metres_per_tile: float) -> StandardMaterial3D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var c := a if ((x >> 3) + (y >> 3)) % 2 == 0 else b
			# A darker 1-pixel line on the tile edge gives the classic grid look.
			if x % 8 == 0 or y % 8 == 0:
				c = c.darkened(0.12)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	# One texture holds 2x2 tiles, so scale so each tile = metres_per_tile.
	mat.uv1_scale = Vector3.ONE / (metres_per_tile * 2.0)
	mat.roughness = 0.9
	return mat


func _box(size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO, ballistic := "concrete") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("material", ballistic)
	body.position = pos
	body.rotation_degrees = rot_deg
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


## Wall running along X at depth z, from x0 to x1.
func _wall_x(z: float, x0: float, x1: float, h: float, y0 := 0.0) -> void:
	_box(Vector3(x1 - x0, h, WALL_T), Vector3((x0 + x1) / 2.0, y0 + h / 2.0, z), _mat_wall, Vector3.ZERO, _wall_ballistic)


## Wall running along Z at x, from z0 to z1.
func _wall_z(x: float, z0: float, z1: float, h: float, y0 := 0.0) -> void:
	_box(Vector3(WALL_T, h, z1 - z0), Vector3(x, y0 + h / 2.0, (z0 + z1) / 2.0), _mat_wall, Vector3.ZERO, _wall_ballistic)


func _label(text: String, pos: Vector3, size := 96) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	add_child(l)


# ---------------------------------------------------------------- layout

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.70)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.62, 0.70)
	env.fog_density = 0.004    # thin enough to see the 100 yd target
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_yard() -> void:
	# Ground and perimeter.
	_box(Vector3(48, 1, 48), Vector3(0, -0.5, 0), _mat_floor)
	_wall_x(-24, LANE_X1, 24, 4)     # north wall, open where the range runs out
	_wall_x(24, -24, 24, 4)
	_wall_z(-24, -24, 24, 4)
	_wall_z(24, -24, 24, 4)
	_build_range_extension()

	# Cover near spawn: low walls (crouch behind) and crates (stand behind).
	_box(Vector3(3, 1.0, 0.4), Vector3(-4, 0.5, 13), _mat_cover)
	_box(Vector3(3, 1.0, 0.4), Vector3(3, 0.5, 11), _mat_cover)
	_box(Vector3(1.2, 1.2, 1.2), Vector3(-7, 0.6, 9), _mat_cover, Vector3(0, 20, 0), "wood_crate")
	_box(Vector3(1.2, 1.2, 1.2), Vector3(-7.2, 1.8, 9.1), _mat_cover, Vector3(0, 5, 0), "wood_crate")
	_box(Vector3(1.0, 1.0, 1.0), Vector3(5, 0.5, 5), _mat_cover, Vector3.ZERO, "wood_crate")
	_box(Vector3(0.6, 2.8, 0.6), Vector3(-2, 1.4, 4), _mat_wall)  # pillar for leaning practice
	_box(Vector3(0.6, 2.8, 0.6), Vector3(3, 1.4, 7), _mat_wall)

	_label("SPAWN", Vector3(0, 2.5, 21), 72)


## The range: a strip x LANE_X0..LANE_X1 from the yard out to a berm past 100 yd.
const LANE_X0 := -24.0
const LANE_X1 := -13.0
const FIRING_LINE_Z := 18.0
const RANGE_END_Z := -84.0
## Lanes from the yard side out: [x, distance label, metres from the line].
const LANES := [
	[-14.0, "25 ft", 7.62], [-16.0, "25 yd", 22.86], [-18.0, "50 yd", 45.72], [-20.0, "75 yd", 68.58], [-22.0, "100 yd", 91.44],
]


func _build_range_extension() -> void:
	# Ground and walls for the part of the range beyond the yard.
	var length_m := -24.0 - RANGE_END_Z
	var mid := (-24.0 + RANGE_END_Z) / 2.0
	_box(Vector3(LANE_X1 - LANE_X0, 1, length_m), Vector3((LANE_X0 + LANE_X1) / 2.0, -0.5, mid), _mat_floor)
	_wall_z(LANE_X0, RANGE_END_Z, -24, 4)
	_wall_z(LANE_X1, RANGE_END_Z, -24, 4)
	# Backstop berm (tall, so high shots don't leave the range).
	_box(Vector3(LANE_X1 - LANE_X0, 8, 2.0), Vector3((LANE_X0 + LANE_X1) / 2.0, 4.0, RANGE_END_Z + 1.0), _mat_cover, Vector3.ZERO, "concrete")


func _build_lane() -> void:
	# Five lanes from one firing line: a post and a sign beside each target.
	_box(Vector3(LANE_X1 - LANE_X0 - 1.0, 0.05, 0.2), Vector3((LANE_X0 + LANE_X1) / 2.0, 0.03, FIRING_LINE_Z), _mat_accent)
	_label("FIRING LINE - 100 YD RANGE", Vector3((LANE_X0 + LANE_X1) / 2.0, 3.4, FIRING_LINE_Z - 1.5), 48)
	for lane: Array in LANES:
		var x: float = lane[0]
		var z: float = FIRING_LINE_Z - float(lane[2])
		_box(Vector3(0.08, 0.05, 0.4), Vector3(x, 0.03, FIRING_LINE_Z - 0.3), _mat_accent)   # lane mark on the line
		_label(lane[1], Vector3(x, 0.35, FIRING_LINE_Z - 1.2), 24)
		_box(Vector3(0.2, 2.0, 0.2), Vector3(x + 0.75, 1.0, z), _mat_accent)
		_label(lane[1], Vector3(x + 0.75, 2.4, z), int(clampf(48.0 + float(lane[2]) * 2.2, 48.0, 260.0)))


func _build_house() -> void:
	# Two-room building: x 8..20, z -8..8, 3 m tall, roof on top.
	var h := 3.0
	_wall_ballistic = "brick"
	_wall_x(8, 8, 13.3, h)        # south wall with front door gap 13.3..14.7
	_wall_x(8, 14.7, 20, h)
	_wall_x(8, 13.3, 14.7, 0.8, 2.2)  # lintel over the door
	_wall_x(-8, 8, 20, h)         # north wall
	_wall_z(8, -8, 3, h)          # west wall with side door gap 3..4.4
	_wall_z(8, 4.4, 8, h)
	_wall_z(8, 3, 4.4, 0.8, 2.2)
	# East wall with a window (gap from 1.0 to 2.0 m high, z -3..-1).
	_wall_z(20, -8, -3, h)
	_wall_z(20, -1, 8, h)
	_wall_z(20, -3, -1, 1.0)
	_wall_z(20, -3, -1, 1.0, 2.0)
	# Interior wall (hollow drywall partition) with doorway 16.8..18.2.
	_wall_ballistic = "drywall_partition"
	_wall_x(0, 8, 16.8, h)
	_wall_x(0, 18.2, 20, h)
	_wall_x(0, 16.8, 18.2, 0.8, 2.2)
	_wall_ballistic = "concrete"
	# Roof.
	_box(Vector3(12.3, 0.2, 16.3), Vector3(14, h + 0.1, 0), _mat_wall)
	# Furniture as indoor cover.
	_box(Vector3(2.0, 0.8, 1.0), Vector3(11, 0.4, 4), _mat_cover, Vector3.ZERO, "wood")
	_box(Vector3(0.5, 1.8, 2.0), Vector3(19.5, 0.9, 5), _mat_cover, Vector3.ZERO, "wood")
	_box(Vector3(1.6, 0.9, 0.8), Vector3(12, 0.45, -5), _mat_cover, Vector3.ZERO, "wood")
	_label("TEST HOUSE", Vector3(14, 4.0, 8.5), 72)


func _build_platform() -> void:
	# Raised platform (top at 2 m) north of spawn, reached by stairs from the south.
	_box(Vector3(6, 2, 6), Vector3(0, 1, -18), _mat_wall)
	var x := 0.0
	var z0 := -10.0  # bottom of the stairs; top meets the platform edge at z = -15
	var steps := 10
	var rise := 0.2
	var run := 0.5
	for i in steps:
		var sh := (i + 1) * rise
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(2, sh, run)
		mi.mesh = m
		mi.material_override = _mat_accent
		mi.position = Vector3(x, sh / 2.0, z0 - run / 2.0 - i * run)
		add_child(mi)
	# Smooth wedge collider under the steps so the capsule walks up them.
	var top_z := z0 - steps * run
	var wedge := ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array([
		Vector3(-1, 0, z0), Vector3(1, 0, z0),
		Vector3(-1, 0, top_z), Vector3(1, 0, top_z),
		Vector3(-1, steps * rise, top_z), Vector3(1, steps * rise, top_z),
	])
	var body := StaticBody3D.new()
	body.position = Vector3(x, 0, 0)
	var cs := CollisionShape3D.new()
	cs.shape = wedge
	body.add_child(cs)
	add_child(body)
	# Low railing on the far edge.
	_box(Vector3(6, 0.9, 0.15), Vector3(0, 2.45, -20.9), _mat_cover, Vector3.ZERO, "wood")
	_label("PLATFORM", Vector3(0, 3.6, -18), 64)


# ---------------------------------------------------------------- shooting tests

func _flat_material(c: Color, transparent := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## A row of real-world barriers with a dummy behind each. Stand at the yellow line (z = 1).
func _build_barriers() -> void:
	var white := _flat_material(Color(0.9, 0.9, 0.88))
	var ply := _checker_material(Color(0.78, 0.62, 0.38), Color(0.72, 0.56, 0.33), 0.25)
	var glass := _flat_material(Color(0.6, 0.8, 0.95, 0.3), true)
	var car := _flat_material(Color(0.55, 0.08, 0.08))
	var steel := _flat_material(Color(0.42, 0.44, 0.47))
	var brick := _checker_material(Color(0.62, 0.32, 0.22), Color(0.55, 0.27, 0.19), 0.25)
	var conc := _mat_wall
	# name, ballistic material, sheet thickness (m), sheets, gap between sheets (m), look
	var rows := [
		["DRYWALL\n2 x 1/2 in stud wall", "drywall", 0.5 * Units.IN_TO_M, 2, 3.5 * Units.IN_TO_M, white],
		["PLYWOOD\n3/4 in", "plywood", 0.75 * Units.IN_TO_M, 1, 0.0, ply],
		["GLASS\n1/4 in", "glass", 0.25 * Units.IN_TO_M, 1, 0.0, glass],
		["CAR DOOR\n2 x 22 gauge", "sheet_metal", 0.03 * Units.IN_TO_M, 2, 4.0 * Units.IN_TO_M, car],
		["STEEL\n1/8 in", "steel", 0.125 * Units.IN_TO_M, 1, 0.0, steel],
		["STEEL\n1/4 in", "steel", 0.25 * Units.IN_TO_M, 1, 0.0, steel],
		["BRICK\n4 in", "brick", 4.0 * Units.IN_TO_M, 1, 0.0, brick],
		["CONCRETE\n6 in", "concrete", 6.0 * Units.IN_TO_M, 1, 0.0, conc],
	]
	var z := -4.0
	for i in rows.size():
		var r: Array = rows[i]
		var x := -11.0 + i * 2.3
		for k in int(r[3]):
			if r[1] == "glass":
				# Real pane: 2-4 holes, then it breaks into pieces; whole again after 5 s.
				var pane := GlassPane.new()
				pane.size = Vector2(1.5, 2.0)
				pane.thickness = r[2]
				pane.material = r[5]
				pane.respawn = 5.0
				pane.position = Vector3(x, 1.0, z)
				add_child(pane)
				continue
			_box(Vector3(1.5, 2.0, r[2]), Vector3(x, 1.0, z - k * (r[4] + r[2])), r[5], Vector3.ZERO, r[1])
		# Steel frame posts so the panel reads as mounted.
		_box(Vector3(0.06, 2.1, 0.06), Vector3(x - 0.78, 1.05, z), steel, Vector3.ZERO, "steel")
		_box(Vector3(0.06, 2.1, 0.06), Vector3(x + 0.78, 1.05, z), steel, Vector3.ZERO, "steel")
		_label(r[0], Vector3(x, 2.6, z), 44)
		var d := TargetDummy.new()
		d.position = Vector3(x, 0.0, z - 2.2)
		add_child(d)
	_box(Vector3(19.0, 0.05, 0.2), Vector3(-2.95, 0.03, 1.0), _mat_accent)
	_label("BARRIER TEST - shoot from here", Vector3(-2.95, 1.0, 1.4), 48)


func _build_dummies() -> void:
	# One target per lane: 25 ft, 25 / 50 / 75 / 100 yd.
	for lane: Array in LANES:
		var dummy := TargetDummy.new()
		dummy.position = Vector3(lane[0], 0.0, FIRING_LINE_Z - float(lane[2]))
		add_child(dummy)
	# Inside the house, behind the drywall partition: shoot it from the front room.
	var hidden := TargetDummy.new()
	hidden.position = Vector3(12.5, 0.0, -2.5)
	add_child(hidden)


## A row of randomly generated people: same base body, different skin, hair,
## beard, height, clothes and pocket contents every time the range loads.
## They can be shot (same body-part damage as the dummies) and searched.
func _build_civilians() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 5:
		var n := Npc.new()
		n.position = Vector3(9.5 + i * 2.2, 0.0, 11.5)
		n.rotation.y = PI  # face the spawn
		add_child(n)
		n.randomize_person(rng)
	_label("LOOT TEST - shoot them, then search the bodies (A)", Vector3(13.9, 2.4, 11.5), 44)


func _mag8() -> InvItem:
	var m := InvItem.create("mag_1911_8")
	m.mag_ammo = AmmoDB.get_ammo("45_2_jhp230")
	m.mag_count = 8
	return m


## Supply crate (A to search) and a mirror (A for a new look) next to spawn.
func _build_supply() -> void:
	var crate := LootContainer.new("Supply crate", 14, 16)
	crate.position = Vector3(-2.6, 0.45, 17.2)
	crate.set_meta("material", "wood_crate")
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 0.9, 0.8)
	mesh.mesh = box
	mesh.material_override = _checker_material(Color(0.42, 0.45, 0.28), Color(0.38, 0.41, 0.25), 0.25)
	crate.add_child(mesh)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	cs.shape = shape
	crate.add_child(cs)
	add_child(crate)
	_label("SUPPLY CRATE", Vector3(-2.6, 1.3, 17.2), 40)
	for id in ["backpack", "vest", "jacket", "cap", "beanie", "tshirt", "laptop"]:
		crate.add(InvItem.create(id))
	for a in AmmoDB.all_for(".45 ACP"):
		crate.add(InvItem.magazine(a, 7))
	for i in 4:
		crate.add(InvItem.magazine(null, 0))
	for a in AmmoDB.all_for(".45 ACP"):
		crate.add(InvItem.rounds(a.id, 50))
		crate.add(InvItem.rounds(a.id, 50))
	# 5.56 for the M4: two loaded 30-rounders of each load, empties, and loose rounds.
	for a in AmmoDB.all_for("5.56 NATO"):
		for i in 2:
			crate.add(InvItem.magazine(a, 30, "mag_stanag"))
	for i in 2:
		crate.add(InvItem.magazine(null, 0, "mag_stanag"))
	for a in AmmoDB.all_for("5.56 NATO"):
		crate.add(InvItem.rounds(a.id, 50))
	# Gun parts bench: attachments for the 1911, 8-round mags and a spare pistol.
	var bench := LootContainer.new("Gun parts", 10, 10)
	bench.position = Vector3(-4.6, 0.45, 17.2)
	bench.set_meta("material", "wood_crate")
	var bm := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.4, 0.9, 0.8)
	bm.mesh = bb
	bm.material_override = _checker_material(Color(0.3, 0.3, 0.32), Color(0.26, 0.26, 0.28), 0.25)
	bench.add_child(bm)
	var bcs := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = bb.size
	bcs.shape = bshape
	bench.add_child(bcs)
	add_child(bench)
	_label("GUN PARTS", Vector3(-4.6, 1.3, 17.2), 40)
	for id in ["barrel_1911_threaded", "supp_45", "rail_1911", "light_m3", "grips_1911_rubber", "sights_1911_night"]:
		bench.add(InvItem.create(id))
	for i in 3:
		bench.add(_mag8())
	bench.add(InvItem.pistol(AmmoDB.get_ammo("45_1_fmj230"), 7, true))
	bench.add(InvItem.rifle(AmmoDB.get_ammo("556_2_m855"), 30, false))
	for id in ["gpu", "medkit", "water", "ifak", "painkillers", "painkillers", "beans", "cash", "cash", "cash", "gold", "gold", "docs"]:
		crate.add(InvItem.create(id))

	var mirror := Mirror.new()
	mirror.position = Vector3(2.6, 1.0, 19.6)
	var glass := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.0, 1.9, 0.05)
	glass.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.75, 0.8, 0.85)
	gm.metallic = 0.9
	gm.roughness = 0.1
	glass.material_override = gm
	mirror.add_child(glass)
	var ms := CollisionShape3D.new()
	var mshape := BoxShape3D.new()
	mshape.size = pm.size
	ms.shape = mshape
	mirror.add_child(ms)
	mirror.set_meta("material", "glass")
	add_child(mirror)
	_label("MIRROR", Vector3(2.6, 2.2, 19.6), 40)
