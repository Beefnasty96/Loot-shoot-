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
	apply_appearance()
	_apply_layers(self)


# ------------------------------------------------------------------ appearance + gear

func apply_appearance() -> void:
	if _body_mat == null:
		return
	_body_mat.set_shader_parameter("skin_tone", appearance.skin_tone)
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
	if skeleton == null:
		return
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

	for i in n:
		var p := _parent[i]
		var pg: Transform3D = G[p] if p >= 0 else Transform3D.IDENTITY
		var neutral: Transform3D = pg * _rest_local[i]
		var want := neutral
		var name := skeleton.get_bone_name(i)
		var side := 1.0 if name.begins_with("Left") else -1.0

		if name == "Hips":
			want.origin.y -= drop + absf(sin(_phase)) * 0.02 * speed_k
		elif name == "Spine":
			want = _rot(neutral, Vector3.RIGHT, crouch * 0.25)
		elif name == "UpperChest":
			var pitch := aim_pitch * (0.45 if pose_mode == PoseMode.PISTOL else 0.15)
			want = _rot(neutral, Vector3.LEFT, pitch)
		elif name == "Head":
			want = _rot(neutral, Vector3.LEFT, aim_pitch * 0.4)
		elif name.ends_with("UpperLeg"):
			var hip := neutral.origin
			var knee_i := _b(name.replace("Upper", "Lower"))
			var foot_i := _b(name.replace("UpperLeg", "Foot"))
			var ankle := _rest_global[foot_i].origin
			var swing := sin(_phase + (0.0 if side > 0 else PI))
			ankle.z += swing * 0.2 * speed_k
			ankle.y += maxf(0.0, -cos(_phase + (0.0 if side > 0 else PI))) * 0.07 * speed_k
			ankle.x += side * crouch * 0.06
			var l1 := _child_dir[i].length()
			var l2 := _child_dir[knee_i].length()
			var knee := _two_bone(hip, ankle, l1, l2, Vector3(side * 0.15, 0.0, 1.0))
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
				target = sh + Vector3(side * 0.07, -0.49, 0.05 + swing)
				pole = Vector3(side * 0.3, 0.0, -1.0)
				hand_dir = Vector3(side * 0.1, -1.0, 0.15)
			var elbow := _two_bone(sh, target, l1, l2, pole)
			want = _aim(neutral, i, elbow - sh)
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
