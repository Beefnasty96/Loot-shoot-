extends SceneTree
## Enemy AI in the shoot house, and the player's own wounds, meds and death.
## (No Enemy/Player/Melee class names here: they depend on autoloads.)
## Run: godot --headless --fixed-fps 60 -s tools/tests/enemy_ai_test.gd

var f := 0
var rs
var p
var fails := 0
var A
var B
var C
var K
var step := {}


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	rs = load("res://scenes/shoot_house.tscn").instantiate()
	rs.spawn_enemies = false
	root.add_child(rs)


func _put_player(at: Vector3, yaw_deg := 0.0) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation = Vector3(0, deg_to_rad(yaw_deg), 0)


func _hurt_total() -> float:
	var lost := 0.0
	for z in p.vitals.damage.hp:
		lost -= p.vitals.damage.hp[z]
	return lost


func _process(_d: float) -> bool:
	f += 1
	if f == 5:
		p = rs.player
		var map: RID = rs.get_world_3d().navigation_map
		var unreachable := []
		for r in rs.rooms:
			var path: PackedVector3Array = NavigationServer3D.map_get_path(map, Vector3(-2.55, 0, 13.0), rs.rooms[r], true)
			var cp: Vector3 = NavigationServer3D.map_get_closest_point(map, rs.rooms[r])
			if path.is_empty() or path[path.size() - 1].distance_to(cp) > 0.3:
				unreachable.append(r)
		check(unreachable.is_empty(), "navmesh: every room can be walked to from the street %s" % ("" if unreachable.is_empty() else str(unreachable)))
		# 1) A pistol holder in the living room; you walk in front of him.
		A = rs.add_enemy(Vector3(3.2, 0.05, 2.6), Vector3(-1.0, 0, 2.6), "pistol", "holder")
		_put_player(Vector3(-0.6, 0.05, 2.6), -90.0)
		for z in p.vitals.damage.hp:      # tough enough to survive the test
			p.vitals.damage.hp[z] = 1000.0
		step.hurt0 = _hurt_total()
	if f == 5 + 90:
		check(A.awareness >= 1.0 and A.state == A.State.COMBAT, "an enemy who can see you engages (awareness %.2f)" % A.awareness)
	if f == 5 + 480:
		var lost: float = _hurt_total() - step.hurt0
		print("      you took %.0f HP of damage, blood %d%%" % [lost, roundi(p.vitals.damage.blood_fraction() * 100.0)])
		check(lost > 0.0 or p.vitals.dead, "and shoots you")
		check(A.mag < 7 or not A.chambered or A.reloading > 0.0, "spending real rounds (%d left in the mag)" % A.mag)
		# Make him wounded in both arms: aim gets worse.
		var e0: float = A.aim_error_deg()
		A.damage.hp.arm_l = 5.0
		A.damage.hp.arm_r = 5.0
		check(A.aim_error_deg() > e0 * 1.5, "shot-up arms ruin his aim (%.1f -> %.1f deg)" % [e0, A.aim_error_deg()])
		A.queue_free()
		rs.enemies.erase(A)
		p.vitals.damage.reset()
		p.vitals.pain = 0.0
		if p.vitals.dead:
			print("      (you died there; restarting the checks with a fresh body)")
		# 2) Through a wall: B in bedroom 3 facing the hall wall, you stand still in the hall behind it.
		B = rs.add_enemy(Vector3(5.3, 0.05, -1.4), Vector3(5.3, 0, 0.5), "pistol", "holder")
		C = rs.add_enemy(Vector3(10.0, 0.05, 2.8), Vector3(9.2, 0, 0.6), "pistol", "pusher")
		_put_player(Vector3(5.3, 0.05, 0.0), 90.0)
	if f == 5 + 600:
		check(not B.can_see_target and B.awareness < 0.5, "walls block their sight (awareness %.2f)" % B.awareness)
		# 3) You fire a shot in the hall: they hear it through the walls.
		var bal = root.get_node("/root/Ballistics")
		bal.fire(p.global_position + Vector3(0, 1.5, 0), Vector3(1, -0.2, 0), AmmoDB.get_ammo("45_1_fmj230"), p.get_rid())
		_put_player(Vector3(-3.0, 0.05, 3.5))      # and slip away to the foyer
		var office_door
		for d in get_nodes_in_group("door"):
			if d.global_position.distance_to(Vector3(9.2, 0, 0.6)) < 0.6:
				office_door = d
		step.office_door = office_door
		check(office_door != null and not office_door.is_open, "the office door is shut")
	if f == 5 + 620:
		check(B.awareness >= 0.55 and B.state != B.State.IDLE, "a gunshot next door puts them on alert (%.2f)" % B.awareness)
	if f == 5 + 1100:
		print("      pusher state %s, at %s" % [C.State.keys()[C.state], C.global_position])
		check(step.office_door.is_open, "the pusher opens the office door to investigate")
		check(C.global_position.distance_to(Vector3(10.0, 0.05, 2.8)) > 1.5, "and comes out looking (moved %.1f m)" % C.global_position.distance_to(Vector3(10.0, 0.05, 2.8)))
		B.queue_free()
		C.queue_free()
		rs.enemies.erase(B)
		rs.enemies.erase(C)
		p.vitals.damage.reset()
		# 4) A knife man in the garage; you're 5 m away in the open.
		K = rs.add_enemy(Vector3(-13.6, 0.05, 3.5), Vector3(-10.0, 0, 1.0), "knife", "pusher")
		_put_player(Vector3(-10.0, 0.05, -0.6), 0.0)
		p.rotation.y = atan2(-(-13.6 + 10.0), -(3.5 + 0.6))
	if f == 5 + 1500:
		var blade := false
		for w in p.vitals.damage.wounds:
			if w.get("kind", "") in ["stab", "slash"]:
				blade = true
		print("      knife man %.1f m away, you have %d wound(s)" % [K.global_position.distance_to(p.global_position), p.vitals.damage.wounds.size()])
		check(K.global_position.distance_to(p.global_position) < 1.6, "the knife man closes in")
		check(blade, "and cuts you")
		# 5) Shoot the knife man dead: he drops the knife, the body can be searched.
		K.damage.apply("head", 100.0)
		K.die()
	if f == 5 + 1520:
		check(K.dead and K.gun == null, "dead enemies drop their weapon")
		check(K.is_in_group("interactable"), "and can be searched")
		# 6) Meds: an arterial bleed and an IFAK in your pocket.
		p.vitals.damage.reset()
		p.vitals.damage.add_wound({zone = "leg_l", bone = "LeftUpperLeg", rate = 20.0, heavy = true, through = false, lost = 0.0})
		var msg: String = p.vitals.use_meds()
		print("      " + msg)
		check(msg.begins_with("Using"), "D-pad up reaches for the IFAK")
		check(not p.can_act(), "no shooting while you treat yourself")
	if f == 5 + 1520 + 330:
		check(not p.vitals.damage.is_bleeding_heavily(), "the tourniquet stops the arterial bleed")
		check(p.vitals._find("ifak").is_empty(), "and the IFAK is used up")
		check(p.can_act(), "then you're free to fight again")
		# 7) Death: lethal damage puts you down for good.
		p.vitals.take_hit({zone = "head", damage = 99.0, result = "stopped", wound_ratio = 1.0, depth_mm = 50.0, position = p.global_position + Vector3(0, 1.7, 0), normal = Vector3.UP, collider = null, exit_pos = null, direction = Vector3.FORWARD})
	if f == 5 + 1520 + 360:
		check(p.vitals.dead, "a head shot kills you")
		check(p.character.ragdoll_active and p.effective_view() == 1, "you go limp; the camera pulls back to third person")
		check(not p.can_act(), "and you can't act")
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
