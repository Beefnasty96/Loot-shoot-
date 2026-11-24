class_name InventoryScreen
extends Control
## Tarkov-style inventory: worn gear on the left, the storage your gear gives you
## (rig, pockets, backpack) in the middle, and on the right whatever you're
## searching: a container, a body (its worn gear and pockets), or the ground.
## Anything put on the Ground panel is dropped at your feet when you close.
##
## Controller:  D-pad / left stick move the cursor
##              A  pick up / put down        Y  rotate (or unload a magazine)
##              X  quick-move to the other side (or equip / take off)
##              B or Select  close
## Touch/mouse: drag an item and let go where you want it; or tap to pick up, tap to drop.
## Drop loose rounds on a magazine to load it; drop rounds on rounds to stack them.
##
## Weapons: Primary / Holster / Sheath slots under your gear (and on bodies).
## Drop a magazine or an attachment on a gun to fit it (a magazine swaps with
## the one inside). Y on a gun opens it up: every attachment slot as a tree
## (a threaded barrel brings a muzzle slot, a rail brings a tactical slot), with
## the stats it adds up to. Parts go in and out there; required parts (barrel,
## grips, sights) can only be swapped, not left empty.

signal changed

const CELL := 52
const SLOT_SIZE := Vector2(170, 84)
const COL_EQUIP := 40.0
const COL_STORAGE := 440.0
const COL_LOOT := 1190.0
const TOP := 110.0
const BG := Color(0.07, 0.08, 0.07, 0.94)
const CELL_BG := Color(0.13, 0.14, 0.13)
const CELL_LINE := Color(0.24, 0.26, 0.23)
const ACCENT := Color(0.85, 0.78, 0.45)

const GROUND_RADIUS := 2.5

var player: Player
var source: Node                  ## LootContainer, Npc (body) or null (= the ground)
var container: LootContainer      ## Set when the source is a container.
var _ground: InvGrid
var _ground_nodes := {}           ## InvItem -> WorldItem already lying there

var _targets: Array = []          ## {kind: "cell"/"slot", rect, grid, cell, slot}
var _grid_rects: Array = []       ## {grid, origin, label}
var _labels: Array = []           ## {text, pos, size, color}
var _cursor := 0
var _held: InvItem
var _held_from := {}
var _mod_gun: InvItem              ## Gun opened for modding (null = panel closed).
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


func open(target: Node = null) -> void:
	source = target
	container = target as LootContainer
	if target == null:
		_build_ground()
	visible = true
	player.ui_locked = true
	player.sprinting = false
	_cursor = 0
	_mod_gun = null
	_layout()
	queue_redraw()


func close() -> void:
	if _held and not _return_held():
		_flash("No room to put that back. Find it a spot first.")
		return
	visible = false
	if source == null:
		_sync_ground()
	container = null
	source = null
	player.ui_locked = false
	changed.emit()


func _body() -> Npc:
	return source as Npc


## Grids on the other side (container, body storage, or the ground).
func _other_grids() -> Array:
	if container:
		return [container.grid]
	if _body():
		return _body().model.equipment.grids()
	if source == null and _ground:
		return [_ground]
	return []


func _build_ground() -> void:
	_ground = InvGrid.new(12, 14, "Ground")
	_ground_nodes.clear()
	for n in get_tree().get_nodes_in_group("world_item"):
		var w := n as WorldItem
		if w.is_queued_for_deletion() or w.global_position.distance_to(player.global_position) > GROUND_RADIUS:
			continue
		if _ground.auto_place(w.item):
			_ground_nodes[w.item] = w


## Make the world match the Ground panel: new items are dropped at your feet,
## items you took are removed from the floor.
func _sync_ground() -> void:
	var still := {}
	var i := 0
	for e in _ground.entries:
		var it: InvItem = e.item
		still[it] = true
		if not _ground_nodes.has(it):
			var a := TAU * (i / 7.0) + randf() * 0.4
			var r := 0.45 + (i % 3) * 0.18
			var fwd := -player.global_transform.basis.z
			var at := player.global_position + fwd * 0.35 + Vector3(cos(a), 0.0, sin(a)) * r
			WorldItem.spawn(it, at, player.get_parent())
			i += 1
	for it: InvItem in _ground_nodes:
		if not still.has(it) and is_instance_valid(_ground_nodes[it]):
			_ground_nodes[it].queue_free()
	_ground_nodes.clear()
	_ground = null


# ------------------------------------------------------------------ layout

func _equipment() -> Equipment:
	return player.character.equipment


func _layout() -> void:
	_targets.clear()
	_grid_rects.clear()
	_labels.clear()
	_label("EQUIPMENT", Vector2(COL_EQUIP, TOP - 34), 26, ACCENT)
	_layout_slots(_equipment(), Vector2(COL_EQUIP, TOP), SLOT_SIZE, 2, 14)
	var wy := TOP + 6 * (SLOT_SIZE.y + 22) + 6
	_label("WEAPONS", Vector2(COL_EQUIP, wy), 18, ACCENT)
	_layout_weapon_slots(_equipment(), Vector2(COL_EQUIP, wy + 22), Vector2(SLOT_SIZE.x * 2 + 12, 52), Vector2(SLOT_SIZE.x, 52), 13)
	_label("YOUR STORAGE", Vector2(COL_STORAGE, TOP - 34), 26, ACCENT)
	var y := _layout_storage(_equipment(), COL_STORAGE, COL_LOOT - 40, TOP)
	if y < 0:
		_label("No pockets. Wear pants, a jacket, a rig or a backpack to carry things.", Vector2(COL_STORAGE, TOP), 18, Color(0.7, 0.6, 0.5))
	if _mod_gun:
		_layout_mod_panel()
	elif container:
		_label(container.title.to_upper(), Vector2(COL_LOOT, TOP - 34), 26, ACCENT)
		_add_grid(container.grid, Vector2(COL_LOOT, TOP), "")
	elif _body():
		_label("BODY", Vector2(COL_LOOT, TOP - 34), 26, Color(0.9, 0.5, 0.4))
		var small := Vector2(104, 66)
		_layout_slots(_body().model.equipment, Vector2(COL_LOOT, TOP), small, 4, 12)
		var bw := TOP + 3 * (small.y + 22)
		_layout_weapon_slots(_body().model.equipment, Vector2(COL_LOOT, bw + 4), Vector2(small.x * 2 + 12, 46), Vector2(small.x, 46), 12)
		var by := bw + 46 + 30 + 46 + 22
		if _layout_storage(_body().model.equipment, COL_LOOT, size.x - 20, by) < 0:
			_label("Nothing to carry things in.", Vector2(COL_LOOT, by + 10), 18, Color(0.55, 0.57, 0.52))
	elif _ground:
		_label("GROUND", Vector2(COL_LOOT, TOP - 34), 26, Color(0.7, 0.72, 0.6))
		_label("Put things here to drop them. Items lying nearby show up here.", Vector2(COL_LOOT, TOP - 8), 14, Color(0.55, 0.57, 0.52))
		_add_grid(_ground, Vector2(COL_LOOT, TOP + 8), "")
	_cursor = clampi(_cursor, 0, _targets.size() - 1)


func _layout_slots(eq: Equipment, origin: Vector2, slot_size: Vector2, cols: int, label_size: int) -> void:
	for i in Equipment.SLOTS.size():
		var slot: String = Equipment.SLOTS[i]
		var pos := origin + Vector2((i % cols) * (slot_size.x + 12), (i / cols) * (slot_size.y + 22))
		_label(Equipment.SLOT_NAMES[slot].to_upper(), pos + Vector2(0, -4), label_size, Color(0.7, 0.72, 0.66))
		_targets.append({kind = "slot", slot = slot, eq = eq, rect = Rect2(pos + Vector2(0, 4), slot_size)})


## Primary (wide) on one row, holster + sheath on the next.
func _layout_weapon_slots(eq: Equipment, origin: Vector2, wide: Vector2, small: Vector2, label_size: int) -> void:
	var rows := [[["primary", wide]], [["sidearm", small], ["melee", small]]]
	var y := origin.y
	for row: Array in rows:
		var x := origin.x
		for cell: Array in row:
			var r := Rect2(Vector2(x, y + 14), cell[1])
			_label(Equipment.WEAPON_SLOT_NAMES[cell[0]].to_upper(), Vector2(x, y + 10), label_size, Color(0.7, 0.72, 0.66))
			_targets.append({kind = "wslot", slot = cell[0], eq = eq, rect = r})
			x += (cell[1] as Vector2).x + 12
		y += (row[0][1] as Vector2).y + 22


## The gun's attachment tree, one row per slot (children indented), plus its stats.
func _layout_mod_panel() -> void:
	var g := _mod_gun
	_label("%s - MODIFY" % g.def.display_name.to_upper(), Vector2(COL_LOOT, TOP - 34), 26, ACCENT)
	_label("Drop parts in the slots. Y closes.", Vector2(COL_LOOT, TOP - 8), 14, Color(0.55, 0.57, 0.52))
	var y := TOP + 14
	y = _layout_mod_slots(g, g, 0, y)
	var st := WeaponDB.stats(g)
	var loads := AmmoDB.all_for(st.caliber)
	var vel_text := ""
	if not loads.is_empty():
		var l0: AmmoType = loads[0]
		vel_text = "%s %d fps" % [l0.short_name, roundi(l0.muzzle_fps * l0.velocity_factor(st.barrel_in))]
	var lines := [
		"Weight %s    Ergonomics %d    Recoil %d%%" % [Units.pounds(st.weight + (g.wpn_mag.weight() if g.wpn_mag else 0.0)), roundi(st.ergo), roundi(st.recoil * 100.0)],
		"Barrel %.1f in (%s)    Loudness %d%%%s" % [st.barrel_in, vel_text, roundi(st.loudness * 100.0), "    Light" if not st.light.is_empty() else ""],
	]
	if not st.working:
		lines.append("WON'T FIRE: missing " + ", ".join(st.missing))
	for i in lines.size():
		_label(lines[i], Vector2(COL_LOOT, y + 26 + i * 26), 18, Color(1, 0.45, 0.35) if i == 2 else Color(0.85, 0.87, 0.8))


func _layout_mod_slots(gun: InvItem, owner: InvItem, depth: int, y: float) -> float:
	var sl := WeaponDB.slots_of(owner)
	for sn: String in sl:
		var x := COL_LOOT + depth * 36
		var req: bool = sl[sn].get("required", false)
		_label(sn.to_upper() + (" *" if req else ""), Vector2(x, y + 12), 13, Color(0.7, 0.72, 0.66))
		_targets.append({kind = "mod", gun = gun, owner = owner, slot = sn, rect = Rect2(Vector2(x, y + 16), Vector2(300, 50))})
		y += 76
		if owner.mods.has(sn):
			y = _layout_mod_slots(gun, owner.mods[sn], depth + 1, y)
	return y


## Rig / pockets / backpack grids of `eq`, flowing between x0 and x1. Returns the next y, or -1 if none.
func _layout_storage(eq: Equipment, x0: float, x1: float, y0: float) -> float:
	var y := y0
	var sections := [["RIG", ["vest"]], ["POCKETS", ["legs", "torso_outer", "torso_inner", "belt"]], ["BACKPACK", ["back"]]]
	var any := false
	for sec: Array in sections:
		var grids: Array = []
		for slot: String in sec[1]:
			var g: GearInstance = eq.get_slot(slot)
			if g:
				grids.append_array(g.grids)
		if grids.is_empty():
			continue
		any = true
		_label(sec[0], Vector2(x0, y), 18, Color(0.8, 0.82, 0.75))
		y += 24
		var x := x0
		var row_h := 0.0
		for grid: InvGrid in grids:
			var w := grid.size.x * CELL
			var h := grid.size.y * CELL
			if x + w > x1 and x > x0:
				x = x0
				y += row_h + 22
				row_h = 0.0
			_add_grid(grid, Vector2(x, y + 16), grid.label)
			x += w + 12
			row_h = maxf(row_h, h + 16)
		y += row_h + 26
	return y if any else -1.0


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
	return grid in _equipment().grids()


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
		var g: GearInstance = (t.eq as Equipment).get_slot(t.slot)
		if g:
			var it := InvItem.from_gear(g)
			_draw_item_in(it, t.rect, true)
		elif GearDB.for_slot(t.slot).is_empty():
			draw_string(_font, t.rect.position + Vector2(8, t.rect.size.y - 10), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.4, 0.38))
	for t in _targets:
		if t.kind != "wslot" and t.kind != "mod":
			continue
		draw_rect(t.rect, CELL_BG)
		draw_rect(t.rect, CELL_LINE if t.kind == "wslot" or t.owner.mods.has(t.slot) else Color(0.45, 0.4, 0.25), false, 2.0)
		var it := _item_at_target(t)
		if it:
			_draw_item_in(it, t.rect, true)
		elif t.kind == "mod":
			draw_string(_font, t.rect.position + Vector2(8, t.rect.size.y - 18), "empty", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.45, 0.42))
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
			ok = _fits_slot(t, _held) or (t.kind == "wslot" and _item_at_target(t) != null and not _slot_for(_item_at_target(t), _held).is_empty())
		draw_rect(r, Color(0.2, 0.8, 0.3, 0.25) if ok else Color(0.9, 0.2, 0.2, 0.25))
		_draw_item_in(_held, r, t.kind != "cell", 0.8)
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
	elif t.kind == "wslot":
		info = Equipment.WEAPON_SLOT_NAMES[t.slot] + ": empty"
	elif t.kind == "mod":
		info = "%s slot: empty\nTakes: %s" % [t.slot.capitalize(), ", ".join(WeaponDB.slots_of(t.owner)[t.slot].accepts)]
	var ib := Rect2(COL_STORAGE, 890, COL_LOOT - COL_STORAGE - 40, 150)
	draw_rect(ib, Color(0.04, 0.05, 0.04, 0.9))
	var lines := info.split("\n")
	for i in mini(lines.size(), 6):
		draw_string(_font, ib.position + Vector2(10, 24 + i * 22), lines[i], HORIZONTAL_ALIGNMENT_LEFT, ib.size.x - 20, 17 if i else 20,
			ACCENT if i == 0 else Color(0.85, 0.87, 0.8))
	var hints := "A pick up/put down    Y rotate / unload mag / open a gun    X quick move    B close    Rounds on a mag = load it    Mags & parts on a gun = fit them"
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
			var t: Dictionary = _targets[_cursor]
			var it := _item_at_target(t)
			if t.kind == "mod" or (it and it == _mod_gun):
				_mod_gun = null
				_relayout()
			elif it and it.def.is_firearm():
				_mod_gun = it
				_relayout()
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
	if t.kind == "wslot":
		return (t.eq as Equipment).get_weapon(t.slot)
	if t.kind == "mod":
		return (t.owner as InvItem).mods.get(t.slot)
	var g: GearInstance = (t.eq as Equipment).get_slot(t.slot)
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
	elif t.kind == "wslot":
		var eq: Equipment = t.eq
		var w := eq.get_weapon(t.slot)
		if w == null:
			return
		_held = w
		_held_from = {wslot = t.slot, eq = eq}
		eq.disarm(t.slot)
		if _mod_gun == w:
			_mod_gun = null
		_relayout()
	elif t.kind == "mod":
		var owner: InvItem = t.owner
		var part: InvItem = owner.mods.get(t.slot)
		if part == null:
			return
		if WeaponDB.slots_of(owner)[t.slot].get("required", false):
			_flash("The gun needs its %s: drop a replacement on it to swap." % t.slot)
			return
		owner.mods.erase(t.slot)
		_held = part
		_held_from = {mod_owner = owner, mod_slot = t.slot}
		_gun_changed(t.gun)
		_relayout()
	else:
		var eq: Equipment = t.eq
		var g: GearInstance = eq.get_slot(t.slot)
		if g == null:
			return
		_held = InvItem.from_gear(g)
		_held_from = {slot = t.slot, eq = eq}
		eq.unequip(t.slot)
		_relayout()
	_changed()


## Can `it` go in slot-type target `t`?
func _fits_slot(t: Dictionary, it: InvItem) -> bool:
	match t.kind:
		"slot":
			return it.def.is_gear() and GearDB.get_item(it.def.gear_id).slot == t.slot
		"wslot":
			return it.def.is_weapon() and it.def.weapon_slot == t.slot
		"mod":
			return WeaponDB.accepts(t.owner, t.slot, it) and it != t.gun
	return false


## Put `part` into `owner`'s slot inside `gun`; returns {ok, old}. If the gun lies in a grid and
## gets longer, it has to still fit there.
func _install(gun: InvItem, owner: InvItem, slot: String, part: InvItem) -> Dictionary:
	var old: InvItem = owner.mods.get(slot)
	owner.mods[slot] = part
	var grid := _grid_holding(gun)
	if grid and not grid.fits(gun, grid.pos_of(gun), gun):
		if old:
			owner.mods[slot] = old
		else:
			owner.mods.erase(slot)
		return {ok = false}
	_gun_changed(gun)
	return {ok = true, old = old}


func _grid_holding(it: InvItem) -> InvGrid:
	for g in _grid_rects:
		if (g.grid as InvGrid).pos_of(it) != Vector2i(-1, -1):
			return g.grid
	return null


## First slot anywhere in the gun's tree that takes `part` (empty ones first; a magazine swaps).
func _slot_for(gun: InvItem, part: InvItem) -> Dictionary:
	var owners: Array = [gun]
	for e: Dictionary in WeaponDB.walk(gun):
		owners.append(e.item)
	var taken := {}
	for owner: InvItem in owners:
		for sn: String in WeaponDB.slots_of(owner):
			if WeaponDB.accepts(owner, sn, part):
				if not owner.mods.has(sn):
					return {owner = owner, slot = sn}
				if taken.is_empty():
					taken = {owner = owner, slot = sn}
	return taken


## A gun's parts changed: rebuild the model if it's one of the guns you carry.
func _gun_changed(gun: InvItem) -> void:
	for fa in player.firearms:
		if fa.gun == gun:
			fa.refresh()


func _can_drop_at(t: Dictionary) -> bool:
	var grid: InvGrid = t.grid
	var other := grid.item_at(t.cell)
	if other and _merge_kind(other) != "":
		return true
	return grid.fits(_held, t.cell)


func _merge_kind(other: InvItem) -> String:
	if other.def == _held.def and _held.def.max_stack > 1 and other.count < other.def.max_stack:
		return "stack"
	if other.def.is_weapon() and (_held.def.is_mag() or _held.def.is_part()) and not _slot_for(other, _held).is_empty():
		return "fit"
	if _held.def.is_ammo() and other.def.is_mag() and other.def.caliber == _held.def.caliber \
			and other.mag_count < other.def.mag_capacity and (other.mag_count == 0 or other.mag_ammo.id == _held.def.ammo_id):
		return "load"
	return ""


func _drop() -> void:
	var t: Dictionary = _targets[_cursor]
	if t.kind == "wslot" and (_held.def.is_mag() or _held.def.is_part()):
		# A magazine or part dropped on the gun in your holster: fit it.
		var w := (t.eq as Equipment).get_weapon(t.slot)
		var where := _slot_for(w, _held) if w else {}
		if where.is_empty():
			_flash("That doesn't fit this weapon.")
			return
		var pname := _held.def.display_name
		var r := _install(w, where.owner, where.slot, _held)
		_flash(("Swapped in the %s." if r.old else "Fitted the %s.") % pname)
		_held = r.old
		_held_from = {}
		_relayout()
		_changed()
		return
	if t.kind == "wslot" or t.kind == "mod":
		if not _fits_slot(t, _held):
			_flash("That doesn't go there.")
			return
		if t.kind == "wslot":
			var eq: Equipment = t.eq
			var old := eq.arm(_held)
			_held = old
			_held_from = {wslot = t.slot, eq = eq} if old else {}
		else:
			var r := _install(t.gun, t.owner, t.slot, _held)
			if not r.ok:
				_flash("No room for the longer gun where it's lying.")
				return
			_held = r.old
			_held_from = {}
		_relayout()
		_changed()
		return
	if t.kind == "slot":
		if not _held.def.is_gear() or GearDB.get_item(_held.def.gear_id).slot != t.slot:
			_flash("That doesn't go there.")
			return
		var eq: Equipment = t.eq
		var old: GearInstance = eq.get_slot(t.slot)
		eq.equip(_held.gear)
		_held = InvItem.from_gear(old) if old else null
		_held_from = {slot = t.slot, eq = eq} if old else {}
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
			"fit":
				var where := _slot_for(other, _held)
				var pname := _held.def.display_name
				var r := _install(other, where.owner, where.slot, _held)
				if not r.ok:
					_flash("No room for the longer gun where it's lying.")
					return
				_flash(("Swapped in the %s." if r.old else "Fitted the %s.") % pname)
				_held = r.old
				_held_from = {}
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
	if _held_from.has("wslot") and (_held_from.eq as Equipment).get_weapon(_held_from.wslot) == null:
		(_held_from.eq as Equipment).arm(_held)
		_held = null
		_relayout()
		return true
	if _held_from.has("mod_owner") and not (_held_from.mod_owner as InvItem).mods.has(_held_from.mod_slot):
		(_held_from.mod_owner as InvItem).mods[_held_from.mod_slot] = _held
		_held = null
		for fa in player.firearms:
			fa.refresh()
		_relayout()
		return true
	if _held_from.has("slot") and (_held_from.eq as Equipment).get_slot(_held_from.slot) == null and _held.gear:
		(_held_from.eq as Equipment).equip(_held.gear)
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
	if _store(_held, true) or _store_in(_other_grids(), _held):
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
	if t.kind == "mod":
		return
	if t.kind == "wslot":
		var eq: Equipment = t.eq
		var w := eq.get_weapon(t.slot)
		if w == null:
			return
		eq.disarm(t.slot)
		var ok := false
		if eq == _equipment():
			ok = _store_in(_other_grids(), w) or _store(w)
		elif _equipment().get_weapon(t.slot) == null:
			_equipment().arm(w)       # off the body and straight into your holster
			ok = true
		else:
			ok = _store(w)
		if ok:
			_flash("Moved %s." % w.def.display_name)
		else:
			eq.arm(w)
			_flash("No room for it.")
		_relayout()
		_changed()
		return
	if t.kind == "slot":
		var eq: Equipment = t.eq
		var g: GearInstance = eq.get_slot(t.slot)
		if g == null:
			return
		var it := InvItem.from_gear(g)
		eq.unequip(t.slot)
		var ok := false
		if eq == _equipment():
			ok = _store_in(_other_grids(), it) or _store(it)
		elif _equipment().get_slot(t.slot) == null:
			_equipment().equip(g)  # take it off the body and put it straight on
			ok = true
		else:
			ok = _store(it)
		if ok:
			_flash("Moved %s." % g.item.display_name)
		else:
			eq.equip(g)
			_flash("No room for it.")
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
		elif it.def.is_weapon() and _equipment().get_weapon(it.def.weapon_slot) == null:
			_equipment().arm(it)
			_relayout()
			ok = true
		else:
			ok = _store(it)
	else:
		ok = _store_in(_other_grids(), it)
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
	grids.append_array(_other_grids())
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
