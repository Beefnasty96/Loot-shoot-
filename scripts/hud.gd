extends CanvasLayer
## Main-screen HUD: crosshair, view/stance readout, FPS, and a pause/controls panel.

var player: Player

var _status: Label
var _crosshair: Label
var _pause_panel: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 40)
	_crosshair.add_theme_color_override("font_outline_color", Color.BLACK)
	_crosshair.add_theme_constant_override("outline_size", 6)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_crosshair)

	_status = Label.new()
	_status.position = Vector2(24, 18)
	_status.add_theme_font_size_override("font_size", 28)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	add_child(_status)

	var hint := Label.new()
	hint.text = "START: controls"
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 5)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position += Vector2(24, -48)
	add_child(hint)

	_build_pause_panel()


func _build_pause_panel() -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	style.set_content_margin_all(32)
	_pause_panel.add_theme_stylebox_override("panel", style)
	var text := Label.new()
	text.add_theme_font_size_override("font_size", 28)
	text.text = "\n".join([
		"PAUSED  -  Loot Shoot test gym v0.1",
		"",
		"Left stick ........ move",
		"Right stick ....... look",
		"L3 ................ sprint (3rd person, standing: swap shoulder)",
		"R3 ................ first / third person",
		"L2 ................ aim (zoom, first person)",
		"L1 / R1 ........... lean left / right",
		"B ................. crouch",
		"",
		"Firing arrives in the next step.",
		"START to resume",
	])
	_pause_panel.add_child(text)
	add_child(_pause_panel)
	# Re-centre after the label sizes the panel.
	_pause_panel.resized.connect(func():
		_pause_panel.position = (get_viewport().get_visible_rect().size - _pause_panel.size) / 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var paused := not get_tree().paused
		get_tree().paused = paused
		_pause_panel.visible = paused
		if paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if player == null:
		return
	var stance := "Crouched" if player.crouching else ("Sprinting" if player.sprinting else "Standing")
	if player.aiming:
		stance += " - Aiming"
	var shoulder := "R" if player.shoulder > 0.0 else "L"
	var view := player.view_name()
	if player.effective_view() == Player.View.THIRD:
		view += " (%s shoulder)" % shoulder
	_status.text = "%s\n%s\nFPS %d" % [view, stance, Engine.get_frames_per_second()]
	_crosshair.visible = not get_tree().paused and not player.aiming
