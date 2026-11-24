class_name WeaponDB
extends RefCounted
## Every gun, knife and attachment, as data. Adding a gun = an entry in WEAPONS
## (plus its model); adding a part = an entry in PARTS (plus its model).
##
## Attachments work like Tarkov: a weapon has named SLOTS; each slot accepts part
## TYPES; a part can bring SLOTS of its own (a threaded barrel brings a muzzle
## slot, a rail adapter brings a tactical slot), so the build is a tree.
## Magazines plug into a slot too (accepting a magazine FAMILY), which is how one
## gun can take 7- and 8-round mags and a rifle later takes any STANAG mag.
##
## Weapon fields:
##   name, kind (pistol/rifle/smg/shotgun/knife), slot (primary/sidearm/melee),
##   caliber, action (semi/auto/bolt/pump), modes, rpm, barrel_in (inches; the
##   ammo data is measured from a 5 in pistol barrel), weight (kg, bare), size
##   (grid squares), ergo (0-100: aim speed, sway), recoil (1.0 = a 1911 with ball),
##   moa (mechanical accuracy), scene (model), sound, slots, rig (how it's handled
##   and animated: see RIG_DEFAULTS).
## Slot fields: accepts (part types or a magazine family), required (gun won't work
##   without it; can only be swapped), default (part id it comes with), at
##   (attach point in gun space, for parts modelled around their own mount), parent
##   (model node the part rides on, e.g. "Slide").
## Part fields: name, type, weight, size_add (extra squares the gun takes up), ergo,
##   recoil (fraction: -0.1 = 10% less), barrel_in, loudness (1 = unsuppressed),
##   ads (aim speed multiplier), glow (tritium sights), light ({range, energy,
##   angle}), length (m added at the muzzle), flash (false = hides muzzle flash),
##   sound (replaces the gunshot), scene (model; "" = part of the base model),
##   on_mount (modelled around its mount point -> placed at the slot's `at`),
##   slots (slots this part brings), description.

const WEAPONS := {
	"m1911": {
		name = "M1911A1", kind = "pistol", slot = "sidearm", caliber = ".45 ACP", action = "semi", modes = ["semi"], rpm = 0,
		barrel_in = 5.0, weight = 0.98, size = Vector2i(2, 1), ergo = 60, recoil = 1.0, moa = 3.0,
		scene = "res://assets/weapons/m1911/m1911.glb", sound = "shot_45", value = 600,
		description = "Government model .45. Drop parts or a magazine on it, or Y to open it up.",
		slots = {
			barrel = {accepts = ["barrel_1911"], required = true, default = "barrel_1911_gi", parent = "Slide"},
			grips = {accepts = ["grips_1911"], required = true, default = "grips_1911_walnut"},
			sights = {accepts = ["sights_1911"], required = true, default = "sights_1911_gi", parent = "Slide"},
			mount = {accepts = ["mount_1911"]},
			magazine = {accepts = ["mag_1911"], magazine = true},
		},
	},
	"m4a1": {
		name = "M4A1 carbine", kind = "rifle", slot = "primary", caliber = "5.56 NATO", action = "auto", modes = ["semi", "auto"], rpm = 800,
		barrel_in = 14.5, weight = 2.95, size = Vector2i(5, 2), ergo = 52, recoil = 1.0, moa = 1.5,   # barrel; ammo adds its own (M855: ~3.4 MOA total)
		scene = "res://assets/weapons/m4a1/m4a1.glb", sound = "shot_556", value = 1800,
		description = "14.5 in select-fire carbine: flat-top upper with a detachable carry handle, quad rail. Hold Y for semi / auto.",
		rig = {
			anim = "rifle", travel = 0.075, cycle = 0.062, reload = 2.3, reload_empty = 2.7, mag_axis = Vector3(0.0, -0.99, -0.12),
			mag_drop = 0.26, zero_m = 45.72, zero_ammo = "556_1_m193", casing = Vector2(0.0048, 0.045), flash = 0.16,
			recoil_k = 0.42, view_kick = 0.12, bloom = 0.22, sight_hold = 0.06, hip_spread = 1.2, aim_fov = 55.0, auto_climb = 0.85,
			view = {
				hip = Vector3(0.12, -0.145, -0.27), hip_rot = Vector3(1.5, 2.5, -5.0),
				aim = Vector3(0.0, -0.0649, -0.2128), sprint = Vector3(0.06, -0.16, -0.291), sprint_rot = Vector3(-24.0, 40.0, 14.0),
				reload_pos = Vector3(-0.05, 0.06, -0.05), reload_rot = Vector3(8.0, 12.0, -38.0), kick_pos = Vector3(0.0, 0.004, 0.035), kick_rot = 5.0,
				arms = "res://assets/viewmodels/arms/arms_rifle.glb",
			},
			tp = {pos = Vector3(0.08, -0.12, -0.36), grip = Vector3(0.0, -0.078, 0.156), right = Vector3(0.018, -0.081, 0.199), left = Vector3(-0.03, -0.046, -0.116)},
		},
		slots = {
			handguard = {accepts = ["handguard_m4"], required = true, default = "rail_m4_quad"},
			stock = {accepts = ["stock_m4"], required = true, default = "stock_m4_6pos"},
			rear_sight = {accepts = ["rsight_m4"], required = true, default = "carry_m4"},
			muzzle = {accepts = ["muzzle_556"], required = true, default = "fh_a2"},
			magazine = {accepts = ["stanag"], magazine = true},
		},
	},
	"kabar": {
		name = "USMC Ka-Bar", kind = "knife", slot = "melee", weight = 0.45, size = Vector2i(3, 1), ergo = 80, value = 80,
		scene = "res://assets/weapons/kabar/kabar.glb", description = "7 in clip-point fighting knife, with its leather sheath.",
		slots = {},
	},
}

const PARTS := {
	# --- 1911 barrels
	"barrel_1911_gi": {name = "1911 GI barrel, 5 in", type = "barrel_1911", weight = 0.15, barrel_in = 5.0, scene = "", size = Vector2i(2, 1),
		description = "The standard barrel. Not threaded."},
	"barrel_1911_threaded": {name = "1911 threaded barrel, 5.5 in", type = "barrel_1911", weight = 0.17, barrel_in = 5.5, size = Vector2i(2, 1),
		scene = "res://assets/weapons/parts/barrel_1911_threaded.glb", value = 220,
		description = "Stainless, 0.578-28 thread. Takes a suppressor.",
		slots = {muzzle = {accepts = ["muzzle_45"], at = Vector3(0.0, 0.0, -0.141), parent = "Slide"}}},
	# --- muzzle devices
	"supp_45": {name = ".45 suppressor", type = "muzzle_45", weight = 0.28, size = Vector2i(2, 1), size_add = Vector2i(1, 0),
		loudness = 0.3, recoil = -0.12, ergo = -10, length = 0.188, flash = false, sound = "shot_45_supp", on_mount = true,
		scene = "res://assets/weapons/parts/supp_45.glb", value = 700,
		description = "Subsonic .45 is quiet through a can: about 30% as loud, no flash. Heavy on the front."},
	# --- grips
	"grips_1911_walnut": {name = "1911 rosewood grips", type = "grips_1911", weight = 0.05, scene = "", size = Vector2i(1, 1),
		description = "Double-diamond checkered rosewood, the stock grips."},
	"grips_1911_rubber": {name = "1911 wraparound rubber grips", type = "grips_1911", weight = 0.06, ergo = 6, recoil = -0.06, size = Vector2i(1, 1),
		scene = "res://assets/weapons/parts/grips_1911_rubber.glb", value = 40,
		description = "Finger grooves, soaks up some kick."},
	# --- sights
	"sights_1911_gi": {name = "1911 GI sights", type = "sights_1911", weight = 0.01, scene = "", size = Vector2i(1, 1),
		description = "Small fixed blade and notch."},
	"sights_1911_night": {name = "1911 tritium night sights", type = "sights_1911", weight = 0.012, ergo = 4, ads = 1.15, glow = true, size = Vector2i(1, 1),
		scene = "res://assets/weapons/parts/sights_1911_night.glb", value = 120,
		description = "Three glowing dots. Faster to line up, readable in the dark."},
	# --- mounts and tactical devices
	"rail_1911": {name = "1911 dust-cover rail adapter", type = "mount_1911", weight = 0.09, ergo = -2, size = Vector2i(1, 1),
		scene = "res://assets/weapons/parts/rail_1911.glb", value = 45,
		description = "Clamps under the frame. Adds a rail for a light.",
		slots = {tactical = {accepts = ["tactical_rail"], at = Vector3(0.0, -0.036, -0.065)}}},
	# --- M4 furniture (part of the base model for now; the slots are there so optics,
	#     handguards, stocks and muzzle devices can be swapped in later).
	"rail_m4_quad": {name = "M4 quad rail (RIS)", type = "handguard_m4", weight = 0.29, scene = "", size = Vector2i(3, 1),
		description = "Four Picatinny rails round the barrel. Takes a light underneath.",
		slots = {tactical = {accepts = ["tactical_rail"], at = Vector3(0.0, -0.0304, -0.17)}}},
	"stock_m4_6pos": {name = "M4 six-position stock", type = "stock_m4", weight = 0.23, scene = "", size = Vector2i(2, 1),
		description = "Collapsible carbine stock, set at the fourth notch."},
	"carry_m4": {name = "M4 carry handle (rear sight)", type = "rsight_m4", weight = 0.25, scene = "", size = Vector2i(2, 1),
		description = "Detachable carry handle on the flat-top rail, with the flip rear aperture lined up with the A2 front sight post."},
	"fh_a2": {name = "A2 birdcage flash hider", type = "muzzle_556", weight = 0.06, scene = "", size = Vector2i(1, 1),
		description = "Slotted flash hider: keeps the flash out of your eyes, not quieter."},
	"light_m3": {name = "Weapon light (M3-style)", type = "tactical_rail", weight = 0.12, ergo = -3, size = Vector2i(1, 1), on_mount = true,
		light = {range = 28.0, energy = 7.0, angle = 20.0}, scene = "res://assets/weapons/parts/light_m3.glb", value = 150,
		description = "D-pad down turns it on. Lights up dark rooms - and you."},
}

## Magazines (items in ItemDB with mag_family): family -> calibre, for reference.
const MAG_FAMILIES := {"mag_1911": ".45 ACP", "stanag": "5.56 NATO"}

## How a gun is handled and animated (a weapon's `rig` overrides these; the 1911's are the defaults).
##   anim: "pistol" (Slide/Hammer) or "rifle" (Bolt carrier, ChargingHandle, DustCover, Selector)
##   travel: m the slide/bolt runs back; cycle: s for one cycle; reload(_empty): s
##   mag_axis / mag_drop: direction (gun space) and distance the magazine comes out
##   zero_m / zero_ammo: where the sights cross the bullet path, for which load
##   casing: (radius, length) m; flash: muzzle flash size m
##   recoil_k: kick per unit of bullet momentum; view_kick: viewmodel jolt; bloom: spread added per shot
##   sight_hold: extra spread aimed (degrees); aim_fov: aimed field of view; auto_climb: muzzle climb kept in auto
##   view: first-person poses (gun-model origin relative to the camera) and arms model
##   tp: third-person hold: model offset from the head, and hand markers (gun space)
const RIG_DEFAULTS := {
	anim = "pistol", travel = 0.032, cycle = 0.075, reload = 1.7, reload_empty = 2.2, mag_axis = Vector3(0.0, -0.951, 0.309),
	mag_drop = 0.14, zero_m = 22.86, zero_ammo = "45_1_fmj230", casing = Vector2(0.006, 0.023), flash = 0.09,
	recoil_k = 0.72, view_kick = 1.0 / 3.8, bloom = 0.45, sight_hold = 0.12, hip_spread = 1.6, aim_fov = 50.0, auto_climb = 1.0,
	view = {
		hip = Vector3(0.072, -0.06, -0.215), hip_rot = Vector3(2.0, 4.0, -3.0), aim = Vector3(0.0, -0.0202, -0.40),
		sprint = Vector3(0.05, -0.15, -0.21), sprint_rot = Vector3(-38.0, 22.0, 12.0),
		reload_pos = Vector3(-0.02, 0.025, 0.03), reload_rot = Vector3(18.0, -10.0, 32.0), kick_pos = Vector3(0.0, 0.01, 0.05), kick_rot = 14.0,
		arms = "res://assets/viewmodels/arms/arms.glb",
	},
	tp = {pos = Vector3(0.1, -0.3, -0.45), grip = Vector3(0.0, -0.064, 0.057), right = Vector3(0.006, -0.085, 0.125), left = Vector3(-0.035, -0.1, 0.105)},
}


## A weapon's rig with the defaults filled in.
static func rig(weapon_id: String) -> Dictionary:
	var r := RIG_DEFAULTS.duplicate(true)
	var own: Dictionary = weapon(weapon_id).get("rig", {})
	for k: String in own:
		if own[k] is Dictionary and r.get(k) is Dictionary:
			(r[k] as Dictionary).merge(own[k], true)
		else:
			r[k] = own[k]
	return r


static func weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


static func part(id: String) -> Dictionary:
	return PARTS.get(id, {})


## The slot table of whatever an item is (a weapon or a part).
static func slots_of(item: InvItem) -> Dictionary:
	if item == null:
		return {}
	if item.def.weapon_id != "":
		return weapon(item.def.weapon_id).get("slots", {})
	if item.def.part_id != "":
		return part(item.def.part_id).get("slots", {})
	return {}


## Can `part_item` go into slot `slot_name` of `owner`?
static func accepts(owner: InvItem, slot_name: String, part_item: InvItem) -> bool:
	var s: Dictionary = slots_of(owner).get(slot_name, {})
	if s.is_empty() or part_item == null:
		return false
	if s.get("magazine", false):
		return part_item.def.is_mag() and part_item.def.mag_family in s.accepts
	return part_item.def.part_id != "" and part(part_item.def.part_id).type in s.accepts


## Fill a weapon's (or part's) slots with their default parts, recursively.
static func fill_defaults(item: InvItem) -> void:
	for slot_name: String in slots_of(item):
		var s: Dictionary = slots_of(item)[slot_name]
		if s.has("default") and not item.mods.has(slot_name):
			var p := InvItem.create(s.default)
			item.mods[slot_name] = p


## Every part in the tree (depth first), with the slot and owner it sits in.
static func walk(item: InvItem, out: Array = [], owner: InvItem = null, slot_name := "") -> Array:
	if owner != null:
		out.append({item = item, owner = owner, slot = slot_name})
	for sn: String in item.mods:
		walk(item.mods[sn], out, item, sn)
	return out


## Everything that the parts add up to.
static func stats(gun: InvItem) -> Dictionary:
	var w := weapon(gun.def.weapon_id)
	var st := {
		weight = float(w.get("weight", 0.0)), ergo = float(w.get("ergo", 50)), recoil = float(w.get("recoil", 1.0)),
		barrel_in = float(w.get("barrel_in", 5.0)), loudness = 1.0, ads = 1.0, glow = false, light = {}, length = 0.0,
		flash = true, sound = String(w.get("sound", "")), size = w.get("size", Vector2i(1, 1)), caliber = String(w.get("caliber", "")),
		moa = float(w.get("moa", 3.0)), working = true, missing = [],
	}
	var recoil_frac := 0.0
	for e: Dictionary in walk(gun):
		var it: InvItem = e.item
		if it.def.is_mag():
			continue
		var p := part(it.def.part_id)
		st.weight += float(p.get("weight", 0.0))
		st.ergo += float(p.get("ergo", 0.0))
		recoil_frac += float(p.get("recoil", 0.0))
		if p.has("barrel_in"):
			st.barrel_in = p.barrel_in
		st.loudness = minf(st.loudness, float(p.get("loudness", 1.0)))
		st.ads *= float(p.get("ads", 1.0))
		st.glow = st.glow or p.get("glow", false)
		if p.has("light"):
			st.light = p.light
		st.length += float(p.get("length", 0.0))
		if not p.get("flash", true):
			st.flash = false
		if p.has("sound"):
			st.sound = p.sound
		st.size += p.get("size_add", Vector2i.ZERO)
	st.recoil *= maxf(0.3, 1.0 + recoil_frac)
	st.ergo = clampf(st.ergo, 0.0, 100.0)
	# A required slot left empty: the gun doesn't work.
	for e: Dictionary in [{item = gun}] + walk(gun):
		var owner: InvItem = e.item
		var sl := slots_of(owner)
		for sn: String in sl:
			if sl[sn].get("required", false) and not owner.mods.has(sn):
				st.working = false
				st.missing.append(sn)
	return st


## Muzzle velocity multiplier for a barrel length, for a calibre's standard load.
## Each load knows its own reference barrel and fps-per-inch (AmmoType.velocity_factor):
## pistol calibres gain ~1.8% per inch around 5 in, 5.56 loses ~35 fps per inch under 20 in.
static func velocity_factor(barrel_in: float, caliber := ".45 ACP") -> float:
	var loads := AmmoDB.all_for(caliber)
	if loads.is_empty():
		return 1.0
	return loads[0].velocity_factor(barrel_in)


# ------------------------------------------------------------------ models

## Build the visual of a weapon's parts on its model `root` (an instance of its scene).
## Removes earlier part visuals first. Returns {muzzle: Node3D, light: Node3D or null}.
static func assemble(gun: InvItem, root: Node3D, layer := 1) -> Dictionary:
	for n in root.find_children("Part_*", "", true, false):
		n.get_parent().remove_child(n)
		n.queue_free()
	var model := root.get_child(0) as Node3D if root.get_child_count() > 0 else root
	var out := {muzzle = root.find_child("Muzzle", true, false), light = null}
	_attach(gun, gun, root, model, Vector3.ZERO, layer, out)
	return out


static func _attach(gun: InvItem, owner: InvItem, root: Node3D, model: Node3D, base: Vector3, layer: int, out: Dictionary) -> void:
	var sl := slots_of(owner)
	for sn: String in owner.mods:
		var it: InvItem = owner.mods[sn]
		var s: Dictionary = sl.get(sn, {})
		if it.def.is_mag():
			continue
		var p := part(it.def.part_id)
		var parent_node: Node3D = model
		if s.has("parent"):
			var pn := root.find_child(s.parent, true, false) as Node3D
			if pn:
				parent_node = pn
		var at: Vector3 = base + (s.get("at", Vector3.ZERO) as Vector3)
		var scene_path: String = p.get("scene", "")
		if scene_path != "" and ResourceLoader.exists(scene_path):
			var inst: Node3D = (load(scene_path) as PackedScene).instantiate()
			inst.name = "Part_" + it.def.part_id
			parent_node.add_child(inst)
			# Parts on a moving model node (the slide) are modelled in gun space: undo that node's rest offset.
			inst.position = (at if p.get("on_mount", false) else Vector3.ZERO)
			_layers(inst, layer)
			if p.has("light"):
				var spot := SpotLight3D.new()
				spot.name = "Part_beam"
				spot.light_color = Color(1.0, 0.96, 0.86)
				spot.light_energy = p.light.energy
				spot.spot_range = p.light.range
				spot.spot_angle = p.light.angle
				spot.spot_attenuation = 1.2
				spot.shadow_enabled = false
				spot.visible = false
				spot.position = Vector3(0, -0.017, -0.045)
				inst.add_child(spot)
				out.light = spot
			if float(p.get("length", 0.0)) > 0.0:
				var tip := Node3D.new()
				tip.name = "Part_muzzle"
				tip.position = Vector3(0, 0, -float(p.length))
				inst.add_child(tip)
				out.muzzle = tip
		_attach(gun, it, root, model, at, layer, out)


static func _layers(n: Node, layer: int) -> void:
	if n is GeometryInstance3D:
		n.layers = layer
	for c in n.get_children():
		_layers(c, layer)
