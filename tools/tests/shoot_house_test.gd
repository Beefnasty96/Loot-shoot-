extends SceneTree
## The 1995 shoot house: rooms, doors, wall construction vs bullets, windows.
## Run: godot --headless --fixed-fps 60 -s tools/tests/shoot_house_test.gd

var f := 0
var rs
var fails := 0
var hits: Array = []
var bal
var front


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	rs = load("res://scenes/shoot_house.tscn").instantiate()
	root.add_child(rs)


func _fire(from: Vector3, to: Vector3) -> void:
	bal.fire(from, (to - from).normalized(), AmmoDB.get_ammo("45_1_fmj230"), RID())


func _first_hit(mat: String) -> Dictionary:
	for h in hits:
		if h.material == mat:
			return h
	return {}


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		bal = root.get_node("/root/Ballistics")
		bal.impact.connect(func(i): hits.append(i))
		check(rs.rooms.size() >= 13, "%d rooms laid out" % rs.rooms.size())
		var doors := get_nodes_in_group("door")
		check(doors.size() == 9, "9 hinged doors (%d)" % doors.size())
		for d in doors:
			if d.label == "front door":
				front = d
		check(front != null and not front.is_open, "the front door starts closed")
		# This test is about the building: keep the occupants still so none of them
		# walks through the front door while we check it (enemy_ai_test covers them).
		for e in get_nodes_in_group("enemy"):
			e.process_mode = Node.PROCESS_MODE_DISABLED
		# Open it from the street side.
		front.use(rs.player)
		# Interior wall: from the hallway into bedroom 3 (2x4 + drywall).
		_fire(Vector3(5.0, 1.3, 0.3), Vector3(5.0, 1.3, -3.0))
		# Fireplace brick from the family room.
		_fire(Vector3(-1.4, 1.0, -2.0), Vector3(-1.4, 1.0, -6.0))
		# A front window from the lawn: glass takes 2-4 holes before it breaks.
		for c in rs.get_children():
			if c.has_method("breaks_after") and c.global_position.distance_to(Vector3(1.3, 1.3, 4.75)) < 1.0:
				set_meta("pane", c)
		_fire(Vector3(1.3, 1.3, 9.0), Vector3(1.3, 1.3, 2.0))
	if f == 8:
		var p = rs.player
		var seers := 0
		for e in rs.enemies:
			if rs.seen_by(e, p.global_position - Vector3(0, 0.05, 0)):
				seers += 1
		var pp: Vector3 = p.global_position
		check((pp.z > 6.0 or pp.x < -15.0 or pp.x > 12.0) and seers == 0, "you start outside where nobody inside can see you (%.1f, %.1f)" % [pp.x, pp.z])
	if f in [12, 21, 30] and has_meta("pane") and not get_meta("pane").shattered:
		var dx: float = [0.0, 0.3, -0.25, 0.2][[3, 12, 21, 30].find(f)]
		_fire(Vector3(1.3 + dx, 1.1 + dx, 9.0), Vector3(1.3 + dx, 1.1 + dx, 2.0))
	if f == 60:
		check(front.is_open and absf(front._hinge.rotation.y) > 1.4, "A swings the front door open")
		check(front._hinge.rotation.y > 0.0, "away from you (inward)")
		var dw := _first_hit("drywall_partition")
		print("      interior wall: %s, %d fps out" % [dw.get("result", "?"), roundi(AmmoType.ms_to_fps(dw.get("speed_out", 0.0)))])
		check(dw.get("result", "") == "penetrated", "a .45 goes through an interior wall")
		var br := _first_hit("brick")
		check(br.get("result", "") in ["stopped", "ricochet"], "but not through the brick fireplace (%s)" % br.get("result", "?"))
		var pane = get_meta("pane", null)
		check(pane != null and pane.shattered and pane.hits == pane.breaks_after(), "a window takes %d hits, then breaks" % (pane.breaks_after() if pane else 0))
		check(pane != null and pane.shards.size() >= 1, "and some of it stays in the frame (%d pieces)" % (pane.shards.size() if pane else 0))
		hits.clear()
		_fire(Vector3(6.0, 1.3, 9.0), Vector3(6.0, 1.3, -10.0))   # into bedroom 2 through siding
	if f == 90:
		var ext := _first_hit("exterior_sheathing")
		print("      exterior wall: %s" % ext.get("result", "?"))
		check(not ext.is_empty(), "the exterior wall is siding/OSB/drywall")
		front.close()
	if f == 60 + 420:
		var pane = get_meta("pane")
		check(pane != null and pane.shattered, "and stays broken")
		check(not front.is_open and absf(front._hinge.rotation.y) < 0.01, "the door closes again")
		var p = rs.player

		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
