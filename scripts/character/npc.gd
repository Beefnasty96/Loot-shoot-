class_name Npc
extends Node3D
## A non-player person: a CharacterModel with hitboxes on its bones, a
## DamageModel and gear with things in the pockets. When killed it falls and
## the body can be searched (A): its worn gear and everything stored in it.
## AI comes later; for now they stand still.
##
## Getting shot: each hit hands the body the momentum the bullet lost plus a
## share of the energy it dumped. Alive, the struck part flinches and the
## person staggers, scaled by how heavy they are (body + gear). Dead, they go
## limp as a ragdoll and the push goes into the part that was hit, so a
## hollow point that stops in the chest shoves harder than ball ammo that
## passes through.
##
## Bleeding: each hit opens a wound (DamageModel) that bleeds onto their clothes
## and drips onto the floor, pooling where they stand or lie. As blood runs low
## they sag; at 40% lost they collapse and die.

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
var _stagger := Vector3.ZERO      ## Sideways shove velocity while alive (m/s).

## How much the deposited energy adds to the push, kg·m/s per joule. Real bullet momentum
## alone barely moves a body; the extra stands in for the involuntary flinch/collapse.
const ENERGY_PUSH := 0.02


func _ready() -> void:
	model = CharacterModel.new()
	add_child(model)
	add_to_group("npc")
	_build_hitboxes()
	damage.set_body_mass(model.body_mass_kg())


## New random person: looks, clothes and pocket contents.
func randomize_person(rng: RandomNumberGenerator) -> void:
	model.appearance.randomize(rng)
	model.apply_appearance()
	damage.set_body_mass(model.body_mass_kg())
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
		hb.bone_name = h[1]
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = h[3]
		cs.shape = shape
		hb.add_child(cs)
		# Placed in rest pose (rig space), expressed in the bone's frame so it follows the bone.
		hb.transform = sk.get_bone_global_rest(bone).affine_inverse() * Transform3D(Basis(), h[2])
		att.add_child(hb)
		_hitboxes.append(hb)


func _process(delta: float) -> void:
	_bleed(delta)
	if dead or _stagger.length_squared() < 1e-6:
		return
	model.position += _stagger * delta
	_stagger = _stagger.move_toward(Vector3.ZERO, 5.0 * delta)


func _physics_process(delta: float) -> void:
	if not dead and _stagger == Vector3.ZERO and model.position != Vector3.ZERO:
		model.position = model.position.move_toward(Vector3.ZERO, 0.2 * delta)   # step back into place


## Push (kg·m/s) a hit gives this body.
static func hit_impulse(info: Dictionary) -> float:
	return float(info.get("momentum", 0.0)) + float(info.get("deposited", 0.0)) * ENERGY_PUSH


func _bleed(delta: float) -> void:
	if damage.wounds.is_empty():
		return
	var before: Array[float] = []
	for w: Dictionary in damage.wounds:
		before.append(w.lost)
	damage.tick(delta)
	for i in damage.wounds.size():
		var w: Dictionary = damage.wounds[i]
		var ml: float = w.lost - before[i]
		if ml <= 0.0:
			continue
		Ballistics.blood.grow_stain(w)
		w.drip_acc = w.get("drip_acc", 0.0) + ml
		if w.drip_acc >= maxf(1.5, w.rate * 0.25):
			var marks: Array = w.get("marks", [])
			var from: Vector3 = (marks[0] as Node3D).global_position if not marks.is_empty() and is_instance_valid(marks[0]) else model.centre_world()
			# Running blood drips off a little out from the body, not from inside it.
			Ballistics.blood.drip(from + Vector3(randf_range(-0.04, 0.04), 0.0, randf_range(-0.04, 0.04)), w.drip_acc)
			w.drip_acc = 0.0
	if dead:
		return
	# Low on blood: they sag at the knees, then collapse.
	var lost := 1.0 - damage.blood_fraction()
	model.crouch = clampf((lost - 0.2) / 0.2, 0.0, 1.0) * 0.8
	if damage.dead:
		die()


func take_hit(info: Dictionary) -> void:
	var dir: Vector3 = info.get("direction", -global_transform.basis.z)
	var push := hit_impulse(info)
	var wound := DamageModel.make_wound(info)
	damage.add_wound(wound)
	Ballistics.blood.hit(info, wound)
	info.bleed = ("ARTERIAL BLEED " if wound.heavy else "bleed ") + "%.1f ml/s" % wound.rate
	if dead:
		model.apply_ragdoll_impulse(dir * push, info.position, info.bone)
		return
	damage.apply(info.zone, info.damage)
	if damage.dead:
		die(dir * push, info.position, info.bone)
		return
	# Flinch: the struck part reacts by its own mass (an arm jerks more than a chest).
	# Stagger: the whole body, so lighter people (and lighter loads) get moved more.
	model.react(info.zone, dir, clampf(push / model.segment_mass_kg(info.bone) * 1.5, 0.05, 1.5))
	var mass := model.total_mass_kg()
	var flat := Vector3(dir.x, 0.0, dir.z)
	_stagger += global_transform.basis.inverse() * flat * (push / mass) * 8.0


func die(impulse := Vector3.ZERO, at := Vector3.ZERO, bone := "") -> void:
	dead = true
	model.move_speed = 0.0
	model.start_ragdoll(impulse, at, bone)   # hitboxes stay on, so the body still takes shots
	add_to_group("interactable")


## Where the body actually is (the ragdoll can slide away from where they stood).
func interact_point() -> Vector3:
	return model.centre_world()


func prompt() -> String:
	return "A: search body" if dead else ""


func use(p: Player) -> void:
	if dead:
		p.get_tree().call_group("hud", "open_inventory", self)
