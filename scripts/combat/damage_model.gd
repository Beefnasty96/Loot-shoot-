class_name DamageModel
extends RefCounted
## Per-zone health shared by the player, NPCs and test dummies.
## Damage comes from the energy a bullet deposits plus the tissue its
## (possibly expanded) diameter crushes. Head or thorax at zero = dead.

const ZONES := {
	"head": {max = 35.0, lethal = true},
	"thorax": {max = 85.0, lethal = true},
	"stomach": {max = 70.0, lethal = false},
	"arm_l": {max = 60.0, lethal = false},
	"arm_r": {max = 60.0, lethal = false},
	"leg_l": {max = 65.0, lethal = false},
	"leg_r": {max = 65.0, lethal = false},
}

var hp: Dictionary = {}
var dead := false


func _init() -> void:
	reset()


func reset() -> void:
	dead = false
	for z: String in ZONES:
		hp[z] = ZONES[z].max


## deposited_j: energy left in this zone. wound_ratio: current diameter / caliber.
static func damage_for(deposited_j: float, wound_ratio: float) -> float:
	return 12.0 * wound_ratio + deposited_j * 0.085 * sqrt(wound_ratio)


func apply(zone: String, damage: float) -> void:
	if not hp.has(zone):
		return
	hp[zone] = maxf(0.0, hp[zone] - damage)
	if hp[zone] <= 0.0 and ZONES[zone].lethal:
		dead = true
	# Total health pooled below 0 also kills (many limb hits).
	var total := 0.0
	for z: String in hp:
		total += hp[z]
	if total <= 0.0:
		dead = true
