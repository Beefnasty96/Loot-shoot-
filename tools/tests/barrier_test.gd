extends SceneTree
var root3d: Node3D
var f := 0
var hits := []
var barriers = [["drywall stud wall (2x12.7mm)", "drywall", 0.0127, 2], ["plywood 19mm", "plywood", 0.019, 1], ["glass 6mm", "glass", 0.006, 1], ["car door (2x0.8mm)", "sheet_metal", 0.0008, 2], ["mild steel 3mm", "steel", 0.003, 1], ["mild steel 6mm", "steel", 0.006, 1], ["brick 100mm", "brick", 0.1, 1], ["concrete 150mm", "concrete", 0.15, 1]]
var ammo: Array

func _initialize():
	root3d = Node3D.new(); root.add_child(root3d)
	seed(7)

func box(size: Vector3, pos: Vector3, mat: String):
	var b := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; b.add_child(cs); b.position = pos; b.set_meta("material", mat); root3d.add_child(b)

func lane_x(i, j): return (i * 6 + j) * 2.0

func _process(_d):
	f += 1
	var B = root.get_node("/root/Ballistics"); B.debug_enabled = false
	if f == 1:
		ammo = AmmoDB.all_for(".45 ACP")
		B.impact.connect(func(info): hits.append(info))
		for i in barriers.size():
			for j in ammo.size():
				var x = lane_x(i, j)
				for k in barriers[i][3]:
					box(Vector3(1, 1, barriers[i][2]), Vector3(x, 1.5, -3.0 - k * 0.1), barriers[i][1])
				box(Vector3(1, 1, 1.2), Vector3(x, 1.5, -4.2), "gel")
	if f == 4:
		for i in barriers.size():
			for j in ammo.size():
				B.fire(Vector3(lane_x(i, j), 1.5, 0), Vector3(0, 0, -1), ammo[j], RID())
	if f > 4 and f < 40:
		pass
	if f == 40:
		for i in barriers.size():
			print("-- " + barriers[i][0])
			for j in ammo.size():
				var x = lane_x(i, j)
				var parts = []
				for h in hits:
					if absf(h.position.x - x) > 0.6: continue
					if h.material == "gel":
						var tag = " (expanded %.2f\")" % ammo[j].expanded_in if h.expanded else (" (plugged)" if h.clogged else (" (crushed/deformed)" if h.deformed else ""))
						parts.append("GEL %s %.1f in%s" % [h.result, h.depth_mm/25.4, tag])
					else:
						parts.append("%s %d->%d fps, %d ftlb delivered" % [h.result, AmmoType.ms_to_fps(h.speed_in), AmmoType.ms_to_fps(h.get("speed_out", 0.0)), h.deposited * AmmoType.J_TO_FTLB])
				print("   %-6s %s" % [ammo[j].short_name, " | ".join(parts)])
		quit()
	return false
