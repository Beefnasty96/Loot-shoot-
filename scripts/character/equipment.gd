class_name Equipment
extends RefCounted
## What a character is wearing, slot by slot. Purely data: CharacterModel
## listens to `changed` and rebuilds the visuals.

signal changed(slot: String)

const SLOTS := ["head", "face", "torso_inner", "torso_outer", "vest", "hands", "legs", "feet", "back", "belt", "accessory"]
const SLOT_NAMES := {
	head = "Head", face = "Face", torso_inner = "Shirt", torso_outer = "Jacket", vest = "Vest / rig",
	hands = "Hands", legs = "Legs", feet = "Feet", back = "Back", belt = "Belt", accessory = "Accessory",
}

var worn: Dictionary = {}   ## slot -> GearInstance


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


func total_weight() -> float:
	var kg := 0.0
	for g: GearInstance in worn.values():
		kg += g.item.weight_kg
	return kg


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
