extends SceneTree
## M4A1 + 5.56 NATO: barrel-length velocity, yaw and fragmentation in tissue,
## the icepick wound, barriers knocking it off balance, M855 on steel, tracers,
## and the carbine in your hands (primary slot, semi/auto, selector, iron sights,
## reload, third-person hold).
## Run: godot --headless --fixed-fps 60 -s tools/tests/rifle_556_test.gd

var f := 0
var fails := 0
var lab: Node3D
var hits: Array = []
var B
var rs
var p
var shots := 0
var wall_hits: Array = []


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	lab = Node3D.new()
	lab.position = Vector3(0, 0, -2000)   # well away from the range
	root.add_child(lab)


func box(size: Vector3, pos: Vector3, mat: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	b.set_meta("material", mat)
	lab.add_child(b)
	return b


func clear_lab() -> void:
	for c in lab.get_children():
		c.free()


## Fire one round level along -Z into whatever is in the lab; returns the impacts.
func shoot(ammo_id: String, vf: float) -> Array:
	hits.clear()
	var o := lab.global_position + Vector3(0, 1.5, 0)
	B.fire(o, Vector3(0, 0, -1), AmmoDB.get_ammo(ammo_id), RID(), vf)
	for i in 40:
		B._physics_process(1.0 / 60.0)
	return hits.duplicate()


func gel(hs: Array) -> Dictionary:
	for h in hs:
		if h.material == "gel":
			return h
	return {}


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		B = root.get_node("/root/Ballistics")
		B.debug_enabled = false
		B.impact.connect(func(i): hits.append(i))
		var m193 := AmmoDB.get_ammo("556_1_m193")
		var vf := m193.velocity_factor(14.5)
		print("M193 from 14.5 in: %d fps (x%.3f)" % [roundi(m193.muzzle_fps * vf), vf])
		check(absf(m193.muzzle_fps * vf - 3047.5) < 1.0, "M193 loses 35 fps per inch from 20 in: ~3048 fps from the M4")
		var fmj := AmmoDB.get_ammo("45_1_fmj230")
		check(absf(fmj.velocity_factor(5.5) - 1.009) < 0.002, ".45 still gains ~1.8%/in from its 5 in reference")
		check(AmmoDB.all_for("5.56 NATO").size() == 3, "three 5.56 loads: M193, M855, M856")
	if f == 3:
		box(Vector3(1, 1, 1.2), Vector3(0, 1.5, -3.6), "gel")
	if f == 5:
		print("== 1.2 m gel block at 3 m, from a 14.5 in barrel ==")
		for id in ["556_1_m193", "556_2_m855", "556_3_m856"]:
			var a := AmmoDB.get_ammo(id)
			var g := gel(shoot(id, a.velocity_factor(14.5)))
			print("  %-20s %s  depth %.1f in  yaw=%s  wound x%.1f  dmg %d  in %d ft-lb" % [a.display_name, g.result, g.depth_mm / 25.4, g.yaw, g.get("wound_ratio", 1.0), g.damage, g.energy_in * AmmoType.J_TO_FTLB])
			if id == "556_1_m193":
				check(g.yaw == "fragmented" and g.result == "stopped", "M193 up close fragments and stays in the block")
				check(g.depth_mm / 25.4 > 6.0 and g.depth_mm / 25.4 < 14.0, "fragmenting M193 penetrates 6-14 in (%.1f)" % (g.depth_mm / 25.4))
		# Slow (long range / short barrel): it yaws but doesn't break up - goes deeper.
		var slow := gel(shoot("556_1_m193", 2400.0 / 3240.0))
		print("  M193 arriving at 2400 fps: %s depth %.1f in yaw=%s" % [slow.result, slow.depth_mm / 25.4, slow.yaw])
		check(slow.yaw == "tumbled", "below 2700 fps M193 tumbles without fragmenting")
		var fast := gel(shoot("556_1_m193", m193_vf()))
		check(slow.depth_mm > fast.depth_mm, "a tumbling (not fragmenting) bullet goes deeper (%.1f vs %.1f in)" % [slow.depth_mm / 25.4, fast.depth_mm / 25.4])
		check(slow.get("wound_ratio", 1.0) < fast.get("wound_ratio", 1.0), "and makes a smaller wound")
	if f == 6:
		clear_lab()
		box(Vector3(1, 1, 0.08), Vector3(0, 1.5, -3.0), "gel")   # a 3 in arm
	if f == 8:
		var g := gel(shoot("556_1_m193", m193_vf()))
		var frac: float = g.deposited / g.energy_in
		print("== 3 in of tissue: %s yaw=%s, %.0f%% of the energy left behind" % [g.result, g.yaw, frac * 100.0])
		check(g.result == "penetrated" and g.yaw == "icepick", "through a thin limb before it can turn: an icepick wound")
		check(frac < 0.2, "which leaves little of its energy behind")
		clear_lab()
		box(Vector3(1, 1, 0.0127), Vector3(0, 1.5, -3.0), "drywall")
		box(Vector3(1, 1, 0.0127), Vector3(0, 1.5, -3.1), "drywall")
		box(Vector3(1, 1, 1.2), Vector3(0, 1.5, -4.3), "gel")
	if f == 10:
		var g := gel(shoot("556_1_m193", m193_vf()))
		print("== stud wall then gel: %s %.1f in yaw=%s" % [g.result, g.depth_mm / 25.4, g.yaw])
		check(g.yaw == "tumbling", "a wall knocks it off balance: it arrives already tumbling")
		clear_lab()
		box(Vector3(1, 1, 0.00635), Vector3(0, 1.5, -3.0), "steel")
	if f == 12:
		var r: Array = []
		for id in ["556_1_m193", "556_2_m855", "45_1_fmj230"]:
			var a := AmmoDB.get_ammo(id)
			var hs := shoot(id, a.velocity_factor(14.5 if a.caliber == "5.56 NATO" else 5.0))
			r.append(hs[0].result)
			print("== 1/4 in mild steel: %-20s %s" % [a.display_name, hs[0].result])
		check(r[1] == "penetrated", "M855's steel penetrator punches 1/4 in mild steel")
		check(r[0] != "penetrated" and r[2] != "penetrated", "M193 and .45 ball don't")
		clear_lab()
	if f == 14:
		var o := lab.global_position + Vector3(0, 400, 0)
		B.fire(o, Vector3(0, 0, -1), AmmoDB.get_ammo("556_3_m856"), RID(), 0.94)
		B.fire(o + Vector3(1, 0, 0), Vector3(0, 0, -1), AmmoDB.get_ammo("556_1_m193"), RID(), 0.94)
	if f == 24:
		check(B.tracers_visible() == 1, "the M856 draws a glowing trace (the M193 doesn't)")
	if f == 14 + 150:
		check(B.tracers_visible() == 0, "the trace burns out by ~800 m")
		rs = load("res://scenes/shooting_range.tscn").instantiate()
		root.add_child(rs)
	# ---------------------------------------------------------------- in your hands
	if f == 170:
		p = rs.player
		var eq = p.character.equipment
		check(eq.get_weapon("primary") != null and eq.get_weapon("primary").def.id == "m4a1", "you start with an M4A1 in the primary slot")
		p.primary_fa.shot_fired.connect(func(_a): shots += 1)
		B.impact.connect(_on_impact)
		p.switch_weapon("rifle")
		check(p.active_weapon == "rifle" and p.firearm == p.primary_fa, "Y draws the rifle")
		check(p.viewmodel.visible and not p.sidearm_fa.viewmodel.visible, "its arms and gun are on screen, the 1911's aren't")
		check(p.firearm.mode == "semi", "selector starts on SEMI")
		# A chest rig with spare mags.
		eq.equip(GearInstance.create("vest", 0))
		for id in ["556_2_m855", "556_3_m856"]:
			var placed := false
			for g in eq.grids(false):
				if g.auto_place(InvItem.magazine(AmmoDB.get_ammo(id), 30, "mag_stanag")):
					placed = true
					break
			check(placed, "a loaded %s mag goes in the rig" % id)
		# A private lane well away from the range: floor, and (later) a wall at 50 yd.
		var floor := StaticBody3D.new()
		var fcs := CollisionShape3D.new()
		var fsh := BoxShape3D.new()
		fsh.size = Vector3(20, 1, 120)
		fcs.shape = fsh
		floor.add_child(fcs)
		rs.add_child(floor)
		floor.global_position = Vector3(400, -0.5, 340)
		p.global_position = Vector3(400, 0.05, 380)
		p.rotation = Vector3.ZERO
		p.pitch = 0.0
	if f == 175:
		Input.action_press("switch_weapon")
	if f == 175 + 30:
		Input.action_release("switch_weapon")
	if f == 207:
		check(p.firearm.mode == "auto" and p.active_weapon == "rifle", "holding Y flips the selector to AUTO (still on the rifle)")
		shots = 0
		Input.action_press("fire")
	if f == 207 + 60:
		Input.action_release("fire")
		print("auto: %d rounds in 1.0 s" % shots)
		check(shots >= 12 and shots <= 15, "full auto runs at ~800 rpm (%d in 1 s)" % shots)
	if f == 300:
		Input.action_press("fire")
	if f == 300 + 90:
		Input.action_release("fire")
		var fa = p.firearm
		check(fa.chambered == null and fa.slide_locked and fa.mag_count == 0, "30 + 1 rounds and the bolt locks back")
		Input.action_press("reload")
	if f == 392:
		Input.action_release("reload")
	if f == 392 + 200:
		var fa = p.firearm
		check(not fa.reloading and fa.chambered != null and fa.mag_count == 29 and not fa.slide_locked, "reload: fresh 30-rounder, bolt catch drops the carrier (29 + 1)")
		fa.toggle_mode()
		check(fa.mode == "semi", "back to SEMI")
		# Iron sights at 50 yd.
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(6, 6, 0.3)
		cs.shape = sh
		wall.add_child(cs)
		wall.set_meta("material", "test_wall")
		rs.add_child(wall)
		wall.global_position = Vector3(400, 1.6, 380 - 45.72 - 0.15)
		# All that auto fire walked the muzzle up and right: level it again.
		p.rotation = Vector3.ZERO
		p.pitch = 0.0
		p._recoil_recover = 0.0
		Input.action_press("aim")
	if f == 650:
		var vm = p.viewmodel
		var cam: Camera3D = p.fp_camera
		var rear: Vector3 = cam.to_local(vm.weapon.find_child("SightRear", true, false).global_position)
		var front: Vector3 = cam.to_local(vm.weapon.find_child("SightFront", true, false).global_position)
		print("aimed: rear aperture %s, front post %s (camera space, m)" % [rear, front])
		check(vm.aim_amount() > 0.99, "on the sights")
		check(absf(rear.x) < 0.004 and absf(rear.y) < 0.004 and absf(front.x) < 0.004 and absf(front.y) < 0.004,
			"rear aperture and front post line up on the eye")
		check(rear.z < -0.06 and rear.z > -0.12, "cheek weld: the aperture is %.0f mm from the eye" % (-rear.z * 1000.0))
		check(absf(p.fp_camera.fov - 55.0) < 1.5, "aiming narrows the view to 55 deg")
		wall_hits.clear()
	for k in 6:
		if f == 659 + k * 25:
			p.rotation = Vector3.ZERO   # recover from the last shot's kick, like a shooter would
			p.pitch = 0.0
			p._recoil_recover = 0.0
		if f == 660 + k * 25:
			Input.action_press("fire")
		if f == 662 + k * 25:
			Input.action_release("fire")
	if f == 820:
		var eye_y: float = p.fp_camera.global_position.y
		var dys: Array = []
		for h in wall_hits:
			dys.append((h.position.y - eye_y) * 100.0)
		print("aimed hits at 50 yd (cm vs sight line): %s  (shots %d, player at %s)" % [dys, shots, p.global_position])
		var mean := 0.0
		for d in dys:
			mean += d / dys.size()
		check(dys.size() == 6 and absf(mean) < 12.0, "zeroed at 50 yd: the group centres on the front post (mean %+.1f cm)" % mean)
		Input.action_release("aim")
		p.view = 1
		p._apply_view()
	if f == 830:
		check(p.character.pose_mode == 3, "third person: rifle hold (right hand on the grip, left under the rail)")
		var lh: Vector3 = p.character.grip_left.global_position
		var rh: Vector3 = p.character.grip_right.global_position
		check(lh.distance_to(rh) > 0.25, "hands are apart along the rifle (%.2f m)" % lh.distance_to(rh))
		Input.action_press("switch_weapon")
	if f == 834:
		Input.action_release("switch_weapon")
	if f == 838:
		check(p.active_weapon == "pistol" and p.character.pose_mode == 1, "tap Y: on to the 1911")
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false


func _on_impact(i: Dictionary) -> void:
	if i.material == "test_wall":
		wall_hits.append(i)
	elif f > 640:
		print("  stray impact: %s at %s" % [i.material, i.position])


func m193_vf() -> float:
	return AmmoDB.get_ammo("556_1_m193").velocity_factor(14.5)
