extends SceneTree
## Menus with a gamepad: D-pad / stick move the highlight (wrapping), A presses
## (on release, like a click),
## B goes back, a tap that clears the highlight is recovered by the next press,
## and the pause menu has Resume / Restart / Main menu you can pick.
## Run: godot --headless --fixed-fps 60 -s tools/tests/pad_menu_test.gd

var f := 0
var fails := 0
var menu
var steps: Array = []
var si := 0
var wait := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _btn(b: int, down := true) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b as JoyButton
	e.pressed = down
	e.pressure = 1.0 if down else 0.0
	Input.parse_input_event(e)


func _stick(v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = v
	Input.parse_input_event(e)


func _focus() -> Control:
	return root.get_viewport().gui_get_focus_owner()


func _ftext() -> String:
	var c := _focus()
	return c.text if c is BaseButton else ("<none>" if c == null else c.get_class())


func _settings_open() -> bool:
	for n in root.find_children("*", "", true, false):
		if n.get_script() and n.get_script().resource_path.ends_with("settings_panel.gd") and n.is_visible_in_tree():
			return true
	return false


func _initialize() -> void:
	menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	# [action, then a check run a few frames later]
	steps = [
		[func(): pass, func(): check(_ftext() == "Play (range)", "the first button is highlighted (%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_DPAD_DOWN), func(): check(_ftext() == "Play (random mission)", "D-pad down moves the highlight (%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_DPAD_DOWN, false); _stick(1.0), func(): check(_ftext() == "Play (suburban house)", "so does the left stick (%s)" % _ftext())],
		[func(): _stick(0.0); _btn(JOY_BUTTON_DPAD_UP), func(): pass],
		[func(): _btn(JOY_BUTTON_DPAD_UP, false); _btn(JOY_BUTTON_DPAD_UP), func(): pass],
		[func(): _btn(JOY_BUTTON_DPAD_UP, false); _btn(JOY_BUTTON_DPAD_UP), func(): check(_ftext() == "Quit", "up from the top wraps to the bottom (%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_DPAD_UP, false); _btn(JOY_BUTTON_DPAD_UP), func(): check(_ftext() == "Settings", "(%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_DPAD_UP, false); _btn(JOY_BUTTON_A); _btn(JOY_BUTTON_A, false), func(): check(menu._pages.settings.visible, "A presses the highlighted button (Settings opens)")],
		[func(): _btn(JOY_BUTTON_B), func(): check(menu._pages.main.visible, "B goes back")],
		[func(): _btn(JOY_BUTTON_B, false); var c := _focus(); if c: c.release_focus(), func(): check(_focus() == null, "a tap clears the highlight")],
		[func(): _btn(JOY_BUTTON_DPAD_DOWN), func(): check(_ftext() == "Play (range)", "and the next press brings it back on the first button (%s)" % _ftext())],
		[func():
			_btn(JOY_BUTTON_DPAD_DOWN, false)
			menu.queue_free()
			root.get_tree().change_scene_to_file("res://scenes/shooting_range.tscn"), func(): pass],
		[func(): _btn(JOY_BUTTON_START), func():
			check(paused, "START pauses")
			check(_ftext() == "Resume", "and highlights Resume (%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_START, false); _btn(JOY_BUTTON_DPAD_RIGHT), func(): check(_ftext() == "Settings", "D-pad right: Settings (%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_DPAD_RIGHT, false); _btn(JOY_BUTTON_A); _btn(JOY_BUTTON_A, false), func():
			check(root.get_tree().current_scene.find_children("*", "SettingsPanel", true, false).size() >= 0 and _settings_open(), "A on Settings opens the settings page")
			check(_focus() != null and _focus().name == "Field of view", "with its first control highlighted (%s)" % (_focus().name if _focus() else "<none>"))],
		[func(): _btn(JOY_BUTTON_B); _btn(JOY_BUTTON_B, false), func():
			check(not _settings_open() and paused, "B closes it, still paused")
			check(_ftext() == "Settings", "back on the Settings button (%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_DPAD_RIGHT), func(): check(_ftext() == "Restart", "then Restart (%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_DPAD_RIGHT, false); _btn(JOY_BUTTON_DPAD_RIGHT), func(): pass],
		[func(): _btn(JOY_BUTTON_DPAD_RIGHT, false); _btn(JOY_BUTTON_DPAD_RIGHT), func(): check(_ftext() == "Resume", "wraps round to Resume (%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_DPAD_RIGHT, false); _btn(JOY_BUTTON_A); _btn(JOY_BUTTON_A, false), func():
			check(not paused, "A on Resume unpauses")
			check(_focus() == null, "and nothing stays highlighted (A in the game won't press a hidden button)")],
		[func(): _btn(JOY_BUTTON_START), func(): pass],
		[func(): _btn(JOY_BUTTON_START, false); _btn(JOY_BUTTON_B), func(): check(not paused, "B also resumes")],
		[func(): _btn(JOY_BUTTON_B, false); _btn(JOY_BUTTON_START), func(): pass],
		[func(): _btn(JOY_BUTTON_START, false); _btn(JOY_BUTTON_DPAD_LEFT), func(): check(_ftext() == "Main menu", "D-pad left from Resume: Main menu (%s)" % _ftext())],
		[func(): _btn(JOY_BUTTON_DPAD_LEFT, false); _btn(JOY_BUTTON_A), func(): pass],
		[func(): _btn(JOY_BUTTON_A, false), func(): check(current_scene != null and current_scene.scene_file_path.ends_with("main_menu.tscn") and not paused, "A on Main menu goes to the main menu")],
	]


func _process(_d: float) -> bool:
	f += 1
	if f < 5:
		return false
	wait += 1
	if si < steps.size():
		if wait == 1:
			steps[si][0].call()
		elif wait == 8:
			steps[si][1].call()
			si += 1
			wait = 0
	else:
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
