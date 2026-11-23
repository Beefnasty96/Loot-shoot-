class_name GearInstance
extends RefCounted
## One physical copy of a GearItem: its colour, wear and (for bags/vests) contents.

var item: GearItem
var color_index := 0
var condition := 1.0              ## 0..1, for wear and armour damage later.
var grids: Array = []             ## InvGrid per pocket / pouch / compartment.


static func create(item_id: String, color := 0) -> GearInstance:
	var g := GearInstance.new()
	g.item = GearDB.get_item(item_id)
	g.color_index = color
	var names := GearDB.grid_names(item_id)
	for i in g.item.grid_layout.size():
		var s: Vector2i = g.item.grid_layout[i]
		g.grids.append(InvGrid.new(s.x, s.y, names[i] if i < names.size() else ""))
	return g


func color() -> Color:
	if item.colors.is_empty():
		return Color(0.5, 0.5, 0.5)
	return item.colors[color_index % item.colors.size()]


func color_name() -> String:
	return GearDB.color_name(color())
