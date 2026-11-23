extends Node3D
## Main menu: a slowly turning 1911 behind Play / Settings / Quit.
## Settings holds the options and the Credits page. Works with the Thor's
## controls (D-pad + A/B) and the touchscreen.

const GYM := "res://scenes/gym.tscn"
const CREDITS := [
	["LOOT SHOOT", ""],
	["Game design", "Beefnasty96"],
	["Human base model", "Beefnasty96"],
	["Code, weapons, gear, textures, sounds", "Built with Claude (Anthropic)"],
	["Engine", "Godot Engine 4.7 (MIT license)"],
	["Ballistics references", "Published factory data and 10% gel tests"],
]

var _gun: Node3D
var _pages := {}
var _ui: CanvasLayer


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_backdrop()
	_ui = CanvasLayer.new()
	add_child(_ui)
	_pages.main = _page_main()
	_pages.settings = _page_settings()
	_pages.credits = _page_credits()
	_show("main")


func _process(delta: float) -> void:
	if _gun:
		_gun.rotate_y(delta * 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _pages.credits.visible:
			_show("settings")
		elif _pages.settings.visible:
			Settings.save_settings()
			_show("main")


# ------------------------------------------------------------------ backdrop

func _build_backdrop() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.4)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 40, 0)
	light.light_energy = 1.4
	add_child(light)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-0.4, 0.2, -0.5)
	rim.light_color = Color(1.0, 0.8, 0.5)
	rim.light_energy = 1.5
	add_child(rim)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, -0.02, 0.6)
	cam.fov = 40
	add_child(cam)
	_gun = Node3D.new()
	_gun.position = Vector3(0.1, 0.0, 0)
	add_child(_gun)
	var model: Node3D = load("res://assets/weapons/m1911/m1911.glb").instantiate()
	model.position = Vector3(0, 0, 0.03)
	_gun.add_child(model)


# ------------------------------------------------------------------ pages

func _panel() -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.04, 0.8)
	style.set_content_margin_all(28)
	style.border_color = Color(0.5, 0.55, 0.4)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(80, 120)
	_ui.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return box


func _title(box: VBoxContainer, text: String, size := 56) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	box.add_child(l)


func _button(box: VBoxContainer, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 64)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(action)
	box.add_child(b)
	return b


func _page_main() -> Control:
	var box := _panel()
	_title(box, "LOOT SHOOT")
	var sub := Label.new()
	sub.text = "Tactical roguelike - test build"
	sub.add_theme_font_size_override("font_size", 22)
	box.add_child(sub)
	_button(box, "Play (test gym)", func(): get_tree().change_scene_to_file(GYM))
	_button(box, "Settings", func(): _show("settings"))
	_button(box, "Quit", func(): get_tree().quit())
	return box.get_parent()


func _page_settings() -> Control:
	var box := _panel()
	_title(box, "SETTINGS", 44)
	_slider(box, "Look sensitivity", 0.3, 2.5, 0.05, Settings.look_sensitivity, func(v): Settings.look_sensitivity = v, "%.2fx")
	_slider(box, "Field of view", 60.0, 95.0, 1.0, Settings.fov, func(v): Settings.fov = v, "%d deg")
	_check(box, "Invert look up/down", Settings.invert_look_y, func(on): Settings.invert_look_y = on)
	_check(box, "Bullet paths in test gym", Settings.show_bullet_paths, func(on): Settings.show_bullet_paths = on)
	_button(box, "Credits", func(): _show("credits"))
	_button(box, "Back", func():
		Settings.save_settings()
		_show("main"))
	return box.get_parent()


func _page_credits() -> Control:
	var box := _panel()
	_title(box, "CREDITS", 44)
	for row: Array in CREDITS:
		if row[1] == "":
			continue
		var head := Label.new()
		head.text = row[0]
		head.add_theme_font_size_override("font_size", 20)
		head.add_theme_color_override("font_color", Color(0.65, 0.68, 0.6))
		box.add_child(head)
		var who := Label.new()
		who.text = row[1]
		who.add_theme_font_size_override("font_size", 28)
		box.add_child(who)
	_button(box, "Back", func(): _show("settings"))
	return box.get_parent()


func _slider(box: VBoxContainer, label: String, lo: float, hi: float, step: float, value: float, on_change: Callable, fmt: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", 24)
	row.add_child(l)
	var s := HSlider.new()
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
	box.add_child(row)


func _check(box: VBoxContainer, label: String, value: bool, on_change: Callable) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 24)
	c.toggled.connect(on_change)
	box.add_child(c)


func _show(page: String) -> void:
	for k: String in _pages:
		_pages[k].visible = k == page
	# Focus the first button so the D-pad works straight away.
	var first: Control = _first_focusable(_pages[page])
	if first:
		first.grab_focus.call_deferred()


func _first_focusable(node: Node) -> Control:
	for c in node.get_children():
		if c is Button or c is HSlider:
			return c
		var f := _first_focusable(c)
		if f:
			return f
	return null
