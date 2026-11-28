extends SceneTree
## Generated suburban houses: every layout is walkable, seeds rebuild the same
## house, both the ranch and the two-storey colonial come up, and you can climb
## the stairs. Run: godot --headless --fixed-fps 60 -s tools/tests/house_gen_test.gd

const SCENE := "res://scenes/suburban_house.tscn"
const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 11, 23, 42, 99]

var f := 0
var fails := 0
var rs
var idx := -1
var styles := {}
var stair_seed := 0
var phase := "seeds"
var wait := 0
var first_plan := ""
var spots_in_view := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _plan_text(level) -> String:
	var out := ""
	for r in level.plan:
		out += "%s %.3f %.3f %.3f %.3f|" % [r.name, r.x0, r.z0, r.x1, r.z1]
	return out


func _load(seed_v: int, enemies := true) -> void:
	if rs:
		rs.free()
	rs = load(SCENE).instantiate()
	rs.layout_seed = seed_v
	rs.spawn_enemies = enemies
	root.add_child(rs)
	wait = 0


func _initialize() -> void:
	_next_seed()


func _next_seed() -> void:
	idx += 1
	if idx < SEEDS.size():
		_load(SEEDS[idx])


func _check_layout() -> void:
	var s: int = SEEDS[idx]
	var tag := "#%d %s" % [s, rs.summary]
	styles[rs.style] = true
	if rs.style == "colonial" and stair_seed == 0:
		stair_seed = s
	check(rs.rooms.size() >= 9, "%s: %d rooms" % [tag, rs.rooms.size()])
	var doors := get_nodes_in_group("door")
	var fronts := doors.filter(func(d): return d.label == "front door")
	check(fronts.size() == 1 and not fronts[0].is_open, "%s: one front door, shut (%d doors)" % [tag, doors.size()])
	var pp: Vector3 = rs.player.global_position
	var outside: bool = pp.x < rs.fx0 - 0.5 or pp.x > rs.fx1 + 0.5 or pp.z < rs.fz0 - 0.5 or pp.z > rs.fz1 + 0.5
	var seers := 0
	for e in rs.enemies:
		if rs.seen_by(e, pp - Vector3(0, 0.05, 0)):
			seers += 1
	check(outside and seers == 0, "%s: you start outside where nobody can see you (%.1f, %.1f; seen by %d)" % [tag, pp.x, pp.z, seers])
	# (and the check has teeth: some of the other spots are in view)
	for c in rs.spawn_candidates():
		for e in rs.enemies:
			if rs.seen_by(e, c):
				spots_in_view += 1
				break
	var map: RID = rs.get_world_3d().navigation_map
	var street := Vector3(rs.front_door_pos.x, 0, 13.0)
	var bad: Array = []
	for name in rs.rooms:
		var target: Vector3 = rs.rooms[name]
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, street, target, true)
		var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3(INF, INF, INF)
		if Vector2(end.x - target.x, end.z - target.z).length() > 0.6 or absf(end.y - target.y) > 0.6:
			bad.append(name)
	check(bad.is_empty(), "%s: every room can be walked to from the street %s" % [tag, "" if bad.is_empty() else str(bad)])
	if rs.stories == 2:
		var up := 0
		for name in rs.rooms:
			if rs.rooms[name].y > 2.0:
				up += 1
		check(up >= 4, "%s: %d rooms upstairs" % [tag, up])
	var n: int = rs.enemies.size()
	check(n >= 4 and n <= 7, "%s: %d occupants" % [tag, n])
	var stuck := 0
	for e in rs.enemies:
		var cp: Vector3 = NavigationServer3D.map_get_closest_point(map, e.global_position)
		if Vector2(cp.x - e.global_position.x, cp.z - e.global_position.z).length() > 0.4:
			stuck += 1
	check(stuck == 0, "%s: every occupant starts on walkable floor (%d off)" % [tag, stuck])
	# Freeze them so the next layout starts clean.
	for e in rs.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED


func _process(_d: float) -> bool:
	f += 1
	wait += 1
	match phase:
		"seeds":
			if wait == 4:
				_check_layout()
				_next_seed()
				if idx >= SEEDS.size():
					check(styles.has("ranch") and styles.has("colonial"), "both plans come up (%s)" % str(styles.keys()))
					check(spots_in_view > 10, "%d possible start spots were in an occupant's view (so they weren't used)" % spots_in_view)
					phase = "same"
					_load(SEEDS[0], false)
		"same":
			if wait == 3:
				first_plan = _plan_text(rs)
				_load(SEEDS[0], false)
				phase = "same_b"
		"same_b":
			if wait == 3:
				check(_plan_text(rs) == first_plan, "the same seed rebuilds the same house")
				_load(SEEDS[1], false)
				phase = "same_c"
		"same_c":
			if wait == 3:
				check(_plan_text(rs) != first_plan, "a different seed makes a different house")
				phase = "stairs"
				_load(stair_seed, false)
		"stairs":
			if wait == 3:
				var st: Dictionary = rs.stair
				var p = rs.player
				p.global_position = Vector3((st.x0 + st.x1) / 2.0, 0.1, st.z_base + 0.6)
				p.rotation.y = 0.0      # facing -Z, up the flight
				p.velocity = Vector3.ZERO
				Input.action_press("move_forward")
			if wait == 3 + 240:
				Input.action_release("move_forward")
				var y: float = rs.player.global_position.y
				check(y > rs.FH - 0.3, "you can walk up the stairs (y %.2f m)" % y)
				print("%d failure(s)" % fails)
				quit(1 if fails else 0)
	return false
