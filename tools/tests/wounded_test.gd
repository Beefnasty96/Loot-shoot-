extends SceneTree
## People who are shot but alive act hurt.
## Run: godot --headless --fixed-fps 60 -s tools/tests/wounded_test.gd

var f := 0
var rs
var fails := 0
var npcs: Array = []
var bal
var rest := {}


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	rs = load("res://scenes/shooting_range.tscn").instantiate()
	root.add_child(rs)


func _bw(n, bone: String) -> Vector3:
	var sk = n.model.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


func _shoot(n, bone: String, off := Vector3.ZERO) -> void:
	var at := _bw(n, bone) + off
	if bone.contains("Upper"):   # bone origins are joints: aim mid-way down the limb
		at = (_bw(n, bone) + _bw(n, bone.replace("Upper", "Lower"))) * 0.5 + off
	bal.fire(at + Vector3(0, 0, 5), Vector3(0, 0, -1), AmmoDB.get_ammo("45_1_fmj230"), RID())


func _calm(n) -> void:
	# Keep the test about body language: no arterial surprises.
	for w in n.damage.wounds:
		w.heavy = false
		w.rate = minf(w.rate, 3.0)


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		bal = root.get_node("/root/Ballistics")
		npcs = get_nodes_in_group("npc")
		for i in npcs.size():
			rest[i] = {
				hips = _bw(npcs[i], "Hips"), head = _bw(npcs[i], "Head"),
				lfoot = _bw(npcs[i], "LeftFoot"), rfoot = _bw(npcs[i], "RightFoot"),
				rhand = _bw(npcs[i], "RightHand"),
			}
		_shoot(npcs[0], "LeftUpperLeg")           # thigh
		_shoot(npcs[1], "RightUpperArm")          # arm
		_shoot(npcs[2], "Spine")                  # belly
		_shoot(npcs[3], "LeftLowerLeg")
		_shoot(npcs[3], "LeftUpperLeg")
		_shoot(npcs[3], "LeftUpperLeg", Vector3(0, 0.08, 0))
	if f == 8:
		for n in npcs:
			_calm(n)
		# Knock out npc 3's left leg completely and put npc 4 into blood-loss shock (no wound needed for that).
		npcs[3].damage.hp.leg_l = 0.0
		npcs[4].damage.wounds.append({zone = "stomach", bone = "Spine", rate = 0.0, heavy = false, through = false, lost = 0.0})
		npcs[4].damage.blood_ml = npcs[4].damage.blood_max * 0.66
	if f == 8 + 150:
		var a = npcs[0]
		print("      thigh: hurt %.2f, left foot up %.1f cm, hips shifted %.1f cm" % [a.model.hurt.leg_l, (_bw(a, "LeftFoot").y - rest[0].lfoot.y) * 100, (_bw(a, "Hips") - rest[0].hips).length() * 100])
		check(not a.dead and a.model.hurt.leg_l > 0.2, "a thigh hit hurts the leg")
		check(_bw(a, "LeftFoot").y - _bw(a, "RightFoot").y > 0.01, "they keep weight off it (foot lifted)")
		check(a.damage.mobility() < 0.95, "and it slows them (mobility %.2f)" % a.damage.mobility())

		var b = npcs[1]
		var hand := _bw(b, "LeftHand")
		var wound: Vector3 = b.model.clutch.global_position if b.model.clutch else Vector3.INF
		print("      arm: hurt %.2f, left hand %.0f cm from the wound" % [b.model.hurt.arm_r, hand.distance_to(wound) * 100])
		check(b.model.hurt.arm_r > 0.2, "an arm hit hurts the arm")
		check(hand.distance_to(wound) < 0.2, "the other hand holds the wounded arm")

		var c = npcs[2]
		var dz: Vector3 = _bw(c, "Head") - rest[2].head
		var near: float = minf(_bw(c, "LeftHand").distance_to(c.model.clutch.global_position), _bw(c, "RightHand").distance_to(c.model.clutch.global_position))
		print("      belly: head moved %.1f cm, hand %.0f cm from the wound, pain %.2f" % [dz.length() * 100, near * 100, c.pain])
		check(dz.length() > 0.03, "a belly wound makes them hunch over")
		check(near < 0.15, "with a hand pressed on it")
		check(c.pain > 0.1, "and they're in pain")

		var d = npcs[3]
		print("      leg out: kneel %.2f sit %.2f, hips at %.2f m" % [d.model.kneel, d.model.sit, _bw(d, "Hips").y])
		check(not d.dead and d.model.sit > 0.9, "a leg that gives out puts them on the ground")
		check(_bw(d, "Hips").y < 0.45, "sitting on the floor, still alive")

		var e = npcs[4]
		print("      shock %.2f, kneel %.2f" % [e.model.shock, e.model.kneel])
		check(e.model.shock > 0.5, "blood loss puts them in shock (pale, head down)")
		check(e.model.kneel > 0.9 and _bw(e, "Hips").y < rest[4].hips.y - 0.25, "and they sink to a knee")
		check(e.damage.steadiness() < 0.9, "shaky (steadiness %.2f)" % e.damage.steadiness())
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
