extends SceneTree
## Ground drops/pickups and looting bodies.
## Run: godot --headless --fixed-fps 60 -s tools/tests/loot_test.gd

var f := 0
var rs
var fails := 0
var npc
var inv


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	rs = load("res://scenes/shooting_range.tscn").instantiate()
	root.add_child(rs)


func _process(_d: float) -> bool:
	f += 1
	var p = rs.player
	if f == 3:
		for c in rs.find_children("*", "Control", true, false):
			if c.has_method("_quick_move"):
				inv = c
		p.global_position = Vector3(0, 0.05, 15.0)
		p.rotation = Vector3.ZERO
	if f == 6:
		# --- Drop painkillers on the ground with X (no container open = Ground panel).
		inv.open(null)
		check(inv._ground != null, "inventory with nothing nearby shows the Ground panel")
		var pockets: Array = p.character.equipment.get_slot("legs").grids
		inv._cursor = _target(pockets[2], Vector2i.ZERO)
		inv._quick_move()
		check(pockets[2].item_at(Vector2i.ZERO) == null, "painkillers left the pocket")
		check(inv._ground.entries.size() == 1, "painkillers are on the Ground panel")
		inv.close()
	if f == 8:
		var items = get_nodes_in_group("world_item")
		check(items.size() == 1, "closing dropped a world item")
		if items.size() == 1:
			var w = items[0]
			check(w.global_position.distance_to(p.global_position) < 1.5 and absf(w.global_position.y) < 0.1, "it lies on the floor at your feet")
			check(p.interact_target() == w, "it's the A target when you stand on it")
			# Reopen: the ground panel lists it.
			inv.open(null)
			check(inv._ground.entries.size() == 1, "reopening shows it on the Ground panel")
			inv.close()
			w.use(p)
	if f == 10:
		check(get_nodes_in_group("world_item").is_empty(), "A picked it up (gone from the floor)")
		var found := false
		for g in p.character.equipment.grids():
			for e in g.entries:
				if e.item.def.id == "painkillers":
					found = true
		check(found, "painkillers are back in a pocket")
		# --- Bodies: give the first civilian a backpack with gold, then shoot them in the head.
		npc = get_nodes_in_group("npc")[0]
		npc.model.equipment.equip(GearInstance.create("backpack"))
		npc.model.equipment.get_slot("back").grids[0].place(InvItem.create("gold"), Vector2i.ZERO)
		var head = npc.model.skeleton.get_bone_global_pose(npc.model.skeleton.find_bone("Head"))
		var head_world = npc.model.skeleton.global_transform * head.origin + Vector3(0, 0.12, 0)
		var from = head_world + Vector3(0, 0, 5)
		var bal = root.get_node("/root/Ballistics")
		bal.fire(from, (head_world - from).normalized(), AmmoDB.get_ammo("45_2_jhp230"), RID())
	if f == 30:
		check(npc.dead, "a JHP to the head kills the civilian (hitboxes on bones work)")
		check(npc.is_in_group("interactable") and npc.prompt() == "A: search body", "the body is searchable")
		p.global_position = npc.global_position + Vector3(0, 0, 1.2)
		inv.open(npc)
		check(inv._body() == npc, "inventory opens on the body")
		var slot_i := -1
		for i in inv._targets.size():
			var t = inv._targets[i]
			if t.kind == "slot" and t.slot == "back" and t.eq == npc.model.equipment:
				slot_i = i
		inv._cursor = slot_i
		inv._quick_move()
		var pack = p.character.equipment.get_slot("back")
		check(pack != null, "X on the body's backpack puts it straight on you")
		check(npc.model.equipment.get_slot("back") == null, "and it's gone from the body")
		check(pack != null and pack.grids[0].item_at(Vector2i.ZERO) != null and pack.grids[0].item_at(Vector2i.ZERO).def.id == "gold", "its contents came with it (gold bar)")
		# Take something from the body's pockets, if it has any.
		var body_items := 0
		for g in npc.model.equipment.grids():
			body_items += g.entries.size()
		print("      body still carries %d item(s) in pockets" % body_items)
		inv.close()
	if f == 32:
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false


func _target(grid, cell: Vector2i) -> int:
	for i in inv._targets.size():
		var t = inv._targets[i]
		if t.kind == "cell" and t.grid == grid and t.cell == cell:
			return i
	return -1
