class_name InvGrid
extends RefCounted
## A rectangle of squares holding items at integer positions (top-left anchored).

var size := Vector2i(1, 1)
var label := ""
var entries: Array = []   ## Array of {item: InvItem, pos: Vector2i}


func _init(w := 1, h := 1, name := "") -> void:
	size = Vector2i(w, h)
	label = name


func entry_at(cell: Vector2i) -> Dictionary:
	for e in entries:
		var it: InvItem = e.item
		var r := Rect2i(e.pos, it.footprint())
		if r.has_point(cell):
			return e
	return {}


func item_at(cell: Vector2i) -> InvItem:
	var e := entry_at(cell)
	return e.item if not e.is_empty() else null


func pos_of(item: InvItem) -> Vector2i:
	for e in entries:
		if e.item == item:
			return e.pos
	return Vector2i(-1, -1)


func fits(item: InvItem, pos: Vector2i, ignore: InvItem = null) -> bool:
	var r := Rect2i(pos, item.footprint())
	if r.position.x < 0 or r.position.y < 0 or r.end.x > size.x or r.end.y > size.y:
		return false
	if item.contains_grid(self):
		return false
	for e in entries:
		if e.item == ignore or e.item == item:
			continue
		if r.intersects(Rect2i(e.pos, (e.item as InvItem).footprint())):
			return false
	return true


func place(item: InvItem, pos: Vector2i) -> bool:
	if not fits(item, pos):
		return false
	remove(item)
	entries.append({item = item, pos = pos})
	return true


func remove(item: InvItem) -> bool:
	for i in entries.size():
		if entries[i].item == item:
			entries.remove_at(i)
			return true
	return false


## First free spot scanning row by row; tries rotating if it doesn't fit as is.
func auto_place(item: InvItem) -> bool:
	for rot in [item.rotated, not item.rotated]:
		item.rotated = rot
		for y in size.y:
			for x in size.x:
				if fits(item, Vector2i(x, y)):
					entries.append({item = item, pos = Vector2i(x, y)})
					return true
	return false


## Top up existing stacks of the same thing first. Returns how many didn't fit.
func merge_stacks(item: InvItem) -> int:
	if item.def.max_stack <= 1:
		return item.count
	for e in entries:
		var other: InvItem = e.item
		if other != item and other.def == item.def and other.count < other.def.max_stack:
			var moved := mini(item.count, other.def.max_stack - other.count)
			other.count += moved
			item.count -= moved
			if item.count <= 0:
				return 0
	return item.count


func content_weight() -> float:
	var kg := 0.0
	for e in entries:
		kg += (e.item as InvItem).weight()
	return kg


func free_cells() -> int:
	var used := 0
	for e in entries:
		var f: Vector2i = (e.item as InvItem).footprint()
		used += f.x * f.y
	return size.x * size.y - used
