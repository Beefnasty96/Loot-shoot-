class_name TouchControls
extends CanvasLayer
## On-screen Xbox-layout controller for phones (e.g. a Galaxy S25 Ultra).
## Shown only on touchscreens with no real gamepad connected; it hides as soon as
## a gamepad connects (or one that was already there gets used) and comes back
## when it disconnects. On the AYN Thor the built-in controls are a gamepad, so it
## never shows there.
##
## Every button sends the same input actions a gamepad does (InputEventAction
## through Input.parse_input_event), so the game can't tell the difference:
##   left half      - floating move stick (L3 button beside it = sprint)
##   right half     - drag to look (also while holding RT, so you can fire and steer)
##   RT fire, LT aim (tap = toggle, hold = while held), LB / RB lean
##   A B X Y        - interact, crouch, reload, weapon (hold = whatever holding Y does)
##   D-pad          - ammo / meds / light (and moves the inventory cursor)
##   View / Menu    - inventory / pause; R3 = first / third person

const STICK_RADIUS := 120.0
const LOOK_GAIN := 0.16          ## Degrees per pixel of drag (times look sensitivity).
const AIM_TAP := 0.25            ## LT released sooner than this = toggle.
## Phantom "gamepads" some phones report (fingerprint readers, key panels).
const FAKE_PADS := ["uinput", "fpc", "goodix", "fingerprint", "gpio", "touchkey", "sec_", "qwerty", "virtual"]

var forced := false              ## Tests: show even without a touchscreen.
var buttons: Array[Dictionary] = []
var _canvas: Control
var _touches := {}               ## index -> {kind, button?, start, pos}
var _stick_center := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _stick_touch := -1
var _aim_on := false
var _aim_down_at := 0.0
var _pad_used := false
var _font: Font


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	_font = ThemeDB.fallback_font
	Input.joy_connection_changed.connect(func(_d, _c): _update_visibility(true))
	get_viewport().size_changed.connect(_layout)
	_layout()
	_update_visibility()


## True if a real gamepad is connected (or a connected one has been used).
func has_gamepad() -> bool:
	if _pad_used:
		return true
	for d in Input.get_connected_joypads():
		var n := Input.get_joy_name(d).to_lower()
		var fake := false
		for f: String in FAKE_PADS:
			if n.contains(f):
				fake = true
		if not fake:
			return true
	return false


func _update_visibility(connection_changed := false) -> void:
	if connection_changed and Input.get_connected_joypads().is_empty():
		_pad_used = false   # the last gamepad went away: back to touch
	var show := (forced or DisplayServer.is_touchscreen_available()) and not has_gamepad()
	if visible and not show:
		_release_all()
	visible = show


func _layout() -> void:
	var s := _canvas.get_viewport_rect().size if _canvas.is_inside_tree() else Vector2(1920, 1080)
	var w := s.x
	var h := s.y
	buttons.clear()
	var face := Vector2(w - 230, h - 270)
	_btn("A", ["interact", "ui_accept"], face + Vector2(0, 105), 58, Color(0.3, 0.75, 0.3))
	_btn("B", ["crouch", "ui_cancel"], face + Vector2(105, 0), 58, Color(0.85, 0.25, 0.25))
	_btn("X", ["reload"], face + Vector2(-105, 0), 58, Color(0.25, 0.45, 0.9))
	_btn("Y", ["switch_weapon"], face + Vector2(0, -105), 58, Color(0.9, 0.78, 0.2))
	_btn("RT", ["fire"], Vector2(w - 470, h - 470), 82, Color(0.75, 0.75, 0.75), "look")
	_btn("LT", ["aim"], Vector2(w - 640, h - 300), 62, Color(0.75, 0.75, 0.75), "toggle")
	_btn("RB", ["lean_right"], Vector2(w - 110, 200), 50, Color(0.6, 0.6, 0.6))
	_btn("LB", ["lean_left"], Vector2(110, 200), 50, Color(0.6, 0.6, 0.6))
	_btn("R3", ["toggle_view"], Vector2(w - 470, h - 100), 44, Color(0.55, 0.55, 0.55))
	_btn("L3", ["sprint"], Vector2(470, h - 100), 44, Color(0.55, 0.55, 0.55))
	var dp := Vector2(150, h - 560)
	_btn("^", ["use_meds", "ui_up"], dp + Vector2(0, -72), 40, Color(0.5, 0.5, 0.5))
	_btn("v", ["toggle_light", "ui_down"], dp + Vector2(0, 72), 40, Color(0.5, 0.5, 0.5))
	_btn("<", ["ammo_prev", "ui_left"], dp + Vector2(-72, 0), 40, Color(0.5, 0.5, 0.5))
	_btn(">", ["ammo_next", "ui_right"], dp + Vector2(72, 0), 40, Color(0.5, 0.5, 0.5))
	_btn("VIEW", ["inventory"], Vector2(w / 2.0 - 120, 60), 40, Color(0.5, 0.5, 0.5))
	_btn("MENU", ["pause"], Vector2(w / 2.0 + 120, 60), 40, Color(0.5, 0.5, 0.5))
	_stick_center = Vector2(270, h - 260)
	_canvas.queue_redraw()


func _btn(label: String, actions: Array, pos: Vector2, r: float, color: Color, mode := "") -> void:
	buttons.append({label = label, actions = actions, pos = pos, r = r, color = color, mode = mode, down = false})


func button(label: String) -> Dictionary:
	for b in buttons:
		if b.label == label:
			return b
	return {}


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	# A real gamepad being used: hide.
	if (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		if not _pad_used:
			_pad_used = true
			_update_visibility()
		return
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position, event.relative)


func _touch_down(index: int, pos: Vector2) -> void:
	for b in buttons:
		if pos.distance_to(b.pos) <= b.r * 1.15:
			_touches[index] = {kind = "button", button = b, pos = pos}
			b.down = true
			if b.mode == "toggle":
				_aim_down_at = Time.get_ticks_msec() / 1000.0
				if not _aim_on:
					_send(b.actions, true)
			else:
				_send(b.actions, true)
			_canvas.queue_redraw()
			get_viewport().set_input_as_handled()
			return
	var w := _canvas.get_viewport_rect().size.x
	if pos.x < w * 0.45 and _stick_touch < 0 and not get_tree().paused:
		_stick_touch = index
		_stick_center = pos
		_touches[index] = {kind = "stick", pos = pos}
		_set_stick(Vector2.ZERO)
	elif pos.x >= w * 0.45 and not get_tree().paused:
		_touches[index] = {kind = "look", pos = pos}
	_canvas.queue_redraw()


func _touch_drag(index: int, pos: Vector2, rel: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	t.pos = pos
	match t.kind:
		"stick":
			_set_stick((pos - _stick_center) / STICK_RADIUS)
		"look":
			_look(rel)
		"button":
			if t.button.mode == "look":   # fire and steer with one thumb
				_look(rel)
	_canvas.queue_redraw()


func _touch_up(index: int) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	_touches.erase(index)
	if t.kind == "stick":
		_stick_touch = -1
		_set_stick(Vector2.ZERO)
		_stick_center = Vector2(270, _canvas.get_viewport_rect().size.y - 260)
	elif t.kind == "button":
		var b: Dictionary = t.button
		b.down = false
		if b.mode == "toggle":
			var held := Time.get_ticks_msec() / 1000.0 - _aim_down_at
			if held < AIM_TAP:
				_aim_on = not _aim_on      # tap: aim stays on until the next tap
				if not _aim_on:
					_send(b.actions, false)
			else:
				_aim_on = false            # held: aim only while held
				_send(b.actions, false)
		else:
			_send(b.actions, false)
	_canvas.queue_redraw()


func _set_stick(v: Vector2) -> void:
	v = v.limit_length(1.0)
	_stick_vec = v
	_axis("move_left", maxf(0.0, -v.x))
	_axis("move_right", maxf(0.0, v.x))
	_axis("move_forward", maxf(0.0, -v.y))
	_axis("move_back", maxf(0.0, v.y))


var _axis_state := {}


func _axis(action: String, strength: float) -> void:
	var was: float = _axis_state.get(action, 0.0)
	if is_equal_approx(was, strength):
		return
	_axis_state[action] = strength
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = strength > 0.15
	ev.strength = strength if ev.pressed else 0.0
	Input.parse_input_event(ev)


func _look(rel: Vector2) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("touch_look"):
		p.touch_look(rel * LOOK_GAIN)


func _send(actions: Array, pressed: bool) -> void:
	for a: String in actions:
		if not InputMap.has_action(a):
			continue
		var ev := InputEventAction.new()
		ev.action = a
		ev.pressed = pressed
		ev.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(ev)


func _release_all() -> void:
	for b in buttons:
		if b.down or (b.mode == "toggle" and _aim_on):
			_send(b.actions, false)
		b.down = false
	_aim_on = false
	_touches.clear()
	_stick_touch = -1
	_set_stick(Vector2.ZERO)


# ------------------------------------------------------------------ drawing

func _draw_controls() -> void:
	# Move stick: base ring + thumb.
	var base_col := Color(1, 1, 1, 0.16 if _stick_touch < 0 else 0.28)
	_canvas.draw_circle(_stick_center, STICK_RADIUS, Color(0, 0, 0, 0.18))
	_canvas.draw_arc(_stick_center, STICK_RADIUS, 0, TAU, 48, base_col, 4.0)
	_canvas.draw_circle(_stick_center + _stick_vec * STICK_RADIUS, 52, Color(1, 1, 1, 0.3 if _stick_touch >= 0 else 0.18))
	for b in buttons:
		var lit: bool = b.down or (b.mode == "toggle" and _aim_on)
		var c: Color = b.color
		_canvas.draw_circle(b.pos, b.r, Color(c.r, c.g, c.b, 0.55 if lit else 0.22))
		_canvas.draw_arc(b.pos, b.r, 0, TAU, 40, Color(c.r, c.g, c.b, 0.85), 3.0)
		var fs := int(clampf(b.r * 0.62, 18, 44)) if String(b.label).length() <= 2 else 20
		var size := _font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		_canvas.draw_string(_font, b.pos + Vector2(-size.x / 2.0, size.y * 0.32), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
