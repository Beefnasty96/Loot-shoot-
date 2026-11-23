class_name Mirror
extends StaticBody3D
## Range mirror: press A for a new face, skin and hair (testing appearance variety).

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	add_to_group("interactable")
	_rng.randomize()


func prompt() -> String:
	return "A: new look"


func use(p: Player) -> void:
	p.character.appearance.randomize(_rng)
	p.character.apply_appearance()
