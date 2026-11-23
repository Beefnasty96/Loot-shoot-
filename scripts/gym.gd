extends Node3D
## Grey-box test gym, built in code: open yard with cover, a firing lane with
## distance markers, a two-room building with a roof, and stairs to a platform.
## Everything sits on a 1 m checker grid so distances are easy to judge.

const WALL_T := 0.3

var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_cover: StandardMaterial3D
var _mat_accent: StandardMaterial3D
var player: Player


func _ready() -> void:
	DisplayServer.screen_set_keep_on(true)
	_mat_floor = _checker_material(Color(0.42, 0.42, 0.40), Color(0.36, 0.36, 0.34), 1.0)
	_mat_wall = _checker_material(Color(0.62, 0.60, 0.55), Color(0.56, 0.54, 0.50), 1.0)
	_mat_cover = _checker_material(Color(0.55, 0.42, 0.26), Color(0.48, 0.36, 0.22), 0.5)
	_mat_accent = _checker_material(Color(0.70, 0.55, 0.20), Color(0.62, 0.48, 0.16), 0.5)

	_build_environment()
	_build_yard()
	_build_lane()
	_build_house()
	_build_platform()

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


func _box(size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
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
	_box(Vector3(x1 - x0, h, WALL_T), Vector3((x0 + x1) / 2.0, y0 + h / 2.0, z), _mat_wall)


## Wall running along Z at x, from z0 to z1.
func _wall_z(x: float, z0: float, z1: float, h: float, y0 := 0.0) -> void:
	_box(Vector3(WALL_T, h, z1 - z0), Vector3(x, y0 + h / 2.0, (z0 + z1) / 2.0), _mat_wall)


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
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


func _build_yard() -> void:
	# Ground and perimeter.
	_box(Vector3(48, 1, 48), Vector3(0, -0.5, 0), _mat_floor)
	_wall_x(-24, -24, 24, 4)
	_wall_x(24, -24, 24, 4)
	_wall_z(-24, -24, 24, 4)
	_wall_z(24, -24, 24, 4)

	# Cover near spawn: low walls (crouch behind) and crates (stand behind).
	_box(Vector3(3, 1.0, 0.4), Vector3(-4, 0.5, 13), _mat_cover)
	_box(Vector3(3, 1.0, 0.4), Vector3(3, 0.5, 11), _mat_cover)
	_box(Vector3(1.2, 1.2, 1.2), Vector3(-7, 0.6, 9), _mat_cover, Vector3(0, 20, 0))
	_box(Vector3(1.2, 1.2, 1.2), Vector3(-7.2, 1.8, 9.1), _mat_cover, Vector3(0, 5, 0))
	_box(Vector3(1.0, 1.0, 1.0), Vector3(5, 0.5, 5), _mat_cover)
	_box(Vector3(0.6, 2.8, 0.6), Vector3(-2, 1.4, 4), _mat_wall)  # pillar for leaning practice
	_box(Vector3(0.6, 2.8, 0.6), Vector3(2, 1.4, -1), _mat_wall)

	_label("SPAWN", Vector3(0, 2.5, 21), 72)


func _build_lane() -> void:
	# Firing lane down the west side: posts every 10 m from the line at z = 18.
	_box(Vector3(6, 0.05, 0.2), Vector3(-14, 0.03, 18), _mat_accent)  # firing line
	_label("FIRING LINE", Vector3(-14, 1.2, 18.5), 64)
	for d: int in [10, 20, 30]:
		var z: float = 18.0 - d
		_box(Vector3(0.25, 2.0, 0.25), Vector3(-17, 1.0, z), _mat_accent)
		_label("%d m" % d, Vector3(-17, 2.5, z))
	# Backstop.
	_box(Vector3(8, 3, 0.6), Vector3(-14, 1.5, -15), _mat_wall)


func _build_house() -> void:
	# Two-room building: x 8..20, z -8..8, 3 m tall, roof on top.
	var h := 3.0
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
	# Interior wall with doorway 16.8..18.2.
	_wall_x(0, 8, 16.8, h)
	_wall_x(0, 18.2, 20, h)
	_wall_x(0, 16.8, 18.2, 0.8, 2.2)
	# Roof.
	_box(Vector3(12.3, 0.2, 16.3), Vector3(14, h + 0.1, 0), _mat_wall)
	# Furniture as indoor cover.
	_box(Vector3(2.0, 0.8, 1.0), Vector3(11, 0.4, 4), _mat_cover)
	_box(Vector3(0.5, 1.8, 2.0), Vector3(19.5, 0.9, 5), _mat_cover)
	_box(Vector3(1.6, 0.9, 0.8), Vector3(12, 0.45, -5), _mat_cover)
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
	_box(Vector3(6, 0.9, 0.15), Vector3(0, 2.45, -20.9), _mat_cover)
	_label("PLATFORM", Vector3(0, 3.6, -18), 64)
