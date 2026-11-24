extends SceneTree
## On-screen controller: shows on touchscreens without a gamepad, sends the same
## actions a gamepad does (move, look, fire, aim toggle, crouch, weapon swap),
## gets out of the way of the HUD, and hides when a gamepad is used.
## Run: godot --headless --fixed-fps 60 -s tools/tests/touch_test.gd

var f := 0
var fails := 0
var rs
var p
var tc
var hud
var start_yaw := 0.0
var shots := 0
var H := 1080.0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	rs = load("res://scenes/shooting_range.tscn").instantiate()
	root.add_child(rs)


func touch(i: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = pos
	e.pressed = down
	tc._input(e)   # straight in: headless window scaling would garble screen coordinates


func drag(i: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = pos
	e.relative = rel
	tc._input(e)


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		p = rs.player
		for n in root.find_children("*", "CanvasLayer", true, false):
			if n.get_script() and String(n.get_script().resource_path).ends_with("touch_controls.gd"):
				tc = n
			if n.get("touch") != null:
				hud = n
		check(tc != null, "the HUD has an on-screen controller")
		check(not tc.visible, "hidden with no touchscreen (PC / headless)")
		H = tc._canvas.get_viewport_rect().size.y
		tc.forced = true
		tc._update_visibility()
		check(tc.visible, "shown on a touchscreen with no gamepad")
		p.firearm.shot_fired.connect(func(_a): shots += 1)
		p.global_position = Vector3(-14, 0.05, 18)
		p.rotation = Vector3.ZERO
		p.pitch = 0.0
		var labels := []
		for b in tc.buttons:
			labels.append(b.label)
		check(labels.has("A") and labels.has("B") and labels.has("X") and labels.has("Y") and labels.has("RT") and labels.has("LT") and labels.has("LB") and labels.has("RB"),
			"Xbox layout: A B X Y, RT LT, LB RB (%s)" % ", ".join(labels))
	if f == 5:
		# Move stick: touch the left half, push right.
		touch(0, Vector2(300, H - 280), true)
	if f == 6:
		drag(0, Vector2(420, H - 280), Vector2(120, 0))
	if f == 30:
		check(hud._touch_layout and not hud._hint.visible, "HUD makes room: readouts move, the button hint goes")
		check(Input.get_action_strength("move_right") > 0.9, "left half is a move stick (move_right %.2f)" % Input.get_action_strength("move_right"))
		check(p.velocity.x > 1.0, "and you walk right (%.1f m/s)" % p.velocity.x)
		touch(0, Vector2(420, H - 280), false)
		start_yaw = p.rotation.y
		touch(1, Vector2(1300, H / 2.0), true)
	if f == 31:
		drag(1, Vector2(1400, H / 2.0), Vector2(100, 0))
	if f == 32:
		touch(1, Vector2(1400, H / 2.0), false)
		check(Input.get_action_strength("move_right") == 0.0, "letting go of the stick stops you")
		check(p.rotation.y < start_yaw - 0.1, "dragging on the right half turns you (%.1f deg)" % rad_to_deg(p.rotation.y - start_yaw))
		touch(2, tc.button("RT").pos, true)
	if f == 34:
		touch(2, tc.button("RT").pos, false)
		check(shots == 1, "RT fires")
		touch(3, tc.button("LT").pos, true)
	if f == 35:
		touch(3, tc.button("LT").pos, false)
	if f == 40:
		check(p.aiming, "tap LT: aim stays on")
		touch(3, tc.button("LT").pos, true)
	if f == 41:
		touch(3, tc.button("LT").pos, false)
	if f == 45:
		check(not p.aiming, "tap LT again: aim off")
		touch(4, tc.button("B").pos, true)
	if f == 46:
		touch(4, tc.button("B").pos, false)
		check(p.crouching, "B crouches")
		touch(5, tc.button("Y").pos, true)
	if f == 47:
		touch(5, tc.button("Y").pos, false)
	if f == 50:
		check(p.active_weapon != "pistol", "Y switches weapon (now %s)" % p.active_weapon)
		# A real gamepad gets used: the overlay steps aside.
		touch(6, Vector2(300, H - 280), true)
		var e := InputEventJoypadButton.new()
		e.button_index = JOY_BUTTON_A
		e.pressed = true
		Input.parse_input_event(e)
	if f == 52:
		check(not tc.visible, "pressing a gamepad button hides it")
		check(Input.get_action_strength("move_forward") == 0.0 and Input.get_action_strength("move_right") == 0.0, "and lets go of anything it was holding")
		check(not hud._touch_layout and hud._hint.visible, "HUD goes back to the gamepad layout")
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
