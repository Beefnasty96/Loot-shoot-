extends SceneTree
## Headless checks for the grid inventory, magazine reloads and encumbrance.
## Run: godot --headless --fixed-fps 60 -s tools/tests/inventory_test.gd

var f := 0
var range_scene
var fails := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	# Pure grid logic.
	var g := InvGrid.new(4, 3)
	var laptop := InvItem.create("laptop")          # 3x2
	check(g.place(laptop, Vector2i(0, 0)), "3x2 laptop fits at 0,0 in a 4x3 grid")
	var water := InvItem.create("water")            # 1x2
	check(not g.fits(water, Vector2i(2, 0)), "water can't overlap the laptop")
	check(g.place(water, Vector2i(3, 0)), "water fits in the last column")
	var gpu := InvItem.create("gpu")                # 2x1
	check(g.place(gpu, Vector2i(0, 2)), "GPU fits on the bottom row")
	var medkit := InvItem.create("medkit")          # 2x1
	check(g.auto_place(medkit), "auto-place finds the last 2x1 gap")
	check(g.free_cells() == 0, "grid is now full")
	var tall := InvItem.create("water")
	var g2 := InvGrid.new(2, 1)
	check(g2.auto_place(tall) and tall.rotated, "1x2 bottle rotates to fit a 2x1 pocket")
	var a := InvItem.rounds("45_1_fmj230", 30)
	var b := InvItem.rounds("45_1_fmj230", 30)
	var g3 := InvGrid.new(2, 1)
	g3.place(a, Vector2i.ZERO)
	check(g3.merge_stacks(b) == 10 and a.count == 50, "stacks merge up to 50 and leave 10 over")
	var pack := InvItem.create("backpack")
	check(not pack.gear.grids[0].fits(pack, Vector2i.ZERO), "a backpack can't go inside itself")
	pack.gear.grids[0].place(InvItem.create("gold"), Vector2i.ZERO)
	check(absf(pack.weight() - 2.8) < 0.01, "backpack weight includes a 1 kg gold bar (1.8 + 1.0 kg)")
	range_scene = load("res://scenes/shooting_range.tscn").instantiate()
	root.add_child(range_scene)


func _process(_d: float) -> bool:
	f += 1
	var p = range_scene.player
	var fa = p.firearm
	if f == 5:
		var pockets: Array = p.character.equipment.get_slot("legs").grids
		check(pockets[0].item_at(Vector2i.ZERO) != null and pockets[0].item_at(Vector2i.ZERO).def.is_mag(), "starting FMJ mag is in a pants pocket")
		check(fa.spare_mags().size() == 2, "two spare mags reachable (rig/pockets)")
		# Empty the gun's mag, then reload: should take the FMJ mag (preferred) from pocket 0.
		fa.mag_count = 0
		fa._start_reload()
		check(fa.reloading, "reload starts")
	if f == 5 + 150:
		var pockets: Array = p.character.equipment.get_slot("legs").grids
		check(not fa.reloading and fa.mag_count == 7 and fa.mag_ammo.id == "45_1_fmj230", "reloaded with the full FMJ mag")
		var back: InvItem = pockets[0].item_at(Vector2i.ZERO)
		check(back != null and back.def.is_mag() and back.mag_count == 0, "old empty mag went back into that pocket")
		check(fa.spare_mags().size() == 1, "one loaded spare left")
		# Inventory screen: open the crate, drop a stack of JHP rounds on the empty mag in the pocket.
		var crate = null
		for n in range_scene.get_children():
			if n.is_in_group("loot_container"):
				crate = n
		var inv = null
		for c in range_scene.find_children("*", "Control", true, false):
			if c.has_method("_quick_move"):
				inv = c
		inv.open(crate)
		var ammo_cell := Vector2i(-1, -1)
		for e in crate.grid.entries:
			if (e.item as InvItem).def.ammo_id == "45_2_jhp230":
				ammo_cell = e.pos
				break
		inv._cursor = _target(inv, crate.grid, ammo_cell)
		inv._pick()
		check(inv._held != null and inv._held.def.is_ammo(), "picked up a stack of JHP rounds")
		inv._cursor = _target(inv, pockets[0], Vector2i.ZERO)
		inv._drop()
		check(back.mag_count == 7 and back.mag_ammo.id == "45_2_jhp230", "dropping rounds on the empty mag loaded 7 JHP")
		check(inv._held != null and inv._held.count == 43, "43 rounds left in hand")
		inv._return_held()
		# Quick-move the backpack from the crate: it should be worn.
		var pack_cell := Vector2i(-1, -1)
		for e in crate.grid.entries:
			if (e.item as InvItem).def.id == "backpack":
				pack_cell = e.pos
		inv._cursor = _target(inv, crate.grid, pack_cell)
		inv._quick_move()
		check(p.character.equipment.get_slot("back") != null, "quick-move puts the backpack on")
		# Fill it with gold until overweight.
		var kg0: float = p.carried_weight()
		var bag: InvGrid = p.character.equipment.get_slot("back").grids[0]
		var placed := 0
		for i in 20:
			var gold := InvItem.create("gold")
			if bag.auto_place(gold):
				placed += 1
		var kg1: float = p.carried_weight()
		check(absf(kg1 - kg0 - placed) < 0.01, "carried weight rose by %d kg of gold" % placed)
		print("      load %.1f kg -> speed x%.2f, sprint %s" % [kg1, Encumbrance.speed_factor(kg1), Encumbrance.can_sprint(kg1)])
		check(Encumbrance.speed_factor(kg1) < 1.0, "heavy load slows you down")
		inv.close()
	if f == 5 + 160:
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false


func _target(inv, grid: InvGrid, cell: Vector2i) -> int:
	for i in inv._targets.size():
		var t: Dictionary = inv._targets[i]
		if t.kind == "cell" and t.grid == grid and t.cell == cell:
			return i
	return -1
