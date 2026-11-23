class_name Npc
extends Node3D
## A non-player person: a CharacterModel with hitboxes on its bones, a
## DamageModel and gear with things in the pockets. When killed it falls and
## the body can be searched (A): its worn gear and everything stored in it.
## AI comes later; for now they stand still.

const HITBOXES := [
	# zone, bone, centre (rest pose, rig space: +Z forward, +X = their left), size, gel factor
	["head", "Head", Vector3(0, 1.70, 0.04), Vector3(0.17, 0.25, 0.22), 1.3],
	["thorax", "UpperChest", Vector3(0, 1.33, 0.0), Vector3(0.36, 0.30, 0.25), 1.1],
	["stomach", "Spine", Vector3(0, 1.08, 0.0), Vector3(0.32, 0.24, 0.22), 1.0],
	["stomach", "Hips", Vector3(0, 0.92, 0.0), Vector3(0.34, 0.14, 0.22), 1.0],
	["arm_l", "LeftUpperArm", Vector3(0.30, 1.43, 0.0), Vector3(0.27, 0.10, 0.10), 1.0],
	["arm_l", "LeftLowerArm", Vector3(0.57, 1.415, 0.0), Vector3(0.26, 0.08, 0.08), 1.0],
	["arm_r", "RightUpperArm", Vector3(-0.30, 1.43, 0.0), Vector3(0.27, 0.10, 0.10), 1.0],
	["arm_r", "RightLowerArm", Vector3(-0.57, 1.415, 0.0), Vector3(0.26, 0.08, 0.08), 1.0],
	["leg_l", "LeftUpperLeg", Vector3(0.12, 0.715, 0.0), Vector3(0.15, 0.43, 0.17), 1.0],
	["leg_l", "LeftLowerLeg", Vector3(0.165, 0.29, 0.0), Vector3(0.12, 0.42, 0.13), 1.0],
	["leg_r", "RightUpperLeg", Vector3(-0.12, 0.715, 0.0), Vector3(0.15, 0.43, 0.17), 1.0],
	["leg_r", "RightLowerLeg", Vector3(-0.165, 0.29, 0.0), Vector3(0.12, 0.42, 0.13), 1.0],
]
const LOOT := [  # id, weight
	["cash", 25], ["painkillers", 15], ["water", 10], ["beans", 10], ["ifak", 5], ["docs", 3],
	["gold", 1], ["gpu", 3], ["mag", 6], ["rounds", 8],
]

var model: CharacterModel
var damage := DamageModel.new()
var dead := false
var title := "Body"
var _hitboxes: Array[Hitbox] = []


func _ready() -> void:
	model = CharacterModel.new()
	add_child(model)
	add_to_group("npc")
	_build_hitboxes()


## New random person: looks, clothes and pocket contents.
func randomize_person(rng: RandomNumberGenerator) -> void:
	model.appearance.randomize(rng)
	model.apply_appearance()
	model.random_outfit(rng)
	var total := 0
	for l: Array in LOOT:
		total += l[1]
	for i in rng.randi_range(1, 4):
		var roll := rng.randi() % total
		for l: Array in LOOT:
			roll -= l[1]
			if roll < 0:
				var it: InvItem
				var loads := AmmoDB.all_for(".45 ACP")
				match l[0]:
					"mag":
						it = InvItem.magazine(loads[rng.randi() % loads.size()], rng.randi_range(0, 7))
					"rounds":
						it = InvItem.rounds(loads[rng.randi() % loads.size()].id, rng.randi_range(5, 25))
					_:
						it = InvItem.create(l[0])
				model.equipment.store(it)
				break


func _build_hitboxes() -> void:
	var sk := model.skeleton
	for h: Array in HITBOXES:
		var bone := sk.find_bone(h[1])
		if bone < 0:
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = h[1]
		sk.add_child(att)
		var hb := Hitbox.new()
		hb.zone = h[0]
		hb.gel_factor = h[4]
		hb.receiver = self
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = h[3]
		cs.shape = shape
		hb.add_child(cs)
		# Placed in rest pose (rig space), expressed in the bone's frame so it follows the bone.
		hb.transform = sk.get_bone_global_rest(bone).affine_inverse() * Transform3D(Basis(), h[2])
		att.add_child(hb)
		_hitboxes.append(hb)


func take_hit(info: Dictionary) -> void:
	if dead:
		return
	damage.apply(info.zone, info.damage)
	if damage.dead:
		die()


func die() -> void:
	dead = true
	for hb in _hitboxes:
		hb.collision_layer = 0
	# Fall onto the back. (Ragdolls come later.)
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", PI / 2.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(model, "position:y", 0.13, 0.45)
	model.move_speed = 0.0
	add_to_group("interactable")


func prompt() -> String:
	return "A: search body" if dead else ""


func use(p: Player) -> void:
	if dead:
		p.get_tree().call_group("hud", "open_inventory", self)
