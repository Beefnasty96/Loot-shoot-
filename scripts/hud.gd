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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

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
		"PAUSED  -  Loot Shoot shooting range v0.4",
		"",
		"Left stick ........ move            Right stick ....... look",
		"R2 ................ fire            L2 ................ aim down sights",
		"X ................. reload (hold: check magazine)",
		"Y ................. switch 1911 / Ka-Bar (knife: R2 slash, L2+R2 stab)",
		"D-pad left/right .. load for your NEXT magazine",
		"D-pad down ........ bullet paths + ballistics readout",
		"R3 ................ first / third person",
		"L3 ................ sprint (3rd person, standing: swap shoulder)",
		"L1 / R1 ........... lean         B ......... crouch",
		"SELECT ............ inventory (A near a crate to search it)",
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
	_crosshair.visible = not get_tree().paused and not player.aiming and not player.preview and not inventory.is_open()

	var f := player.firearm
	if player.active_weapon == "knife":
		_ammo_big.text = "KA-BAR"
		var lines := ["R2: slash     L2 + R2: stab", "Y: back to the 1911"]
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
		if f.reloading:
			lines.push_front("RELOADING")
		elif f.slide_locked:
			lines.push_front("SLIDE LOCKED - reload")
		_ammo_info.text = "\n".join(lines)
		_mag_check.text = f.notice if f.notice_time > 0.0 else (f.mag_check_text if f.mag_check_time > 0.0 else "")
	var kg := player.carried_weight()
	var st := Encumbrance.status(kg)
	_load.text = "Load %s%s" % [Units.pounds(kg), ("  " + st) if st != "" else ""]
	_load.add_theme_color_override("font_color", Color(0.9, 0.9, 0.86) if st == "" else (Color(1, 0.8, 0.3) if st == "HEAVY" else Color(1, 0.35, 0.3)))
	var target := player.interact_target() if not inventory.is_open() else null
	_prompt.text = target.prompt() if target and target.has_method("prompt") else ""
	_hits.text = "\n".join(_hit_lines) if Ballistics.debug_enabled else ""
