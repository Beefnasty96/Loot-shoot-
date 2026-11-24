extends LevelKit
## Test level: a 1995 suburban ranch house to clear, built in code.
##
## 64 x 32 ft single storey with an attached two-car garage, on a lot with a lawn,
## driveway, sidewalk, street, a fenced back yard and a deck. Inside, builder-grade
## 1995: popcorn ceilings, beige carpet, almond appliances, oak cabinets, a
## country-geese wallpaper border, wood paneling and a brick fireplace in the
## family room, brass doorknobs, floral sofas and CRT TVs.
##
## Hostiles: five armed occupants (Enemy) — some hold rooms covering doorways,
## some patrol, one waits with a knife. Kill or incapacitate them all to clear
## the house; the HUD counts them down and times you. A navmesh is baked from
## the level at load (doors excluded, so they walk up and open them).
##
## Construction is real enough for bullets: interior walls are 2x4 + drywall
## (pistol rounds go through), exterior walls are siding/OSB/batts/drywall,
## hollow-core interior doors, a solid front door, windows that break, brick,
## porcelain and appliance steel.
##
## Rooms (x east, z toward the street, metres):
##   front row  z 0.6..4.75 : kitchen | foyer | living | laundry | bedroom 2 | office
##   hallway    z -0.6..0.6 : runs from the kitchen to the east wall
##   back row   z -5..-0.6  : dining | family | bath | bedroom 3 | master (+ master bath)
##   garage     x -14.7..-8, z -2..4.75

const X0 := -8.0
const X1 := 11.5
const Z0 := -5.0
const Z1 := 4.75
const GX0 := -14.7
const GZ0 := -2.0

var player: Player
var enemies: Array[Enemy] = []
var spawn_enemies := true        ## Tests turn this off to place their own.
var _clock := 0.0
var _cleared := false
var _hud: Node
var _nav: NavigationRegion3D
## Spots for the AI (next step): room centres the enemies can be placed in or patrol between.
var rooms := {}

var _paint: StandardMaterial3D
var _siding: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 1995
	DisplayServer.screen_set_keep_on(true)
	Ballistics.debug_enabled = false
	_materials()
	_environment()
	_lot()
	_shell()
	_interior_walls()
	_rooms()
	_furnish()
	_garage()
	_yard()
	_neighbours()
	batch_meshes()
	_bake_navigation()

	player = Player.new()
	player.name = "Player"
	player.position = Vector3(-2.55, 0.05, 15.0)    # on the sidewalk, facing the front door
	add_child(player)
	var hud: Node = load("res://scripts/hud.gd").new()
	hud.player = player
	add_child(hud)
	_hud = hud
	if spawn_enemies:
		_spawn_enemies()


func _process(delta: float) -> void:
	if _hud == null:
		return
	if enemies.is_empty():
		_hud.objective_text = ""
		return
	var left := 0
	for e in enemies:
		if is_instance_valid(e) and not e.dead and not e.incapacitated():
			left += 1
	if not _cleared:
		_clock += delta
	if left == 0 and not _cleared:
		_cleared = true
	var t := "%d:%02d" % [int(_clock) / 60, int(_clock) % 60]
	_hud.objective_text = ("HOUSE CLEAR  -  %s" % t) if _cleared else ("Hostiles: %d    %s" % [left, t])


# ------------------------------------------------------------------ AI

## Navmesh for the AI, baked from the static level geometry at load (doors are on their own layer).
func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.15          # with 0.1 m cells, 30 in interior doors stay open (capsules slide past the frames)
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.1
	nm.cell_height = 0.05
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.filter_baking_aabb = AABB(Vector3(-22, -1, -16), Vector3(42, 5, 32))
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = nm
	add_child(_nav)


## Five occupants: [room, weapon, role, facing toward, patrol rooms].
func _spawn_enemies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var plan := [
		["living", "pistol", "holder", Vector3(-2.55, 0, 4.7), []],                  # covers the front door
		["kitchen", "pistol", "pusher", Vector3(-8.0, 0, 1.8), ["kitchen", "dining"]],
		["master", "pistol", "holder", Vector3(7.8, 0, -0.6), []],                    # covers the bedroom door
		["family", "pistol", "pusher", Vector3(0.0, 0, 0.0), ["family", "hall", "office"]],
		["bedroom3", "knife", "holder", Vector3(4.4, 0, -0.6), []],                   # waits by the door
	]
	for p: Array in plan:
		var at: Vector3 = rooms[p[0]] + Vector3(rng.randf_range(-0.6, 0.6), 0.05, rng.randf_range(-0.6, 0.6))
		var pts: Array[Vector3] = []
		for r: String in p[4]:
			pts.append(rooms[r])
		add_enemy(at, p[3], p[1], p[2], pts, rng)


func add_enemy(at: Vector3, look_at_point: Vector3, weapon: String, role: String, patrol: Array[Vector3] = [], rng: RandomNumberGenerator = null) -> Enemy:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var e := Enemy.new()
	e.position = at
	var d := look_at_point - at
	e.rotation.y = atan2(-d.x, -d.z)
	e.patrol = patrol
	add_child(e)
	e.post = at
	e.post_facing = e.rotation.y
	e._yaw_target = e.rotation.y
	e.setup(rng, weapon, role)
	enemies.append(e)
	return e


func _materials() -> void:
	_paint = textured("paint", img_noise(Color(0.88, 0.85, 0.78), 0.015, 16, 2), 1.0, 0.9)    # "antique white" eggshell
	_siding = textured("siding", img_boards(Color(0.84, 0.82, 0.72), Color(0.6, 0.58, 0.5), 8), 0.8, 0.7)
	_mats["siding"] = _siding


func _ext_layers() -> Array:
	return [[0.016, "drywall", _paint], [EXT_WALL - 0.016, "exterior_sheathing", _siding]]


func _int_layers() -> Array:
	return [[INT_WALL, "drywall_partition", _paint]]


# ------------------------------------------------------------------ world

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.7, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.72, 0.85)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)      # late-afternoon sun from the south-west
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


func _lot() -> void:
	var lawn := textured("lawn", img_noise(Color(0.3, 0.45, 0.2), 0.06, 32, 7), 1.5, 1.0)
	var concrete := textured("concrete", img_noise(Color(0.68, 0.67, 0.64), 0.04, 32, 8), 1.2, 0.95)
	var asphalt := textured("asphalt", img_noise(Color(0.22, 0.22, 0.23), 0.05, 32, 9), 1.0, 0.95)
	box(Vector3(90, 1, 70), Vector3(0, -0.5, -5), lawn, "concrete")
	# House and garage slab (the floor finishes sit on top).
	box(Vector3(X1 - GX0, 0.02, Z1 - Z0), Vector3((X1 + GX0) / 2.0, 0.0, (Z0 + Z1) / 2.0), concrete, "concrete", 0.0, false)
	box(Vector3(6.7, 0.02, 7.0), Vector3((GX0 + X0) / 2.0, 0.005, Z1 + 3.5), concrete, "concrete", 0.0, false)   # driveway
	box(Vector3(1.0, 0.02, 4.2), Vector3(-2.55, 0.006, Z1 + 2.1), concrete, "concrete", 0.0, false)               # front walk
	box(Vector3(1.6, 0.03, 1.4), Vector3(-2.55, 0.008, Z1 + 0.7), concrete, "concrete", 0.0, false)               # stoop
	box(Vector3(90, 0.02, 1.5), Vector3(0, 0.007, 12.0), concrete, "concrete", 0.0, false)                       # sidewalk
	box(Vector3(90, 0.02, 8.0), Vector3(0, 0.004, 17.5), asphalt, "concrete", 0.0, false)                        # street
	var yellow := flat("lane", Color(0.85, 0.7, 0.2))
	for i in 12:
		box(Vector3(2.0, 0.005, 0.12), Vector3(-40.0 + i * 7.0, 0.016, 17.5), yellow, "concrete", 0.0, false)
	var curb := flat("curb", Color(0.6, 0.6, 0.58))
	box(Vector3(90, 0.12, 0.2), Vector3(0, 0.06, 13.4), curb, "concrete", 0.0, false)


func _shell() -> void:
	var ext := _ext_layers()
	var front_door := {ballistic = "solid_door", color = Color(0.12, 0.28, 0.2), thickness = 0.045, label = "front door"}
	# Front (z = Z1), inside is -Z.
	wall(Vector2(X0, Z1), Vector2(X1, Z1), ext, -1.0, [
		{at = 2.25, w = 1.5, kind = "window", sill = 42.0 * IN},          # over the kitchen sink
		{at = 5.45, w = 0.97, kind = "door", door = front_door},
		{at = 9.3, w = 2.6, kind = "window", sill = 0.55},                # living-room picture window
		{at = 15.0, w = 1.4, kind = "window"},
		{at = 18.0, w = 1.2, kind = "window"},
	])
	# Back (z = Z0), inside +Z.
	wall(Vector2(X0, Z0), Vector2(X1, Z0), ext, 1.0, [
		{at = 2.1, w = 1.8, kind = "window", sill = 0.0, head = DOOR_H},  # sliding glass door to the deck
		{at = 8.75, w = 1.1, kind = "window"},
		{at = 10.55, w = 0.7, kind = "window", sill = 1.4},
		{at = 13.3, w = 1.4, kind = "window"},
		{at = 16.0, w = 0.8, kind = "window", sill = 1.4},
		{at = 18.3, w = 1.4, kind = "window"},
	])
	# East (x = X1), inside -X.
	wall(Vector2(X1, Z0), Vector2(X1, Z1), ext, -1.0, [
		{at = 3.0, w = 1.2, kind = "window"},
		{at = 5.0, w = 0.9, kind = "window"},
		{at = 8.0, w = 1.0, kind = "window"},
	])
	# West: outside wall of the dining room, then the firewall to the garage with the kitchen door.
	wall(Vector2(X0, Z0), Vector2(X0, GZ0), ext, 1.0, [{at = 1.5, w = 1.2, kind = "window"}])
	var fire := [[0.016, "drywall", _paint], [EXT_WALL - 0.032, "exterior_sheathing", _paint], [0.016, "drywall", _paint]]
	wall(Vector2(X0, GZ0), Vector2(X0, Z1), fire, 1.0, [
		{at = 3.8, w = 0.86, kind = "door", door = {ballistic = "solid_door", color = Color(0.95, 0.94, 0.9), thickness = 0.045, label = "garage door"}},
	])
	# Ceiling slab and roof.
	box(Vector3(X1 - X0, 0.05, Z1 - Z0), Vector3((X0 + X1) / 2.0, CEILING + 0.045, (Z0 + Z1) / 2.0), _paint, "drywall")
	var shingles := textured("shingles", img_boards(Color(0.3, 0.28, 0.27), Color(0.18, 0.17, 0.17), 10, false, 64, 0.06), 1.0, 1.0)
	gable_roof(X0, Z0, X1, Z1, CEILING + 0.07, 25.0, shingles)
	# Shutters by the front windows (black louvered, very 1995) and a porch light.
	var shutter := textured("shutter", img_boards(Color(0.1, 0.12, 0.11), Color(0.04, 0.04, 0.04), 12), 0.4)
	for win in [[X0 + 9.3, 2.6], [X0 + 15.0, 1.4], [X0 + 18.0, 1.2]]:
		for side in [-1.0, 1.0]:
			box(Vector3(0.38, 1.3, 0.03), Vector3(win[0] + side * (win[1] / 2.0 + 0.24), 1.45, Z1 + EXT_WALL / 2.0 + 0.02), shutter, "wood", 0.0, false)
	var porch := OmniLight3D.new()
	porch.position = Vector3(-1.9, 2.0, Z1 + 0.3)
	porch.light_color = Color(1, 0.85, 0.6)
	porch.light_energy = 0.6
	porch.omni_range = 4.0
	add_child(porch)


func _interior_walls() -> void:
	var L := _int_layers()
	var door := {label = "door"}
	# Kitchen | foyer.
	wall(Vector2(-3.5, 0.6), Vector2(-3.5, Z1), L)
	# Foyer | living, cased opening.
	wall(Vector2(-1.6, 0.6), Vector2(-1.6, Z1), L, 1.0, [{at = 2.7, w = 1.2, kind = "open"}])
	# Front rooms | hallway.
	wall(Vector2(-1.6, 0.6), Vector2(X1, 0.6), L, 1.0, [
		{at = 2.1, w = 2.0, kind = "open"},
		{at = 6.3, w = 0.76, kind = "door", door = door},
		{at = 7.6, w = 0.76, kind = "door", door = {label = "door", is_open = true}},
		{at = 10.8, w = 0.76, kind = "door", door = door},
	])
	wall(Vector2(4.0, 0.6), Vector2(4.0, Z1), L)
	wall(Vector2(5.4, 0.6), Vector2(5.4, Z1), L)
	wall(Vector2(8.6, 0.6), Vector2(8.6, Z1), L)
	# Hallway | back rooms.
	wall(Vector2(-3.5, -0.6), Vector2(X1, -0.6), L, 1.0, [
		{at = 2.0, w = 2.0, kind = "open"},
		{at = 6.1, w = 0.71, kind = "door", door = {label = "bathroom door"}},
		{at = 7.9, w = 0.76, kind = "door", door = door},
		{at = 11.3, w = 0.76, kind = "door", door = {label = "door", is_open = true}},
	])
	# Dining | family, wide opening.
	wall(Vector2(-3.5, Z0), Vector2(-3.5, -0.6), L, 1.0, [{at = 2.5, w = 1.8, kind = "open"}])
	wall(Vector2(1.6, Z0), Vector2(1.6, -0.6), L)
	wall(Vector2(3.6, Z0), Vector2(3.6, -0.6), L)
	wall(Vector2(7.0, Z0), Vector2(7.0, -0.6), L)
	# Master bath.
	wall(Vector2(7.0, -2.9), Vector2(9.2, -2.9), L, 1.0, [{at = 1.5, w = 0.71, kind = "door", door = {label = "bathroom door"}}])
	wall(Vector2(9.2, Z0), Vector2(9.2, -2.9), L)


func _rooms() -> void:
	var carpet := textured("carpet_beige", img_noise(Color(0.72, 0.66, 0.56), 0.04, 32, 11), 0.4, 1.0)
	var carpet_mauve := textured("carpet_mauve", img_noise(Color(0.6, 0.47, 0.5), 0.04, 32, 12), 0.4, 1.0)
	var carpet_teal := textured("carpet_teal", img_noise(Color(0.3, 0.48, 0.48), 0.04, 32, 13), 0.4, 1.0)
	var carpet_blue := textured("carpet_blue", img_noise(Color(0.34, 0.4, 0.56), 0.04, 32, 14), 0.4, 1.0)
	var vinyl := textured("vinyl", img_checker(Color(0.86, 0.82, 0.7), Color(0.75, 0.68, 0.55)), 0.6, 0.5)
	var tile := textured("tile", img_checker(Color(0.93, 0.93, 0.9), Color(0.88, 0.88, 0.86), 32, 4), 0.6, 0.3)
	var oak := textured("oak_floor", img_boards(Color(0.62, 0.45, 0.26), Color(0.45, 0.3, 0.17), 8, true), 0.9, 0.5)
	room(X0, 0.6, -3.5, Z1, vinyl, true, 1.0);            rooms["kitchen"] = Vector3(-5.75, 0, 2.7)
	room(X0, Z0, -3.5, 0.6, vinyl, true, 0.9);            rooms["dining"] = Vector3(-5.75, 0, -2.5)
	room(-3.5, 0.6, -1.6, Z1, oak, true, 0.6);            rooms["foyer"] = Vector3(-2.55, 0, 2.7)
	room(-1.6, 0.6, 4.0, Z1, carpet, true, 1.0);          rooms["living"] = Vector3(1.2, 0, 2.7)
	room(4.0, 0.6, 5.4, Z1, vinyl, true, 0.5);            rooms["laundry"] = Vector3(4.7, 0, 2.7)
	room(5.4, 0.6, 8.6, Z1, carpet_teal, true, 0.8);      rooms["bedroom2"] = Vector3(7.0, 0, 2.7)
	room(8.6, 0.6, X1, Z1, carpet, true, 0.8);            rooms["office"] = Vector3(10.05, 0, 2.7)
	room(-3.5, -0.6, X1, 0.6, carpet, true, 0.7);         rooms["hall"] = Vector3(4.0, 0, 0.0)
	room(-3.5, Z0, 1.6, -0.6, carpet, true, 1.0);         rooms["family"] = Vector3(-0.95, 0, -2.8)
	room(1.6, Z0, 3.6, -0.6, tile, true, 0.6);            rooms["bath"] = Vector3(2.6, 0, -2.8)
	room(3.6, Z0, 7.0, -0.6, carpet_blue, true, 0.8);     rooms["bedroom3"] = Vector3(5.3, 0, -2.8)
	room(7.0, -2.9, X1, -0.6, carpet_mauve, true, 0.8);   rooms["master"] = Vector3(9.3, 0, -1.8)
	room(9.2, Z0, X1, -2.9, carpet_mauve, true, 0.0)
	room(7.0, Z0, 9.2, -2.9, tile, true, 0.5);            rooms["master_bath"] = Vector3(8.1, 0, -3.9)
	# Wallpaper border in the kitchen (country geese on cream) and wood paneling in the family room.
	var border := textured("geese", img_floral(Color(0.9, 0.86, 0.72), Color(0.95, 0.95, 0.95), Color(0.3, 0.45, 0.6)), 0.3, 0.8)
	for seg in [[Vector3(X0 + 0.02, 2.2, 2.7), Vector3(0.01, 0.18, 4.1)], [Vector3(-3.52, 2.2, 2.7), Vector3(0.01, 0.18, 4.1)], [Vector3(-5.75, 2.2, Z1 - 0.09), Vector3(4.5, 0.18, 0.01)]]:
		box(seg[1], seg[0], border, "drywall", 0.0, false)
	var panel := textured("paneling", img_boards(Color(0.45, 0.3, 0.17), Color(0.28, 0.18, 0.1), 6, true, 64, 0.05), 1.2, 0.6)
	# [x0, x1, z0, z1, y0, y1]: the paneled walls, leaving the openings and the window clear.
	var oh := DOOR_H
	var wh := 82.0 * IN
	var ws := 36.0 * IN
	for r in [
		[-3.44, -3.44, Z0, -3.4, 0.0, CEILING], [-3.44, -3.44, -1.6, -0.6, 0.0, CEILING], [-3.44, -3.44, -3.4, -1.6, oh, CEILING],
		[1.54, 1.54, Z0, -0.6, 0.0, CEILING],
		[-3.5, 0.2, Z0 + 0.09, Z0 + 0.09, 0.0, CEILING], [1.3, 1.6, Z0 + 0.09, Z0 + 0.09, 0.0, CEILING],
		[0.2, 1.3, Z0 + 0.09, Z0 + 0.09, 0.0, ws], [0.2, 1.3, Z0 + 0.09, Z0 + 0.09, wh, CEILING],
		[-3.5, -2.5, -0.66, -0.66, 0.0, CEILING], [-0.5, 1.6, -0.66, -0.66, 0.0, CEILING], [-2.5, -0.5, -0.66, -0.66, oh, CEILING],
	]:
		var size := Vector3(maxf(r[1] - r[0], 0.01), r[5] - r[4], maxf(r[3] - r[2], 0.01))
		box(size, Vector3((r[0] + r[1]) / 2.0, (r[4] + r[5]) / 2.0, (r[2] + r[3]) / 2.0), panel, "wood", 0.0, false)
	# Tile wainscot in the bathrooms.
	var wainscot := flat("wainscot", Color(0.85, 0.9, 0.88), 0.3)
	for seg in [[Vector3(1.66, 0.6, -2.8), Vector3(0.01, 1.2, 4.4)], [Vector3(3.54, 0.6, -2.8), Vector3(0.01, 1.2, 4.4)], [Vector3(2.6, 0.6, Z0 + 0.09), Vector3(2.0, 1.2, 0.01)]]:
		box(seg[1], seg[0], wainscot, "porcelain", 0.0, false)


# ------------------------------------------------------------------ furniture

func _furnish() -> void:
	var oak := textured("oak", img_boards(Color(0.66, 0.48, 0.28), Color(0.55, 0.38, 0.2), 4, false, 64, 0.06), 0.6, 0.6)
	var almond := flat("almond", Color(0.88, 0.84, 0.74), 0.4, 0.1)
	var laminate := flat("laminate", Color(0.85, 0.8, 0.68), 0.5)
	var floral := textured("sofa_floral", img_floral(Color(0.25, 0.32, 0.28), Color(0.72, 0.35, 0.4), Color(0.45, 0.55, 0.35)), 0.5, 0.95)
	var plaid := textured("plaid", img_checker(Color(0.55, 0.3, 0.2), Color(0.3, 0.32, 0.22), 32, 6), 0.4, 0.95)
	var black := flat("plastic_black", Color(0.08, 0.08, 0.09), 0.4)
	var beige_plastic := flat("beige_plastic", Color(0.86, 0.83, 0.74), 0.5)
	var white := flat("porcelain", Color(0.95, 0.95, 0.93), 0.2)
	var sheets := [flat("sheets_a", Color(0.78, 0.7, 0.85)), flat("sheets_b", Color(0.35, 0.45, 0.65)), flat("sheets_c", Color(0.85, 0.82, 0.75))]
	var brass := flat("brass", Color(0.78, 0.62, 0.25), 0.35, 0.8)

	# --- Kitchen: oak cabinets in an L, laminate tops, almond appliances, a peninsula to the dining nook.
	_counter(Vector3(-5.8, 0, Z1 - 0.32), 4.2, 0.62, oak, laminate)                 # under the window
	_counter(Vector3(X0 + 0.32, 0, 3.6), 2.2, 0.62, oak, laminate, 90.0)            # west wall
	_counter(Vector3(-6.0, 0, 0.95), 2.0, 0.62, oak, laminate)                      # peninsula
	box(Vector3(0.8, 0.02, 0.5), Vector3(-5.8, 0.92, Z1 - 0.32), flat("sink", Color(0.7, 0.72, 0.74), 0.2, 0.9), "sheet_metal", 0.0, false)
	box(Vector3(0.78, 1.72, 0.72), Vector3(-4.0, 0.86, Z1 - 0.42), almond, "appliance")         # fridge
	box(Vector3(0.76, 0.92, 0.66), Vector3(X0 + 0.38, 0.46, 2.0 + 0.6), almond, "appliance")    # range
	box(Vector3(0.6, 0.02, 0.6), Vector3(X0 + 0.38, 0.93, 2.6), black, "appliance", 0.0, false)
	box(Vector3(4.0, 0.75, 0.33), Vector3(-5.8, 1.85, Z1 - 0.2), oak, "cabinet")                # uppers
	box(Vector3(0.33, 0.75, 2.2), Vector3(X0 + 0.2, 1.85, 3.6), oak, "cabinet")

	# --- Dining nook: oak table, four chairs, a hutch.
	box(Vector3(1.5, 0.05, 0.9), Vector3(-5.8, 0.74, -2.6), oak, "wood")
	for lx in [-0.65, 0.65]:
		for lz in [-0.38, 0.38]:
			box(Vector3(0.06, 0.72, 0.06), Vector3(-5.8 + lx, 0.36, -2.6 + lz), oak, "wood")
	for c in [[-6.3, -3.25, 0.0], [-5.3, -3.25, 0.0], [-6.3, -1.95, 180.0], [-5.3, -1.95, 180.0]]:
		_chair(Vector3(c[0], 0, c[1]), c[2], oak)
	box(Vector3(0.45, 1.9, 1.4), Vector3(X0 + 0.3, 0.95, -1.5), oak, "cabinet")

	# --- Living room: floral sofa, recliner, oak coffee table, entertainment centre with a 27" CRT.
	_sofa(Vector3(2.75, 0, 1.15), 0.0, 2.1, floral)
	_sofa(Vector3(-0.9, 0, 2.6), 90.0, 0.9, plaid)                                   # recliner
	box(Vector3(1.1, 0.42, 0.6), Vector3(2.75, 0.21, 2.35), oak, "wood")
	box(Vector3(1.6, 1.25, 0.5), Vector3(3.15, 0.62, Z1 - 0.32), oak, "cabinet")
	_crt(Vector3(3.15, 0.55, Z1 - 0.38), 0.68)
	_lamp(Vector3(3.75, 0, 1.0), brass)
	box(Vector3(2.4, 0.01, 1.7), Vector3(1.8, 0.025, 2.4), flat("rug", Color(0.5, 0.22, 0.2), 1.0), "concrete", 0.0, false)

	# --- Foyer: a bench and a mirror.
	box(Vector3(0.4, 0.45, 1.0), Vector3(-3.25, 0.22, 3.6), oak, "wood")

	# --- Family room: brick fireplace, sectional, bookshelf, ceiling fan.
	var brick := textured("brick", img_brick(Color(0.55, 0.27, 0.2), Color(0.7, 0.68, 0.62)), 0.9, 0.95)
	box(Vector3(1.8, CEILING, 0.55), Vector3(-1.4, CEILING / 2.0, Z0 + 0.32), brick, "brick")
	box(Vector3(0.8, 0.7, 0.1), Vector3(-1.4, 0.45, Z0 + 0.55), black, "brick", 0.0, false)        # firebox
	box(Vector3(2.0, 0.08, 0.3), Vector3(-1.4, 1.3, Z0 + 0.62), oak, "wood", 0.0, false)          # mantel
	_sofa(Vector3(-1.0, 0, -2.3), 180.0, 2.2, floral)
	_sofa(Vector3(-3.05, 0, -2.9), 90.0, 1.6, floral)
	box(Vector3(0.35, 1.8, 1.2), Vector3(1.3, 0.9, -3.4), oak, "cabinet")
	_fan(Vector3(-0.95, CEILING, -2.8), oak, brass)

	# --- Hall bath: tub, toilet, vanity.
	box(Vector3(1.9, 0.5, 0.78), Vector3(2.6, 0.25, Z0 + 0.45), white, "porcelain")
	_toilet(Vector3(3.25, 0, -3.3), 270.0, white)
	_counter(Vector3(1.95, 0, -1.6), 0.9, 0.55, oak, flat("marble", Color(0.92, 0.9, 0.85), 0.3), 90.0)
	box(Vector3(0.02, 0.8, 0.9), Vector3(1.67, 1.5, -1.6), flat("mirror", Color(0.75, 0.8, 0.85), 0.05, 0.9), "glass", 0.0, false)

	# --- Bedroom 3 (kid's room): twin bed, dresser, toy chest, posters.
	_bed(Vector3(4.3, 0, -3.8), 0.0, Vector2(1.0, 1.95), sheets[1], oak)
	box(Vector3(1.0, 0.85, 0.45), Vector3(6.3, 0.42, -0.95), oak, "cabinet")
	box(Vector3(0.8, 0.45, 0.45), Vector3(6.4, 0.22, -4.6), flat("toy_red", Color(0.75, 0.15, 0.12)), "wood")
	_poster(Vector3(3.67, 1.6, -2.4), 90.0, Color(0.2, 0.35, 0.8))
	_poster(Vector3(5.3, 1.6, Z0 + 0.09), 0.0, Color(0.9, 0.7, 0.15))

	# --- Master: queen bed against the back wall, nightstands, dresser.
	_bed(Vector3(10.4, 0, -3.95), 0.0, Vector2(1.55, 2.0), sheets[0], oak)
	for nx in [9.35, 11.35]:
		box(Vector3(0.45, 0.6, 0.4), Vector3(nx, 0.3, Z0 + 0.25), oak, "cabinet")
	box(Vector3(1.6, 0.85, 0.5), Vector3(9.6, 0.42, -0.9), oak, "cabinet")
	box(Vector3(1.2, 0.9, 0.02), Vector3(9.6, 1.4, -0.66), flat("mirror", Color(0.75, 0.8, 0.85), 0.05, 0.9), "glass", 0.0, false)

	# --- Master bath: shower stall, toilet, vanity.
	box(Vector3(0.9, 2.0, 0.9), Vector3(7.5, 1.0, Z0 + 0.5), flat("shower", Color(0.85, 0.9, 0.92, 1.0), 0.2), "glass")
	_toilet(Vector3(8.8, 0, -4.4), 0.0, white)
	_counter(Vector3(7.3, 0, -3.5), 0.9, 0.5, oak, flat("marble", Color(0.92, 0.9, 0.85), 0.3), 90.0)

	# --- Bedroom 2 (teenager): full bed, dresser with a small TV, posters.
	_bed(Vector3(7.6, 0, 3.6), 90.0, Vector2(1.4, 1.95), sheets[1], black)
	box(Vector3(1.2, 0.85, 0.5), Vector3(6.0, 0.42, 4.4), oak, "cabinet")
	_crt(Vector3(6.0, 0.86 + 0.2, 4.35), 0.36)
	_poster(Vector3(5.47, 1.6, 2.6), 90.0, Color(0.1, 0.1, 0.1))
	_poster(Vector3(8.53, 1.7, 1.6), 270.0, Color(0.6, 0.2, 0.6))

	# --- Office: desk with a beige computer, filing cabinet, bookshelf.
	box(Vector3(1.5, 0.05, 0.7), Vector3(10.1, 0.74, 4.25), oak, "wood")
	box(Vector3(0.45, 0.72, 0.65), Vector3(9.55, 0.36, 4.25), oak, "cabinet")
	box(Vector3(0.45, 0.72, 0.65), Vector3(10.65, 0.36, 4.25), oak, "cabinet")
	box(Vector3(0.42, 0.38, 0.4), Vector3(10.0, 0.96, 4.3), beige_plastic, "crt")            # 15" monitor
	box(Vector3(0.18, 0.42, 0.45), Vector3(10.6, 0.98, 4.25), beige_plastic, "appliance")    # tower
	box(Vector3(0.45, 0.02, 0.16), Vector3(10.0, 0.775, 4.0), beige_plastic, "appliance", 0.0, false)
	box(Vector3(0.45, 1.3, 0.6), Vector3(X1 - 0.35, 0.65, 1.2), flat("file", Color(0.55, 0.55, 0.5), 0.5, 0.3), "sheet_metal")
	box(Vector3(1.0, 1.8, 0.32), Vector3(8.84, 0.9, 2.4), oak, "cabinet", 90.0)
	_chair(Vector3(10.1, 0, 3.6), 0.0, black)

	# --- Laundry: washer and dryer.
	box(Vector3(0.68, 0.92, 0.66), Vector3(4.37, 0.46, Z1 - 0.4), flat("white_appl", Color(0.94, 0.94, 0.92), 0.3), "appliance")
	box(Vector3(0.68, 0.92, 0.66), Vector3(5.05, 0.46, Z1 - 0.4), flat("white_appl", Color(0.94, 0.94, 0.92), 0.3), "appliance")


func _counter(pos: Vector3, length: float, depth: float, cab: Material, top: Material, rot := 0.0) -> void:
	var body := box(Vector3(length, 0.86, depth - 0.04), pos + Vector3(0, 0.43, 0), cab, "cabinet", rot)
	box(Vector3(length + 0.02, 0.04, depth), Vector3(0, 0.45, 0.02), top, "wood", 0.0, false, body)


func _sofa(pos: Vector3, rot: float, length: float, m: Material) -> void:
	var body := box(Vector3(length, 0.42, 0.9), pos + Vector3(0, 0.21, 0), m, "upholstery", rot)
	box(Vector3(length, 0.45, 0.22), Vector3(0, 0.43, -0.34), m, "upholstery", 0.0, true, body)       # back
	for s in [-1.0, 1.0]:
		box(Vector3(0.2, 0.25, 0.9), Vector3(s * (length / 2.0 - 0.1), 0.33, 0), m, "upholstery", 0.0, true, body)


func _chair(pos: Vector3, rot: float, m: Material) -> void:
	var body := box(Vector3(0.44, 0.05, 0.44), pos + Vector3(0, 0.45, 0), m, "wood", rot)
	box(Vector3(0.44, 0.5, 0.04), Vector3(0, 0.27, -0.2), m, "wood", 0.0, true, body)
	for lx in [-0.19, 0.19]:
		for lz in [-0.19, 0.19]:
			box(Vector3(0.04, 0.45, 0.04), Vector3(lx, -0.22, lz), m, "wood", 0.0, false, body)


func _bed(pos: Vector3, rot: float, size: Vector2, sheets: Material, frame: Material) -> void:
	var body := box(Vector3(size.x, 0.3, size.y), pos + Vector3(0, 0.15, 0), frame, "wood", rot)
	box(Vector3(size.x - 0.04, 0.25, size.y - 0.04), Vector3(0, 0.27, 0), sheets, "mattress", 0.0, true, body)
	box(Vector3(size.x, 1.0, 0.06), Vector3(0, 0.35, -size.y / 2.0), frame, "wood", 0.0, true, body)  # headboard
	box(Vector3(size.x * 0.4, 0.1, 0.35), Vector3(-size.x * 0.22, 0.44, -size.y / 2.0 + 0.25), flat("pillow", Color(0.95, 0.95, 0.92)), "mattress", 0.0, false, body)


func _crt(pos: Vector3, size: float) -> void:
	var tv := box(Vector3(size, size * 0.85, size * 0.85), pos + Vector3(0, size * 0.42, 0), flat("tv_case", Color(0.12, 0.12, 0.13), 0.5), "crt")
	box(Vector3(size * 0.82, size * 0.62, 0.01), Vector3(0, 0.02, size * 0.43), flat("tv_screen", Color(0.16, 0.2, 0.2), 0.1, 0.2), "crt", 0.0, false, tv)


func _lamp(pos: Vector3, brass: Material) -> void:
	cylinder(0.02, 1.5, pos + Vector3(0, 0.75, 0), brass, "sheet_metal", false)
	cylinder(0.2, 0.25, pos + Vector3(0, 1.55, 0), flat("shade", Color(0.95, 0.9, 0.78)), "upholstery", false)


func _fan(pos: Vector3, blades: Material, brass: Material) -> void:
	cylinder(0.1, 0.18, pos + Vector3(0, -0.2, 0), brass, "sheet_metal", false)
	for i in 5:
		var b := box(Vector3(0.6, 0.012, 0.12), pos + Vector3(0, -0.26, 0), blades, "wood", i * 72.0, false)
		b.translate_object_local(Vector3(0.38, 0, 0))


func _toilet(pos: Vector3, rot: float, m: Material) -> void:
	var body := box(Vector3(0.4, 0.4, 0.5), pos + Vector3(0, 0.2, 0), m, "porcelain", rot)
	box(Vector3(0.45, 0.4, 0.2), Vector3(0, 0.35, -0.32), m, "porcelain", 0.0, true, body)


func _poster(pos: Vector3, rot: float, c: Color) -> void:
	var p := box(Vector3(0.55, 0.8, 0.005), pos, flat("poster_%s" % c.to_html(), c, 0.6), "drywall", rot, false)
	box(Vector3(0.4, 0.12, 0.004), Vector3(0, 0.25, 0.003), flat("poster_title", Color(0.95, 0.9, 0.3), 0.6), "drywall", 0.0, false, p)


# ------------------------------------------------------------------ garage, yard, neighbours

func _garage() -> void:
	var ext := _ext_layers()
	wall(Vector2(GX0, GZ0), Vector2(GX0, Z1), ext, 1.0, [{at = 3.4, w = 0.86, kind = "window"}])
	wall(Vector2(GX0, GZ0), Vector2(X0, GZ0), ext, 1.0)
	wall(Vector2(GX0, Z1), Vector2(X0, Z1), ext, -1.0, [{at = 3.35, w = 4.9, kind = "open", head = 7.0 * FT}])
	# Sectional steel garage door, closed: ribbed white panels.
	var gdoor := textured("garage_door", img_boards(Color(0.93, 0.93, 0.9), Color(0.7, 0.7, 0.68), 4), 0.55, 0.5)
	box(Vector3(4.9, 7.0 * FT, 0.05), Vector3((GX0 + X0) / 2.0, 7.0 * FT / 2.0, Z1), gdoor, "appliance")
	box(Vector3(X0 - GX0, 0.05, Z1 - GZ0), Vector3((GX0 + X0) / 2.0, CEILING + 0.045, (GZ0 + Z1) / 2.0), _paint, "drywall")
	gable_roof(GX0, GZ0, X0, Z1, CEILING + 0.07, 22.0, _mats["shingles"], 0.3)
	room(GX0, GZ0, X0, Z1, flat("garage_floor", Color(0.55, 0.55, 0.53)), false, 0.7)
	# A maroon '90s sedan, workbench, shelves, mower.
	var maroon := flat("car_paint", Color(0.38, 0.06, 0.1), 0.35, 0.4)
	var glass: Material = _mats.get("glass", maroon)
	var car := box(Vector3(1.78, 0.75, 4.7), Vector3(-12.3, 0.55, 1.4), maroon, "car")
	box(Vector3(1.5, 0.5, 2.4), Vector3(0, 0.62, -0.2), glass, "car", 0.0, true, car)   # cabin
	for wx in [-0.85, 0.85]:
		for wz in [-1.5, 1.5]:
			cylinder(0.32, 0.2, car.position + Vector3(wx, -0.22, wz), flat("tyre", Color(0.06, 0.06, 0.06)), "car", false).rotation_degrees.z = 90.0
	var pine := textured("pine", img_boards(Color(0.75, 0.6, 0.38), Color(0.6, 0.45, 0.28), 4), 0.6)
	box(Vector3(2.4, 0.9, 0.6), Vector3(-10.0, 0.45, GZ0 + 0.35), pine, "wood")
	box(Vector3(1.8, 1.8, 0.45), Vector3(-13.6, 0.9, GZ0 + 0.3), flat("shelf_steel", Color(0.4, 0.42, 0.42), 0.5, 0.4), "sheet_metal")
	box(Vector3(0.55, 0.4, 0.9), Vector3(-9.0, 0.2, 3.9), flat("mower", Color(0.75, 0.15, 0.1), 0.4), "sheet_metal")


func _yard() -> void:
	var fence := textured("fence", img_boards(Color(0.6, 0.48, 0.32), Color(0.4, 0.3, 0.2), 8, true), 1.2)
	# 6 ft privacy fence around the back yard.
	var fy := 6.0 * FT
	box(Vector3(X1 - GX0 + 4.0, fy, 0.05), Vector3((X1 + GX0) / 2.0, fy / 2.0, Z0 - 9.0), fence, "wood")
	box(Vector3(0.05, fy, 9.0), Vector3(GX0 - 2.0, fy / 2.0, Z0 - 4.5), fence, "wood")
	box(Vector3(0.05, fy, 9.0), Vector3(X1 + 2.0, fy / 2.0, Z0 - 4.5), fence, "wood")
	box(Vector3(2.0, fy, 0.05), Vector3(GX0 - 1.0, fy / 2.0, GZ0), fence, "wood")
	box(Vector3(2.0, fy, 0.05), Vector3(X1 + 1.0, fy / 2.0, -2.0), fence, "wood")
	# Deck off the sliding door, a grill.
	var deck := textured("deck", img_boards(Color(0.55, 0.42, 0.28), Color(0.35, 0.25, 0.15), 8, true), 0.9)
	box(Vector3(5.5, 0.04, 3.2), Vector3(-5.2, 0.02, Z0 - 1.6), deck, "wood", 0.0, false)
	cylinder(0.3, 0.6, Vector3(-3.4, 0.6, Z0 - 2.4), flat("grill", Color(0.08, 0.08, 0.08), 0.4, 0.3), "sheet_metal")
	# Trees, a mailbox, hedges under the front windows.
	var bark := flat("bark", Color(0.3, 0.22, 0.15))
	var leaves := flat("leaves", Color(0.2, 0.38, 0.16), 1.0)
	for t in [Vector3(5.0, 0, 8.5), Vector3(-18.0, 0, -6.0), Vector3(8.0, 0, -11.5)]:
		cylinder(0.18, 3.0, t + Vector3(0, 1.5, 0), bark, "wood")
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.0
		sm.height = 3.2
		sm.radial_segments = 10
		sm.rings = 6
		crown.mesh = sm
		crown.material_override = leaves
		crown.position = t + Vector3(0, 4.0, 0)
		add_child(crown)
	cylinder(0.05, 1.1, Vector3(-11.4, 0.55, 11.5), flat("post", Color(0.3, 0.3, 0.3)), "wood")
	box(Vector3(0.2, 0.22, 0.48), Vector3(-11.4, 1.2, 11.5), flat("mailbox", Color(0.12, 0.12, 0.12), 0.4, 0.5), "sheet_metal")
	var hedge := flat("hedge", Color(0.16, 0.32, 0.14), 1.0)
	box(Vector3(3.6, 0.8, 0.7), Vector3(X0 + 9.3, 0.4, Z1 + 0.55), hedge, "upholstery")
	box(Vector3(5.0, 0.8, 0.7), Vector3(X0 + 16.5, 0.4, Z1 + 0.55), hedge, "upholstery")
	label3d("1995 SUBURBAN SHOOT HOUSE\nclear it room by room", Vector3(-2.55, 2.4, 12.4), 40)


## Two neighbouring houses as closed shells for a sense of street.
func _neighbours() -> void:
	var colours := [Color(0.75, 0.78, 0.82), Color(0.82, 0.76, 0.62)]
	var i := 0
	for x in [-30.0, 26.0]:
		var sid := textured("siding_n%d" % i, img_boards(colours[i], colours[i].darkened(0.25), 8), 0.8, 0.7)
		box(Vector3(16.0, CEILING, 10.0), Vector3(x, CEILING / 2.0, 0.0), sid, "exterior_sheathing")
		gable_roof(x - 8.0, -5.0, x + 8.0, 5.0, CEILING, 25.0, _mats["shingles"])
		box(Vector3(0.95, DOOR_H, 0.05), Vector3(x, DOOR_H / 2.0, 5.02), flat("ndoor", Color(0.95, 0.94, 0.9)), "solid_door")
		i += 1
