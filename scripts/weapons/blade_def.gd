class_name BladeDef
extends RefCounted
## A knife's numbers. The USMC Ka-Bar is the first: 7 in clip-point blade,
## 1.5 in wide, 11 7/8 in overall, about 11 oz (plus a 5 oz leather sheath).

var id := ""
var name := ""
var length_mm := 0.0         ## Blade length: the deepest it can go.
var width_mm := 0.0
var weight_kg := 0.0         ## Knife + sheath carried on the belt.
var stab_energy := 60.0      ## J a hard thrust delivers (strength 1.0).
var slash_depth_mm := 20.0   ## How deep the edge bites bare skin on a full slash.
var reach := 0.95            ## m from the eye a stab reaches (arm + blade).
var scene_path := ""


static func kabar() -> BladeDef:
	var b := BladeDef.new()
	b.id = "kabar"
	b.name = "USMC Ka-Bar"
	b.length_mm = 178.0
	b.width_mm = 38.0
	b.weight_kg = 0.31 + 0.14
	b.stab_energy = 60.0
	b.slash_depth_mm = 20.0
	b.reach = 0.95
	b.scene_path = "res://assets/weapons/kabar/kabar.glb"
	return b
