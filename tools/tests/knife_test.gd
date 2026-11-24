extends SceneTree
## Ka-Bar: switching, stab and slash wounds, clothing, blood.
## (No class names that depend on autoloads here: Knife/Melee are reached through instances or load().)
## Run: godot --headless --fixed-fps 60 -s tools/tests/knife_test.gd

var f := 0
var rs
var p
var fails := 0
var npcs: Array = []
var hits: Array = []
var step := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_model_checks()
	rs = load("res://scenes/shooting_range.tscn").instantiate()
	root.add_child(rs)


func _model_checks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var stab := {kind = "stab", zone = "thorax", depth_mm = 170.0}
	var heavy := 0
	for i in 400:
		if DamageModel.make_blade_wound(stab.duplicate(), rng).heavy:
			heavy += 1
	var info := stab.duplicate()
	DamageModel.make_blade_wound(info, rng)
	print("      full-depth chest stab: %d HP, opens a vessel %d%% of the time" % [info.damage, heavy / 4])
	check(info.damage > 30.0 and info.damage < 45.0, "a deep chest stab does gunshot-class damage")
	check(heavy > 60 and heavy < 260, "and often opens a major vessel")
	var bare := {kind = "slash", zone = "arm_l", depth_mm = 20.0, length_mm = 150.0}
	var w := DamageModel.make_blade_wound(bare, rng)
	print("      forearm slash: %d HP, %.1f ml/s" % [bare.damage, w.rate])
	check(bare.damage < 15.0, "a slash does little damage")
	check(w.rate > 2.0 or w.heavy, "but bleeds freely")
	check(w.clot > 150.0, "and is slow to clot")
	var eq := Equipment.new()
	check(load("res://scripts/combat/melee.gd").cloth_resist(eq, "arm_l") == 0.0, "bare arm: nothing in the way")
	eq.equip(GearInstance.create("jacket"))
	check(load("res://scripts/combat/melee.gd").cloth_resist(eq, "arm_l") >= 8.0, "a jacket sleeve resists cuts")


func _face(n, bone: String, dist := 0.7) -> void:
	var sk = n.model.skeleton
	var at: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
	p.global_position = Vector3(at.x, 0.05, n.global_position.z + dist)
	p.rotation = Vector3.ZERO
	var eye: float = p.global_position.y + 1.62
	p.pitch = rad_to_deg(atan2(at.y - eye, dist))


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		p = rs.player
		var bal = root.get_node("/root/Ballistics")
		bal.melee_impact.connect(func(i): hits.append(i))
		npcs = get_nodes_in_group("npc")
		p.knife._rng.seed = 11
		p.switch_weapon("knife")
		check(p.active_weapon == "knife" and p.knife.view.visible and not p.viewmodel.visible, "Y swaps the 1911 for the Ka-Bar")
		var kb = p.character.equipment.get_weapon("melee")
		check(kb != null and absf(kb.weight() - 0.45) < 0.01 and p.carried_weight() >= kb.weight(), "the knife and sheath (1 lb) are in your sheath slot and your load")
		# Strip npc 1's top so the stab meets skin.
		for s in ["torso_inner", "torso_outer", "vest"]:
			npcs[1].model.equipment.unequip(s)
		_face(npcs[1], "Spine", 0.6)
	if f == 30:
		p.knife._begin(3)
	if f == 60:
		var n = npcs[1]
		check(not hits.is_empty() and hits[-1].zone != "", "the stab connects")
		if not hits.is_empty():
			var h: Dictionary = hits[-1]
			print("      stab %s %.0f mm deep, -%d HP, %s" % [h.zone, h.depth_mm, h.damage, h.bleed])
			check(h.depth_mm > 50.0, "and goes deep")
		check(n.damage.wounds.size() == 1 and n.damage.wounds[0].kind == "stab", "it leaves a stab wound")
		check(n.damage.wounds[0].has("marks") and n.damage.wounds[0].marks.size() == 2, "a slit and stain on the body")
		check(p.knife.blood > 0.3, "blood on the blade")
		check(Ballistics_puddles() > 0.0, "blood spills onto the floor")
		# Slash a jacketed arm and a bare arm.
		npcs[2].model.equipment.equip(GearInstance.create("jacket"))
		_face(npcs[2], "LeftLowerArm", 0.55)
		hits.clear()
		p.knife._begin(1)
	if f == 100:
		var jacket: Dictionary = hits[-1] if not hits.is_empty() else {}
		print("      slash through jacket: %s, %.0f mm deep" % [jacket.get("zone", "miss"), jacket.get("depth_mm", 0.0)])
		npcs[3].model.equipment.unequip("torso_outer")
		_face(npcs[3], "LeftLowerArm", 0.55)
		step = hits.size()
		p.knife._begin(1)
		set_meta("jacket", jacket)
	if f == 140:
		var jacket: Dictionary = get_meta("jacket")
		var bare: Dictionary = hits[-1] if hits.size() > step else {}
		print("      slash on bare skin: %s, %.0f mm deep, %s" % [bare.get("zone", "miss"), bare.get("depth_mm", 0.0), bare.get("bleed", "")])
		check(not jacket.is_empty() and jacket.zone != "", "a slash connects through a jacket")
		check(not bare.is_empty() and bare.zone != "", "and on bare skin")
		if not jacket.is_empty() and not bare.is_empty():
			check(bare.depth_mm > jacket.depth_mm * 2.0, "the jacket turns the cut into a scratch")
			check(bare.has("wound") and bare.wound.kind == "slash", "a slash leaves a cut")
		# Hitting a wall: the blade glances off.
		p.global_position = Vector3(0, 0.05, 0)
		p.rotation = Vector3.ZERO
		p.pitch = 0.0
		var wall = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2, 3, 0.2)
		cs.shape = bs
		wall.add_child(cs)
		rs.add_child(wall)
		wall.global_position = Vector3(0, 1.5, -0.65)
		step = hits.size()
		p.knife._begin(3)
	if f == 170:
		check(hits.size() > step and hits[-1].zone == "", "a stab into a wall glances off")
		# Arterial spurts pump blood away from the body.
		var n = npcs[4]
		n.damage.add_wound({zone = "arm_l", bone = "LeftLowerArm", rate = 20.0, heavy = true, through = false, lost = 0.0, kind = "slash"})
		var mk := Node3D.new()
		n.model.skeleton.add_child(mk)
		mk.global_position = n.global_position + Vector3(0.3, 1.0, 0.1)
		mk.global_transform.basis = Basis(Vector3.RIGHT, Vector3.FORWARD * -1.0, Vector3.UP).orthonormalized()
		n.damage.wounds[-1].marks = [mk]
		set_meta("pud", Ballistics_puddles())
	if f == 260:
		check(Ballistics_puddles() > get_meta("pud") + 20.0, "an arterial bleed spurts blood onto the floor")
		p.switch_weapon("pistol")
		check(p.active_weapon == "pistol" and p.viewmodel.visible and not p.knife.view.visible, "and Y goes back to the 1911")
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false


func Ballistics_puddles() -> float:
	return root.get_node("/root/Ballistics").blood.puddle_ml()
