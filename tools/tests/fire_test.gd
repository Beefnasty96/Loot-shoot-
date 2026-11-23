extends SceneTree
var f := 0
var gym
var p
var impacts := []
func _initialize():
	gym = load("res://scenes/gym.tscn").instantiate()
	root.add_child(gym)
	seed(3)
func press(a):
	var ev = InputEventAction.new(); ev.action = a; ev.pressed = true; ev.strength = 1.0
	Input.parse_input_event(ev)
func release(a):
	var ev = InputEventAction.new(); ev.action = a; ev.pressed = false
	Input.parse_input_event(ev)
func _process(_d):
	f += 1
	p = gym.player
	var fa = p.firearm
	if f == 2:
		root.get_node("/root/Ballistics").impact.connect(func(i): impacts.append(i))
		# Firing line facing the 10 m dummy (x=-14, z=8). Eye height 1.62 -> aim at thorax 1.36: look down slightly.
		p.global_position = Vector3(-14, 0.05, 18)
		p.rotation = Vector3.ZERO
		p.pitch = rad_to_deg(atan2(1.36 - 1.67, 10.0))
		Input.action_press("aim")
	if f == 40:
		print("start: chamber=%s mag=%d (%s)" % [fa.current_ammo_name(), fa.mag_count, fa.mag_ammo.short_name])
	# fire 9 trigger pulls, 12 frames apart
	if f >= 50 and f < 50 + 9 * 12:
		var k = (f - 50) % 12
		if k == 0:
			p.pitch = rad_to_deg(atan2(1.36 - 1.67, 10.0)); p._recoil_recover = 0
			Input.action_press("fire")
		if k == 3: Input.action_release("fire")
	if f == 50 + 9 * 12 + 30:
		print("after 9 pulls: chamber=%s mag=%d slide_locked=%s" % [fa.current_ammo_name(), fa.mag_count, fa.slide_locked])
		var zones = {}
		for i in impacts:
			if i.zone != "": zones[i.zone] = zones.get(i.zone, 0) + 1
		print("impacts: %d, zone hits %s" % [impacts.size(), zones])
		for i in impacts.slice(0, 3):
			print("  %s %s %s %d fps %d ftlb -> %s dep %d ftlb dmg %.0f" % [i.ammo.short_name, i.material, i.zone, AmmoType.ms_to_fps(i.speed_in), AmmoType.j_to_ftlb(i.energy_in), i.result, AmmoType.j_to_ftlb(i.deposited), i.damage])
		# select JHP for the next mag and reload
		Input.action_press("ammo_next")
	if f == 50 + 9 * 12 + 32:
		Input.action_release("ammo_next")
		Input.action_press("reload")
	if f == 50 + 9 * 12 + 34:
		Input.action_release("reload")
	if f == 50 + 9 * 12 + 34 + 160:
		print("after reload: reloading=%s chamber=%s mag=%d (%s) slide_locked=%s" % [fa.reloading, fa.current_ammo_name(), fa.mag_count, fa.mag_ammo.short_name, fa.slide_locked])
		Input.action_press("reload")
	if f == 50 + 9 * 12 + 34 + 160 + 40:
		Input.action_release("reload")
		print("mag check text: %s" % fa.mag_check_text.replace("\n", " | "))
		# Zero check: ADS at a wall placed at exactly 25 yd, level.
		var wall = StaticBody3D.new(); var cs = CollisionShape3D.new(); var sh = BoxShape3D.new(); sh.size = Vector3(4, 4, 0.2); cs.shape = sh; wall.add_child(cs)
		wall.position = Vector3(-21, 1.67, 20.0 - 22.86 - 0.1); wall.set_meta("material", "concrete"); gym.add_child(wall)
		p.global_position = Vector3(-21, 0.05, 20.0); p.rotation = Vector3.ZERO; p.pitch = 0
		impacts.clear()
	if f == 50 + 9 * 12 + 34 + 160 + 80:
		# swap to FMJ mag for zero test
		fa.mag_ammo = AmmoDB.get_ammo("45_1_fmj230"); fa.chambered = fa.mag_ammo
		fa.bloom = 0
	if f >= 50 + 9 * 12 + 34 + 160 + 90 and f < 50 + 9 * 12 + 34 + 160 + 90 + 8*20:
		var k = (f - (50 + 9 * 12 + 34 + 160 + 90)) % 20
		if k == 0:
			p.pitch = 0; p._recoil_recover = 0; fa.bloom = 0
			Input.action_press("fire")
		if k == 3: Input.action_release("fire")
	if f == 50 + 9 * 12 + 34 + 160 + 90 + 8*20 + 30:
		var eye = p.fp_camera.global_position
		print("eye height %.3f m; aimed hits on 25 yd wall (cm relative to sight line):" % eye.y)
		for i in impacts:
			if i.material == "concrete" and absf(i.position.x + 21) < 2:
				print("  dx %+.1f cm  dy %+.1f cm" % [(i.position.x - eye.x) * 100, (i.position.y - eye.y) * 100])
		quit()
	return false
