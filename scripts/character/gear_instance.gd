class_name GearInstance
extends RefCounted
## One physical copy of a GearItem: its colour, wear and (for bags/vests) contents.

var item: GearItem
var color_index := 0
var condition := 1.0              ## 0..1, for wear and armour damage later.
var contents: Array = []          ## Items stored inside (grid inventory comes later).


static func create(item_id: String, color := 0) -> GearInstance:
	var g := GearInstance.new()
	g.item = GearDB.get_item(item_id)
	g.color_index = color
	return g


func color() -> Color:
	if item.colors.is_empty():
		return Color(0.5, 0.5, 0.5)
	return item.colors[color_index % item.colors.size()]


func color_name() -> String:
	return GearDB.color_name(color())
