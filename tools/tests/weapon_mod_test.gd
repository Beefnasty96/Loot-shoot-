extends SceneTree
## Guns as items with an attachment tree: slots, fitting parts, stats, models,
## the light, suppressed shots and AI hearing, dropping and picking up guns.
## Run: godot --headless --fixed-fps 60 -s tools/tests/weapon_mod_test.gd

var f := 0
var rs
var p
var inv
var bench
var fails := 0
var shots: Array = []


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	rs = load("res://scenes/shooting_range.tscn").instantiate()
	root.add_child(rs)


func _target(kind: String, match_fn: Callable) -> int:
	for i in inv._targets.size():
		var t: Dictionary = inv._targets[i]
		if t.kind == kind and match_fn.call(t):
			return i
	return -1


func _hold_from_bench(id: String) -> void:
	for e in bench.grid.entries:
		if e.item.def.id == id:
			inv._cursor = _target("cell", func(t): return t.grid == bench.grid and t.cell == e.pos)
			inv._pick()
			return


func _drop_on_holster() -> void:
	inv._cursor = _target("wslot", func(t): return t.slot == "sidearm" and t.eq == p.character.equipment)
	inv._drop()


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		p = rs.player
		var bal = root.get_node("/root/Ballistics")
		bal.gunshot.connect(func(o, s, l): shots.append(l))
		var eq = p.character.equipment
		var gun = eq.get_weapon("sidearm")
		check(gun != null and gun.def.id == "m1911", "you carry the 1911 as an item in your holster")
		check(eq.get_weapon("melee") != null and eq.get_weapon("melee").def.id == "kabar", "and the Ka-Bar in your sheath")
		check(p.firearm.gun == gun, "the pistol you shoot is that item")
		check(gun.mods.has("barrel") and gun.mods.has("grips") and gun.mods.has("sights") and gun.wpn_mag != null, "it comes with its stock barrel, grips, sights and a magazine")
		var st0 = WeaponDB.stats(gun)
		check(st0.working and is_equal_approx(st0.barrel_in, 5.0) and st0.loudness == 1.0, "stock: works, 5 in barrel, full volume")
		check(gun.label() == "7+1", "its tile shows 7+1")
		set_meta("st0", st0)
		for n in rs.get_children():
			if n.is_in_group("loot_container") and n.title == "Gun parts":
				bench = n
		inv = null
		for c in rs.find_children("*", "Control", true, false):
			if c.has_method("_quick_move"):
				inv = c
		inv.open(bench)
		# Threaded barrel onto the gun in the holster: swaps out the GI barrel.
		_hold_from_bench("barrel_1911_threaded")
		_drop_on_holster()
		check(gun.mods.barrel.def.id == "barrel_1911_threaded", "dropping a threaded barrel on the holstered gun fits it")
		check(inv._held != null and inv._held.def.id == "barrel_1911_gi", "and hands you the old GI barrel")
		inv._return_held()
		# Suppressor: needs the threaded barrel's muzzle slot.
		_hold_from_bench("supp_45")
		_drop_on_holster()
		check(gun.mods.barrel.mods.has("muzzle"), "the suppressor screws onto the threaded barrel (a slot the barrel brings)")
		var st = WeaponDB.stats(gun)
		print("      suppressed: loudness %d%%, recoil %d%%, ergo %d, %.1f in barrel, %s" % [st.loudness * 100, st.recoil * 100, st.ergo, st.barrel_in, gun.footprint()])
		check(st.loudness < 0.5 and st.recoil < st0.recoil and st.ergo < st0.ergo, "quieter, softer recoil, slower to handle")
		check(gun.footprint() == Vector2i(3, 1), "and the gun now takes 3 squares")
		check(WeaponDB.velocity_factor(st.barrel_in) > 1.0, "the longer barrel adds velocity")
		check(rs.player.viewmodel.weapon.find_child("Part_supp_45", true, false) != null, "the suppressor shows on your first-person gun")
		# Rail adapter, then a light on the rail.
		_hold_from_bench("rail_1911")
		_drop_on_holster()
		_hold_from_bench("light_m3")
		_drop_on_holster()
		check(gun.mods.has("mount") and gun.mods.mount.mods.has("tactical"), "rail adapter on the frame, light on the rail")
		check(p.firearm.has_light(), "the gun has a light")
		# Required parts can only be swapped.
		inv._mod_gun = gun
		inv._relayout()
		inv._cursor = _target("mod", func(t): return t.owner == gun and t.slot == "barrel")
		inv._pick()
		check(inv._held == null and gun.mods.has("barrel"), "you can't leave the barrel slot empty (swap only)")
		# The magazine is a slot too: take it out.
		inv._cursor = _target("mod", func(t): return t.owner == gun and t.slot == "magazine")
		inv._pick()
		check(inv._held != null and inv._held.def.is_mag() and gun.wpn_mag == null, "the magazine comes out of its slot")
		inv._return_held()
		check(gun.wpn_mag != null, "and goes back in")
		# An 8-round magazine fits the same well.
		inv._mod_gun = null          # the crate shows again
		inv._relayout()
		_hold_from_bench("mag_1911_8")
		inv._mod_gun = gun
		inv._relayout()
		inv._cursor = _target("mod", func(t): return t.owner == gun and t.slot == "magazine")
		inv._drop()
		check(gun.wpn_mag.def.id == "mag_1911_8" and gun.label() == "8+1", "an 8-round mag fits: 8+1")
		check(inv._held != null and inv._held.def.id == "mag_1911", "swapping out the 7-rounder")
		inv._return_held()
		inv._mod_gun = null
		inv.close()
		# Fire: a suppressed gunshot.
		p.global_position = Vector3(0, 0.05, 10)
		p.rotation = Vector3.ZERO
		shots.clear()
		Input.action_press("fire")
	if f == 6:
		Input.action_release("fire")
		check(not shots.is_empty() and shots[0] < 0.5, "the shot goes out suppressed (loudness %.2f)" % (shots[0] if not shots.is_empty() else -1.0))
		# Light toggle (tap D-pad down).
		p.firearm.toggle_light()
	if f == 10:
		var beam = p.firearm._parts[0].get("beam")
		check(p.firearm.light_on and beam != null and beam.visible, "the light switches on")
		# Swap guns: the spare 1911 into the holster, the modded one into your pocket.
		inv.open(bench)
		var spare = null
		for e in bench.grid.entries:
			if e.item.def.id == "m1911":
				spare = e.item
		set_meta("modded", p.character.equipment.get_weapon("sidearm"))
		inv._cursor = _target("cell", func(t): return t.grid == bench.grid and t.cell == bench.grid.pos_of(spare))
		inv._pick()
		_drop_on_holster()
		check(p.character.equipment.get_weapon("sidearm") == spare and p.firearm.gun == spare, "a different 1911 in the holster is the one you now shoot")
		check(inv._held == get_meta("modded"), "and you're holding the modded one")
		inv._return_held()
		inv.close()
		# Drop the holstered gun on the ground, then pick it back up with A.
		var eq = p.character.equipment
		var g = eq.disarm("sidearm")
		var w = load("res://scripts/inventory/world_item.gd").spawn(g, p.global_position + Vector3(0, 0, -1.0), rs)
		set_meta("dropped", w)
		check(p.active_weapon == "knife", "with the holster empty you switch to the knife")
	if f == 14:
		var w = get_meta("dropped")
		check(w.find_child("M1911", true, false) != null, "a gun on the floor lies there as its model")
		w.use(p)
		check(p.character.equipment.get_weapon("sidearm") != null and p.active_weapon == "knife", "picking it up puts it straight back in the holster")
		p.switch_weapon("pistol")
		check(p.active_weapon == "pistol", "and Y draws it again")
		# Hearing: an enemy 20 m away doesn't hear a suppressed shot, does hear an open one.
		var e = load("res://scripts/ai/enemy.gd").new()
		e.position = p.global_position + Vector3(20, 0, 0)
		rs.add_child(e)
		var rng := RandomNumberGenerator.new()
		e.setup(rng, "pistol", "holder")
		set_meta("enemy", e)
		var bal = root.get_node("/root/Ballistics")
		bal.gunshot.emit(p.global_position, p.get_rid(), 0.3)
		check(e.awareness < 0.1, "a suppressed shot 20 m away goes unheard (awareness %.2f)" % e.awareness)
		bal.gunshot.emit(p.global_position, p.get_rid(), 1.0)
		check(e.awareness > 0.5, "an unsuppressed one is heard (%.2f)" % e.awareness)
		# Enemies' guns are items too: killed, they drop it as a pickup with its magazine.
		e.damage.apply("head", 100.0)
		e.die()
	if f == 18:
		var e = get_meta("enemy")
		var found = null
		for n in get_nodes_in_group("world_item"):
			if n.item.def.id == "m1911" and n.global_position.distance_to(e.global_position) < 2.0:
				found = n
		check(found != null and found.item.wpn_mag != null, "a dead enemy's 1911 lies by the body, magazine and all")
	if f == 18:
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
