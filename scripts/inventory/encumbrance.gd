class_name Encumbrance
extends RefCounted
## How carried weight slows anyone down (player now, enemies when they exist).
##
##   up to 25 kg (55 lb)   no penalty
##   25-45 kg (55-99 lb)   speed falls to 80%
##   45-65 kg (99-143 lb)  OVERWEIGHT: no sprinting, speed falls to 45%
##   over 65 kg            barely moving (30%)

const COMFORT_KG := 25.0
const OVERWEIGHT_KG := 45.0
const MAX_KG := 65.0


static func speed_factor(kg: float) -> float:
	if kg <= COMFORT_KG:
		return 1.0
	if kg <= OVERWEIGHT_KG:
		return lerpf(1.0, 0.8, (kg - COMFORT_KG) / (OVERWEIGHT_KG - COMFORT_KG))
	if kg <= MAX_KG:
		return lerpf(0.8, 0.45, (kg - OVERWEIGHT_KG) / (MAX_KG - OVERWEIGHT_KG))
	return 0.3


static func can_sprint(kg: float) -> bool:
	return kg < OVERWEIGHT_KG


static func status(kg: float) -> String:
	if kg <= COMFORT_KG:
		return ""
	if kg <= OVERWEIGHT_KG:
		return "HEAVY"
	return "OVERWEIGHT"
