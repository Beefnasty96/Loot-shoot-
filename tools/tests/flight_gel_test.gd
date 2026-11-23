extends SceneTree
# Flight: fire each load level from 1.5 m, record speed/energy/drop at 25/50/100 yd.
# Terminal: fire into a 1.2 m gel block and barriers; print outcomes.
var root3d: Node3D
var f := 0
var phase := 0
var results := []
var tracked := []
var gates := [22.86, 45.72, 91.44]
var hits := []

func _initialize():
	root3d = Node3D.new()
	root.add_child(root3d)

func box(size: Vector3, pos: Vector3, mat: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = size; cs.shape = sh
	b.add_child(cs); b.position = pos; b.set_meta("material", mat)
	root3d.add_child(b)
	return b

func _process(_d):
	f += 1
	var B = root.get_node("/root/Ballistics")
	B.debug_enabled = false
	if f == 2:
		B.impact.connect(func(info): hits.append(info))
		print("== FLIGHT (zero ignored, fired level from 1.5 m) ==")
		for a in AmmoDB.all_for(".45 ACP"):
			var b = B.fire(Vector3(0, 1.5, 0), Vector3(0, 0, -1), a, RID())
			tracked.append({b = b, a = a, next = 0, row = []})
	if f > 2 and phase == 0:
		var done := true
		for t in tracked:
			var b = t.b
			while t.next < gates.size() and -b.pos.z >= gates[t.next]:
				var spd = b.vel.length()
				t.row.append("%3dyd %4d fps %3d ftlb drop %5.1f cm" % [[25,50,100][t.next], AmmoType.ms_to_fps(spd), t.a.energy_j(spd)*AmmoType.J_TO_FTLB, (1.5 - b.pos.y)*100])
				t.next += 1
			if t.next < gates.size(): done = false
		if done:
			for t in tracked:
				print("%-26s muzzle %4d fps %3d ftlb | %s" % [t.a.display_name, t.a.muzzle_fps, t.a.muzzle_energy_ftlb(), " | ".join(t.row)])
			phase = 1
			f = 1000
	if phase == 1 and f == 1001:
		print("\n== GEL BLOCK (1.2 m) at 3 m, flesh-like, per load ==")
		box(Vector3(1, 1, 1.2), Vector3(0, 1.5, -3.6), "gel")
	if phase == 1 and f == 1003:
		for a in AmmoDB.all_for(".45 ACP"):
			hits.clear()
			B.fire(Vector3(0, 1.5, 0), Vector3(0, 0, -1), a, RID())
			for i in 30: B._physics_process(1.0/60.0)
			for h in hits:
				print("%-26s %s  depth %.1f in  expanded=%s  in %d ftlb" % [a.display_name, h.result, h.depth_mm/25.4, h.expanded, h.energy_in*AmmoType.J_TO_FTLB])
		phase = 2
	if phase == 2 and f == 1005:
		for c in root3d.get_children(): c.free()
	if phase == 2 and f == 1007:
		print("\n== BARRIERS at 3 m, then gel behind (square-on) ==")
		var barriers = [["drywall 2x12.7mm (stud wall)", "drywall", 0.0127, 2], ["plywood 19mm", "plywood", 0.019, 1], ["glass 6mm", "glass", 0.006, 1], ["car door 2x0.8mm", "sheet_metal", 0.0008, 2], ["mild steel 3mm", "steel", 0.003, 1], ["mild steel 6mm", "steel", 0.006, 1], ["brick 100mm", "brick", 0.1, 1], ["concrete 150mm", "concrete", 0.15, 1]]
		for bar in barriers:
			print("-- " + bar[0])
			for a in AmmoDB.all_for(".45 ACP"):
				for c in root3d.get_children(): c.free()
				for k in bar[3]:
					box(Vector3(1, 1, bar[2]), Vector3(0, 1.5, -3.0 - k * 0.1), bar[1])
				box(Vector3(1, 1, 1.2), Vector3(0, 1.5, -4.2), "gel")
				await physics_frame
				hits.clear()
				B.fire(Vector3(0, 1.5, 0), Vector3(0, 0, -1), a, RID())
				for i in 30: B._physics_process(1.0/60.0)
				var parts = []
				for h in hits:
					if h.material == "gel":
						parts.append("gel: %s %.1f in%s" % [h.result, h.depth_mm/25.4, " (expanded)" if h.expanded else (" (plugged)" if h.clogged else (" (deformed)" if h.deformed else ""))])
					else:
						parts.append("%s %d->%d fps" % [h.result, AmmoType.ms_to_fps(h.speed_in), AmmoType.ms_to_fps(h.get("speed_out", 0.0))])
				print("   %-26s %s" % [a.short_name, " | ".join(parts)])
		quit()
	return false
