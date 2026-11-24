class_name Equipment
extends RefCounted
## What a character is wearing, slot by slot. Purely data: CharacterModel
## listens to `changed` and rebuilds the visuals.

signal changed(slot: String)
signal weapon_changed(slot: String)

const SLOTS := ["head", "face", "torso_inner", "torso_outer", "vest", "hands", "legs", "feet", "back", "belt", "accessory"]
const SLOT_NAMES := {
	head = "Head", face = "Face", torso_inner = "Shirt", torso_outer = "Jacket", vest = "Vest / rig",
	hands = "Hands", legs = "Legs", feet = "Feet", back = "Back", belt = "Belt", accessory = "Accessory",
}

const WEAPON_SLOTS := ["primary", "sidearm", "melee"]
const WEAPON_SLOT_NAMES := {primary = "Primary", sidearm = "Holster", melee = "Sheath"}

var worn: Dictionary = {}     ## slot -> GearInstance
var weapons: Dictionary = {}  ## weapon slot -> InvItem (a gun or a knife)


## Put a weapon in its slot; returns whatever was there.
func arm(item: InvItem) -> InvItem:
	var slot := item.def.weapon_slot
	var old: InvItem = weapons.get(slot)
	weapons[slot] = item
	weapon_changed.emit(slot)
	return old


func disarm(slot: String) -> InvItem:
	var old: InvItem = weapons.get(slot)
	if old:
		weapons.erase(slot)
		weapon_changed.emit(slot)
	return old


func get_weapon(slot: String) -> InvItem:
	return weapons.get(slot)


func equip(g: GearInstance) -> GearInstance:
	## Returns whatever was in that slot before (so it can go back into the inventory).
	var slot := g.item.slot
	var old: GearInstance = worn.get(slot)
	worn[slot] = g
	changed.emit(slot)
	return old


func unequip(slot: String) -> GearInstance:
	var old: GearInstance = worn.get(slot)
	if old:
		worn.erase(slot)
		changed.emit(slot)
	return old


func get_slot(slot: String) -> GearInstance:
	return worn.get(slot)


## Worn gear plus everything stored in it, plus weapons (guns with their magazines).
func total_weight() -> float:
	var kg := 0.0
	for w: InvItem in weapons.values():
		kg += w.weight()
	for g: GearInstance in worn.values():
		kg += g.item.weight_kg
		for grid: InvGrid in g.grids:
			kg += grid.content_weight()
	return kg


## Storage grids in worn gear, in reload-search order: rig, then pockets, then bag.
func grids(include_back := true) -> Array:
	var out: Array = []
	for slot in ["vest", "legs", "torso_outer", "torso_inner", "belt"] + (["back"] if include_back else []):
		var g: GearInstance = worn.get(slot)
		if g:
			out.append_array(g.grids)
	return out


## Put an item into worn storage: top up matching stacks first, then the first spot it fits.
func store(item: InvItem, include_back := true) -> bool:
	var gs := grids(include_back)
	for grid: InvGrid in gs:
		if grid.merge_stacks(item) == 0:
			return true
	for grid: InvGrid in gs:
		if grid.auto_place(item):
			return true
	return false


func storage_cells() -> int:
	var n := 0
	for grid: InvGrid in grids():
		n += grid.size.x * grid.size.y
	return n


func total_capacity() -> float:
	var l := 0.0
	for g: GearInstance in worn.values():
		l += g.item.capacity_l
	return l


func hidden_regions() -> Dictionary:
	var out := {}
	for g: GearInstance in worn.values():
		for r in g.item.hides_regions:
			out[r] = true
	return out
