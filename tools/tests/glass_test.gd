extends SceneTree
## Glass: panes are cut into 6-12 pieces, take 2-4 bullet holes, then break;
## the pieces near the hit fall out and land, some stay in the frame; range
## panels come back. Run: godot --headless --fixed-fps 60 -s tools/tests/glass_test.gd

const PANE := "res://scripts/ballistics/glass_pane.gd"
var f := 0
var fails := 0
var bal
var world: Node3D
var a          # the pane we shoot to pieces
var r          # a range pane (respawns)
var shots := [Vector2(-0.3, 0.25), Vector2(0.28, -0.3), Vector2(0.1, 0.38), Vector2(-0.22, -0.12), Vector2(0.3, 0.3)]
var shot_i := 0
var glass_hits := 0
var n0 := 0
var low_y := 0.0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _pane(pos: Vector3, seed_v: int, respawn := 0.0) -> Node3D:
	var p: Node3D = load(PANE).new()
	p.size = Vector2(1.0, 1.2)
	p.thickness = 0.006
	p.seed_value = seed_v
	p.respawn = respawn
	p.position = pos
	world.add_child(p)
	return p


func _initialize() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 1, 20)
	cs.shape = bs
	floor_b.add_child(cs)
	floor_b.position = Vector3(0, -0.5, 0)
	world.add_child(floor_b)
	a = _pane(Vector3(0, 1.4, 0), 12345)
	r = _pane(Vector3(4, 1.4, 0), 777, 1.0)


func _fire_at(p: Node3D, at: Vector2) -> void:
	var target: Vector3 = p.to_global(Vector3(at.x, at.y, 0))
	var from := target + Vector3(0, 0, 3.0)
	bal.fire(from, (target - from).normalized(), AmmoDB.get_ammo("45_1_fmj230"), RID())


func _holes(p: Node3D) -> int:
	var n := 0
	for s in p.shards:
		for c in s.get_children():
			if c.name.begins_with("Hole"):
				n += 1
	return n


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		bal = root.get_node("/root/Ballistics")
		bal.impact.connect(func(i): if i.material == "glass": glass_hits += 1)
		n0 = a.shards.size()
		check(n0 >= 6 and n0 <= 12, "a pane is cut into %d pieces (6-12)" % n0)
		var area := 0.0
		for s in a.shards:
			area += a.area_of(s.get_meta("poly"))
		check(absf(area - 1.2) < 0.001, "the pieces fill the pane exactly (%.4f of 1.2 m2)" % area)
		var rolls := {}
		var counts := {}
		var ok := true
		for i in 30:
			var p := _pane(Vector3(-10 + i * 0.3, 5, -5), 1000 + i)
			rolls[p.breaks_after()] = true
			counts[p.shards.size()] = true
			ok = ok and p.breaks_after() >= 2 and p.breaks_after() <= 4 and p.shards.size() >= 6 and p.shards.size() <= 12
			p.queue_free()
		check(ok and rolls.size() >= 2 and counts.size() >= 3, "panes take 2-4 hits (%s) and have 6-12 pieces (%s)" % [str(rolls.keys()), str(counts.keys())])
		print("      this pane breaks on hit %d" % a.breaks_after())
	# Shoot pane A once every 20 frames until it breaks.
	if f >= 10 and f < 200 and (f - 10) % 20 == 0 and not a.shattered and shot_i < shots.size():
		var before: int = a.hits
		if shot_i > 0:
			check(_holes(a) == before, "hit %d: a hole with cracks, still in one piece" % before)
		_fire_at(a, shots[shot_i])
		shot_i += 1
	if a.shattered and not has_meta("broke_at"):
		set_meta("broke_at", f)
		check(a.hits == a.breaks_after(), "it breaks on hit %d" % a.hits)
		var left: int = a.shards.size()
		check(left >= 1 and left < n0, "%d of %d pieces stay in the frame" % [left, n0])
		var loose := 0
		low_y = INF
		for c in world.get_children():
			if c is RigidBody3D:
				loose += 1
		check(loose == n0 - left and loose >= 1, "%d pieces come loose" % loose)
		var shown := true
		for s in a.shards:
			shown = shown and s.get_node("Mesh").visible
		check(shown, "the pieces left in the frame are drawn")
	if has_meta("broke_at") and f == get_meta("broke_at") + 120:
		var fell := 0
		var total := 0
		for c in world.get_children():
			if c is RigidBody3D:
				total += 1
				if c.global_position.y < 0.6:
					fell += 1
		check(total > 0 and fell == total, "and they fall to the floor (%d/%d)" % [fell, total])
		# Knock out a piece that stayed.
		var left: int = a.shards.size()
		var s = a.shards[0]
		var c: Vector2 = a.centroid_of(s.get_meta("poly"))
		_fire_at(a, c)
		set_meta("left", left)
	if has_meta("broke_at") and f == get_meta("broke_at") + 150:
		check(a.shards.size() == get_meta("left") - 1, "a shot knocks out a piece that was left (%d -> %d)" % [get_meta("left"), a.shards.size()])
		# Range pane: break it, it comes back.
		for i in 4:
			_fire_at(r, Vector2(-0.3 + i * 0.2, 0.1 * i))
	if has_meta("broke_at") and f == get_meta("broke_at") + 190:
		check(r.shattered, "a range pane breaks too")
	if has_meta("broke_at") and f == get_meta("broke_at") + 190 + 80:
		check(not r.shattered and r.shards.size() >= 6 and r.hits == 0, "and is whole again a second later (%d pieces)" % r.shards.size())
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	if f > 1200:
		check(false, "timed out (pane never broke)")
		quit(1)
	return false
