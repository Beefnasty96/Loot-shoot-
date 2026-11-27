class_name Melee
extends RefCounted
## Blade contact: finds what a stab or slash touches and turns it into a hit.
##
## A stab drives the blade in with the thrust's energy (about 60 J for a hard
## thrust from a standing man); clothing over the spot soaks some of it up,
## ribs can deflect the point and the skull stops it, so depth varies. A slash
## cuts as deep as the edge bites (about 2 cm into bare skin, much less through
## a jacket) along 9-19 cm of skin. DamageModel.make_blade_wound turns depth and
## length into damage and bleeding. Used by the player's Ka-Bar and, later, by
## knife-armed enemies.

const MASK := 1 | 4 | 32   ## World, hitboxes, doors.
## Cut/stab resistance of clothing, in joules of thrust it soaks up (slashes lose 2.5 mm per joule).
const CUT_RESIST := {tshirt = 2.0, jacket = 8.0, vest = 6.0, pants = 3.0, gloves = 4.0, cap = 1.0, beanie = 1.5, boots = 12.0, backpack = 0.0}
## Which worn slots cover each zone.
const COVER := {
	head = ["head"], thorax = ["torso_inner", "torso_outer", "vest"], stomach = ["torso_inner", "torso_outer", "vest"],
	arm_l = ["torso_outer"], arm_r = ["torso_outer"], leg_l = ["legs"], leg_r = ["legs"],
}


static func cloth_resist(eq: Equipment, zone: String) -> float:
	if eq == null:
		return 0.0
	var r := 0.0
	for slot: String in COVER.get(zone, []):
		var g := eq.get_slot(slot)
		if g:
			r += CUT_RESIST.get(g.item.id, 2.0)
	return r


## First thing any of the rays touches. rays: Array of [from, to].
static func sweep(space: PhysicsDirectSpaceState3D, rays: Array, exclude: Array[RID]) -> Dictionary:
	var best := {}
	var best_d := INF
	for r: Array in rays:
		var q := PhysicsRayQueryParameters3D.create(r[0], r[1], MASK)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var d: float = (r[0] as Vector3).distance_to(hit.position)
			if d < best_d:
				best_d = d
				best = hit
	return best


## Resolve a blade contact into an info dictionary and hand it to whatever was hit.
## dir = blade travel direction; cut_dir = the line the edge draws (slash) or the blade's width (stab).
static func strike(hit: Dictionary, kind: String, blade: BladeDef, strength: float, dir: Vector3, cut_dir: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var col: Object = hit.collider
	var info := {
		weapon = "blade", kind = kind, result = kind, blade = blade,
		position = hit.position, normal = hit.normal, direction = dir, cut_dir = cut_dir,
		collider = col, zone = "", bone = "", material = "",
		damage = 0.0, deposited = 0.0, momentum = 0.0, energy_out = 0.0,
		exit_pos = null, wound_ratio = 1.0, depth_mm = 0.0, length_mm = 0.0, neck = false,
	}
	if col is Node and (col as Node).has_meta("material"):
		info.material = (col as Node).get_meta("material")
	if col is Hitbox:
		var hb := col as Hitbox
		info.zone = hb.zone
		info.bone = hb.bone_name
		var eq: Equipment = null
		if hb.receiver and "model" in hb.receiver and hb.receiver.model is CharacterModel:
			eq = (hb.receiver.model as CharacterModel).equipment
		var cloth := cloth_resist(eq, hb.zone)
		info.cloth_j = cloth
		if kind == "stab":
			var e := blade.stab_energy * strength * rng.randf_range(0.85, 1.1)
			var depth := minf(blade.length_mm, maxf(0.0, e - cloth) * 3.0)
			if hb.zone == "thorax" and rng.randf() < 0.25:
				depth *= 0.35                        # point skids off a rib
			elif hb.zone == "head":
				info.neck = rng.randf() < 0.5
				if not info.neck:
					depth = minf(depth, 12.0)       # skull stops it
			info.depth_mm = depth
			info.momentum = 10.0 * strength
		else:
			info.depth_mm = clampf(blade.slash_depth_mm * strength * rng.randf_range(0.8, 1.15) - cloth * 2.5, 1.5, 30.0)
			info.length_mm = rng.randf_range(90.0, 190.0) * clampf(strength, 0.6, 1.3)
			info.momentum = 5.0 * strength
		# Organs and bones the blade reaches: straight in for a stab, just under the skin for a slash.
		var into: Vector3 = dir if kind == "stab" else -(hit.normal as Vector3)
		info.organs = Anatomy.trace(hb, hit.position, into.normalized(), info.depth_mm / 1000.0).filter(
			func(h): return h.kind != "bone")   # a blade nicks bone, it doesn't break it
		var wound := DamageModel.make_blade_wound(info, rng)   # also sets info.damage
		info.wound = wound
		info.bleed = ("ARTERIAL BLEED " if wound.heavy else "bleed ") + "%.1f ml/s" % wound.rate
		if hb.receiver and hb.receiver.has_method("take_hit"):
			hb.receiver.take_hit(info)
	Ballistics.melee_impact.emit(info)
	return info
