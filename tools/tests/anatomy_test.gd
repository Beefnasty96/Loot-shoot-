extends SceneTree
## Organs and bones: wound paths through the anatomy and what each one does.
## Run: godot --headless --fixed-fps 60 -s tools/tests/anatomy_test.gd

var f := 0
var fails := 0
var rs
var bal
var npcs: Array = []
var hits := {}          # npc index -> last impact info
var t_heart := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	seed(7)
	rs = load("res://scenes/shooting_range.tscn").instantiate()
	root.add_child(rs)


func ids(list: Array) -> Array:
	var out := []
	for h in list:
		out.append(h.id)
	return out


## The hitbox of `n` for `zone` whose rig box contains rig point `c`.
func hitbox_for(n, c: Vector3):
	for hb in n._hitboxes:
		var local: Vector3 = hb.to_rig.affine_inverse() * c
		var half: Vector3 = (hb.get_child(0).shape as BoxShape3D).size / 2.0
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return hb
	return null


## Fire `ammo` at rig point `c` of npc `n`, coming from rig direction `from_dir` (unit, rig space).
func shoot_rig(n, c: Vector3, from_dir: Vector3, ammo: String) -> void:
	var hb = hitbox_for(n, c)
	var world: Vector3 = hb.global_transform * (hb.to_rig.affine_inverse() * c)
	var wdir: Vector3 = (hb.global_transform.basis * (hb.to_rig.basis.inverse() * -from_dir)).normalized()
	bal.fire(world - wdir * 3.0, wdir, AmmoDB.get_ammo(ammo), RID())


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		print("== wound paths in the rig (front to back unless noted) ==")
		var heart := Anatomy.trace_rig(Vector3(0.025, 1.31, 0.3), Vector3(0.025, 1.31, -0.3), 0.6)
		print("  chest, left of centre: %s" % [ids(heart)])
		check("heart" in ids(heart), "a shot through the left chest at heart height hits the heart")
		var lung := Anatomy.trace_rig(Vector3(-0.1, 1.38, 0.3), Vector3(-0.1, 1.38, -0.3), 0.6)
		print("  right chest: %s" % [ids(lung)])
		check("lung_r" in ids(lung) and not ("heart" in ids(lung)), "the right chest is lung, not heart")
		var head := Anatomy.trace_rig(Vector3(0, 1.75, 0.3), Vector3(0, 1.75, -0.3), 0.6)
		print("  forehead: %s" % [ids(head)])
		check("brain" in ids(head) and "skull" in ids(head), "a forehead shot goes through the skull into the brain")
		var jaw := Anatomy.trace_rig(Vector3(0.3, 1.61, 0.03), Vector3(-0.3, 1.61, 0.03), 0.6)
		print("  across the jaw/neck front: %s" % [ids(jaw)])
		check(not ("brain" in ids(jaw)) and "carotid_l" in ids(jaw), "across the front of the neck: carotids, not the brain")
		var thigh := Anatomy.trace_rig(Vector3(0.12, 0.72, 0.3), Vector3(0.12, 0.72, -0.3), 0.6)
		print("  mid thigh: %s, bone adds %.0f gel-mm" % [ids(thigh), Anatomy.bone_gel_mm(thigh)])
		check("femur_l" in ids(thigh) and Anatomy.bone_gel_mm(thigh) > 30.0, "mid thigh: the femur, which soaks up penetration")
		var miss := Anatomy.trace_rig(Vector3(0.17, 1.22, 0.3), Vector3(0.17, 1.22, -0.3), 0.6)
		print("  side of the lower chest: %s" % [ids(miss)])
		check(miss.is_empty(), "a path down the side of the ribs misses every organ")
		# Damage model effects without shooting anyone.
		var dm := DamageModel.new()
		var info := {zone = "stomach", damage = 20.0, organs = Anatomy.trace_rig(Vector3(-0.07, 1.15, 0.3), Vector3(-0.07, 1.15, -0.3), 0.6)}
		dm.apply_organs(info)
		print("  liver shot: %s, internal %.1f ml/s, damage %.0f" % [info.organ_names, dm.internal_bleed_rate(), info.damage])
		check(dm.internal_bleed_rate() > 10.0, "a liver hit bleeds inside")
		dm.treat(true)
		check(dm.internal_bleed_rate() > 10.0, "and an IFAK can't stop it")
		var dm2 := DamageModel.new()
		var head_info := {zone = "head", damage = 60.0, organs = jaw}
		dm2.apply_organs(head_info)
		dm2.apply("head", head_info.damage)
		check(not dm2.dead and dm2.is_bleeding_heavily(true), "a neck shot that misses the brain doesn't kill outright, but the carotid pumps")
		var dm3 := DamageModel.new()
		var lungs := {zone = "thorax", damage = 10.0, organs = Anatomy.trace_rig(Vector3(0.3, 1.38, 0.0), Vector3(-0.3, 1.38, 0.0), 0.6)}
		dm3.apply_organs(lungs)
		print("  side to side through the chest: %s -> breathing %.2f, mobility %.2f" % [lungs.organ_names, dm3.breathing(), dm3.mobility()])
		check(dm3.lungs_hit.size() == 2 and dm3.breathing() < 0.3 and dm3.mobility() < 0.6, "both lungs: can barely breathe or move")
	if f == 3:
		bal = root.get_node("/root/Ballistics")
		bal.debug_enabled = false
		npcs = get_nodes_in_group("npc")
		check(npcs.size() >= 4, "range has people to test on (%d)" % npcs.size())
		bal.impact.connect(func(i):
			if i.zone == "":
				return
			for k in npcs.size():
				var n = npcs[k]
				if i.collider in n._hitboxes:
					hits[k] = i)
		# 0: .45 ball through the heart. 1: through the brain. 2: through the left femur.
		# 3: from behind into the lower spine.
		shoot_rig(npcs[0], Vector3(0.025, 1.31, 0.03), Vector3(0, 0, 1), "45_1_fmj230")
		shoot_rig(npcs[1], Vector3(0, 1.75, 0.02), Vector3(0, 0, 1), "45_1_fmj230")
		shoot_rig(npcs[2], Vector3(0.12, 0.72, 0.0), Vector3(0, 0, 1), "45_1_fmj230")
		shoot_rig(npcs[3], Vector3(0, 1.06, -0.09), Vector3(0, 0, -1), "45_1_fmj230")
	if f == 10:
		var names := []
		for k in 4:
			names.append(hits.get(k, {}).get("organ_names", []))
		print("organs hit: heart shot %s | head %s | thigh %s | lower back %s" % names)
		check("heart" in names[0], "the heart shot reached the heart")
		check(not npcs[0].dead, "...and he's still up for now")
		check(npcs[1].dead and npcs[1].damage.cause == "brain", "a brain shot drops him on the spot")
		check(npcs[2].damage.broken.get("leg_l", false) and not npcs[2].dead, "the thigh shot broke the femur")
		check(npcs[3].damage.legs_paralysed, "the lower-back shot cut the spinal cord: legs paralysed")
		t_heart = f
	if f == 10 + 60:
		check(npcs[2].model.sit > 0.3 or npcs[2].model.kneel > 0.5, "on a broken leg he goes down")
		check(npcs[3].model.sit > 0.3, "paralysed, he collapses")
		check(npcs[2].damage.mobility() < 0.3, "and can hardly move (mobility %.2f)" % npcs[2].damage.mobility())
	if f == 10 + 16 * 60:
		check(npcs[0].dead and npcs[0].damage.cause == "heart stopped", "the heart stops within ~15 s (%s)" % npcs[0].damage.cause)
		# The range dummies have the same anatomy stretched over their zones.
		var dummy: Node = null
		for c in rs.get_children():
			if c.get_script() and String(c.get_script().resource_path).ends_with("target_dummy.gd"):
				dummy = c
				break
		var thorax_hb = null
		for hb in dummy._body.get_children():
			if hb is Hitbox and hb.zone == "thorax":
				thorax_hb = hb
		hits.clear()
		set_meta("dummy", dummy)
		var at: Vector3 = thorax_hb.global_position + Vector3(0.025, -0.03, 0)
		bal.impact.connect(func(i): if i.collider == thorax_hb: set_meta("dhit", i))
		bal.fire(at + Vector3(0, 0, 4), Vector3(0, 0, -1), AmmoDB.get_ammo("45_1_fmj230"), RID())
	if f == 10 + 16 * 60 + 6:
		var dh: Dictionary = get_meta("dhit") if has_meta("dhit") else {}
		print("dummy chest: %s" % [dh.get("organ_names", [])])
		check(not dh.get("organ_names", []).is_empty(), "the range dummies have organs too")
		bal.debug_enabled = true
	if f == 10 + 16 * 60 + 9:
		var xr = npcs[2]._hitboxes[1].get_node_or_null("XRay")
		check(xr != null and xr.visible and xr.get_child_count() > 3, "debug view shows the organs and bones (x-ray)")
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
