class_name GearMenu
extends PanelContainer
## Equipment screen (Select). The camera turns round so you can see yourself.
##   D-pad up/down: slot     D-pad left/right: item (or none)
##   A: next colour          Y: new random face/skin/hair
##   Select or B: close
## On the range every catalogue item is available; real runs will only offer
## what's in your inventory.

var player: Player
var _slot := 0
var _rows: VBoxContainer
var _info: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.05, 0.85)
	style.set_content_margin_all(22)
	style.border_color = Color(0.5, 0.55, 0.4)
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "GEAR"
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)
	_rows = VBoxContainer.new()
	box.add_child(_rows)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 20)
	_info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.75))
	box.add_child(_info)
	var hint := Label.new()
	hint.text = "Up/Down slot   Left/Right item   A colour   Y new look   Select close"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
	box.add_child(hint)
	_rng.randomize()
	position = Vector2(30, 120)


func toggle() -> void:
	visible = not visible
	player.set_preview(visible)
	if visible:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	var eq := player.character.equipment
	var slot: String = Equipment.SLOTS[_slot]
	if event.is_action_pressed("ui_down"):
		_slot = (_slot + 1) % Equipment.SLOTS.size()
	elif event.is_action_pressed("ui_up"):
		_slot = (_slot - 1 + Equipment.SLOTS.size()) % Equipment.SLOTS.size()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		var options: Array = [null]
		options.append_array(GearDB.for_slot(slot))
		var cur := eq.get_slot(slot)
		var idx := 0
		for i in options.size():
			if options[i] != null and cur and options[i] == cur.item:
				idx = i
		idx = (idx + (1 if event.is_action_pressed("ui_right") else -1) + options.size()) % options.size()
		if options[idx] == null:
			eq.unequip(slot)
		else:
			eq.equip(GearInstance.create(options[idx].id, _rng.randi() % maxi(1, options[idx].colors.size())))
	elif event.is_action_pressed("interact"):
		var cur := eq.get_slot(slot)
		if cur:
			cur.color_index = (cur.color_index + 1) % maxi(1, cur.item.colors.size())
			player.character.refresh_slot(slot)
	elif event.is_action_pressed("switch_weapon"):
		player.character.appearance.randomize(_rng)
		player.character.apply_appearance()
	elif event.is_action_pressed("crouch") or event.is_action_pressed("pause"):
		toggle()
	else:
		return
	get_viewport().set_input_as_handled()
	_refresh()


func _refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var eq := player.character.equipment
	for i in Equipment.SLOTS.size():
		var slot: String = Equipment.SLOTS[i]
		var g := eq.get_slot(slot)
		var l := Label.new()
		var what := "-"
		if g:
			what = "%s (%s)" % [g.item.display_name, g.color_name()]
		var has_items := not GearDB.for_slot(slot).is_empty()
		l.text = "%s %-11s %s" % [">" if i == _slot else " ", Equipment.SLOT_NAMES[slot], what]
		l.add_theme_font_size_override("font_size", 24)
		var col := Color(1, 0.9, 0.5) if i == _slot else (Color(0.9, 0.9, 0.88) if has_items else Color(0.5, 0.5, 0.5))
		l.add_theme_color_override("font_color", col)
		_rows.add_child(l)
	var sel := eq.get_slot(Equipment.SLOTS[_slot])
	var desc := sel.item.description if sel else ("Nothing to wear here yet." if GearDB.for_slot(Equipment.SLOTS[_slot]).is_empty() else "Empty.")
	_info.text = "\n%s\nWorn: %s   Storage: %d L" % [desc, Units.pounds(eq.total_weight()), roundi(eq.total_capacity())]
