class_name BallisticMaterials
extends RefCounted
## How surfaces resist bullets.
##   gel_per_mm  - millimetres of 10% gel that 1 mm of this material is worth.
##                 Hollow constructions (stud walls, crates) average in the air gaps.
##   ricochet    - critical grazing angle (degrees from the surface) for an FMJ.
##   hard        - deforms hollow/lead noses; frangibles turn to dust.
##   clogs       - can plug a hollow point (drywall, wood).
##   deflect     - random path change on exit, degrees.
##   fx          - impact effect family: dust, wood, spark, glass, flesh.

const TABLE := {
	"concrete": {gel_per_mm = 14.0, ricochet = 18.0, hard = true, clogs = false, deflect = 0.0, fx = "dust", color = Color(0.6, 0.6, 0.58)},
	"brick": {gel_per_mm = 10.0, ricochet = 14.0, hard = true, clogs = false, deflect = 0.0, fx = "dust", color = Color(0.6, 0.35, 0.25)},
	"steel": {gel_per_mm = 125.0, ricochet = 28.0, hard = true, clogs = false, deflect = 4.0, fx = "spark", color = Color(1.0, 0.85, 0.4)},
	"sheet_metal": {gel_per_mm = 40.0, ricochet = 20.0, hard = true, clogs = false, deflect = 6.0, fx = "spark", color = Color(1.0, 0.85, 0.4)},
	"glass": {gel_per_mm = 4.0, ricochet = 8.0, hard = true, clogs = false, deflect = 6.0, fx = "glass", color = Color(0.8, 0.9, 1.0), breakable = true},
	"wood": {gel_per_mm = 3.0, ricochet = 6.0, hard = false, clogs = true, deflect = 3.0, fx = "wood", color = Color(0.55, 0.4, 0.22)},
	"plywood": {gel_per_mm = 3.0, ricochet = 6.0, hard = false, clogs = true, deflect = 3.0, fx = "wood", color = Color(0.7, 0.55, 0.33)},
	"wood_crate": {gel_per_mm = 0.8, ricochet = 5.0, hard = false, clogs = true, deflect = 4.0, fx = "wood", color = Color(0.55, 0.42, 0.26)},
	"drywall": {gel_per_mm = 1.8, ricochet = 0.0, hard = false, clogs = true, deflect = 2.0, fx = "dust", color = Color(0.92, 0.92, 0.9)},
	"drywall_partition": {gel_per_mm = 0.22, ricochet = 0.0, hard = false, clogs = true, deflect = 3.0, fx = "dust", color = Color(0.92, 0.92, 0.9)},
	"gel": {gel_per_mm = 1.0, ricochet = 0.0, hard = false, clogs = false, deflect = 0.5, fx = "flesh", color = Color(0.9, 0.75, 0.5)},
	"flesh": {gel_per_mm = 1.0, ricochet = 0.0, hard = false, clogs = false, deflect = 2.0, fx = "flesh", color = Color(0.45, 0.05, 0.05)},
	"dummy": {gel_per_mm = 1.0, ricochet = 0.0, hard = false, clogs = false, deflect = 2.0, fx = "dummy", color = Color(0.85, 0.7, 0.4)},
}

const DEFAULT := "concrete"


static func get_props(name: String) -> Dictionary:
	return TABLE.get(name, TABLE[DEFAULT])


## Material name for whatever a ray hit.
static func of(collider: Object) -> String:
	if collider == null:
		return DEFAULT
	if collider.has_meta("material"):
		return collider.get_meta("material")
	return DEFAULT
