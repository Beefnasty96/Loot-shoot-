class_name ItemDef
extends Resource
## What an item IS (shared by every copy): footprint in squares, weight, stacking.

enum Category { GEAR, MAGAZINE, AMMO, MEDICAL, FOOD, VALUABLE, TECH }

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


func is_gear() -> bool:
	return gear_id != ""


func is_mag() -> bool:
	return mag_capacity > 0


func is_ammo() -> bool:
	return ammo_id != ""
