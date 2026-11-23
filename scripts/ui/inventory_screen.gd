class_name InventoryScreen
extends Control
## Tarkov-style inventory: worn gear on the left, the storage your gear gives you
## (rig, pockets, backpack) in the middle, and an open container on the right.
##
## Controller:  D-pad / left stick move the cursor
##              A  pick up / put down        Y  rotate (or unload a magazine)
##              X  quick-move to the other side (or equip / take off)
##              B or Select  close
## Touch/mouse: drag an item and let go where you want it; or tap to pick up, tap to drop.
## Drop loose rounds on a magazine to load it; drop rounds on rounds to stack them.

signal changed

const CELL := 52
const SLOT_SIZE := Vector2(170, 104)
const COL_EQUIP := 40.0
const COL_STORAGE := 440.0
const COL_LOOT := 1190.0
const TOP := 110.0
const BG := Color(0.07, 0.08, 0.07, 0.94)
const CELL_BG := Color(0.13, 0.14, 0.13)
const CELL_LINE := Color(0.24, 0.26, 0.23)
const ACCENT := Color(0.85, 0.78, 0.45)

var player: Player
var container: LootContainer

var _targets: Array = []          ## {kind: "cell"/"slot", rect, grid, cell, slot}
var _grid_rects: Array = []       ## {grid, origin, label}
var _labels: Array = []           ## {text, pos, size, color}
var _cursor := 0
var _held: InvItem
var _held_from := {}
var _dragging := false
var _press_target := -1
var _message := ""
var _message_time := 0.0
var _repeat := {}
var _icons := {}
var _font: Font


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font


func is_open() -> bool:
	return visible


func open(with_container: LootContainer = null) -> void:
	container = with_container
	visible = true
	player.ui_locked = true
	player.sprinting = false
	_cursor = 0
	_layout()
	queue_redraw()


func close() -> void:
	if _held and not _return_held():
		_flash("No room to put that back. Find it a spot first.")
		return
	visible = false
	container = null
	player.ui_locked = false
	changed.emit()


# ------------------------------------------------------------------ layout

func _equipment() -> Equipment:
	return player.character.equipment


func _layout() -> void:
	_targets.clear()
	_grid_rects.clear()
	_labels.clear()
	var eq := _equipment()
	# Equipment slots, two columns.
	_label("EQUIPMENT", Vector2(COL_EQUIP, TOP - 34), 26, ACCENT)
	for i in Equipment.SLOTS.size():
		var slot: String = Equipment.SLOTS[i]
		var pos := Vector2(COL_EQUIP + (i % 2) * (SLOT_SIZE.x + 14), TOP + (i / 2) * (SLOT_SIZE.y + 26))
		_label(Equipment.SLOT_NAMES[slot].to_upper(), pos + Vector2(0, -4), 14, Color(0.7, 0.72, 0.66))
		_targets.append({kind = "slot", slot = slot, rect = Rect2(pos + Vector2(0, 4), SLOT_SIZE)})
	# Storage from what you wear.
	var y := TOP
	_label("YOUR STORAGE", Vector2(COL_STORAGE, TOP - 34), 26, ACCENT)
	var sections := [["RIG", ["vest"]], ["POCKETS", ["legs", "torso_outer", "torso_inner", "belt"]], ["BACKPACK", ["back"]]]
	var any := false
	for sec: Array in sections:
		var grids: Array = []
		var owners: Array = []
		for slot: String in sec[1]:
			var g: GearInstance = eq.get_slot(slot)
			if g:
				for grid: InvGrid in g.grids:
					grids.append(grid)
					owners.append(g.item.display_name)
		if grids.is_empty():
			continue
		any = true
		_label(sec[0], Vector2(COL_STORAGE, y), 18, Color(0.8, 0.82, 0.75))
		y += 24
		var x := COL_STORAGE
		var row_h := 0.0
		for gi in grids.size():
			var grid: InvGrid = grids[gi]
			var w := grid.size.x * CELL
			var h := grid.size.y * CELL
			if x + w > COL_LOOT - 40 and x > COL_STORAGE:
				x = COL_STORAGE
				y += row_h + 22
				row_h = 0.0
			_add_grid(grid, Vector2(x, y + 16), grid.label)
			x += w + 12
			row_h = maxf(row_h, h + 16)
		y += row_h + 26
	if not any:
		_label("No pockets. Wear pants, a jacket, a rig or a backpack to carry things.", Vector2(COL_STORAGE, y), 18, Color(0.7, 0.6, 0.5))
	# Container.
	if container:
		_label(container.title.to_upper(), Vector2(COL_LOOT, TOP - 34), 26, ACCENT)
		_add_grid(container.grid, Vector2(COL_LOOT, TOP), "")
	else:
		_label("NEARBY", Vector2(COL_LOOT, TOP - 34), 26, Color(0.5, 0.52, 0.48))
		_label("Nothing open. Walk up to a crate and press A.", Vector2(COL_LOOT, TOP), 18, Color(0.55, 0.57, 0.52))
	_cursor = clampi(_cursor, 0, _targets.size() - 1)


func _label(text: String, pos: Vector2, size: int, color: Color) -> void:
	_labels.append({text = text, pos = pos, size = size, color = color})


func _add_grid(grid: InvGrid, origin: Vector2, label: String) -> void:
	_grid_rects.append({grid = grid, origin = origin, label = label})
	for y in grid.size.y:
		for x in grid.size.x:
			_targets.append({kind = "cell", grid = grid, cell = Vector2i(x, y), rect = Rect2(origin + Vector2(x, y) * CELL, Vector2(CELL, CELL))})


func _grid_origin(grid: InvGrid) -> Vector2:
	for g in _grid_rects:
		if g.grid == grid:
			return g.origin
	return Vector2(-9999, -9999)


func _is_player_grid(grid: InvGrid) -> bool:
	return container == null or grid != container.grid


# ------------------------------------------------------------------ drawing

func _icon(item: InvItem) -> Texture2D:
	var path := item.def.icon_path
	if not _icons.has(path):
		_icons[path] = load(path) if ResourceLoader.exists(path) else null
	return _icons[path]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	# Header: load.
	var kg := player.carried_weight()
	var status := Encumbrance.status(kg)
	var col := Color(0.85, 0.9, 0.8) if status == "" else (Color(1, 0.8, 0.3) if status == "HEAVY" else Color(1, 0.35, 0.3))
	var head := "INVENTORY      Load %s / %s comfortable, %s max   %s   Storage %d squares" % [
		Units.pounds(kg), Units.pounds(Encumbrance.COMFORT_KG), Units.pounds(Encumbrance.OVERWEIGHT_KG), status, _equipment().storage_cells()]
	draw_string(_font, Vector2(COL_EQUIP, 44), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
	for l in _labels:
		draw_string(_font, l.pos, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.size, l.color)
	# Slots.
	for t in _targets:
		if t.kind != "slot":
			continue
		draw_rect(t.rect, CELL_BG)
		draw_rect(t.rect, CELL_LINE, false, 2.0)
		var g: GearInstance = _equipment().get_slot(t.slot)
		if g:
			var it := InvItem.from_gear(g)
			_draw_item_in(it, t.rect, true)
		elif GearDB.for_slot(t.slot).is_empty():
			draw_string(_font, t.rect.position + Vector2(8, t.rect.size.y - 10), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.4, 0.38))
	# Grids.
	for g in _grid_rects:
		var grid: InvGrid = g.grid
		var o: Vector2 = g.origin
		if g.label != "":
			draw_string(_font, o + Vector2(0, -4), g.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.62, 0.57))
		draw_rect(Rect2(o, Vector2(grid.size) * CELL), CELL_BG)
		for y in grid.size.y + 1:
			draw_line(o + Vector2(0, y * CELL), o + Vector2(grid.size.x * CELL, y * CELL), CELL_LINE, 1.0)
		for x in grid.size.x + 1:
			draw_line(o + Vector2(x * CELL, 0), o + Vector2(x * CELL, grid.size.y * CELL), CELL_LINE, 1.0)
		for e in grid.entries:
			var it: InvItem = e.item
			_draw_item_in(it, Rect2(o + Vector2(e.pos) * CELL, Vector2(it.footprint()) * CELL), false)
	# Cursor + held item.
	if _targets.is_empty():
		return
	var t: Dictionary = _targets[_cursor]
	if _held:
		var r: Rect2
		var ok := false
		if t.kind == "cell":
			r = Rect2(t.rect.position, Vector2(_held.footprint()) * CELL)
			ok = _can_drop_at(t)
		else:
			r = t.rect
			ok = _held.def.is_gear() and GearDB.get_item(_held.def.gear_id).slot == t.slot
		draw_rect(r, Color(0.2, 0.8, 0.3, 0.25) if ok else Color(0.9, 0.2, 0.2, 0.25))
		_draw_item_in(_held, r, t.kind == "slot", 0.8)
	draw_rect(t.rect.grow(1), ACCENT, false, 3.0)
	# Info for whatever is under the cursor.
	var info := ""
	var hover := _item_at_target(t)
	if _held:
		info = "Holding: " + _held.info()
	elif hover:
		info = hover.info()
	elif t.kind == "slot":
		info = Equipment.SLOT_NAMES[t.slot] + ": empty"
	draw_rect(Rect2(COL_EQUIP, 880, 370, 170), Color(0.04, 0.05, 0.04, 0.9))
	var lines := info.split("\n")
	for i in lines.size():
		draw_string(_font, Vector2(COL_EQUIP + 10, 906 + i * 24), lines[i], HORIZONTAL_ALIGNMENT_LEFT, 350, 18 if i else 20,
			ACCENT if i == 0 else Color(0.85, 0.87, 0.8))
	var hints := "A pick up/put down    Y rotate / unload mag    X quick move / equip    B close    Drop rounds on a mag to load it"
	draw_string(_font, Vector2(COL_STORAGE, size.y - 24), hints, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.62, 0.57))
	if _message_time > 0.0:
		draw_string(_font, Vector2(COL_STORAGE, size.y - 60), _message, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.7, 0.4))


func _draw_item_in(it: InvItem, r: Rect2, fit_box: bool, alpha := 1.0) -> void:
	draw_rect(r.grow(-1), Color(0.2, 0.22, 0.2, 0.9 * alpha))
	var tex := _icon(it)
	if tex:
		var tsize := Vector2(tex.get_size())
		var area := r.grow(-3)
		if it.rotated and not fit_box:
			# Draw rotated 90 degrees into the rotated footprint.
			var c := area.get_center()
			draw_set_transform(c, PI / 2.0, Vector2.ONE)
			var rs := Vector2(area.size.y, area.size.x)
			var sc := minf(rs.x / tsize.x, rs.y / tsize.y)
			draw_texture_rect(tex, Rect2(-tsize * sc / 2.0, tsize * sc), false, Color(1, 1, 1, alpha))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var sc := minf(area.size.x / tsize.x, area.size.y / tsize.y)
			var s := tsize * sc
			draw_texture_rect(tex, Rect2(area.position + (area.size - s) / 2.0, s), false, Color(1, 1, 1, alpha))
	draw_string(_font, r.position + Vector2(3, 13), it.def.short_name, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6, 12, Color(0.92, 0.92, 0.88, alpha))
	var lab := it.label()
	if lab != "":
		draw_string(_font, r.position + Vector2(3, r.size.y - 5), lab, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6, 14,
			Color(1, 0.9, 0.5, alpha) if it.def.is_mag() and it.mag_count > 0 else Color(0.9, 0.9, 0.86, alpha))
	draw_rect(r, Color(0.35, 0.37, 0.33, alpha), false, 1.0)


# ------------------------------------------------------------------ input

func _process(delta: float) -> void:
	if not visible:
		return
	if _message_time > 0.0:
		_message_time -= delta
	# Held-direction repeat for the cursor.
	for dir_action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		if Input.is_action_pressed(dir_action):
			_repeat[dir_action] = _repeat.get(dir_action, 0.0) + delta
			if _repeat[dir_action] > 0.35:
				_repeat[dir_action] = 0.27
				_move_cursor(dir_action)
		else:
			_repeat.erase(dir_action)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var ti := _target_at(event.position)
		if event.pressed:
			if ti >= 0:
				_cursor = ti
				if _held:
					_drop()
				else:
					_pick()
					_dragging = _held != null
					_press_target = ti
		else:
			if _dragging and _held and ti >= 0 and ti != _press_target:
				_cursor = ti
				_drop()
			_dragging = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var ti := _target_at(event.position)
		if ti >= 0 and (_held or _dragging):
			_cursor = ti
		get_viewport().set_input_as_handled()
		return
	var handled := true
	if event.is_action_pressed("inventory") or event.is_action_pressed("crouch") or event.is_action_pressed("pause"):
		close()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		for a in ["ui_left", "ui_right", "ui_up", "ui_down"]:
			if event.is_action_pressed(a):
				_move_cursor(a)
				break
	elif event.is_action_pressed("interact"):
		if _held:
			_drop()
		else:
			_pick()
	elif event.is_action_pressed("switch_weapon"):
		if _held:
			_held.rotated = not _held.rotated
		else:
			_unload_mag()
	elif event.is_action_pressed("reload"):
		_quick_move()
	elif event is InputEventAction or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventKey:
		handled = event.is_pressed()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
	queue_redraw()


func _target_at(p: Vector2) -> int:
	for i in _targets.size():
		if (_targets[i].rect as Rect2).has_point(p):
			return i
	return -1


func _move_cursor(action: String) -> void:
	var dir := {ui_left = Vector2.LEFT, ui_right = Vector2.RIGHT, ui_up = Vector2.UP, ui_down = Vector2.DOWN}[action] as Vector2
	var from: Vector2 = (_targets[_cursor].rect as Rect2).get_center()
	var best := -1
	var best_score := INF
	for i in _targets.size():
		if i == _cursor:
			continue
		var d: Vector2 = (_targets[i].rect as Rect2).get_center() - from
		var dist := d.length()
		if dist < 1.0:
			continue
		var along := d.dot(dir)
		if along <= 0.0:
			continue
		var cos_a := along / dist
		if cos_a < 0.5:
			continue
		var score := dist * (1.0 + (1.0 - cos_a) * 4.0)
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		_cursor = best


# ------------------------------------------------------------------ actions

func _item_at_target(t: Dictionary) -> InvItem:
	if t.kind == "cell":
		return (t.grid as InvGrid).item_at(t.cell)
	var g: GearInstance = _equipment().get_slot(t.slot)
	return InvItem.from_gear(g) if g else null


func _pick() -> void:
	var t: Dictionary = _targets[_cursor]
	if t.kind == "cell":
		var grid: InvGrid = t.grid
		var e := grid.entry_at(t.cell)
		if e.is_empty():
			return
		_held = e.item
		_held_from = {grid = grid, pos = e.pos, rotated = _held.rotated}
		grid.remove(_held)
	else:
		var g: GearInstance = _equipment().get_slot(t.slot)
		if g == null:
			return
		_held = InvItem.from_gear(g)
		_held_from = {slot = t.slot}
		_equipment().unequip(t.slot)
		_relayout()
	_changed()


func _can_drop_at(t: Dictionary) -> bool:
	var grid: InvGrid = t.grid
	var other := grid.item_at(t.cell)
	if other and _merge_kind(other) != "":
		return true
	return grid.fits(_held, t.cell)


func _merge_kind(other: InvItem) -> String:
	if other.def == _held.def and _held.def.max_stack > 1 and other.count < other.def.max_stack:
		return "stack"
	if _held.def.is_ammo() and other.def.is_mag() and other.def.caliber == _held.def.caliber \
			and other.mag_count < other.def.mag_capacity and (other.mag_count == 0 or other.mag_ammo.id == _held.def.ammo_id):
		return "load"
	return ""


func _drop() -> void:
	var t: Dictionary = _targets[_cursor]
	if t.kind == "slot":
		if not _held.def.is_gear() or GearDB.get_item(_held.def.gear_id).slot != t.slot:
			_flash("That doesn't go there.")
			return
		var old: GearInstance = _equipment().get_slot(t.slot)
		_equipment().equip(_held.gear)
		_held = InvItem.from_gear(old) if old else null
		_held_from = {slot = t.slot} if old else {}
		_relayout()
		_changed()
		return
	var grid: InvGrid = t.grid
	var other := grid.item_at(t.cell)
	if other:
		match _merge_kind(other):
			"stack":
				var moved := mini(_held.count, other.def.max_stack - other.count)
				other.count += moved
				_held.count -= moved
				if _held.count <= 0:
					_held = null
				_changed()
				return
			"load":
				var ammo := AmmoDB.get_ammo(_held.def.ammo_id)
				var n := mini(_held.count, other.def.mag_capacity - other.mag_count)
				other.mag_ammo = ammo
				other.mag_count += n
				_held.count -= n
				_flash("Loaded %d x %s." % [n, ammo.display_name])
				if _held.count <= 0:
					_held = null
				_changed()
				return
	if grid.place(_held, t.cell):
		_held = null
		_changed()
	else:
		_flash("Doesn't fit there.")


func _return_held() -> bool:
	if _held_from.has("slot") and _equipment().get_slot(_held_from.slot) == null and _held.gear:
		_equipment().equip(_held.gear)
		_held = null
		_relayout()
		return true
	if _held_from.has("grid"):
		var rot := _held.rotated
		_held.rotated = _held_from.rotated
		if (_held_from.grid as InvGrid).place(_held, _held_from.pos):
			_held = null
			return true
		_held.rotated = rot
	if _store(_held, true) or (container and _store_in([container.grid], _held)):
		_held = null
		return true
	return false


## Put an item into the player's storage (rig, pockets, bag). Stacks first.
func _store(item: InvItem, include_back := true) -> bool:
	return _store_in(_equipment().grids(include_back), item)


func _store_in(grids: Array, item: InvItem) -> bool:
	for grid: InvGrid in grids:
		if grid.merge_stacks(item) == 0:
			return true
	for grid: InvGrid in grids:
		if grid.auto_place(item):
			return true
	return false


func _quick_move() -> void:
	if _held:
		return
	var t: Dictionary = _targets[_cursor]
	if t.kind == "slot":
		var g: GearInstance = _equipment().get_slot(t.slot)
		if g == null:
			return
		var it := InvItem.from_gear(g)
		_equipment().unequip(t.slot)
		if (container and _store_in([container.grid], it)) or _store(it):
			_flash("Took off %s." % g.item.display_name)
		else:
			_equipment().equip(g)
			_flash("No room to put it.")
		_relayout()
		_changed()
		return
	var grid: InvGrid = t.grid
	var it := grid.item_at(t.cell)
	if it == null:
		return
	var from_player := _is_player_grid(grid)
	var old_pos := grid.pos_of(it)
	grid.remove(it)
	var ok := false
	if not from_player:
		# Wearables go straight on if that slot is free.
		if it.def.is_gear() and _equipment().get_slot(GearDB.get_item(it.def.gear_id).slot) == null:
			_equipment().equip(it.gear)
			_relayout()
			ok = true
		else:
			ok = _store(it)
	elif container:
		ok = _store_in([container.grid], it)
	if not ok:
		if not grid.place(it, old_pos):
			grid.auto_place(it)
		_flash("No room on the other side.")
	_changed()


func _unload_mag() -> void:
	var t: Dictionary = _targets[_cursor]
	var it := _item_at_target(t)
	if it == null or not it.def.is_mag() or it.mag_count <= 0:
		return
	var rounds := InvItem.rounds(it.mag_ammo.id, it.mag_count)
	var grids: Array = [t.grid] if t.kind == "cell" else []
	grids.append_array(_equipment().grids())
	if container:
		grids.append(container.grid)
	if _store_in(grids, rounds):
		_flash("Unloaded %d rounds." % it.mag_count)
		it.mag_count = 0
		it.mag_ammo = null
	else:
		_flash("No room for the rounds.")
	_changed()


func _relayout() -> void:
	var keep: Rect2 = _targets[_cursor].rect if not _targets.is_empty() else Rect2()
	_layout()
	var ti := _target_at(keep.get_center())
	if ti >= 0:
		_cursor = ti


func _flash(text: String) -> void:
	_message = text
	_message_time = 2.5


func _changed() -> void:
	changed.emit()
	queue_redraw()
