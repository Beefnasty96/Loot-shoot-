class_name LootContainer
extends StaticBody3D
## A searchable container in the world (crate, cabinet, safe, body later).
## Walk up and press A to open it next to your inventory.

@export var title := "Container"
var grid: InvGrid


func _init(name_text := "Container", w := 8, h := 8) -> void:
	title = name_text
	grid = InvGrid.new(w, h, name_text)
	add_to_group("loot_container")
	add_to_group("interactable")


func prompt() -> String:
	return "A: search " + title


func use(p: Player) -> void:
	p.get_tree().call_group("hud", "open_inventory", self)


func add(item: InvItem) -> bool:
	if grid.merge_stacks(item) == 0:
		return true
	return grid.auto_place(item)
