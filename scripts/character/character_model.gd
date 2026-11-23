class_name CharacterModel
extends Node3D
## A person: the shared base body + Appearance (skin, hair, eyes, height) +
## Equipment (worn gear). Faces -Z like the player.
##
## Gear visuals:
## - SKINNED items: their meshes are moved onto this character's Skeleton3D.
##   Skin binds are by bone name, so any item built on the base rig fits.
## - RIGID items: mounted on a BoneAttachment3D (offset by the bone's rest pose,
##   since they were modelled in rest-pose space).
## Body regions an item covers are hidden.
##
## Pose: procedural until we have animations. Two-bone IK for arms and legs
## (hands to a pistol grip or hanging, feet planted with a simple walk cycle),
## crouch, aim pitch through the spine and head, finger curl.
##
## Physics: every human has a mass (from height) plus the weight of what they
## wear and carry, spread over 14 ragdoll bodies by real body-segment
## proportions. Hits make the struck part flinch (alive) or push the ragdoll
## (dead); start_ragdoll() hands the body over to physics.

const BODY_SCENE := preload("res://assets/characters/base/body.glb")
const BODY_SHADER := preload("res://shaders/body.gdshader")
const CLOTH_SHADER := preload("res://shaders/cloth.gdshader")
const MASKS_A := preload("res://assets/characters/base/textures/body_masks_a.png")
const MASKS_B := preload("res://assets/characters/base/textures/body_masks_b.png")

enum PoseMode { IDLE, PISTOL }

var equipment := Equipment.new()
var appearance := Appearance.new()
var skeleton: Skeleton3D
var regions: Dictionary = {}       ## region name -> MeshInstance3D
var layers := 1:
	set(v):
		layers = v
		_apply_layers(self)

# Pose inputs (set every frame by whoever drives this character).
var pose_mode: PoseMode = PoseMode.IDLE
var aim_pitch := 0.0               ## Radians, positive = looking up.
var move_speed := 0.0              ## m/s
var crouch := 0.0                  ## 0..1
var grip_right: Node3D             ## World-space wrist targets for PoseMode.PISTOL.
var grip_left: Node3D
var grip_point: Node3D             ## What the hands wrap around (pistol grip centre).

var _root: Node3D
var _body_mat: ShaderMaterial
var _visuals: Dictionary = {}      ## slot -> Array[Node]
var _bone: Dictionary = {}
var _rest_local: Array[Transform3D] = []
var _rest_global: Array[Transform3D] = []
var _parent: PackedInt32Array = []
var _child_dir: Array[Vector3] = []
var _phase := 0.0

# ---- wounded body language (set by Npc from its DamageModel; all 0..1)
var hurt := {leg_l = 0.0, leg_r = 0.0, arm_l = 0.0, arm_r = 0.0, torso = 0.0, head = 0.0}
var pain := 0.0                    ## Fast breathing, hunching, trembling.
var shock := 0.0                   ## Blood loss: head droops, skin goes pale.
var kneel := 0.0                   ## Down on one knee (the hurt leg).
var sit := 0.0                     ## Down on the ground, propped on one arm.
var clutch: Node3D                 ## A wound to press a hand on (world position), or null.
var _clutch_k := 0.0
var _t := 0.0
var _pale := -1.0

# ---- ragdoll / mass
## Body-segment share of mass (Dempster / Winter tables), collision radius, cone swing, twist.
## Bones not listed (Chest, Neck, hands, fingers, toes) ride on their parent.
const RAGDOLL := [
	["Hips", 0.142, 0.11, 0.0, 0.0],
	["Spine", 0.139, 0.12, 20.0, 15.0],
	["UpperChest", 0.216, 0.14, 20.0, 15.0],
	["Head", 0.081, 0.10, 40.0, 30.0],
	["LeftUpperArm", 0.028, 0.045, 80.0, 40.0],
	["LeftLowerArm", 0.022, 0.04, 75.0, 5.0],
	["RightUpperArm", 0.028, 0.045, 80.0, 40.0],
	["RightLowerArm", 0.022, 0.04, 75.0, 5.0],
	["LeftUpperLeg", 0.100, 0.07, 60.0, 15.0],
	["LeftLowerLeg", 0.0465, 0.055, 75.0, 5.0],
	["LeftFoot", 0.0145, 0.045, 25.0, 5.0],
	["RightUpperLeg", 0.100, 0.07, 60.0, 15.0],
	["RightLowerLeg", 0.0465, 0.055, 75.0, 5.0],
	["RightFoot", 0.0145, 0.045, 25.0, 5.0],
]
## Which ragdoll bodies carry the weight of gear in each slot.
const GEAR_LOAD := {
	head = ["Head"], face = ["Head"], torso_inner = ["Spine", "UpperChest"], torso_outer = ["Spine", "UpperChest"],
	vest = ["UpperChest"], back = ["UpperChest"], belt = ["Hips"], hands = ["LeftLowerArm", "RightLowerArm"],
	legs = ["Hips", "LeftUpperLeg", "RightUpperLeg"], feet = ["LeftFoot", "RightFoot"], accessory = ["LeftLowerArm"],
}
const RAGDOLL_LAYER := 16   ## Physics layer 5: ragdolls collide with the world and each other, bullets use hitboxes.
var ragdoll_active := false
var _sim: PhysicalBoneSimulator3D
var _pbones: Dictionary = {}      ## bone name -> PhysicalBone3D
## Hit reaction springs: region -> [axis (rig space), angle, angular velocity]
var _react: Dictionary = {}


func _ready() -> void:
	_root = Node3D.new()
	_root.rotation.y = PI          # the rig faces +Z; the game faces -Z
	add_child(_root)
	var body := BODY_SCENE.instantiate()
	_root.add_child(body)
	skeleton = body.find_children("*", "Skeleton3D", true, false)[0]
	for c in skeleton.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Body_"):
			regions[String(c.name).substr(5)] = c
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = BODY_SHADER
	_body_mat.set_shader_parameter("masks_a", MASKS_A)
	_body_mat.set_shader_parameter("masks_b", MASKS_B)
	for mi: MeshInstance3D in regions.values():
		mi.material_override = _body_mat
	equipment.changed.connect(_on_equipment_changed)
	_cache_skeleton()
	_build_ragdoll()
	apply_appearance()
	_apply_layers(self)


# ------------------------------------------------------------------ appearance + gear

func apply_appearance() -> void:
	if _body_mat == null:
		return
	update_ragdoll_masses()
	_body_mat.set_shader_parameter("skin_tone", appearance.skin_tone)
	_pale = -1.0
	_body_mat.set_shader_parameter("hair_color", appearance.hair_color)
	_body_mat.set_shader_parameter("eye_color", appearance.eye_color)
	_body_mat.set_shader_parameter("underwear_color", appearance.underwear_color)
	_body_mat.set_shader_parameter("scalp_hair", appearance.scalp_hair)
	_body_mat.set_shader_parameter("beard", appearance.beard)
	_body_mat.set_shader_parameter("brows", appearance.brows)
	_root.scale = Vector3.ONE * appearance.height


## Random civilian clothes from the catalogue.
func random_outfit(rng: RandomNumberGenerator) -> void:
	var pick := func(id: String) -> GearInstance:
		var it := GearDB.get_item(id)
		return GearInstance.create(id, rng.randi() % maxi(1, it.colors.size()))
	if rng.randf() < 0.9:
		equipment.equip(pick.call("tshirt"))
	if rng.randf() < 0.4:
		equipment.equip(pick.call("jacket"))
	equipment.equip(pick.call("pants"))
	if rng.randf() < 0.95:
		equipment.equip(pick.call("boots"))
	if rng.randf() < 0.25:
		equipment.equip(pick.call("gloves"))
	var h := rng.randf()
	if h < 0.2:
		equipment.equip(pick.call("beanie"))
	elif h < 0.45:
		equipment.equip(pick.call("cap"))
	if rng.randf() < 0.15:
		equipment.equip(pick.call("vest"))
	if rng.randf() < 0.3:
		equipment.equip(pick.call("backpack"))


func _on_equipment_changed(slot: String) -> void:
	update_ragdoll_masses()
	for n: Node in _visuals.get(slot, []):
		if is_instance_valid(n):
			n.queue_free()
	_visuals.erase(slot)
	var g := equipment.get_slot(slot)
	if g:
		_visuals[slot] = _build_visual(g)
	var hidden := equipment.hidden_regions()
	for r: String in regions:
		regions[r].visible = not hidden.has(r)


func refresh_slot(slot: String) -> void:
	_on_equipment_changed(slot)


func _build_visual(g: GearInstance) -> Array[Node]:
	var item := g.item
	var mat := ShaderMaterial.new()
	mat.shader = CLOTH_SHADER
	if ResourceLoader.exists(item.texture_path):
		mat.set_shader_parameter("detail", load(item.texture_path))
	mat.set_shader_parameter("main_color", g.color())
	mat.set_shader_parameter("accent_color", item.accent)
	mat.set_shader_parameter("roughness", item.roughness)
	var out: Array[Node] = []
	var scene: Node = (load(item.scene_path) as PackedScene).instantiate()
	if item.kind == GearItem.Kind.SKINNED:
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			mi.get_parent().remove_child(mi)
			skeleton.add_child(mi)
			mi.transform = Transform3D.IDENTITY
			mi.skeleton = mi.get_path_to(skeleton)
			mi.material_override = mat
			out.append(mi)
		scene.free()
	else:
		var att := BoneAttachment3D.new()
		att.bone_name = item.attach_bone
		skeleton.add_child(att)
		var holder := Node3D.new()
		holder.transform = skeleton.get_bone_global_rest(skeleton.find_bone(item.attach_bone)).affine_inverse()
		att.add_child(holder)
		holder.add_child(scene)
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
		out.append(att)
	for n in out:
		_apply_layers(n)
	return out


func _apply_layers(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		_apply_layers(c)


# ------------------------------------------------------------------ pose

func _cache_skeleton() -> void:
	var n := skeleton.get_bone_count()
	_rest_local.resize(n)
	_rest_global.resize(n)
	_child_dir.resize(n)
	_parent.resize(n)
	for i in n:
		_bone[skeleton.get_bone_name(i)] = i
		_rest_local[i] = skeleton.get_bone_rest(i)
		_parent[i] = skeleton.get_bone_parent(i)
		_rest_global[i] = skeleton.get_bone_global_rest(i)
		_child_dir[i] = Vector3.ZERO
	for i in n:
		var p := _parent[i]
		if p >= 0 and _child_dir[p] == Vector3.ZERO:
			_child_dir[p] = _rest_local[i].origin
	for i in n:
		if _child_dir[i] == Vector3.ZERO:  # leaf: continue the parent's direction
			var p := _parent[i]
			var d := _rest_global[i].origin - _rest_global[p].origin if p >= 0 else Vector3.UP
			_child_dir[i] = _rest_global[i].basis.inverse() * d.normalized() * 0.03


func _b(name: String) -> int:
	return _bone.get(name, -1)


## Rotate a bone so its rest direction points along `dir` (skeleton space).
func _aim(neutral: Transform3D, i: int, dir: Vector3) -> Transform3D:
	var d := (neutral.basis * _child_dir[i]).normalized()
	var t := dir.normalized()
	if d.dot(t) > 0.99999:
		return neutral
	return Transform3D(Basis(Quaternion(d, t)) * neutral.basis, neutral.origin)


func _rot(neutral: Transform3D, axis: Vector3, angle: float) -> Transform3D:
	return Transform3D(Basis(axis.normalized(), angle) * neutral.basis, neutral.origin)


## Two-bone IK: returns the elbow/knee position.
func _two_bone(a: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var d := target - a
	var dist := clampf(d.length(), 0.01, l1 + l2 - 0.001)
	var dn := d.normalized()
	var along := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var pp := (pole - dn * pole.dot(dn)).normalized()
	return a + dn * along + pp * h


func _process(delta: float) -> void:
	if skeleton == null or ragdoll_active:
		return
	for k: String in _react:
		var r: Array = _react[k]
		r[2] += (-r[1] * 180.0 - r[2] * 16.0) * delta    # stiff, well-damped spring: a sharp flinch
		r[1] += r[2] * delta
	_t += delta
	_clutch_k = move_toward(_clutch_k, 1.0 if clutch and is_instance_valid(clutch) else 0.0, delta * 2.5)
	if _body_mat and absf(shock - _pale) > 0.02:
		_pale = shock
		var c := appearance.skin_tone
		var lum := c.get_luminance()
		_body_mat.set_shader_parameter("skin_tone", c.lerp(Color(lum * 1.05, lum * 1.02, lum * 1.08), shock * 0.7).lightened(shock * 0.08))
	var speed_k := clampf(move_speed / 3.2, 0.0, 1.8)
	_phase = fmod(_phase + delta * (2.0 + move_speed * 2.2) * (1.0 if move_speed > 0.2 else 0.0), TAU)
	_pose(speed_k)


func _pose(speed_k: float) -> void:
	var n := _rest_local.size()
	var G: Array[Transform3D] = []
	G.resize(n)
	var to_skel := skeleton.global_transform.affine_inverse()
	var pending := {}   # bone -> desired direction (computed by IK at the chain root)
	var curl := 1.25 if pose_mode == PoseMode.PISTOL else 0.35
	var drop := crouch * 0.42
	# Wounded: favour the worse leg, hunch over torso wounds, breathe hard, go down.
	var hips_y := _rest_global[_b("Hips")].origin.y
	var limp: float = maxf(hurt.leg_l, hurt.leg_r)
	var bad := 1.0 if hurt.leg_l >= hurt.leg_r else -1.0       # side of the worse leg (+1 = their left)
	var standing := (1.0 - kneel) * (1.0 - sit)
	drop += limp * 0.03 * standing
	drop = lerpf(drop, hips_y - 0.55, kneel * (1.0 - sit))
	drop = lerpf(drop, hips_y - 0.17, sit)
	var hunch: float = clampf(hurt.torso * 0.45 + pain * 0.15 + shock * 0.15, 0.0, 0.6) * (1.0 - sit * 0.5)
	var breath := sin(_t * lerpf(1.6, 4.5, maxf(pain, shock))) * 0.03 * (0.3 + pain)
	var tremble := (sin(_t * 31.0) * 0.5 + sin(_t * 47.0) * 0.5) * 0.012 * maxf(pain - 0.3, shock)
	var clutch_skel := to_skel * clutch.global_position if clutch and is_instance_valid(clutch) else Vector3.ZERO
	var clutch_side := 0.0
	if _clutch_k > 0.0:
		clutch_side = 1.0 if clutch_skel.x >= 0.0 else -1.0
		var arm_on := "arm_l" if clutch_side > 0 else "arm_r"
		if hurt[arm_on] > 0.4 or clutch_skel.distance_to(_rest_global[_b("LeftUpperArm" if clutch_side > 0 else "RightUpperArm")].origin) < 0.45:
			clutch_side = -clutch_side   # use the other hand on a wounded arm or shoulder

	for i in n:
		var p := _parent[i]
		var pg: Transform3D = G[p] if p >= 0 else Transform3D.IDENTITY
		var neutral: Transform3D = pg * _rest_local[i]
		var want := neutral
		var name := skeleton.get_bone_name(i)
		var side := 1.0 if name.begins_with("Left") else -1.0

		if name == "Hips":
			var buckle := (_react_angle("leg_l") + _react_angle("leg_r")) * 0.25
			want.origin.y -= drop + absf(sin(_phase)) * 0.02 * speed_k + absf(buckle)
			want.origin.x -= bad * limp * 0.05 * standing         # weight onto the good leg
			want = _rot(want, Vector3.FORWARD, bad * limp * 0.07 * standing)
			want = _rot(want, Vector3.RIGHT, -0.25 * sit)          # sitting: pelvis rolls back
		elif name == "Spine":
			want = _rot(neutral, Vector3.RIGHT, crouch * 0.25 + hunch * 0.55 + sit * 0.2)
			want = _apply_react(want, "torso", 0.4)
		elif name == "UpperChest":
			var pitch := aim_pitch * (0.45 if pose_mode == PoseMode.PISTOL else 0.15)
			want = _rot(neutral, Vector3.LEFT, pitch - hunch * 0.45 - breath)
			if clutch_side != 0.0:
				want = _rot(want, Vector3.FORWARD, -clutch_side * 0.12 * _clutch_k * (hurt.torso + 0.3))   # curl toward the wound
			want = _apply_react(want, "torso", 0.6)
		elif name == "Head":
			want = _rot(neutral, Vector3.LEFT, aim_pitch * 0.4 - shock * 0.55 - hurt.head * 0.2 + tremble)
			want = _rot(want, Vector3.FORWARD, hurt.head * 0.15 + tremble)
			want = _apply_react(want, "head", 1.0)
		elif name.ends_with("UpperLeg"):
			var hip := neutral.origin
			var knee_i := _b(name.replace("Upper", "Lower"))
			var foot_i := _b(name.replace("UpperLeg", "Foot"))
			var ankle := _rest_global[foot_i].origin
			var swing := sin(_phase + (0.0 if side > 0 else PI))
			ankle.z += swing * 0.2 * speed_k
			ankle.y += maxf(0.0, -cos(_phase + (0.0 if side > 0 else PI))) * 0.07 * speed_k
			ankle.x += side * crouch * 0.06
			var pole := Vector3(side * 0.15, 0.0, 1.0)
			var mine: float = hurt.leg_l if side > 0 else hurt.leg_r
			# Favour a hurt leg: weight off it, foot lifted onto the toes and a little forward.
			ankle += Vector3(0.0, 0.05, 0.06) * mine * standing
			var rest_ankle := _rest_global[foot_i].origin
			if kneel > 0.0:   # down on the bad knee, the other foot planted forward
				var k_target := rest_ankle + (Vector3(0.0, 0.06, -0.42) if side == bad else Vector3(side * 0.03, 0.0, 0.34))
				ankle = ankle.lerp(k_target, kneel * (1.0 - sit))
				pole = pole.lerp(Vector3(side * 0.1, 0.6, 1.0), kneel)
			if sit > 0.0:     # on the ground, legs out in front, knees up a bit
				ankle = ankle.lerp(rest_ankle + Vector3(side * 0.08, 0.0, 0.7 if side == bad else 0.55), sit)
				pole = pole.lerp(Vector3(side * 0.3, 1.0, 0.4), sit)
			var l1 := _child_dir[i].length()
			var l2 := _child_dir[knee_i].length()
			var knee := _two_bone(hip, ankle, l1, l2, pole)
			want = _aim(neutral, i, knee - hip)
			pending[knee_i] = ankle - knee
			pending[foot_i] = "flat"
		elif name.ends_with("UpperArm"):
			var sh := neutral.origin
			var low_i := _b(name.replace("Upper", "Lower"))
			var hand_i := _b(name.replace("UpperArm", "Hand"))
			var l1 := _child_dir[i].length()
			var l2 := _child_dir[low_i].length()
			var target: Vector3
			var pole: Vector3
			var hand_dir: Vector3
			var grip: Node3D = grip_left if side > 0 else grip_right
			if pose_mode == PoseMode.PISTOL and grip:
				target = to_skel * grip.global_position
				pole = Vector3(side * 0.7, -1.0, -0.2)
				var centre := to_skel * (grip_point.global_position if grip_point else grip.global_position)
				hand_dir = (centre - target) + (centre - sh).normalized() * 0.04
			else:
				var swing := sin(_phase + (PI if side > 0 else 0.0)) * 0.12 * speed_k
				var limp_arm: float = hurt.arm_l if side > 0 else hurt.arm_r
				target = sh + Vector3(side * 0.07, -0.49, 0.05 + swing * (1.0 - limp_arm))
				target = target.lerp(sh + Vector3(side * 0.03, -0.54, -0.03), clampf(limp_arm * 1.5, 0.0, 1.0))  # hangs dead
				pole = Vector3(side * 0.3, 0.0, -1.0)
				hand_dir = Vector3(side * 0.1, -1.0, 0.15)
				if sit > 0.0 and side != clutch_side:   # propped up on this hand
					target = target.lerp(Vector3(side * 0.32, 0.04, -0.22), sit)
					hand_dir = hand_dir.lerp(Vector3(side * 0.2, -0.3, -1.0), sit)
				if side == clutch_side:                 # pressing on the wound
					var press := clutch_skel + (clutch_skel - Vector3(0.0, clutch_skel.y, 0.0)).normalized() * 0.03
					target = target.lerp(press, _clutch_k)
					pole = pole.lerp(Vector3(side * 0.8, -0.6, -0.6), _clutch_k)
					hand_dir = hand_dir.lerp((Vector3(0.0, clutch_skel.y, 0.0) - clutch_skel).normalized() + Vector3(0, -0.3, 0), _clutch_k)
				target += Vector3(tremble, tremble * 0.5, 0.0)
			var elbow := _two_bone(sh, target, l1, l2, pole)
			want = _aim(neutral, i, elbow - sh)
			want = _apply_react(want, "arm_l" if side > 0 else "arm_r", 1.0)
			pending[low_i] = target - elbow
			pending[hand_i] = hand_dir
		elif pending.has(i):
			var v = pending[i]
			if v is String:   # keep the foot flat on the ground
				want = Transform3D(_rest_global[i].basis, neutral.origin)
			else:
				want = _aim(neutral, i, v)
		elif name.contains("Index") or name.contains("Middle") or name.contains("Ring") or name.contains("Little") or name.contains("Thumb"):
			var hand := G[_b(("Left" if side > 0 else "Right") + "Hand")]
			var palm_down := (hand.basis * (_rest_global[_b(("Left" if side > 0 else "Right") + "Hand")].basis.inverse() * Vector3.DOWN)).normalized()
			var d := (neutral.basis * _child_dir[i]).normalized()
			var axis := d.cross(palm_down)
			if axis.length() > 0.01:
				var amount := curl * (0.35 if name.contains("Thumb") else (0.8 if name.ends_with("Proximal") else 1.0))
				want = _rot(neutral, axis, amount * 0.75)
		G[i] = want
		var local := pg.affine_inverse() * want
		skeleton.set_bone_pose_position(i, local.origin)
		skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())


# ------------------------------------------------------------------ mass, reactions, ragdoll

## Body mass from height (78 kg at 1.0 scale, cube law), without gear.
func body_mass_kg() -> float:
	return 78.0 * pow(appearance.height, 3.0)


## Body plus everything worn and carried.
func total_mass_kg() -> float:
	return body_mass_kg() + equipment.total_weight()


## Mass of the ragdoll body a bone belongs to (kg).
func segment_mass_kg(bone: String) -> float:
	var pb: PhysicalBone3D = _pbones.get(_ragdoll_body_for(bone))
	return pb.mass if pb else 20.0


## Flinch: the hit part rotates away from the shot. `strength` ~0.2 (graze) to ~1.5 (big dump of energy).
func react(zone: String, dir_world: Vector3, strength: float) -> void:
	var region := zone
	if zone == "thorax" or zone == "stomach":
		region = "torso"
	var dir_rig := (skeleton.global_transform.basis.inverse() * dir_world).normalized()
	var axis := Vector3.UP.cross(dir_rig)       # tilt the top of the part along the shot
	if region.begins_with("arm"):
		axis = Vector3.FORWARD.cross(dir_rig) if axis.length() < 0.1 else axis
	if axis.length() < 0.01:
		axis = Vector3.RIGHT
	var r: Array = _react.get(region, [axis.normalized(), 0.0, 0.0])
	r[0] = axis.normalized()
	r[2] += strength * (9.0 if region == "head" else 6.0)
	_react[region] = r


func _react_angle(region: String) -> float:
	return _react[region][1] if _react.has(region) else 0.0


func _apply_react(t: Transform3D, region: String, share: float) -> Transform3D:
	if not _react.has(region):
		return t
	var r: Array = _react[region]
	if absf(r[1]) < 0.0005:
		return t
	return _rot(t, r[0], r[1] * share)


func _build_ragdoll() -> void:
	_sim = PhysicalBoneSimulator3D.new()
	skeleton.add_child(_sim)
	var parent_of := {}
	for row: Array in RAGDOLL:
		parent_of[row[0]] = true
	for row: Array in RAGDOLL:
		var bname: String = row[0]
		var bi := skeleton.find_bone(bname)
		if bi < 0:
			continue
		var d := _child_dir[bi]                    # bone direction in its own space
		var length := maxf(d.length(), 0.08)
		var pb := PhysicalBone3D.new()
		pb.bone_name = bname
		pb.name = "Ragdoll_" + bname
		# Body centred halfway down the bone, its -Z along the bone (Godot's convention).
		var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var body := Transform3D(Basis.looking_at(d.normalized(), up), d * 0.5)
		pb.body_offset = body
		pb.joint_offset = Transform3D(Basis(), Vector3(0, 0, length * 0.5))
		if bname == "Hips":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		else:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", row[3])
			pb.set("joint_constraints/twist_span", row[4])
		pb.linear_damp = 0.15
		pb.angular_damp = 2.5
		pb.friction = 0.8
		pb.collision_layer = RAGDOLL_LAYER
		pb.collision_mask = 1 | RAGDOLL_LAYER
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = row[2]
		cap.height = maxf(length + row[2] * 0.5, row[2] * 2.0 + 0.01)
		cs.shape = cap
		cs.rotation.x = PI / 2.0                   # capsule Y -> body Z (along the bone)
		pb.add_child(cs)
		_sim.add_child(pb)
		_pbones[bname] = pb
	update_ragdoll_masses()


## Spread body mass by segment share, then add each worn item's weight (and contents) to the parts that carry it.
func update_ragdoll_masses() -> void:
	var m := body_mass_kg()
	for row: Array in RAGDOLL:
		if _pbones.has(row[0]):
			(_pbones[row[0]] as PhysicalBone3D).mass = m * row[1]
	for slot: String in equipment.worn:
		var g: GearInstance = equipment.worn[slot]
		var kg := g.item.weight_kg
		for grid: InvGrid in g.grids:
			kg += grid.content_weight()
		var parts: Array = GEAR_LOAD.get(slot, ["UpperChest"])
		for part: String in parts:
			if _pbones.has(part):
				(_pbones[part] as PhysicalBone3D).mass += kg / parts.size()


## Hand the body to physics (death). Optionally push the part that was hit.
func start_ragdoll(impulse := Vector3.ZERO, at_world := Vector3.ZERO, bone := "") -> void:
	if ragdoll_active:
		return
	update_ragdoll_masses()
	ragdoll_active = true
	_sim.physical_bones_start_simulation()
	if impulse != Vector3.ZERO:
		# Let the bodies spawn at the current pose first, then push.
		await get_tree().physics_frame
		apply_ragdoll_impulse(impulse, at_world, bone)


func apply_ragdoll_impulse(impulse: Vector3, at_world: Vector3, bone: String) -> void:
	var pb: PhysicalBone3D = _pbones.get(_ragdoll_body_for(bone))
	if pb == null:
		pb = _pbones.get("UpperChest")
	if pb:
		pb.apply_impulse(impulse, at_world - pb.global_position)


## Nearest simulated body for any bone (e.g. Neck -> Head's parent chain).
func _ragdoll_body_for(bone: String) -> String:
	var bi := skeleton.find_bone(bone)
	while bi >= 0:
		var n := skeleton.get_bone_name(bi)
		if _pbones.has(n):
			return n
		bi = skeleton.get_bone_parent(bi)
	return "UpperChest"


## Centre of the body (follows the ragdoll once it's simulating).
func centre_world() -> Vector3:
	var pb: PhysicalBone3D = _pbones.get("Spine")
	return pb.global_position if pb and ragdoll_active else global_position + Vector3.UP * 1.0
