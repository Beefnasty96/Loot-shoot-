class_name ItemDB
extends RefCounted
## Every item that can sit in a grid: gear (wrapping GearDB), magazines,
## loose rounds (one per AmmoType) and loot.

const ICONS := "res://assets/icons/%s.png"
const CASE_POWDER_KG := {".45 ACP": 0.0063, "5.56 NATO": 0.0086}   ## Case + powder + primer, added to bullet weight.

static var _defs: Dictionary = {}


static func get_def(id: String) -> ItemDef:
	_ensure()
	return _defs.get(id)


static func all() -> Array[ItemDef]:
	_ensure()
	var out: Array[ItemDef] = []
	for d: ItemDef in _defs.values():
		out.append(d)
	return out


static func round_weight(a: AmmoType) -> float:
	return a.mass_kg() + float(CASE_POWDER_KG.get(a.caliber, 0.0063))


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	var C := ItemDef.Category
	# Wearables: footprint when stored (folded / packed).
	var stored := {tshirt = Vector2i(2, 2), jacket = Vector2i(3, 3), pants = Vector2i(2, 3), boots = Vector2i(2, 2),
		gloves = Vector2i(1, 1), beanie = Vector2i(1, 1), vest = Vector2i(3, 3), cap = Vector2i(2, 1), backpack = Vector2i(4, 4)}
	var shorts := {tshirt = "T-shirt", jacket = "Jacket", pants = "Cargo", boots = "Boots", gloves = "Gloves",
		beanie = "Beanie", vest = "Chest rig", cap = "Cap", backpack = "Daypack"}
	for g: GearItem in GearDB.all():
		var d := _add(g.id, g.display_name, shorts.get(g.id, _short(g.display_name)), C.GEAR, stored.get(g.id, Vector2i(2, 2)), g.weight_kg, 1, 40, g.description)
		d.gear_id = g.id
	# Magazine.
	var mag := _add("mag_1911", "1911 magazine (7 rd)", "Mag", C.MAGAZINE, Vector2i(1, 1), 0.12, 1, 25,
		"Single-stack .45 ACP. Drop loose rounds on it to load.")
	mag.mag_capacity = 7
	mag.caliber = ".45 ACP"
	mag.mag_family = "mag_1911"
	var mag8 := _add("mag_1911_8", "1911 magazine (8 rd)", "Mag 8", C.MAGAZINE, Vector2i(1, 1), 0.13, 1, 35,
		"Extended-follower 8-rounder. Same well, one more round.")
	mag8.mag_capacity = 8
	mag8.caliber = ".45 ACP"
	mag8.mag_family = "mag_1911"
	mag8.icon_path = ICONS % "mag_1911"
	var stanag := _add("mag_stanag", "STANAG magazine (30 rd)", "30rd", C.MAGAZINE, Vector2i(1, 2), 0.117, 1, 20,
		"Aluminium 30-round 5.56 magazine, tan follower. Fits the M4 and any STANAG rifle.")
	stanag.mag_capacity = 30
	stanag.caliber = "5.56 NATO"
	stanag.mag_family = "stanag"
	# Weapons and attachments come from WeaponDB. Weight here is the bare weapon/part;
	# InvItem.weight() adds everything mounted on it.
	for wid: String in WeaponDB.WEAPONS:
		var w: Dictionary = WeaponDB.WEAPONS[wid]
		var d := _add(wid, w.name, w.name.split(" ")[-1] if w.name.length() > 8 else w.name, C.WEAPON, w.size, w.weight, 1, w.get("value", 100), w.get("description", ""))
		d.weapon_id = wid
		d.weapon_slot = w.slot
		d.weapon_kind = w.kind
		d.caliber = w.get("caliber", "")
		d.scene_path = w.scene
	for pid: String in WeaponDB.PARTS:
		var p: Dictionary = WeaponDB.PARTS[pid]
		var d := _add(pid, p.name, _part_short(p), C.PART, p.get("size", Vector2i(1, 1)), p.weight, 1, p.get("value", 20), p.get("description", ""))
		d.part_id = pid
		d.scene_path = p.get("scene", "")
	# Loose rounds, one stack type per load.
	for a in AmmoDB.all_for(".45 ACP") + AmmoDB.all_for("5.56 NATO"):
		var r := _add(a.id, a.caliber + " " + a.display_name, a.short_name, C.AMMO, Vector2i(1, 1), round_weight(a), 50, 1,
			a.notes)
		r.ammo_id = a.id
		r.caliber = a.caliber
		r.icon_path = ICONS % ("ammo_" + a.short_name.to_lower().replace("+", "p").replace(" ", "_"))
	# Loot.
	_add("ifak", "Trauma kit (IFAK)", "IFAK", C.MEDICAL, Vector2i(1, 1), 0.4, 1, 120, "Tourniquet, gauze, chest seal.")
	_add("medkit", "Car first aid kit", "Car kit", C.MEDICAL, Vector2i(2, 1), 0.6, 1, 60, "Bandages and a few pills.")
	_add("painkillers", "Painkillers", "Pills", C.MEDICAL, Vector2i(1, 1), 0.1, 1, 30, "Takes the edge off.")
	_add("water", "Water bottle", "Water", C.FOOD, Vector2i(1, 2), 0.6, 1, 10, "Half a liter.")
	_add("beans", "Canned beans", "Beans", C.FOOD, Vector2i(1, 1), 0.45, 1, 8, "Dinner.")
	_add("cash", "Roll of cash", "Cash", C.VALUABLE, Vector2i(1, 1), 0.1, 1, 500, "Bank loot.")
	_add("gold", "Gold bar (1 kg)", "Gold", C.VALUABLE, Vector2i(1, 1), 1.0, 1, 60000, "Small, valuable and heavy.")
	_add("docs", "Classified folder", "Docs", C.VALUABLE, Vector2i(1, 1), 0.3, 1, 2500, "Government building loot.")
	_add("gpu", "Graphics card", "GPU", C.TECH, Vector2i(2, 1), 1.0, 1, 800, "Office loot.")
	_add("laptop", "Laptop", "Laptop", C.TECH, Vector2i(3, 2), 2.2, 1, 400, "Office loot.")


static func _part_short(p: Dictionary) -> String:
	match String(p.type).split("_")[0]:
		"barrel": return "Barrel"
		"muzzle": return "Supp"
		"grips": return "Grips"
		"sights": return "Sights"
		"mount": return "Rail"
		"tactical": return "Light"
		"handguard": return "Rail"
		"stock": return "Stock"
		"rsight": return "BUIS"
	return "Part"


static func _short(name: String) -> String:
	var words := name.split(" ")
	return words[words.size() - 1] if words.size() > 1 and name.length() > 10 else name


static func _add(id: String, name: String, short: String, cat: ItemDef.Category, size: Vector2i, kg: float,
		stack: int, value: int, desc: String) -> ItemDef:
	var d := ItemDef.new()
	d.id = id
	d.display_name = name
	d.short_name = short
	d.category = cat
	d.size = size
	d.weight_kg = kg
	d.max_stack = stack
	d.value = value
	d.description = desc
	d.icon_path = ICONS % id
	_defs[id] = d
	return d
