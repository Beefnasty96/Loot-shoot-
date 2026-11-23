class_name GearItem
extends Resource
## Definition of a wearable item (shared by every copy of it).
##
## SKINNED items are clothes built on the base body's skeleton: they bend with it.
## RIGID items (hats, bags) ride on one bone.

enum Kind { SKINNED, RIGID }

@export var id := ""
@export var display_name := ""
@export var slot := ""                      ## See Equipment.SLOTS.
@export var kind: Kind = Kind.SKINNED
@export var scene_path := ""
@export var texture_path := ""
@export var attach_bone := ""               ## RIGID only.
@export var hides_regions: PackedStringArray = []  ## Body regions covered (hidden) while worn.
@export var weight_kg := 0.0
@export var capacity_l := 0.0               ## Storage volume (pockets, pouches, bags).
@export var colors: Array[Color] = []       ## Main colour choices.
@export var accent: Color = Color(0.08, 0.08, 0.08)
@export var roughness := 0.9
@export var description := ""
# Reserved for the armour step: protection class and which body zones it covers.
@export var armor_class := 0
@export var armor_zones: PackedStringArray = []
