class_name AmmoDB
extends RefCounted
## Ammunition catalogue. Figures are typical factory / published gel-test values
## for a 5" barrel (sources noted per load). Add new calibers the same way.

static var _cache: Dictionary = {}


static func all_for(caliber: String) -> Array[AmmoType]:
	_ensure()
	var out: Array[AmmoType] = []
	for a: AmmoType in _cache.values():
		if a.caliber == caliber:
			out.append(a)
	out.sort_custom(func(x: AmmoType, y: AmmoType): return x.id < y.id)
	return out


static func get_ammo(id: String) -> AmmoType:
	_ensure()
	return _cache.get(id)


static func _ensure() -> void:
	if not _cache.is_empty():
		return
	var T := AmmoType.Construction

	# 1. Military ball. ~830-840 fps, 30"+ in gel, no expansion, ricochets readily.
	_add({id = "45_1_fmj230", display_name = "230gr FMJ (ball)", short_name = "FMJ",
		construction = T.FMJ, mass_grains = 230.0, muzzle_fps = 835.0, bc_g1 = 0.17,
		gel_unexpanded_in = 30.0, ricochet_factor = 1.0, hard_barrier_factor = 1.0,
		notes = "Round-nose full metal jacket. Deep, narrow wound; overpenetrates; best on hard barriers."})

	# 2. Bonded duty JHP (HST-class): 890 fps, G1 .19, ~12-13.5" / .87-.98" in gel,
	#    17.5" / .51" after steel (nose crushed shut), still expands after wallboard.
	_add({id = "45_2_jhp230", display_name = "230gr JHP (bonded)", short_name = "JHP",
		construction = T.JHP, mass_grains = 230.0, muzzle_fps = 890.0, bc_g1 = 0.19,
		expanded_in = 0.87, expand_min_fps = 700.0, gel_expanded_in = 13.0, gel_unexpanded_in = 17.5,
		clog_chance = 0.15, hard_barrier_factor = 1.2, ricochet_factor = 0.75,
		notes = "Modern bonded hollow point. Expands to ~.87\", stays in the target. Hard barriers crush it shut."})

	# 3. Light +P JHP (Gold Dot-class): ~1050 fps, ~15" / .72".
	_add({id = "45_3_jhp185p", display_name = "185gr JHP +P", short_name = "JHP+P",
		construction = T.JHP, mass_grains = 185.0, muzzle_fps = 1050.0, bc_g1 = 0.13, plus_p = true,
		expanded_in = 0.72, expand_min_fps = 800.0, gel_expanded_in = 15.0, gel_unexpanded_in = 19.0,
		clog_chance = 0.25, hard_barrier_factor = 1.5, ricochet_factor = 0.75,
		notes = "Fast, flat-shooting +P. More recoil, needs speed to open."})

	# 4. Solid copper HP (Barnes TAC-XP): 1000 fps, G1 .167, ~12-14.7" / .68-.81", 100% weight retention.
	_add({id = "45_4_cu185p", display_name = "185gr Solid Copper HP +P", short_name = "Cu HP",
		construction = T.SOLID_COPPER, mass_grains = 185.0, muzzle_fps = 1000.0, bc_g1 = 0.167, plus_p = true,
		expanded_in = 0.76, expand_min_fps = 750.0, gel_expanded_in = 13.9, gel_unexpanded_in = 22.0,
		clog_chance = 0.08, hard_barrier_factor = 1.1, ricochet_factor = 0.8,
		notes = "Monolithic copper: holds together through barriers, rarely plugs."})

	# 5. Lead semi-wadcutter target load: ~850 fps, blunt (low BC), cuts a full-caliber hole.
	_add({id = "45_5_lswc200", display_name = "200gr Lead SWC", short_name = "LSWC",
		construction = T.LEAD, mass_grains = 200.0, muzzle_fps = 850.0, bc_g1 = 0.10,
		gel_unexpanded_in = 24.0, hard_barrier_factor = 1.6, ricochet_factor = 0.7,
		notes = "Cheap practice load. Soft lead smears on hard targets; sharp shoulder cuts clean holes."})

	# 6. Frangible (copper-polymer): ~1100 fps, turns to dust on hard surfaces, shallow in gel.
	_add({id = "45_6_frang155", display_name = "155gr Frangible", short_name = "Frang",
		construction = T.FRANGIBLE, mass_grains = 155.0, muzzle_fps = 1100.0, bc_g1 = 0.09,
		expanded_in = 0.75, expand_min_fps = 300.0, gel_expanded_in = 8.0, gel_unexpanded_in = 10.0,
		disintegrates_on_hard = true, hard_barrier_factor = 1.0, ricochet_factor = 0.0,
		notes = "Breaks into powder on steel/masonry: no ricochets, no hard-barrier penetration."})


static func _add(fields: Dictionary) -> void:
	var a := AmmoType.new()
	for k: String in fields:
		a.set(k, fields[k])
	_cache[a.id] = a
