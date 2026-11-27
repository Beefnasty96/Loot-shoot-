class_name MissionLevel
extends LevelKit
## A level you clear: builds itself (build()), bakes a navmesh for the AI, puts the
## player at player_start with the HUD, spawns the occupants (_spawn_enemies())
## and counts them down with a timer. The fixed 1995 shoot house and every
## generated map type (MapTypes) sit on top of this.

var player: Player
var enemies: Array[Enemy] = []
var spawn_enemies := true        ## Tests turn this off to place their own.
## Layout seed. 0 = pick a new one every time the level loads (generated levels).
var layout_seed := 0
## Room name -> a free spot on its floor (enemies are placed in and patrol between these).
var rooms := {}
var player_start := Vector3.ZERO
var player_yaw := 0.0            ## Degrees; 0 faces -Z.
var clear_text := "CLEAR"
## What the navmesh is baked from (static colliders on layer 1 in here).
var nav_aabb := AABB(Vector3(-22, -1, -16), Vector3(42, 5, 32))

var _clock := 0.0
var _cleared := false
var _hud: Node
var _nav: NavigationRegion3D


func _ready() -> void:
	if layout_seed == 0:
		var r := RandomNumberGenerator.new()
		r.randomize()
		layout_seed = r.randi_range(1, 999999)
	DisplayServer.screen_set_keep_on(true)
	Ballistics.debug_enabled = false
	build()
	floor_y = 0.0
	batch_meshes()
	_bake_navigation()

	player = Player.new()
	player.name = "Player"
	player.position = player_start
	player.rotation.y = deg_to_rad(player_yaw)
	add_child(player)
	var hud: Node = load("res://scripts/hud.gd").new()
	hud.player = player
	add_child(hud)
	_hud = hud
	if spawn_enemies:
		_spawn_enemies()


## Build the level geometry and fill rooms / player_start / nav_aabb.
func build() -> void:
	pass


func _spawn_enemies() -> void:
	pass


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
	_hud.objective_text = ("%s  -  %s" % [clear_text, t]) if _cleared else ("Hostiles: %d    %s" % [left, t])


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
	nm.filter_baking_aabb = nav_aabb
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = nm
	add_child(_nav)


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
