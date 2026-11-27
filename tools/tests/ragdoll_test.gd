extends SceneTree
## Body mass, hit reactions and ragdolls.
## Run: godot --headless --fixed-fps 60 -s tools/tests/ragdoll_test.gd

var f := 0
var rs
var fails := 0
var npcs: Array = []
var hits: Array = []
var start_pos := {}
var bal


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	rs = load("res://scenes/shooting_range.tscn").instantiate()
	root.add_child(rs)


func _bone_world(n, bone: String, lift := Vector3.ZERO) -> Vector3:
	if n.model.ragdoll_active:
		return n.model._pbones[bone].global_position + lift
	var sk = n.model.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin + lift


func _shoot(n, bone: String, ammo_id: String, lift := Vector3.ZERO) -> void:
	var at := _bone_world(n, bone, lift)
	var from := at + Vector3(0, 0, 5)
	bal.fire(from, (at - from).normalized(), AmmoDB.get_ammo(ammo_id), RID())


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		bal = root.get_node("/root/Ballistics")
		bal.impact.connect(func(info):
			print("      [hit] f%d %s %s %s %.0fJ" % [f, info.zone, info.bone, info.result, info.deposited])
			if info.zone != "": hits.append(info))
		npcs = get_nodes_in_group("npc")
		# Masses: segments add up to body + gear.
		var n = npcs[0]
		n.model.update_ragdoll_masses()   # pockets were filled after spawn
		var sum := 0.0
		for pb in n.model._pbones.values():
			sum += pb.mass
		check(n.model._pbones.size() == 14, "14 ragdoll bodies per person")
		check(absf(sum - n.model.total_mass_kg()) < 0.5, "segment masses add up to body + gear (%.1f kg vs %.1f kg)" % [sum, n.model.total_mass_kg()])
		n.model.equipment.unequip("back")
		var before: float = n.model._pbones["UpperChest"].mass
		n.model.equipment.equip(GearInstance.create("backpack"))
		n.model.equipment.get_slot("back").grids[0].place(InvItem.create("gold"), Vector2i.ZERO)
		n.model.update_ragdoll_masses()
		check(n.model._pbones["UpperChest"].mass > before + 1.0, "a loaded backpack makes the chest heavier (%.1f -> %.1f kg)" % [before, n.model._pbones["UpperChest"].mass])
		# Arm hit: alive, flinches.
		_shoot(npcs[3], "LeftLowerArm", "45_1_fmj230")
	if f == 6:
		var n = npcs[3]
		check(not n.dead, "an arm hit doesn't kill")
		check(absf(n.model._react_angle("arm_l")) > 0.02 or absf(n.model._react_angle("arm_r")) > 0.02, "the arm flinches")
		# Same spot, FMJ vs JHP to the stomach of two people.
		hits.clear()
		_shoot(npcs[1], "Spine", "45_1_fmj230")
		_shoot(npcs[2], "Spine", "45_2_jhp230")
	if f == 9:
		var fmj := {}
		var jhp := {}
		for h in hits:
			if h.ammo.id == "45_1_fmj230" and fmj.is_empty():
				fmj = h
			if h.ammo.id == "45_2_jhp230" and jhp.is_empty():
				jhp = h
		var pf: float = npcs[1].hit_impulse(fmj) if not fmj.is_empty() else 0.0
		var pj: float = npcs[2].hit_impulse(jhp) if not jhp.is_empty() else 0.0
		print("      FMJ %s, deposited %.0f J, push %.1f kg·m/s" % [fmj.get("result", "?"), fmj.get("deposited", 0.0), pf])
		print("      JHP %s, deposited %.0f J, push %.1f kg·m/s" % [jhp.get("result", "?"), jhp.get("deposited", 0.0), pj])
		check(pj > pf * 1.3, "JHP (more energy left in the body) pushes harder than FMJ")
		check(absf(npcs[2].model._react_angle("torso")) > absf(npcs[1].model._react_angle("torso")) * 0.9, "and makes a bigger flinch")
	if f == 14:
		print("      stagger %.1f cm" % (npcs[2].model.position.length() * 100.0))
		check(npcs[2].model.position.length() > 0.01, "the hit person staggers back")
	if f == 40:
		# Kill two with head shots.
		for i in [1, 2]:
			start_pos[i] = _bone_world(npcs[i], "Hips")
			_shoot(npcs[i], "Head", "45_2_jhp230", Vector3(0, 0.12, 0))
	if f == 45:
		check(npcs[1].dead and npcs[2].dead, "head shots kill")
		check(npcs[1].model.ragdoll_active, "the body goes limp (ragdoll simulating)")
	if f == 45 + 480:
		for i in [1, 2]:
			var n = npcs[i]
			var hips: Vector3 = n.model._pbones["Hips"].global_position
			var head: Vector3 = n.model._pbones["Head"].global_position
			var speed := 0.0
			for pb in n.model._pbones.values():
				speed = maxf(speed, pb.linear_velocity.length())
			print("      body %d: hips y %.2f, head y %.2f, moved %.2f m, fastest part %.2f m/s" % [i, hips.y, head.y, Vector2(hips.x - start_pos[i].x, hips.z - start_pos[i].z).length(), speed])
			check(hips.y < 0.45 and head.y < 0.5, "body %d ends up on the floor" % i)
			check(hips.y > -0.05, "body %d didn't fall through the floor" % i)
			check(speed < 0.5, "body %d has settled" % i)
			check(n.interact_point().distance_to(hips) < 0.6, "body %d's search point follows the ragdoll" % i)
		# Shooting a corpse moves it.
		var c = npcs[1]
		start_pos[0] = c.model._pbones["UpperChest"].global_position
		_shoot(c, "UpperChest", "45_2_jhp230")
	if f == 45 + 483:
		var moved: float = npcs[1].model._pbones["UpperChest"].linear_velocity.length()
		check(moved > 0.03, "shooting a body pushes it (%.2f m/s)" % moved)
	if f == 45 + 490:
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
