extends SceneTree
## Wounds, bleeding, blood loss and blood effects.
## Run: godot --headless --fixed-fps 60 -s tools/tests/blood_test.gd

var f := 0
var rs
var fails := 0
var npcs: Array = []
var hits: Array = []
var bal


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
	rng.seed = 7
	var fmj := {zone = "thorax", result = "penetrated", wound_ratio = 1.0, thickness_mm = 250.0}
	var jhp := {zone = "thorax", result = "stopped", wound_ratio = 1.75, depth_mm = 250.0}
	var sum := {fmj = 0.0, jhp = 0.0}
	var art := {fmj = 0, jhp = 0}
	for i in 400:
		for k in ["fmj", "jhp"]:
			var w := DamageModel.make_wound(fmj if k == "fmj" else jhp, rng)
			if w.heavy:
				art[k] += 1
			else:
				sum[k] += w.rate
	var lf: float = sum.fmj / (400 - art.fmj)
	var lj: float = sum.jhp / (400 - art.jhp)
	print("      thorax light bleed: FMJ through %.1f ml/s, JHP expanded %.1f ml/s; arterial FMJ %d%%, JHP %d%%" % [lf, lj, art.fmj / 4, art.jhp / 4])
	check(lj > lf * 1.4, "an expanded hollow point bleeds more than ball")
	check(art.jhp > art.fmj, "and opens a major vessel more often")
	check(art.fmj > 20 and art.fmj < 200, "thorax hits are sometimes arterial (%d / 400)" % art.fmj)

	var d := DamageModel.new()
	d.set_body_mass(78.0)
	check(absf(d.blood_max - 5460.0) < 1.0, "78 kg person has ~5.5 L of blood")
	d.add_wound({zone = "leg_l", rate = 20.0, heavy = true, lost = 0.0})
	var t := 0.0
	while not d.dead and t < 600.0:
		d.tick(0.5)
		t += 0.5
	print("      20 ml/s arterial bleed kills in %d s" % t)
	check(d.dead and d.cause == "blood loss", "an untreated arterial bleed kills by blood loss")
	check(t > 90.0 and t < 130.0, "after losing 40% of their blood")

	var e := DamageModel.new()
	e.add_wound({zone = "arm_l", rate = 2.0, heavy = false, lost = 0.0})
	for i in 600:
		e.tick(0.5)
	check(e.wounds[0].rate < 0.2 and not e.dead, "a light bleed clots on its own")
	var g := DamageModel.new()
	g.add_wound({zone = "leg_l", rate = 2.0, heavy = false, lost = 0.0})
	g.add_wound({zone = "leg_r", rate = 18.0, heavy = true, lost = 0.0})
	check(g.treat(false) == 1 and g.is_bleeding_heavily(), "bandage stops the light bleed but not the arterial one")
	check(g.treat(true) == 1 and g.bleed_rate() == 0.0, "a tourniquet stops the arterial bleed")


func _bone_world(n, bone: String) -> Vector3:
	var sk = n.model.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		bal = root.get_node("/root/Ballistics")
		bal.impact.connect(func(info): if info.zone != "": hits.append(info))
		npcs = get_nodes_in_group("npc")
		var at := _bone_world(npcs[1], "Spine")
		bal.fire(at + Vector3(0, 0, 5), Vector3(0, 0, -1), AmmoDB.get_ammo("45_1_fmj230"), RID())
	if f == 6:
		var n = npcs[1]
		check(n.damage.wounds.size() >= 1, "the hit opened a wound")
		var w: Dictionary = n.damage.wounds[0]
		print("      wound: %s, %s, %.1f ml/s" % [w.zone, "arterial" if w.heavy else "light", w.rate])
		check(w.has("marks") and w.marks.size() == (4 if w.through else 2), "entry/exit holes and stains are on the body")
		check(w.marks[0].get_parent() is StaticBody3D, "they ride on the hitbox (follow the bone)")
		check(not hits.is_empty() and hits[0].has("bleed"), "the hit report says how fast it bleeds: " + str(hits[0].get("bleed", "")))
		check(bal.blood._splats.size() >= 1, "the exit wound splattered the wall behind")
		# Make the next one arterial and run their blood low.
		n.damage.wounds[0].rate = 25.0
		n.damage.wounds[0].heavy = true
	if f == 6 + 180:
		var n = npcs[1]
		check(bal.blood.puddle_ml() > 30.0, "blood is pooling on the floor (%.0f ml)" % bal.blood.puddle_ml())
		var stain: Decal = n.damage.wounds[0].stain
		check(stain.size.x > 0.1, "the stain on their clothes spread (%.0f cm)" % (stain.size.x * 100))
		n.damage.blood_ml = n.damage.blood_max * 0.605
	if f == 6 + 240:
		var n = npcs[1]
		check(n.model.crouch > 0.3 or n.dead, "low on blood they sag")
	if f == 6 + 400:
		var n = npcs[1]
		check(n.dead and n.damage.cause == "blood loss", "they bleed out and die")
		check(n.model.ragdoll_active, "and collapse as a ragdoll")
		print("      puddles hold %.0f ml in %d decals" % [bal.blood.puddle_ml(), bal.blood._puddles.size()])
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
