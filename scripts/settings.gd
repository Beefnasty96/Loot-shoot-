extends Node
## Autoload "Settings": player options, saved to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

var look_sensitivity := 1.0     ## Multiplier on stick/mouse look speed.
var invert_look_y := false
var fov := 75.0                 ## Vertical field of view, degrees.
var show_bullet_paths := true   ## On the shooting range.
var aim_sensitivity := 0.45     ## Look speed while aiming down sights, as a fraction of the normal speed.
var toggle_crouch := true       ## true: B toggles crouch; false: crouch while B is held.
var toggle_lean := false        ## true: L1/R1 toggle the lean; false: lean while held.


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	look_sensitivity = cfg.get_value("controls", "look_sensitivity", look_sensitivity)
	invert_look_y = cfg.get_value("controls", "invert_look_y", invert_look_y)
	fov = cfg.get_value("video", "fov", fov)
	show_bullet_paths = cfg.get_value("gameplay", "show_bullet_paths", show_bullet_paths)
	aim_sensitivity = cfg.get_value("controls", "aim_sensitivity", aim_sensitivity)
	toggle_crouch = cfg.get_value("controls", "toggle_crouch", toggle_crouch)
	toggle_lean = cfg.get_value("controls", "toggle_lean", toggle_lean)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "look_sensitivity", look_sensitivity)
	cfg.set_value("controls", "invert_look_y", invert_look_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("gameplay", "show_bullet_paths", show_bullet_paths)
	cfg.set_value("controls", "aim_sensitivity", aim_sensitivity)
	cfg.set_value("controls", "toggle_crouch", toggle_crouch)
	cfg.set_value("controls", "toggle_lean", toggle_lean)
	cfg.save(PATH)
	changed.emit()
