class_name AmmoDB
extends RefCounted
## Ammunition catalogue. Figures are typical factory / published gel-test values
## (sources noted per load): .45 ACP from a 5" barrel, 5.56 NATO from a 20" barrel
## (a 14.5" M4 loses ~35 fps per inch of that). Add new calibers the same way.

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


	# ---------------------------------------------------------------- 5.56x45mm NATO
	# Rifle bullets behave differently from pistol bullets: they go in nose-first
	# for 3-5" ("the neck"), then turn sideways. If they are still fast enough when
	# they turn, the jacket breaks at the cannelure and the bullet fragments - a
	# much bigger wound that stops sooner. Slow (long range, short barrel, through a
	# wall) and they just tumble. A thin arm or a grazing hit never gets past the
	# neck: a small "icepick" hole straight through. (Fackler/WDTL gel work.)

	# Fragmentation is decided by IMPACT velocity: above frag_min_fps it breaks up,
	# between split_min_fps and that it breaks in two (the core and jacket part),
	# below split_min_fps it only yaws. Distance to 2700 fps from a 14.5" barrel:
	# M193 ~95-100 m; M855 anywhere from ~45 to ~125 m depending on the source's
	# muzzle velocity and threshold. With the Army's M4 velocities and published BCs
	# the simulation gives M193 ~95 m, M855 ~75 m (then it splits out to ~165 m).
	# Accuracy: each load has its own dispersion (dispersion_moa, extreme spread),
	# combined with the gun's (WeaponDB moa) as sqrt(gun^2 + ammo^2), and a muzzle
	# velocity spread (vel_sd_fps) that opens groups vertically at range.

	# 7. M193 ball: 55gr FMJBT, 3240 fps / 20", ~2990 fps from an M4 (Army figure 2,986),
	#    G1 ~.243. Yaws at ~4.7" (12 cm), fragments above 2700 fps impact.
	_add({id = "556_1_m193", display_name = "M193 55gr ball", short_name = "M193", caliber = "5.56 NATO",
		construction = T.FMJ, mass_grains = 55.0, muzzle_fps = 3240.0, reference_barrel_in = 20.0, fps_per_inch = 46.2,
		dispersion_moa = 2.0, vel_sd_fps = 25.0, split_min_fps = 2500.0,
		bc_g1 = 0.243, diameter_in = 0.224, gel_unexpanded_in = 11.0, gel_nose_in = 90.0, hard_ref_in = 30.0,
		yaw_neck_in = 4.7, frag_min_fps = 2700.0, gel_frag_in = 8.0, frag_wound_ratio = 2.7, tumble_wound_ratio = 1.7,
		frag_retained = 0.55, hard_barrier_factor = 1.0, ricochet_factor = 1.1,
		notes = "Fast, light, fragments violently up close. Fragmentation range shrinks fast with a short barrel. Mild steel to ~1/4 in."})

	# 8. M855 / SS109 "green tip": 62gr with a 7gr steel penetrator, ~3100 fps / 20",
	#    2,887 fps from an M4 (Army figure), G1 ~.304. Yaws later (~5") and less predictably;
	#    fragments above 2700 fps impact, breaks in two down to 2500 fps (NDIA / Roberts).
	#    The off-centre steel core costs accuracy: ~3 MOA from a service M4.
	#    Steel tip punches 3.5 mm mild steel at 1300 m (the NATO spec plate).
	_add({id = "556_2_m855", display_name = "M855 62gr green tip", short_name = "M855", caliber = "5.56 NATO",
		construction = T.PENETRATOR, mass_grains = 62.0, muzzle_fps = 3100.0, reference_barrel_in = 20.0, fps_per_inch = 38.7,
		dispersion_moa = 3.0, vel_sd_fps = 30.0, split_min_fps = 2500.0,
		bc_g1 = 0.304, diameter_in = 0.224, gel_unexpanded_in = 13.0, gel_nose_in = 100.0, hard_ref_in = 36.0,
		yaw_neck_in = 5.0, frag_min_fps = 2700.0, gel_frag_in = 9.0, frag_wound_ratio = 2.3, tumble_wound_ratio = 1.6,
		frag_retained = 0.65, hard_barrier_factor = 0.65, ricochet_factor = 0.9,
		notes = "Steel penetrator: much better through steel and car bodies. Flies flatter. Inconsistent fragmentation."})

	# 9. M856 tracer: 63.7gr, ~3050 fps / 20", orange tip. Trace visible to ~800 m.
	#    Lead-light base full of tracer compound: tends to yaw and break up less, and
	#    groups about twice as big as ball.
	_add({id = "556_3_m856", display_name = "M856 63.7gr tracer", short_name = "M856", caliber = "5.56 NATO",
		construction = T.FMJ, mass_grains = 63.7, muzzle_fps = 3050.0, reference_barrel_in = 20.0, fps_per_inch = 35.0,
		dispersion_moa = 4.0, vel_sd_fps = 35.0, split_min_fps = 2550.0,
		bc_g1 = 0.29, diameter_in = 0.224, gel_unexpanded_in = 12.0, gel_nose_in = 90.0, hard_ref_in = 32.0,
		yaw_neck_in = 5.5, frag_min_fps = 2750.0, gel_frag_in = 9.0, frag_wound_ratio = 2.0, tumble_wound_ratio = 1.6,
		frag_retained = 0.7, hard_barrier_factor = 1.0, ricochet_factor = 1.0, tracer = true, tracer_range_m = 800.0,
		notes = "Glowing trail shows where your rounds go - and where you are. Burns out at ~800 m."})


static func _add(fields: Dictionary) -> void:
	var a := AmmoType.new()
	for k: String in fields:
		a.set(k, fields[k])
	_cache[a.id] = a
