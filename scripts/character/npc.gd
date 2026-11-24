class_name Npc
extends CharacterBody3D
## A non-player person: a CharacterModel with hitboxes on its bones, a
## DamageModel and gear with things in the pockets. When killed it falls and
## the body can be searched (A): its worn gear and everything stored in it.
## On its own an Npc stands still (the range civilians); Enemy adds a brain and a gun.
## The capsule (layer 2) is for moving and blocking; bullets and blades use the hitboxes.
##
## Getting shot: each hit hands the body the momentum the bullet lost plus a
## share of the energy it dumped. Alive, the struck part flinches and the
## person staggers, scaled by how heavy they are (body + gear). Dead, they go
## limp as a ragdoll and the push goes into the part that was hit, so a
## hollow point that stops in the chest shoves harder than ball ammo that
## passes through.
##
## Bleeding: each hit opens a wound (DamageModel) that bleeds onto their clothes
## and drips onto the floor, pooling where they stand or lie. At 40% lost they die.
##
## Wounded but alive, they show it: limp off a hurt leg, a shot arm hangs, a hand
## presses on the worst wound, they hunch over torso wounds and breathe hard, go
## pale and droop as they lose blood, and go down on a knee or onto the ground
## when a leg gives out or they're close to passing out. Once down they stay down.

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
var pain := 0.0                   ## Spikes when hit, settles to what the wounds justify.
var _kneel_target := 0.0
var _sit_target := 0.0

## How much the deposited energy adds to the push, kg·m/s per joule. Real bullet momentum
## alone barely moves a body; the extra stands in for the involuntary flinch/collapse.
const ENERGY_PUSH := 0.02


const RADIUS := 0.3
const HEIGHT := 1.75


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 2 | 32   # world, other people, doors
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	cs.position.y = HEIGHT / 2.0
	add_child(cs)
	model = CharacterModel.new()
	add_child(model)
	add_to_group("npc")
	_hitboxes = build_hitboxes(model, self)
	damage.set_body_mass(model.body_mass_kg())


## RIDs of this person's own hitboxes (so their own shots don't hit themselves).
func hitbox_rids() -> Array[RID]:
	var out: Array[RID] = []
	for hb in _hitboxes:
		out.append(hb.get_rid())
	return out


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


## Hitboxes on a CharacterModel's bones, reporting hits to `receiver` (take_hit). Used by Npc and Player.
static func build_hitboxes(model: CharacterModel, receiver: Node) -> Array[Hitbox]:
	var out: Array[Hitbox] = []
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
		hb.receiver = receiver
		hb.bone_name = h[1]
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = h[3]
		cs.shape = shape
		hb.add_child(cs)
		# Placed in rest pose (rig space), expressed in the bone's frame so it follows the bone.
		hb.transform = sk.get_bone_global_rest(bone).affine_inverse() * Transform3D(Basis(), h[2])
		att.add_child(hb)
		out.append(hb)
	return out


func _process(delta: float) -> void:
	_bleed(delta)
	_act_wounded(delta)
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
		if w.heavy and not dead and w.rate > 0.0:   # arterial: pumps with the heartbeat
			w.spurt_t = w.get("spurt_t", 0.0) - delta
			if w.spurt_t <= 0.0:
				w.spurt_t = 0.75
				var m: Array = w.get("marks", [])
				if not m.is_empty() and is_instance_valid(m[0]):
					var mk := m[0] as Node3D
					Ballistics.blood.spurt(mk.global_position, mk.global_transform.basis.y.normalized(), w.rate)
		w.drip_acc = w.get("drip_acc", 0.0) + ml
		if w.drip_acc >= maxf(1.5, w.rate * 0.25):
			var marks: Array = w.get("marks", [])
			var from: Vector3 = (marks[0] as Node3D).global_position if not marks.is_empty() and is_instance_valid(marks[0]) else model.centre_world()
			# Running blood drips off a little out from the body, not from inside it.
			Ballistics.blood.drip(from + Vector3(randf_range(-0.04, 0.04), 0.0, randf_range(-0.04, 0.04)), w.drip_acc)
			w.drip_acc = 0.0
	if damage.dead and not dead:
		die()


## Body language for wounds: drives CharacterModel's hurt/pain/shock/kneel/sit/clutch.
func _act_wounded(delta: float) -> void:
	if dead or (damage.wounds.is_empty() and pain <= 0.0):
		return
	var h := model.hurt
	for z in ["leg_l", "leg_r", "arm_l", "arm_r", "head"]:
		h[z] = move_toward(h[z], damage.hurt(z), delta * 2.0)
	h.torso = move_toward(h.torso, maxf(damage.hurt("thorax"), damage.hurt("stomach")), delta * 2.0)
	var shock := damage.shock()
	var base := clampf((h.torso + h.head + maxf(h.leg_l, h.leg_r) + maxf(h.arm_l, h.arm_r)) * 0.5, 0.0, 0.8)
	pain = move_toward(pain, base, delta * 0.15)
	model.pain = pain
	model.shock = move_toward(model.shock, shock, delta * 0.5)
	# Going down: a leg that gives out or nearly passing out puts them on a knee; worse puts them on the ground.
	var legs_bad: float = maxf(h.leg_l, h.leg_r)
	if legs_bad >= 0.7 or shock > 0.45 or h.torso > 0.65:
		_kneel_target = 1.0
	if minf(h.leg_l, h.leg_r) >= 0.5 or damage.hp.leg_l <= 0.0 or damage.hp.leg_r <= 0.0 or shock > 0.7 or h.torso > 0.85:
		_sit_target = 1.0
	model.kneel = move_toward(model.kneel, _kneel_target, delta * 1.8)
	model.sit = move_toward(model.sit, _sit_target, delta * 1.2)
	# Press a hand on the worst wound (the model picks which hand).
	var worst: Dictionary = {}
	var score := 0.0
	for w: Dictionary in damage.wounds:
		if w.zone.begins_with("leg") and model.kneel + model.sit < 0.5:
			continue   # can't reach a thigh wound standing up
		var s: float = w.rate + (8.0 if w.zone in ["thorax", "stomach"] else 0.0) + (3.0 if w.heavy else 0.0)
		if s > score and not w.get("marks", []).is_empty():
			score = s
			worst = w
	model.clutch = worst.marks[0] if not worst.is_empty() and is_instance_valid(worst.marks[0]) else null


func take_hit(info: Dictionary) -> void:
	var dir: Vector3 = info.get("direction", -global_transform.basis.z)
	var push := hit_impulse(info)
	var wound: Dictionary = info.wound if info.has("wound") else DamageModel.make_wound(info)
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
	pain = clampf(pain + info.damage / 40.0, 0.0, 1.0)
	var mass := model.total_mass_kg()
	var flat := Vector3(dir.x, 0.0, dir.z)
	_stagger += global_transform.basis.inverse() * flat * (push / mass) * 8.0


func die(impulse := Vector3.ZERO, at := Vector3.ZERO, bone := "") -> void:
	dead = true
	collision_layer = 0           # the ragdoll takes over; nothing to bump into
	collision_mask = 0
	velocity = Vector3.ZERO
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
