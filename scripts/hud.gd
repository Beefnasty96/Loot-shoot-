extends CanvasLayer
## Main-screen HUD: crosshair, view/stance readout, ammo, mag check,
## ballistics readout (D-pad down toggles it with the bullet-path lines) and pause panel.

var player: Player

var _status: Label
var _crosshair: Label
var _ammo_big: Label
var _ammo_info: Label
var _mag_check: Label
var _hits: Label
var _pause_panel: PanelContainer
var _hit_lines: Array[String] = []
var inventory: InventoryScreen
var _load: Label
var _prompt: Label
var _hurt_flash: ColorRect
var _shock: ColorRect
var _body: Dictionary = {}     ## zone -> ColorRect of the body diagram
var _body_text: Label
var _death: Label
var _objective: Label
var objective_text := ""       ## Set by the level ("Hostiles: 3 left").


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Full-screen overlays first so the text draws over them.
	_shock = ColorRect.new()
	_shock.color = Color(0, 0, 0, 0)
	_shock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shock)
	_hurt_flash = ColorRect.new()
	_hurt_flash.color = Color(0.6, 0, 0, 0)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hurt_flash)
	_build_body_diagram()

	_crosshair = _label("+", 40)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_status = _label("", 26)
	_status.position = Vector2(24, 18)

	var hint := _label("START: controls    SELECT: inventory", 22)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position += Vector2(24, -48)

	_ammo_big = _label("", 64)
	_ammo_big.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_big.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo_big.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ammo_big.position += Vector2(-32, -150)

	_ammo_info = _label("", 22)
	_ammo_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ammo_info.position += Vector2(-32, -40)

	_mag_check = _label("", 30)
	_mag_check.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_mag_check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mag_check.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mag_check.position += Vector2(0, -230)

	_hits = _label("", 20)
	_hits.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hits.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hits.position += Vector2(-24, 18)

	_build_pause_panel()
	Ballistics.impact.connect(_on_impact)
	Ballistics.melee_impact.connect(_on_melee)
	_load = _label("", 22)
	_load.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_load.position += Vector2(24, -84)
	_prompt = _label("", 28)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position += Vector2(0, 90)
	_objective = _label("", 26)
	_objective.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_objective.position += Vector2(0, 18)
	_death = _label("", 44)
	_death.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death.add_theme_color_override("font_color", Color(0.9, 0.15, 0.12))
	add_to_group("hud")
	inventory = InventoryScreen.new()
	inventory.player = player
	add_child(inventory)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	add_child(l)
	return l


## Little body outline, bottom left: each zone goes from grey-green to red as it's hurt, black when gone.
func _build_body_diagram() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	root.position += Vector2(30, -250)
	add_child(root)
	var parts := {
		head = Rect2(22, 0, 20, 22), thorax = Rect2(14, 24, 36, 30), stomach = Rect2(16, 56, 32, 22),
		arm_l = Rect2(52, 26, 11, 50), arm_r = Rect2(1, 26, 11, 50), leg_l = Rect2(34, 80, 14, 56), leg_r = Rect2(16, 80, 14, 56),
	}
	for z: String in parts:
		var r := ColorRect.new()
		r.position = parts[z].position
		r.size = parts[z].size
		r.color = Color(0.55, 0.7, 0.5, 0.8)
		root.add_child(r)
		_body[z] = r
	_body_text = Label.new()
	_body_text.position = Vector2(72, 30)
	_body_text.add_theme_font_size_override("font_size", 20)
	_body_text.add_theme_color_override("font_outline_color", Color.BLACK)
	_body_text.add_theme_constant_override("outline_size", 5)
	root.add_child(_body_text)


func _update_body() -> void:
	var v := player.vitals
	if v == null:
		return
	for z: String in _body:
		var f: float = v.damage.hp[z] / DamageModel.ZONES[z].max
		var c := Color(0.55, 0.7, 0.5, 0.8).lerp(Color(0.85, 0.12, 0.08, 0.9), 1.0 - f)
		if f <= 0.0:
			c = Color(0.05, 0.05, 0.05, 0.9)
		(_body[z] as ColorRect).color = c
	var lines := []
	var b := v.bleeding()
	if b != "":
		lines.append(b)
	var blood := v.damage.blood_fraction()
	if blood < 0.995:
		lines.append("Blood %d%%" % roundi(blood * 100.0))
	if v.painkiller_time > 0.0:
		lines.append("Painkillers %ds" % ceili(v.painkiller_time))
	elif v.felt_pain() > 0.25:
		lines.append("In pain")
	if v.using != "":
		lines.append("Treating... %.1fs" % v.use_left)
	_body_text.text = "\n".join(lines)
	_body_text.add_theme_color_override("font_color", Color(1, 0.3, 0.25) if b != "" else Color(0.95, 0.92, 0.85))
	_hurt_flash.color.a = v.flash * 0.35
	_shock.color.a = clampf(v.shock() * 0.55 + (0.15 if v.bleeding() == "ARTERIAL BLEED" else 0.0), 0.0, 0.7)
	if v.dead:
		_death.text = "YOU DIED\n%s\n\nA: try again      Y: main menu" % v.cause
	_objective.text = objective_text


func _build_pause_panel() -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.82)
	style.set_content_margin_all(28)
	_pause_panel.add_theme_stylebox_override("panel", style)
	var text := Label.new()
	text.add_theme_font_size_override("font_size", 24)
	text.text = "\n".join([
		"PAUSED  -  Loot Shoot v0.5",
		"",
		"Left stick ........ move            Right stick ....... look",
		"R2 ................ fire            L2 ................ aim down sights",
		"X ................. reload (hold: check magazine)",
		"Y ................. switch 1911 / Ka-Bar (knife: R2 slash, L2+R2 stab)",
		"D-pad left/right .. load for your NEXT magazine",
		"D-pad down ........ weapon light (hold: bullet paths + ballistics readout)",
		"R3 ................ first / third person",
		"L3 ................ sprint (3rd person, standing: swap shoulder)",
		"L1 / R1 ........... lean         B ......... crouch",
		"SELECT ............ inventory (A near a crate to search it)",
		"D-pad up .......... treat yourself (IFAK, bandages, painkillers)",
		"",
		"Sights are zeroed at 25 yd (75 ft) for 230gr ball.",
		"Bullet paths: white = flying, orange = after penetrating, yellow = ricochet.",
		"START to resume      Y: quit to main menu",
	])
	_pause_panel.add_child(text)
	add_child(_pause_panel)
	_pause_panel.resized.connect(func():
		_pause_panel.position = (get_viewport().get_visible_rect().size - _pause_panel.size) / 2.0)


## Open the inventory with something to search: a LootContainer, a dead Npc, or null for the ground.
func open_inventory(target: Node = null) -> void:
	if not inventory.is_open():
		inventory.open(target)


func _unhandled_input(event: InputEvent) -> void:
	if inventory and inventory.is_open():
		return
	if player and player.vitals and player.vitals.dead:
		if event.is_action_pressed("interact"):
			get_tree().reload_current_scene()
		elif event.is_action_pressed("switch_weapon"):
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if event.is_action_pressed("inventory") and not get_tree().paused:
		var t := player.interact_target()
		var searchable: Node = t if (t is LootContainer or (t is Npc and (t as Npc).dead)) else null
		open_inventory(searchable)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		var paused := not get_tree().paused
		get_tree().paused = paused
		_pause_panel.visible = paused
		if paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event.is_action_pressed("switch_weapon"):
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif event.is_action_pressed("toggle_debug"):
		Ballistics.debug_enabled = not Ballistics.debug_enabled


func _on_melee(info: Dictionary) -> void:
	var what: String = info.zone.to_upper() if info.zone != "" else (String(info.material).replace("_", " ") if info.material != "" else "wall")
	var line := "KA-BAR %s %s" % [info.kind.to_upper(), what]
	if info.zone != "":
		if info.kind == "stab":
			line += ": %s deep" % Units.inches(info.depth_mm)
		else:
			line += ": %s long, %s deep" % [Units.inches(info.length_mm), Units.inches(info.depth_mm)]
		if info.get("cloth_j", 0.0) > 0.0:
			line += " (through clothing)"
		line += " -%d HP, %s" % [roundi(info.damage), info.bleed]
	else:
		line += ": blade glances off"
	_hit_lines.push_front(line)
	if _hit_lines.size() > 6:
		_hit_lines.resize(6)


func _on_impact(info: Dictionary) -> void:
	var a: AmmoType = info.ammo
	var what: String = info.zone.to_upper() if info.zone != "" else String(info.material).replace("_", " ")
	var line := "%s %s: %d fps, %d ft-lb in" % [a.short_name, what, roundi(AmmoType.ms_to_fps(info.speed_in)), roundi(AmmoType.j_to_ftlb(info.energy_in))]
	match info.result:
		"penetrated":
			line += " -> through %s, %d fps out" % [Units.inches(info.thickness_mm), roundi(AmmoType.ms_to_fps(info.speed_out))]
		"stopped":
			line += " -> stopped at %s" % Units.inches(info.depth_mm)
		"ricochet":
			line += " -> RICOCHET"
		"disintegrated":
			line += " -> turned to dust"
	if info.expanded:
		line += " [expanded]"
	elif info.clogged:
		line += " [plugged]"
	elif info.deformed:
		line += " [deformed]"
	if info.zone != "":
		line += " -%d HP" % roundi(info.damage)
		if info.has("bleed"):
			line += ", " + info.bleed
	line += "  (%s)" % Units.feet(info.distance)
	_hit_lines.push_front(line)
	if _hit_lines.size() > 6:
		_hit_lines.resize(6)


func _process(_delta: float) -> void:
	if player == null:
		return
	var open := inventory != null and inventory.is_open()
	for c in get_children():
		if c != inventory and c != _pause_panel and c is CanvasItem:
			(c as CanvasItem).visible = not open
	var stance := "Crouched" if player.crouching else ("Sprinting" if player.sprinting else "Standing")
	if player.aiming:
		stance += " - Aiming"
	var view := player.view_name()
	if player.effective_view() == Player.View.THIRD:
		view += " (%s shoulder)" % ("R" if player.shoulder > 0.0 else "L")
	_status.text = "%s\n%s\nFPS %d" % [view, stance, Engine.get_frames_per_second()]
	var dead: bool = player.vitals != null and player.vitals.dead
	_crosshair.visible = not get_tree().paused and not player.aiming and not player.preview and not inventory.is_open() and not dead
	_ammo_big.visible = not dead and not open
	_ammo_info.visible = not dead and not open

	var f := player.firearm
	if player.active_weapon == "none":
		_ammo_big.text = "UNARMED"
		_ammo_info.text = "Put a weapon in your holster or sheath (inventory)."
		_mag_check.text = ""
	elif player.active_weapon == "knife":
		_ammo_big.text = "KA-BAR"
		var lines := ["R2: slash     L2 + R2: stab", "Y: next weapon"]
		if player.knife.blood > 0.05:
			lines.push_front("Blade %s" % ("bloody" if player.knife.blood > 0.5 else "stained"))
		_ammo_info.text = "\n".join(lines)
		_mag_check.text = ""
	elif f:
		var mag := str(f.mag_count) if f.has_mag else "-"
		var chamber := " + 1" if f.chambered else " + 0"
		_ammo_big.text = mag + chamber
		var lines := []
		lines.append("Chamber: %s" % f.current_ammo_name())
		lines.append("Mag: %s" % (f.mag_ammo.display_name if f.has_mag else "none"))
		lines.append("Next mag:  <  %s  >  (%d spare)" % [f.next_ammo().display_name, f.spare_count(f.next_ammo())])
		if f.gun:
			var modes: Array = WeaponDB.weapon(f.gun.def.weapon_id).get("modes", ["semi"])
			var sel := ("   [%s]" % f.mode.to_upper()) if modes.size() > 1 else ""
			lines.push_front(f.gun.def.display_name + sel + ("   [LIGHT ON]" if f.light_on else ""))
		if f.reloading:
			lines.push_front("RELOADING")
		elif f.slide_locked:
			lines.push_front(("BOLT" if f.rig.anim == "rifle" else "SLIDE") + " LOCKED - reload")
		_ammo_info.text = "\n".join(lines)
		_mag_check.text = f.notice if f.notice_time > 0.0 else (f.mag_check_text if f.mag_check_time > 0.0 else "")
	_update_body()
	if player.med_notice_time > 0.0:
		_mag_check.text = player.med_notice
	var kg := player.carried_weight()
	var st := Encumbrance.status(kg)
	_load.text = "Load %s%s" % [Units.pounds(kg), ("  " + st) if st != "" else ""]
	_load.add_theme_color_override("font_color", Color(0.9, 0.9, 0.86) if st == "" else (Color(1, 0.8, 0.3) if st == "HEAVY" else Color(1, 0.35, 0.3)))
	var target := player.interact_target() if not inventory.is_open() else null
	_prompt.text = target.prompt() if target and target.has_method("prompt") else ""
	_hits.text = "\n".join(_hit_lines) if Ballistics.debug_enabled else ""
