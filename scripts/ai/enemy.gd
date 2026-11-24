class_name Enemy
extends Npc
## A hostile occupant: an Npc with eyes, ears, a weapon and a plan.
##
## Senses: a vision cone with line-of-sight checks (through glass, not walls or
## closed doors); awareness builds faster the closer and the more exposed you
## are. Gunshots are heard through walls (louder = closer); running footsteps
## carry a few metres. Bullets cracking close by make them take cover.
##
## States: IDLE / PATROL (relaxed, gun at low ready) -> SUSPICIOUS (turns toward
## the noise or glimpse) -> INVESTIGATE (walks to it) -> COMBAT (engages) ->
## COVER (breaks line of sight after being hit, pinned or reloading) -> SEARCH
## (goes to where they last saw you, then checks nearby rooms) -> back to IDLE.
## "Holders" stay put and cover a doorway; "pushers" come and find you.
##
## Shooting: a reaction delay when they first see you, then aimed shots whose
## error grows with distance, your movement, their own movement, and their
## wounds (hurt arms, blood loss, pain). They carry real magazines and reload.
## Knife enemies close the distance and stab/slash with the same blade model as
## yours. Wounded enemies limp and go down like anyone else; down on the floor
## they still shoot if their arms work. Doors on their path get opened.

enum State { IDLE, PATROL, SUSPICIOUS, INVESTIGATE, COMBAT, COVER, SEARCH }

const EYE := 1.6
const VIEW_RANGE := 30.0
const VIEW_COS_RELAXED := 0.45     ## ~127 deg cone
const VIEW_COS_ALERT := -0.1       ## nearly all round once alert
const WALK := 1.3
const MOVE := 2.2
const RUN := 4.0

var weapon := "pistol"             ## "pistol" or "knife"
var role := "holder"               ## "holder" holds a spot; "pusher" hunts
var post: Vector3                  ## Where they start / return to.
var post_facing := 0.0
var patrol: Array[Vector3] = []    ## Patrol points (empty = stand at post)
var state := State.IDLE
var awareness := 0.0               ## 0 unaware .. 1 engaged
var target: Node3D                 ## The player.
var last_known := Vector3.INF
var can_see_target := false

var ammo: AmmoType
var mag := 7
var chambered := true
var reloading := 0.0
var blade := BladeDef.kabar()

var agent: NavigationAgent3D
var aim: Node3D                    ## Pitch pivot at eye height; the gun hangs off it.
var gun: Node3D
var _aim_pitch := 0.0
var _yaw_target := 0.0
var _react := 0.0                  ## Seconds before the first shot after spotting.
var _shot_t := 0.0
var _burst := 0
var _flinch := 0.0
var _think := 0.0
var _state_t := 0.0
var _patrol_i := 0
var _cover_point := Vector3.INF
var _search_points: Array[Vector3] = []
var _melee_t := 0.0
var _melee_windup := -1.0
var _suppressed := 0.0
var _audio: AudioStreamPlayer3D
var _flash: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _hostile_rids: Array[RID] = []


func _ready() -> void:
	super._ready()
	add_to_group("enemy")
	title = "Hostile"
	_rng.randomize()
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.6
	agent.radius = RADIUS
	agent.height = HEIGHT
	agent.max_speed = RUN
	add_child(agent)
	aim = Node3D.new()
	aim.position.y = EYE
	add_child(aim)
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 12.0
	_audio.max_distance = 90.0
	add_child(_audio)
	Ballistics.gunshot.connect(_on_gunshot)
	Ballistics.impact.connect(_on_impact)
	post = global_position
	post_facing = rotation.y
	_yaw_target = rotation.y


## Arm and dress them. Call after adding to the tree.
func setup(rng: RandomNumberGenerator, with: String, as_role: String) -> void:
	weapon = with
	role = as_role
	randomize_person(rng)
	_hostile_rids = hitbox_rids()
	if weapon == "pistol":
		var loads := [AmmoDB.get_ammo("45_1_fmj230"), AmmoDB.get_ammo("45_2_jhp230"), AmmoDB.get_ammo("45_3_jhp185p")]
		ammo = loads[rng.randi() % loads.size()]
		mag = 7
		chambered = true
		for i in rng.randi_range(1, 2):            # spare magazines in their pockets (lootable)
			model.equipment.store(InvItem.magazine(ammo, 7))
		gun = (load("res://assets/weapons/m1911/m1911.glb") as PackedScene).instantiate()
		gun.position = Vector3(0.1, -0.3, -0.42)
		aim.add_child(gun)
		model.grip_point = _marker(gun, Vector3(0.0, -0.064, 0.057))
		model.grip_right = _marker(gun, Vector3(0.006, -0.085, 0.125))
		model.grip_left = _marker(gun, Vector3(-0.035, -0.1, 0.105))
		model.pose_mode = CharacterModel.PoseMode.PISTOL
		var path := "res://assets/audio/shot_45.wav"
		if ResourceLoader.exists(path):
			_audio.stream = load(path)
		_flash = OmniLight3D.new()
		_flash.light_color = Color(1.0, 0.8, 0.45)
		_flash.light_energy = 0.0
		_flash.omni_range = 4.0
		gun.add_child(_flash)
		_flash.position = Vector3(0, 0.0, -0.25)
	else:
		gun = (load(blade.scene_path) as PackedScene).instantiate()
		var holder := Node3D.new()
		holder.position = Vector3(0.2, -0.5, -0.35)
		holder.rotation_degrees = Vector3(-50.0, 15.0, -10.0)
		aim.add_child(holder)
		gun.position = -Knife.GRIP
		holder.add_child(gun)
		model.grip_right = holder
		model.pose_mode = CharacterModel.PoseMode.KNIFE
		var path := "res://assets/audio/knife_swish.wav"
		if ResourceLoader.exists(path):
			_audio.stream = load(path)
	if patrol.size() > 0:
		state = State.PATROL


func _marker(parent: Node3D, pos: Vector3) -> Node3D:
	var m := Node3D.new()
	m.position = pos
	parent.add_child(m)
	return m


# ------------------------------------------------------------------ per frame

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if dead:
		return
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node3D
	_state_t += delta
	_flinch = maxf(0.0, _flinch - delta)
	_suppressed = maxf(0.0, _suppressed - delta)
	_melee_t = maxf(0.0, _melee_t - delta)
	_think -= delta
	if _think <= 0.0:
		_think = 0.1
		_perceive(0.1)
		_decide()
	_act(delta)
	_move(delta)
	_turn(delta)


func _process(delta: float) -> void:
	super._process(delta)
	if dead:
		return
	if _flash and _flash.light_energy > 0.0:
		_flash.light_energy = maxf(0.0, _flash.light_energy - delta * 40.0)
	# Gun up when alert, low ready when relaxed.
	var alert := state in [State.COMBAT, State.COVER, State.SEARCH, State.INVESTIGATE]
	var want := _aim_pitch if alert else -0.55
	aim.rotation.x = lerp_angle(aim.rotation.x, want, minf(1.0, delta * 8.0))
	model.aim_pitch = aim.rotation.x
	model.move_speed = Vector2(velocity.x, velocity.z).length()


## Are they unable to fight back (both arms out, or blacked out)?
func incapacitated() -> bool:
	return damage.hurt("arm_l") >= 0.95 and damage.hurt("arm_r") >= 0.95 or damage.shock() > 0.92


func downed() -> bool:
	return model.sit > 0.4 or model.kneel > 0.6


# ------------------------------------------------------------------ senses

func _eye_pos() -> Vector3:
	return global_position + Vector3(0, EYE - model.sit * 1.0 - model.kneel * 0.45, 0)


## Line of sight from `from` to `to` through glass (but not walls or closed doors).
func _clear(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	ex.append_array(_hostile_rids)
	for _i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 32, ex)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		if BallisticMaterials.of(hit.collider) == "glass":
			ex.append((hit.collider as CollisionObject3D).get_rid())
			continue
		return false
	return false


func _target_points() -> Array[Vector3]:
	var p := target.global_position
	var crouch := 0.6 if ("crouching" in target and target.crouching) else 1.0
	return [p + Vector3(0, 1.55 * crouch, 0), p + Vector3(0, 1.15 * crouch, 0), p + Vector3(0, 0.6, 0)]


func _target_dead() -> bool:
	return target == null or ("vitals" in target and target.vitals and target.vitals.dead)


func _perceive(dt: float) -> void:
	can_see_target = false
	if _target_dead():
		awareness = move_toward(awareness, 0.0, dt * 0.2)
		return
	var eye := _eye_pos()
	var to_t: Vector3 = target.global_position + Vector3(0, 1.2, 0) - eye
	var dist := to_t.length()
	var fwd := -global_transform.basis.z
	var cone := VIEW_COS_ALERT if awareness > 0.5 else VIEW_COS_RELAXED
	if dist < VIEW_RANGE and (fwd.dot(to_t.normalized()) > cone or dist < 1.2):
		for pt in _target_points():
			if _clear(eye, pt):
				can_see_target = true
				break
	if can_see_target:
		var rate := clampf(7.0 / maxf(dist, 0.5), 0.35, 4.0)
		if "crouching" in target and target.crouching:
			rate *= 0.6
		if awareness > 0.3:
			rate *= 2.0
		var was := awareness
		awareness = minf(1.0, awareness + rate * dt)
		last_known = target.global_position
		if awareness >= 1.0 and was < 1.0:
			_react = _rng.randf_range(0.25, 0.6) * (1.6 - damage.steadiness() * 0.6)
	else:
		# Footsteps.
		var speed := Vector2(target.velocity.x, target.velocity.z).length() if "velocity" in target else 0.0
		var hear := 0.0
		if speed > 4.0:
			hear = 8.0
		elif speed > 1.0:
			hear = 3.5 if not ("crouching" in target and target.crouching) else 1.2
		if dist < hear:
			_notice(target.global_position, 0.45)
		awareness = move_toward(awareness, 0.0, dt * (0.05 if state == State.SEARCH else 0.12))


func _notice(where: Vector3, amount: float) -> void:
	awareness = maxf(awareness, minf(0.95, awareness + amount))
	last_known = where
	if state in [State.IDLE, State.PATROL]:
		_set_state(State.SUSPICIOUS)
	_face(where)


func _on_gunshot(origin: Vector3, shooter: RID) -> void:
	if dead or shooter == get_rid():
		return
	var d := origin.distance_to(global_position)
	if d > 45.0:
		return
	var player_shot := target != null and is_instance_valid(target) and shooter == (target as CollisionObject3D).get_rid()
	var where := origin if player_shot else origin
	# Close shots: they know roughly where; far/through walls: just which way.
	_notice(where, 0.9 if d < 12.0 else 0.6)
	if player_shot and d < 12.0:
		awareness = 1.0 if can_see_target else maxf(awareness, 0.95)


func _on_impact(info: Dictionary) -> void:
	if dead or info.collider is Hitbox and (info.collider as Hitbox).receiver == self:
		return
	# A round cracking past or smacking the wall next to them: get down.
	if (info.position as Vector3).distance_to(global_position + Vector3(0, 1.0, 0)) < 1.6:
		_suppressed = 2.5
		if state == State.COMBAT and weapon == "pistol" and _rng.randf() < 0.5:
			_set_state(State.COVER)


func take_hit(info: Dictionary) -> void:
	super.take_hit(info)
	if dead:
		return
	_flinch = 0.35 + info.damage / 60.0
	var from: Vector3 = global_position - (info.get("direction", Vector3.FORWARD) as Vector3) * 5.0
	last_known = target.global_position if target and is_instance_valid(target) else from
	awareness = 1.0
	_face(last_known)
	if weapon == "pistol" and not downed() and _rng.randf() < 0.65:
		_set_state(State.COVER)
	elif state != State.COMBAT:
		_set_state(State.COMBAT)


# ------------------------------------------------------------------ decisions

func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	_state_t = 0.0
	match s:
		State.COVER:
			_cover_point = _find_cover()
			if _cover_point != Vector3.INF:
				agent.target_position = _cover_point
		State.SEARCH:
			_search_points.clear()
			if last_known != Vector3.INF:
				_search_points.append(last_known)
			var level := get_parent()
			if level and "rooms" in level:
				var rs: Array = level.rooms.values()
				rs.sort_custom(func(a, b): return (a as Vector3).distance_to(last_known) < (b as Vector3).distance_to(last_known))
				for i in mini(3, rs.size()):
					_search_points.append(rs[i])
		State.INVESTIGATE:
			agent.target_position = last_known


func _decide() -> void:
	if _target_dead():
		if state in [State.COMBAT, State.COVER]:
			_set_state(State.SEARCH)
		return
	match state:
		State.IDLE, State.PATROL:
			if awareness >= 1.0:
				_set_state(State.COMBAT)
		State.SUSPICIOUS:
			if awareness >= 1.0:
				_set_state(State.COMBAT)
			elif _state_t > 2.0:
				if awareness > 0.4 and (role == "pusher" or awareness > 0.75):
					_set_state(State.INVESTIGATE)
				elif awareness < 0.15:
					_set_state(State.PATROL if patrol.size() > 0 else State.IDLE)
		State.INVESTIGATE:
			if awareness >= 1.0:
				_set_state(State.COMBAT)
			elif _arrived(last_known, 1.2) or _state_t > 15.0:
				_set_state(State.SEARCH)
		State.COMBAT:
			if not can_see_target and _state_t > 0.5:
				if awareness < 0.6:
					_set_state(State.SEARCH)
				elif weapon == "knife" or role == "pusher":
					agent.target_position = last_known
		State.COVER:
			if _state_t > _rng.randf_range(2.5, 4.5) and reloading <= 0.0:
				_set_state(State.COMBAT)
		State.SEARCH:
			if awareness >= 1.0:
				_set_state(State.COMBAT)
			elif _search_points.is_empty() or _state_t > 30.0:
				awareness = 0.3
				agent.target_position = post
				_set_state(State.PATROL if patrol.size() > 0 else State.IDLE)


func _act(delta: float) -> void:
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			_finish_reload()
	if state != State.COMBAT and state != State.COVER:
		return
	if incapacitated() or _target_dead():
		return
	if weapon == "pistol":
		_shoot_logic(delta)
	else:
		_melee_logic(delta)


func _shoot_logic(delta: float) -> void:
	if not can_see_target:
		return
	_face(target.global_position)
	var aim_at: Vector3 = _target_points()[1 if _rng.randf() < 0.75 else 0]
	var to := aim_at - aim.global_position
	_aim_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	if _react > 0.0:
		_react -= delta
		return
	if _flinch > 0.0 or reloading > 0.0 or absf(wrapf(rotation.y - _yaw_target, -PI, PI)) > 0.25:
		return
	_shot_t -= delta
	if _shot_t > 0.0:
		return
	if not chambered:
		_start_reload()
		return
	_fire(aim_at)
	_burst += 1
	_shot_t = _rng.randf_range(0.18, 0.3) if _burst % 2 == 1 else _rng.randf_range(0.45, 0.9)   # controlled pairs


## Angular error (degrees, 1 sigma) of an aimed shot right now.
func aim_error_deg() -> float:
	var dist := aim.global_position.distance_to(target.global_position)
	var e := 1.5 + 0.08 * dist     # a street criminal with a pistol, not a marksman
	e *= 1.0 + (1.0 - damage.steadiness()) * 2.5
	var t_speed := Vector2(target.velocity.x, target.velocity.z).length() if "velocity" in target else 0.0
	e *= 1.0 + clampf(t_speed / 3.0, 0.0, 1.0) * 0.8
	e *= 1.0 + clampf(Vector2(velocity.x, velocity.z).length() / 2.0, 0.0, 1.0) * 0.8
	if _burst == 0:
		e *= 1.4
	if _suppressed > 0.0:
		e *= 1.6
	return e


func _fire(aim_at: Vector3) -> void:
	var origin := aim.global_position + (aim_at - aim.global_position).normalized() * 0.55 + Vector3(0, -0.15, 0)
	var dir := (aim_at - origin).normalized()
	var err := deg_to_rad(aim_error_deg())
	var axis := dir.cross(Vector3.UP).normalized().rotated(dir, _rng.randf() * TAU)
	dir = dir.rotated(axis, absf(_rng.randfn(0.0, err)))
	Ballistics.fire(origin, dir, ammo, get_rid(), 0.95, _hostile_rids)
	if _audio.stream:
		_audio.pitch_scale = _rng.randf_range(0.96, 1.04)
		_audio.play()
	if _flash:
		_flash.light_energy = 3.0
	if mag > 0:
		mag -= 1
	else:
		chambered = false


func _start_reload() -> void:
	if reloading > 0.0:
		return
	# Find a magazine with rounds in it in their own gear.
	for g: InvGrid in model.equipment.grids(true):
		for e: Dictionary in g.entries:
			var it: InvItem = e.item
			if it.def.id == "mag_1911" and it.mag_count > 0:
				reloading = 2.3
				set_meta("next_mag", it)
				set_meta("next_grid", g)
				if role == "holder" or _rng.randf() < 0.6:
					_set_state(State.COVER)
				return
	# Out of ammo: switch to "pusher" with nothing; just hold (could flee later).
	chambered = false


func _finish_reload() -> void:
	var it: InvItem = get_meta("next_mag", null)
	var g: InvGrid = get_meta("next_grid", null)
	if it == null or g == null:
		return
	g.remove(it)
	mag = it.mag_count - 1
	chambered = true
	ammo = it.mag_ammo
	_burst = 0


func _melee_logic(delta: float) -> void:
	if target == null:
		return
	var d := global_position.distance_to(target.global_position)
	if can_see_target or d < 2.0:
		agent.target_position = target.global_position
	_face(target.global_position)
	if _melee_windup >= 0.0:
		_melee_windup -= delta
		if _melee_windup < 0.0:
			_strike()
		return
	if d < 1.25 and _melee_t <= 0.0 and _flinch <= 0.0:
		_melee_windup = 0.22
		_audio.play()


func _strike() -> void:
	_melee_t = _rng.randf_range(0.8, 1.2)
	var eye := _eye_pos()
	var to: Vector3 = target.global_position + Vector3(0, _rng.randf_range(0.9, 1.45), 0) - eye
	var dir := to.normalized()
	var rays: Array = []
	for off in [-0.08, 0.0, 0.08]:
		var side: Vector3 = dir.cross(Vector3.UP).normalized() * float(off)
		rays.append([eye + side, eye + side + dir * 1.35])
	var ex: Array[RID] = [get_rid()]
	ex.append_array(_hostile_rids)
	var hit := Melee.sweep(get_world_3d().direct_space_state, rays, ex)
	if hit.is_empty():
		return
	var kind := "stab" if _rng.randf() < 0.55 else "slash"
	var strength := 0.85 * (1.0 - 0.5 * maxf(damage.hurt("arm_r"), 0.0))
	var cut := Vector3.UP if kind == "stab" else dir.cross(Vector3.UP).normalized()
	Melee.strike(hit, kind, blade, strength, dir, cut, _rng)


# ------------------------------------------------------------------ moving

func _move(delta: float) -> void:
	var want := Vector3.ZERO
	var speed := 0.0
	var moving := true
	match state:
		State.IDLE, State.SUSPICIOUS:
			moving = false
			if state == State.IDLE and global_position.distance_to(post) > 0.8:
				agent.target_position = post
				moving = true
				speed = WALK
			elif state == State.IDLE:
				_yaw_target = post_facing
		State.PATROL:
			if patrol.is_empty():
				moving = false
			else:
				if _arrived(patrol[_patrol_i], 0.9):
					_patrol_i = (_patrol_i + 1) % patrol.size()
				agent.target_position = patrol[_patrol_i]
				speed = WALK
		State.INVESTIGATE:
			speed = MOVE
		State.COMBAT:
			if weapon == "knife":
				speed = RUN
			elif can_see_target or role == "holder":
				moving = false
			else:
				speed = MOVE
		State.COVER:
			if _cover_point == Vector3.INF:
				moving = false
			else:
				speed = RUN
		State.SEARCH:
			speed = MOVE
			if not _search_points.is_empty() and _arrived(_search_points[0], 1.0):
				_search_points.pop_front()
			if not _search_points.is_empty():
				agent.target_position = _search_points[0]
			else:
				moving = false
	if downed() or incapacitated():
		moving = false
	speed *= damage.mobility()
	if moving:
		var next := agent.get_next_path_position()
		want = next - global_position
		want.y = 0.0
		if want.length() > 0.05:
			want = want.normalized() * speed
			if state != State.COMBAT or not can_see_target:
				_yaw_target = atan2(-want.x, -want.z)
			_open_doors(want)
	velocity.x = move_toward(velocity.x, want.x, delta * 12.0)
	velocity.z = move_toward(velocity.z, want.z, delta * 12.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()


## Close enough to a point on the floor plan (ignores height).
func _arrived(p: Vector3, within: float) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < within


## A closed door just ahead on the way: open it.
func _open_doors(dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 1.1, Door.LAYER)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Node = hit.collider
	while n and not (n is Door):
		n = n.get_parent()
	if n and not (n as Door).is_open:
		(n as Door).open_from(global_position)


func _face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		_yaw_target = atan2(-d.x, -d.z)


func _turn(delta: float) -> void:
	var rate := 7.0 if state == State.COMBAT else 3.5
	rotation.y = lerp_angle(rotation.y, _yaw_target, minf(1.0, delta * rate))


## A nearby spot on the navmesh the target can't see.
func _find_cover() -> Vector3:
	if target == null:
		return Vector3.INF
	var map := get_world_3d().navigation_map
	var best := Vector3.INF
	var best_d := INF
	var head: Vector3 = target.global_position + Vector3(0, 1.55, 0)
	for i in 16:
		var ang := TAU * i / 16.0 + _rng.randf() * 0.3
		var r := _rng.randf_range(1.5, 6.0)
		var cand := NavigationServer3D.map_get_closest_point(map, global_position + Vector3(cos(ang) * r, 0, sin(ang) * r))
		if cand.distance_to(global_position) < 1.0:
			continue
		if _clear(cand + Vector3(0, 1.2, 0), head):
			continue
		var d := cand.distance_to(global_position) + cand.distance_to(target.global_position) * -0.15
		if d < best_d:
			best_d = d
			best = cand
	return best


# ------------------------------------------------------------------ death

func die(impulse := Vector3.ZERO, at := Vector3.ZERO, bone := "") -> void:
	super.die(impulse, at, bone)
	_drop_weapon()


## The weapon falls out of their hand.
func _drop_weapon() -> void:
	if gun == null or not is_instance_valid(gun):
		return
	var xf := gun.global_transform
	var rb := RigidBody3D.new()
	rb.collision_layer = 8
	rb.collision_mask = 1
	rb.mass = 1.1 if weapon == "pistol" else 0.3
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.04, 0.14, 0.22) if weapon == "pistol" else Vector3(0.04, 0.3, 0.06)
	cs.shape = bs
	rb.add_child(cs)
	get_parent().add_child(rb)
	rb.global_transform = xf
	gun.get_parent().remove_child(gun)
	rb.add_child(gun)
	gun.transform = Transform3D.IDENTITY
	rb.linear_velocity = velocity + Vector3(_rng.randf_range(-0.5, 0.5), 0.5, _rng.randf_range(-0.5, 0.5))
	model.grip_point = null
	model.grip_right = null
	model.grip_left = null
	gun = null
