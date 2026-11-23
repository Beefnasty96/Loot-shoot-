extends Node
## Autoload "Settings": player options, saved to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

var look_sensitivity := 1.0     ## Multiplier on stick/mouse look speed.
var invert_look_y := false
var fov := 75.0                 ## Vertical field of view, degrees.
var show_bullet_paths := true   ## In the test gym.


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


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "look_sensitivity", look_sensitivity)
	cfg.set_value("controls", "invert_look_y", invert_look_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("gameplay", "show_bullet_paths", show_bullet_paths)
	cfg.save(PATH)
	changed.emit()
