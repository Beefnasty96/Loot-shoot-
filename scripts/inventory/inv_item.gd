class_name InvItem
extends RefCounted
## One item sitting in a grid (or in the gun, or worn).
## Stackables keep a count; magazines keep their rounds; gear keeps a
## GearInstance (colour, condition and its own storage grids with contents).

var def: ItemDef
var count := 1
var rotated := false
var gear: GearInstance          ## Wearable items.
var mag_ammo: AmmoType          ## Magazines: what's loaded.
var mag_count := 0


static func create(id: String, amount := 1) -> InvItem:
	var it := InvItem.new()
	it.def = ItemDB.get_def(id)
	assert(it.def != null, "unknown item " + id)
	it.count = clampi(amount, 1, maxi(1, it.def.max_stack))
	if it.def.is_gear():
		it.gear = GearInstance.create(it.def.gear_id, randi() % maxi(1, GearDB.get_item(it.def.gear_id).colors.size()))
	return it


static func from_gear(g: GearInstance) -> InvItem:
	var it := InvItem.new()
	it.def = ItemDB.get_def(g.item.id)
	it.gear = g
	return it


static func magazine(ammo: AmmoType, rounds: int) -> InvItem:
	var it := create("mag_1911")
	it.mag_ammo = ammo
	it.mag_count = clampi(rounds, 0, it.def.mag_capacity)
	return it


static func rounds(ammo_id: String, amount: int) -> InvItem:
	return create(ammo_id, amount)


func footprint() -> Vector2i:
	return Vector2i(def.size.y, def.size.x) if rotated else def.size


## Own weight plus everything inside it (rounds in a mag, contents of a bag).
func weight() -> float:
	var kg := def.weight_kg * count
	if def.is_mag() and mag_ammo:
		kg += mag_count * ItemDB.round_weight(mag_ammo)
	if gear:
		for g: InvGrid in gear.grids:
			kg += g.content_weight()
	return kg


func contains_grid(grid: InvGrid) -> bool:
	## True if `grid` is somewhere inside this item (stops putting a bag inside itself).
	if gear == null:
		return false
	for g: InvGrid in gear.grids:
		if g == grid:
			return true
		for e in g.entries:
			if (e.item as InvItem).contains_grid(grid):
				return true
	return false


func label() -> String:
	if def.is_mag():
		return "%d/%d" % [mag_count, def.mag_capacity]
	if def.max_stack > 1:
		return str(count)
	return ""


func info() -> String:
	var lines := [def.display_name]
	if def.is_mag():
		lines.append("%d / %d  %s" % [mag_count, def.mag_capacity, mag_ammo.display_name if mag_ammo and mag_count > 0 else "empty"])
	elif def.is_ammo():
		var a := AmmoDB.get_ammo(def.ammo_id)
		lines.append("%d rounds. %d fps, %d ft-lb" % [count, roundi(a.muzzle_fps), roundi(a.muzzle_energy_ftlb())])
	elif gear:
		var cells := 0
		for g: InvGrid in gear.grids:
			cells += g.size.x * g.size.y
		lines.append("%s%s" % [gear.color_name(), ("  |  %d squares of storage" % cells) if cells > 0 else ""])
	lines.append("%s   %d x %d" % [Units.pounds(weight()), footprint().x, footprint().y])
	if def.description != "":
		lines.append(def.description)
	return "\n".join(lines)
