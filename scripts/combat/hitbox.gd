class_name Hitbox
extends StaticBody3D
## A body-part collider. Bullets measure how much of it they pass through and
## report the energy they leave behind to `receiver.take_hit(hit)`.

const LAYER := 4  ## Physics layer 3.

@export var zone := "thorax"
@export var gel_factor := 1.0  ## Tissue/bone density relative to gel (skull and ribs > 1).
var receiver: Node


func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	set_meta("material", "flesh")
