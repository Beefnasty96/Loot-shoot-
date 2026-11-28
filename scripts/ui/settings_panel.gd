class_name SettingsPanel
extends PanelContainer
## The settings page, shared by the main menu and the pause menu. Changes apply
## straight away and are saved when you leave the page (Back, or B).
##   Field of view, look sensitivity, aim sensitivity (while aiming down sights),
##   invert look, crouch toggle/hold, lean hold/toggle, bullet paths on the range.
## Works with a pad (D-pad / stick, A, B), the touchscreen and a mouse.

signal closed

var _box: VBoxContainer


## extra: [[button text, Callable], ...] added above Back (the main menu adds Credits).
func _init(extra: Array = []) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.04, 0.88)
	style.set_content_margin_all(28)
	style.border_color = Color(0.5, 0.55, 0.4)
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	add_child(_box)
	var t := Label.new()
	t.text = "SETTINGS"
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	_box.add_child(t)
	_slider("Field of view", 60.0, 95.0, 1.0, Settings.fov, func(v): Settings.fov = v, "%d deg")
	_slider("Look sensitivity", 0.3, 2.5, 0.05, Settings.look_sensitivity, func(v): Settings.look_sensitivity = v, "%.2fx")
	_slider("Aim sensitivity", 0.1, 1.5, 0.05, Settings.aim_sensitivity, func(v): Settings.aim_sensitivity = v, "%.2fx")
	_check("Invert look up/down", Settings.invert_look_y, func(on): Settings.invert_look_y = on)
	_choice("Crouch", ["Toggle", "Hold"], 0 if Settings.toggle_crouch else 1, func(i): Settings.toggle_crouch = i == 0)
	_choice("Lean", ["Hold", "Toggle"], 1 if Settings.toggle_lean else 0, func(i): Settings.toggle_lean = i == 1)
	_check("Bullet paths on the range", Settings.show_bullet_paths, func(on): Settings.show_bullet_paths = on)
	for e: Array in extra:
		_button(e[0], e[1])
	_button("Back", close)
	PadFocus.wrap(PadFocus.focusables(self))


func close() -> void:
	Settings.save_settings()
	closed.emit()


func focus_first() -> void:
	var f: Array = PadFocus.focusables(self)
	if not f.is_empty():
		(f[0] as Control).grab_focus.call_deferred()


func first_control() -> Control:
	var f: Array = PadFocus.focusables(self)
	return f[0] if not f.is_empty() else null


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 60)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(action)
	_box.add_child(b)
	return b


func _slider(label: String, lo: float, hi: float, step: float, value: float, on_change: Callable, fmt: String) -> HSlider:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", 24)
	row.add_child(l)
	var s := HSlider.new()
	s.name = label
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260, 48)
	row.add_child(s)
	var v := Label.new()
	v.text = fmt % value
	v.custom_minimum_size = Vector2(110, 0)
	v.add_theme_font_size_override("font_size", 24)
	row.add_child(v)
	s.value_changed.connect(func(x):
		on_change.call(x)
		v.text = fmt % x)
	_box.add_child(row)
	return s


func _check(label: String, value: bool, on_change: Callable) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 24)
	c.toggled.connect(on_change)
	_box.add_child(c)


## A button that cycles through options: "Crouch: Toggle" -> "Crouch: Hold".
func _choice(label: String, options: Array, index: int, on_change: Callable) -> void:
	var b := Button.new()
	b.name = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(360, 52)
	b.add_theme_font_size_override("font_size", 24)
	b.set_meta("i", index)
	b.text = "%s: %s" % [label, options[index]]
	b.pressed.connect(func():
		var i: int = (int(b.get_meta("i")) + 1) % options.size()
		b.set_meta("i", i)
		b.text = "%s: %s" % [label, options[i]]
		on_change.call(i))
	_box.add_child(b)
