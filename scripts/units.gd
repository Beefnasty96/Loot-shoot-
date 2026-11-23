class_name Units
extends RefCounted
## Everything shown to the player is in US units (feet, inches, pounds, fps, ft-lbs).
## The engine and the physics keep working in metres/kilograms internally.

const M_TO_FT := 3.28084
const MM_TO_IN := 1.0 / 25.4
const KG_TO_LB := 2.20462
const FT_TO_M := 0.3048
const IN_TO_M := 0.0254


static func feet(metres: float) -> String:
	return "%d ft" % roundi(metres * M_TO_FT)


static func inches(mm: float) -> String:
	var v := mm * MM_TO_IN
	if v < 1.0:
		return "%.2f in" % v
	return "%.1f in" % v


static func pounds(kg: float) -> String:
	return "%.1f lb" % (kg * KG_TO_LB)
