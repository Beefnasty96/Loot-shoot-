class_name Anatomy
extends RefCounted
## Organs, major vessels and bones inside a person, and what a wound path through
## them does. Shared by the player, NPCs, enemies and the range dummies.
##
## Everything is laid out in the character rig's rest pose (metres, +Z forward,
## +X = their left, T-pose arms along X), as ellipsoids sized from adult anatomy.
## Each Hitbox carries `to_rig` (its local space -> rig space), so a bullet or a
## blade's path through a hitbox can be checked against the organs inside it.
##
## Kinds and effects (DamageModel.apply_organs):
##   cns      brain, brainstem         - dead on the spot
##   cord     spinal cord              - neck: everything paralysed and breathing
##                                       stops; chest/lower back: legs paralysed
##   heart    heart                    - torrential bleed, heart stops within ~10 s
##   vessel   aorta, vena cava, carotids, subclavian, femoral, brachial, iliac
##                                     - arterial bleed (rate per vessel)
##   lung     lungs                    - bleeding into the chest and short of breath
##                                       (both lungs: barely breathing)
##   organ    liver, spleen, kidneys, gut - internal bleeding that no bandage stops
##   bone     skull, humerus, forearm, femur, tibia, pelvis, spine body
##                                     - a broken limb won't work; a bone also takes
##                                       extra penetration (dense: ~3x gel)

## id: [name, kind, zone, centre, radii, extra]
## extra: bleed ml/s (vessel/heart/organ/lung), limb (bone/cord), bone gel factor.
const ORGANS := {
	# --- head and neck
	"brain": ["brain", "cns", "head", Vector3(0, 1.745, 0.025), Vector3(0.068, 0.06, 0.085), {}],
	"brainstem": ["brainstem", "cns", "head", Vector3(0, 1.665, -0.005), Vector3(0.018, 0.03, 0.018), {}],
	"skull": ["skull", "bone", "head", Vector3(0, 1.75, 0.025), Vector3(0.078, 0.07, 0.095), {gel = 2.5, shell = true}],
	"cord_neck": ["spinal cord (neck)", "cord", "head", Vector3(0, 1.605, -0.03), Vector3(0.02, 0.045, 0.02), {limb = "all"}],
	"carotid_l": ["left carotid artery", "vessel", "head", Vector3(0.033, 1.61, 0.03), Vector3(0.012, 0.045, 0.012), {bleed = 45.0}],
	"carotid_r": ["right carotid artery", "vessel", "head", Vector3(-0.033, 1.61, 0.03), Vector3(0.012, 0.045, 0.012), {bleed = 45.0}],
	# --- chest
	"heart": ["heart", "heart", "thorax", Vector3(0.025, 1.31, 0.035), Vector3(0.05, 0.06, 0.045), {bleed = 110.0}],
	"aorta": ["aorta", "vessel", "thorax", Vector3(0.01, 1.34, -0.025), Vector3(0.016, 0.14, 0.016), {bleed = 80.0}],
	"subclavian_l": ["left subclavian artery", "vessel", "thorax", Vector3(0.1, 1.45, 0.02), Vector3(0.06, 0.012, 0.012), {bleed = 35.0}],
	"subclavian_r": ["right subclavian artery", "vessel", "thorax", Vector3(-0.1, 1.45, 0.02), Vector3(0.06, 0.012, 0.012), {bleed = 35.0}],
	"lung_l": ["left lung", "lung", "thorax", Vector3(0.085, 1.34, 0.0), Vector3(0.06, 0.12, 0.085), {bleed = 8.0}],
	"lung_r": ["right lung", "lung", "thorax", Vector3(-0.085, 1.34, 0.0), Vector3(0.065, 0.12, 0.085), {bleed = 9.0}],
	"cord_chest": ["spinal cord (chest)", "cord", "thorax", Vector3(0, 1.33, -0.095), Vector3(0.02, 0.17, 0.02), {limb = "legs"}],
	# --- abdomen and pelvis
	"liver": ["liver", "organ", "stomach", Vector3(-0.07, 1.15, 0.02), Vector3(0.09, 0.06, 0.075), {bleed = 25.0}],
	"spleen": ["spleen", "organ", "stomach", Vector3(0.09, 1.15, -0.03), Vector3(0.035, 0.05, 0.03), {bleed = 18.0}],
	"kidney_l": ["left kidney", "organ", "stomach", Vector3(0.06, 1.07, -0.07), Vector3(0.03, 0.05, 0.025), {bleed = 12.0}],
	"kidney_r": ["right kidney", "organ", "stomach", Vector3(-0.06, 1.06, -0.07), Vector3(0.03, 0.05, 0.025), {bleed = 12.0}],
	"gut": ["intestines", "organ", "stomach", Vector3(0, 1.0, 0.04), Vector3(0.12, 0.09, 0.07), {bleed = 4.0}],
	"aorta_abd": ["abdominal aorta", "vessel", "stomach", Vector3(0.008, 1.06, -0.05), Vector3(0.014, 0.12, 0.014), {bleed = 60.0}],
	"cord_low": ["spinal cord (lower back)", "cord", "stomach", Vector3(0, 1.06, -0.092), Vector3(0.022, 0.13, 0.022), {limb = "legs"}],
	"iliac_l": ["left iliac artery", "vessel", "stomach", Vector3(0.065, 0.92, 0.02), Vector3(0.015, 0.05, 0.015), {bleed = 35.0}],
	"iliac_r": ["right iliac artery", "vessel", "stomach", Vector3(-0.065, 0.92, 0.02), Vector3(0.015, 0.05, 0.015), {bleed = 35.0}],
	"pelvis_l": ["pelvis", "bone", "stomach", Vector3(0.11, 0.96, -0.02), Vector3(0.04, 0.06, 0.07), {limb = "pelvis", gel = 2.5}],
	"pelvis_r": ["pelvis", "bone", "stomach", Vector3(-0.11, 0.96, -0.02), Vector3(0.04, 0.06, 0.07), {limb = "pelvis", gel = 2.5}],
	"sacrum": ["pelvis", "bone", "stomach", Vector3(0, 0.93, -0.08), Vector3(0.045, 0.05, 0.025), {limb = "pelvis", gel = 2.5}],
	# --- arms (T-pose, along X)
	"humerus_l": ["left humerus", "bone", "arm_l", Vector3(0.30, 1.43, 0), Vector3(0.13, 0.014, 0.014), {limb = "arm_l", gel = 3.0}],
	"humerus_r": ["right humerus", "bone", "arm_r", Vector3(-0.30, 1.43, 0), Vector3(0.13, 0.014, 0.014), {limb = "arm_r", gel = 3.0}],
	"brachial_l": ["left brachial artery", "vessel", "arm_l", Vector3(0.29, 1.405, 0.012), Vector3(0.12, 0.008, 0.008), {bleed = 20.0}],
	"brachial_r": ["right brachial artery", "vessel", "arm_r", Vector3(-0.29, 1.405, 0.012), Vector3(0.12, 0.008, 0.008), {bleed = 20.0}],
	"forearm_l": ["left forearm bones", "bone", "arm_l", Vector3(0.57, 1.415, 0), Vector3(0.12, 0.012, 0.022), {limb = "arm_l", gel = 3.0}],
	"forearm_r": ["right forearm bones", "bone", "arm_r", Vector3(-0.57, 1.415, 0), Vector3(0.12, 0.012, 0.022), {limb = "arm_r", gel = 3.0}],
	# --- legs
	"femur_l": ["left femur", "bone", "leg_l", Vector3(0.12, 0.72, 0.0), Vector3(0.016, 0.21, 0.016), {limb = "leg_l", gel = 3.0}],
	"femur_r": ["right femur", "bone", "leg_r", Vector3(-0.12, 0.72, 0.0), Vector3(0.016, 0.21, 0.016), {limb = "leg_r", gel = 3.0}],
	"femoral_l": ["left femoral artery", "vessel", "leg_l", Vector3(0.10, 0.80, 0.03), Vector3(0.01, 0.12, 0.01), {bleed = 40.0}],
	"femoral_r": ["right femoral artery", "vessel", "leg_r", Vector3(-0.10, 0.80, 0.03), Vector3(0.01, 0.12, 0.01), {bleed = 40.0}],
	"tibia_l": ["left tibia", "bone", "leg_l", Vector3(0.165, 0.29, 0.015), Vector3(0.015, 0.2, 0.018), {limb = "leg_l", gel = 3.0}],
	"tibia_r": ["right tibia", "bone", "leg_r", Vector3(-0.165, 0.29, 0.015), Vector3(0.015, 0.2, 0.018), {limb = "leg_r", gel = 3.0}],
}


## Organs crossed by the path `from` -> `from + dir * length` (world space) through
## hitbox `hb`, in the order they're reached. Each: {id, name, kind, zone, at_mm
## (distance along the path where it enters), chord_mm, extra}.
static func trace(hb: Hitbox, from: Vector3, dir: Vector3, length_m: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hb == null or not hb.has_anatomy or length_m <= 0.0:
		return out
	var inv := hb.global_transform.affine_inverse()
	var a: Vector3 = hb.to_rig * (inv * from)
	var b: Vector3 = hb.to_rig * (inv * (from + dir * length_m))
	return trace_rig(a, b, length_m)


## Same, with the path already in rig space (`length_m` = its real length, for at_mm).
static func trace_rig(a: Vector3, b: Vector3, length_m: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ORGANS:
		var o: Array = ORGANS[id]
		var hit := _segment_ellipsoid(a, b, o[3], o[4], o[5].get("shell", false))
		if hit.is_empty():
			continue
		out.append({id = id, name = o[0], kind = o[1], zone = o[2], at_mm = hit.t0 * length_m * 1000.0,
			chord_mm = (hit.t1 - hit.t0) * length_m * 1000.0, extra = o[5]})
	out.sort_custom(func(x, y): return x.at_mm < y.at_mm)
	return out


## Gel-equivalent millimetres the bones on a path add (bone is far denser than muscle).
static func bone_gel_mm(hits: Array[Dictionary]) -> float:
	var mm := 0.0
	for h in hits:
		if h.kind == "bone":
			var chord: float = minf(h.chord_mm, 12.0) if h.extra.get("shell", false) else h.chord_mm
			mm += chord * (float(h.extra.get("gel", 2.5)) - 1.0)
	return mm


## Entry/exit parameters (0..1) of segment a->b through an ellipsoid; {} if it misses.
## shell: hollow (the skull) - only the wall counts, so a path that starts inside still hits it.
static func _segment_ellipsoid(a: Vector3, b: Vector3, c: Vector3, r: Vector3, shell := false) -> Dictionary:
	var p := (a - c) / r
	var d := (b - a) / r
	var qa := d.dot(d)
	if qa < 1e-12:
		return {}
	var qb := 2.0 * p.dot(d)
	var qc := p.dot(p) - 1.0
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return {}
	var s := sqrt(disc)
	var t0 := (-qb - s) / (2.0 * qa)
	var t1 := (-qb + s) / (2.0 * qa)
	if t1 < 0.0 or t0 > 1.0:
		return {}
	if shell and t0 < 0.0 and t1 > 1.0:
		return {}
	return {t0 = maxf(t0, 0.0), t1 = minf(t1, 1.0)}


## The rig-space box each zone covers on a person (for mapping simple targets like
## the range dummies onto the anatomy). [centre, size]
const ZONE_BOXES := {
	"head": [Vector3(0, 1.70, 0.04), Vector3(0.17, 0.25, 0.22)],
	"thorax": [Vector3(0, 1.33, 0.0), Vector3(0.36, 0.30, 0.25)],
	"stomach": [Vector3(0, 1.035, 0.0), Vector3(0.34, 0.37, 0.22)],
	"arm_l": [Vector3(0.4325, 1.42, 0.0), Vector3(0.535, 0.10, 0.10)],
	"arm_r": [Vector3(-0.4325, 1.42, 0.0), Vector3(0.535, 0.10, 0.10)],
	"leg_l": [Vector3(0.14, 0.5, 0.0), Vector3(0.17, 0.86, 0.17)],
	"leg_r": [Vector3(-0.14, 0.5, 0.0), Vector3(0.17, 0.86, 0.17)],
}


## Local -> rig transform that stretches a box of `size` (centred on its own origin,
## facing +Z, +X = its left) over the person's `zone`. Hanging arms (box taller than
## wide) are turned onto the T-pose arm: shoulder at the top, inner side toward the body.
static func box_to_rig(zone: String, size: Vector3) -> Transform3D:
	var zb: Array = ZONE_BOXES[zone]
	var c: Vector3 = zb[0]
	var s: Vector3 = zb[1]
	if zone.begins_with("arm") and size.y > size.x:
		var side := 1.0 if zone == "arm_l" else -1.0
		var k := s.x / size.y
		# local x (toward/away from the body) -> rig y; local y (down the arm) -> rig x.
		return Transform3D(Basis(Vector3(0, side * s.y / size.x, 0), Vector3(-side * k, 0, 0), Vector3(0, 0, s.z / size.z)), c)
	return Transform3D(Basis.from_scale(s / size), c)


# ------------------------------------------------------------------ x-ray (debug view)

const XRAY_COLORS := {cns = Color(1.0, 0.6, 0.8), cord = Color(1.0, 1.0, 0.5), heart = Color(0.9, 0.05, 0.1),
	vessel = Color(0.95, 0.15, 0.15), lung = Color(1.0, 0.55, 0.6), organ = Color(0.55, 0.25, 0.2), bone = Color(0.95, 0.93, 0.85)}


## Show (or hide) the organs and bones inside these hitboxes, seen through the body.
## Built the first time it's asked for; each organ goes in the hitbox that contains its centre.
static func set_xray(hitboxes: Array, on: bool) -> void:
	for hb: Hitbox in hitboxes:
		if not is_instance_valid(hb) or not hb.has_anatomy:
			continue
		var holder := hb.get_node_or_null("XRay") as Node3D
		if holder == null:
			if not on:
				continue
			holder = _build_xray(hb)
		holder.visible = on


static func _build_xray(hb: Hitbox) -> Node3D:
	var holder := Node3D.new()
	holder.name = "XRay"
	hb.add_child(holder)
	var half := Vector3.ONE * 0.1
	for c in hb.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			half = ((c as CollisionShape3D).shape as BoxShape3D).size / 2.0 + Vector3.ONE * 0.005
	var inv := hb.to_rig.affine_inverse()
	for id: String in ORGANS:
		var o: Array = ORGANS[id]
		if o[5].get("shell", false):
			continue   # the skull would hide the brain
		var local: Vector3 = inv * (o[3] as Vector3)
		if absf(local.x) > half.x or absf(local.y) > half.y or absf(local.z) > half.z:
			continue
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.height = 2.0
		sph.radial_segments = 12
		sph.rings = 6
		mi.mesh = sph
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
		m.render_priority = 2
		var col: Color = XRAY_COLORS.get(o[1], Color.WHITE)
		m.albedo_color = Color(col.r, col.g, col.b, 0.75)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = inv * Transform3D(Basis.from_scale(o[4]), o[3])
		mi.name = id
		holder.add_child(mi)
	return holder
