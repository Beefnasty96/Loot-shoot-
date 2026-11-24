class_name ItemDef
extends Resource
## What an item IS (shared by every copy): footprint in squares, weight, stacking.

enum Category { GEAR, MAGAZINE, AMMO, MEDICAL, FOOD, VALUABLE, TECH, WEAPON, PART }

@export var id := ""
@export var display_name := ""
@export var short_name := ""                 ## Shown on the item's tile.
@export var category: Category = Category.VALUABLE
@export var size := Vector2i(1, 1)           ## Width x height in squares (unrotated).
@export var weight_kg := 0.1                 ## Per unit (per round for ammo).
@export var max_stack := 1
@export var value := 0                       ## Dollars, for trading/XP later.
@export var icon_path := ""
@export var description := ""
# Links to other systems.
@export var gear_id := ""                    ## Wearable: GearDB id.
@export var ammo_id := ""                    ## Loose rounds: AmmoDB id.
@export var mag_capacity := 0                ## Magazine: rounds it holds.
@export var caliber := ""
@export var mag_family := ""                 ## Magazine: which guns' magazine slots take it (WeaponDB).
@export var weapon_id := ""                  ## Weapon: WeaponDB.WEAPONS id.
@export var weapon_slot := ""                ## Weapon: "primary", "sidearm" or "melee".
@export var weapon_kind := ""                ## Weapon: pistol, rifle, smg, shotgun, knife.
@export var part_id := ""                    ## Attachment: WeaponDB.PARTS id.
@export var scene_path := ""                 ## Weapon/part: the 3D model.


func is_gear() -> bool:
	return gear_id != ""


func is_mag() -> bool:
	return mag_capacity > 0


func is_ammo() -> bool:
	return ammo_id != ""


func is_weapon() -> bool:
	return weapon_slot != ""


func is_firearm() -> bool:
	return is_weapon() and weapon_kind != "knife"


func is_part() -> bool:
	return part_id != ""
