class_name GearDB
extends RefCounted
## Catalogue of wearable gear. Models come from tools/blender/gear_build.py.

static var _items: Dictionary = {}

const COLOR_NAMES := {
	"white": Color(0.85, 0.85, 0.82), "grey": Color(0.45, 0.46, 0.47), "black": Color(0.12, 0.12, 0.13),
	"olive": Color(0.33, 0.36, 0.22), "tan": Color(0.62, 0.53, 0.38), "navy": Color(0.16, 0.2, 0.33),
	"red": Color(0.55, 0.12, 0.1), "denim": Color(0.3, 0.38, 0.55), "khaki": Color(0.55, 0.5, 0.36),
	"brown": Color(0.36, 0.24, 0.15), "orange": Color(0.85, 0.42, 0.1), "coyote": Color(0.5, 0.4, 0.27),
	"forest": Color(0.2, 0.3, 0.2), "maroon": Color(0.35, 0.1, 0.12),
}


static func get_item(id: String) -> GearItem:
	_ensure()
	return _items.get(id)


static func all() -> Array[GearItem]:
	_ensure()
	var out: Array[GearItem] = []
	for it: GearItem in _items.values():
		out.append(it)
	return out


static func for_slot(slot: String) -> Array[GearItem]:
	var out: Array[GearItem] = []
	for it in all():
		if it.slot == slot:
			out.append(it)
	return out


static func color_name(c: Color) -> String:
	var best := ""
	var bd := 1e9
	for n: String in COLOR_NAMES:
		var k: Color = COLOR_NAMES[n]
		var d := Vector3(c.r - k.r, c.g - k.g, c.b - k.b).length()
		if d < bd:
			bd = d
			best = n
	return best.capitalize()


static func _c(names: Array) -> Array[Color]:
	var out: Array[Color] = []
	for n: String in names:
		out.append(COLOR_NAMES[n])
	return out


static func _ensure() -> void:
	if not _items.is_empty():
		return
	var S := GearItem.Kind.SKINNED
	var R := GearItem.Kind.RIGID
	_add("tshirt", "T-shirt", "torso_inner", S, ["torso", "upper_arms"], 0.2, 0.0,
		_c(["white", "grey", "black", "olive", "navy", "red", "maroon"]), Color(0.1, 0.1, 0.1), "Plain cotton tee.")
	_add("jacket", "Field jacket", "torso_outer", S, ["torso", "upper_arms", "forearms"], 1.4, 2.0,
		_c(["olive", "black", "tan", "navy", "brown", "forest"]), Color(0.1, 0.1, 0.1), "Canvas jacket. Two chest pockets.")
	_add("pants", "Cargo pants", "legs", S, ["hips", "thighs", "shins"], 0.8, 3.0,
		_c(["denim", "khaki", "black", "olive", "grey", "coyote"]), Color(0.12, 0.12, 0.12), "Thigh cargo pockets.")
	_add("boots", "Work boots", "feet", S, ["feet"], 1.6, 0.0,
		_c(["brown", "black", "tan", "coyote"]), Color(0.06, 0.06, 0.06), "Lace-up leather boots.")
	_add("gloves", "Shooting gloves", "hands", S, ["hands"], 0.15, 0.0,
		_c(["black", "tan", "olive", "coyote"]), Color(0.2, 0.2, 0.21), "Thin gloves with knuckle pads.")
	_add("beanie", "Beanie", "head", S, [], 0.1, 0.0,
		_c(["black", "olive", "grey", "orange", "navy", "maroon"]), Color(0.1, 0.1, 0.1), "Knit watch cap.")
	_add("vest", "Chest rig", "vest", S, [], 1.2, 6.0,
		_c(["olive", "tan", "black", "coyote"]), Color(0.1, 0.1, 0.1), "Webbing and magazine pouches.")
	var cap := _add("cap", "Baseball cap", "head", R, [], 0.1, 0.0,
		_c(["navy", "black", "red", "tan", "olive"]), Color(0.1, 0.1, 0.1), "Brim keeps the sun out.")
	cap.attach_bone = "Head"
	var pack := _add("backpack", "Daypack (25 L)", "back", R, [], 1.8, 25.0,
		_c(["tan", "olive", "black", "grey", "coyote"]), Color(0.1, 0.1, 0.1), "Main compartment plus front and side pockets.")
	pack.attach_bone = "UpperChest"


static func _add(id: String, name: String, slot: String, kind: GearItem.Kind, hides: Array, kg: float, litres: float,
		colors: Array[Color], accent: Color, desc: String) -> GearItem:
	var it := GearItem.new()
	it.id = id
	it.display_name = name
	it.slot = slot
	it.kind = kind
	it.scene_path = "res://assets/gear/%s/%s.glb" % [id, id]
	it.texture_path = "res://assets/gear/%s/%s_detail.png" % [id, id]
	it.hides_regions = PackedStringArray(hides)
	it.weight_kg = kg
	it.capacity_l = litres
	it.colors = colors
	it.accent = accent
	it.description = desc
	_items[id] = it
	return it
