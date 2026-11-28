extends SceneTree
## Settings: aim sensitivity, crouch toggle/hold, lean hold/toggle, saving them,
## and aiming down sights magnifying the view 1.5x.
## Run: godot --headless --fixed-fps 60 -s tools/tests/settings_test.gd

var f := 0
var fails := 0
var rs
var p
var S
var saved := {}
var steps: Array = []
var si := 0
var wait := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _act(action: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = down
	Input.parse_input_event(e)


func _initialize() -> void:
	rs = load("res://scenes/shooting_range.tscn").instantiate()
	root.add_child(rs)
	steps = [
		[func():
			S = root.get_node("/root/Settings")
			p = rs.player
			for k in ["fov", "look_sensitivity", "aim_sensitivity", "toggle_crouch", "toggle_lean"]:
				saved[k] = S.get(k)
			S.fov = 75.0
			S.look_sensitivity = 1.2
			S.aim_sensitivity = 0.5, func():
			var z: float = tan(deg_to_rad(75.0) / 2.0) / tan(deg_to_rad(p.ads_fov()) / 2.0)
			check(absf(z - 1.5) < 0.001, "aiming down sights is a 1.5x zoom (%.1f deg view -> %.1f deg)" % [75.0, p.ads_fov()])
			check(absf(p.look_scale() - 1.2) < 0.001, "look speed = look sensitivity when not aiming")],
		[func(): Input.action_press("aim"), func(): pass],
		[func(): pass, func():
			check(p.aiming, "holding L2 aims")
			check(absf(p.fp_camera.fov - p.ads_fov()) < 1.0, "the view zooms to %.1f deg (camera at %.1f)" % [p.ads_fov(), p.fp_camera.fov])
			check(absf(p.look_scale() - 0.6) < 0.001, "aim sensitivity scales look speed while aiming (1.2 x 0.5 = %.2f)" % p.look_scale())
			S.fov = 90.0],
		[func(): pass, func():
			var z: float = tan(deg_to_rad(90.0) / 2.0) / tan(deg_to_rad(p.fp_camera.fov) / 2.0)
			check(absf(z - 1.5) < 0.05, "still 1.5x with a wider field of view (%.2fx)" % z)
			Input.action_release("aim")],
		[func(): pass, func(): check(not p.aiming and absf(p.fp_camera.fov - 90.0) < 1.0, "letting go zooms back out (%.1f deg)" % p.fp_camera.fov)],
		# Crouch: toggle (default), then hold.
		[func(): S.toggle_crouch = true; _act("crouch", true); _act("crouch", false), func(): check(p.crouching, "crouch toggle: a tap crouches")],
		[func(): _act("crouch", true); _act("crouch", false), func(): check(not p.crouching, "another tap stands up")],
		[func(): S.toggle_crouch = false; Input.action_press("crouch"), func(): check(p.crouching, "crouch hold: crouched while B is held")],
		[func(): Input.action_release("crouch"), func(): check(not p.crouching, "and standing when it's let go")],
		# Lean: hold (default), then toggle.
		[func(): S.toggle_lean = false; Input.action_press("lean_right"), func(): pass],
		[func(): pass, func(): check(p.lean > 0.9, "lean hold: leans while R1 is held (%.2f)" % p.lean)],
		[func(): Input.action_release("lean_right"), func(): pass],
		[func(): pass, func(): check(absf(p.lean) < 0.05, "upright when it's let go (%.2f)" % p.lean)],
		[func(): S.toggle_lean = true; _act("lean_left", true); _act("lean_left", false), func(): pass],
		[func(): pass, func(): check(p.lean < -0.9, "lean toggle: a tap of L1 leans left and stays (%.2f)" % p.lean)],
		[func(): _act("lean_right", true); _act("lean_right", false), func(): pass],
		[func(): pass, func(): check(p.lean > 0.9, "R1 switches straight to the right (%.2f)" % p.lean)],
		[func(): _act("lean_right", true); _act("lean_right", false), func(): pass],
		[func(): pass, func(): check(absf(p.lean) < 0.05, "R1 again stands up straight (%.2f)" % p.lean)],
		# Saved and loaded.
		[func():
			S.aim_sensitivity = 0.8
			S.toggle_crouch = false
			S.toggle_lean = true
			S.fov = 88.0
			S.save_settings()
			S.aim_sensitivity = 0.2
			S.toggle_crouch = true
			S.toggle_lean = false
			S.fov = 60.0
			S.load_settings(), func():
			check(absf(S.aim_sensitivity - 0.8) < 0.001 and not S.toggle_crouch and S.toggle_lean and absf(S.fov - 88.0) < 0.001, "the new settings are saved and load back")
			for k in saved:
				S.set(k, saved[k])
			S.save_settings()],
	]


func _process(_d: float) -> bool:
	f += 1
	if f < 5:
		return false
	wait += 1
	if si < steps.size():
		if wait == 1:
			steps[si][0].call()
		elif wait == 40:
			steps[si][1].call()
			si += 1
			wait = 0
	else:
		print("%d failure(s)" % fails)
		quit(1 if fails else 0)
	return false
