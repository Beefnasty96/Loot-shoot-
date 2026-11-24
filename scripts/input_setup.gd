extends Node
## Registers every input action in code so the controls live in one readable place.
## Thor buttons map to Godot's standard gamepad layout (Xbox-style names).
## Keyboard + mouse bindings are included for testing on a PC.

const DEADZONE := 0.15

func _enter_tree() -> void:
	# Movement (left stick / WASD)
	_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0, [KEY_W])
	_axis("move_back", JOY_AXIS_LEFT_Y, 1.0, [KEY_S])
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0, [KEY_A])
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0, [KEY_D])

	# Looking (right stick; mouse handled in player.gd)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0, [])
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0, [])
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0, [])
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0, [])

	# Triggers
	_axis("aim", JOY_AXIS_TRIGGER_LEFT, 1.0, [], [MOUSE_BUTTON_RIGHT])
	_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0, [], [MOUSE_BUTTON_LEFT])

	# Buttons
	_button("toggle_view", JOY_BUTTON_RIGHT_STICK, [KEY_V])       # R3
	_button("sprint", JOY_BUTTON_LEFT_STICK, [KEY_SHIFT])         # L3 (also shoulder swap)
	_button("swap_shoulder", -1, [KEY_C])                         # keyboard only; L3 handles it on pad
	_button("lean_left", JOY_BUTTON_LEFT_SHOULDER, [KEY_Q])       # L1
	_button("lean_right", JOY_BUTTON_RIGHT_SHOULDER, [KEY_E])     # R1
	_button("interact", JOY_BUTTON_A, [KEY_F])
	_button("crouch", JOY_BUTTON_B, [KEY_CTRL])
	_button("reload", JOY_BUTTON_X, [KEY_R])
	_button("switch_weapon", JOY_BUTTON_Y, [KEY_1])
	_button("pause", JOY_BUTTON_START, [KEY_ESCAPE])
	_button("inventory", JOY_BUTTON_BACK, [KEY_TAB])
	_button("ammo_next", JOY_BUTTON_DPAD_RIGHT, [KEY_BRACKETRIGHT])  # load for the next magazine
	_button("ammo_prev", JOY_BUTTON_DPAD_LEFT, [KEY_BRACKETLEFT])
	_button("toggle_debug", -1, [KEY_F3])                            # bullet paths + hit readout (pad: hold D-pad down)
	_button("toggle_light", JOY_BUTTON_DPAD_DOWN, [KEY_T])           # weapon light
	_button("use_meds", JOY_BUTTON_DPAD_UP, [KEY_H])                 # treat yourself with what you carry


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)


func _axis(action: String, axis: JoyAxis, dir: float, keys: Array, mouse_buttons: Array = []) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis
	ev.axis_value = dir
	InputMap.action_add_event(action, ev)
	_add_keys(action, keys)
	_add_mouse(action, mouse_buttons)


func _button(action: String, button: int, keys: Array, mouse_buttons: Array = []) -> void:
	_ensure(action)
	if button >= 0:
		var ev := InputEventJoypadButton.new()
		ev.device = -1
		ev.button_index = button as JoyButton
		InputMap.action_add_event(action, ev)
	_add_keys(action, keys)
	_add_mouse(action, mouse_buttons)


func _add_keys(action: String, keys: Array) -> void:
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _add_mouse(action: String, buttons: Array) -> void:
	for b in buttons:
		var ev := InputEventMouseButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)
