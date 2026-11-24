class_name TargetDummy
extends Node3D
## Crash-test-style target with seven hit zones. Shows damage, zone and the
## energy each bullet left behind; goes down when head/thorax reach zero and
## resets a few seconds later.

const ZONES := [
	# zone, size (m), centre (m), gel factor (skull / ribs denser than gel)
	["head", Vector3(0.2, 0.24, 0.22), Vector3(0, 1.66, 0), 1.3],
	["thorax", Vector3(0.4, 0.34, 0.25), Vector3(0, 1.36, 0), 1.1],
	["stomach", Vector3(0.34, 0.26, 0.22), Vector3(0, 1.06, 0), 1.0],
	["arm_l", Vector3(0.1, 0.62, 0.12), Vector3(-0.27, 1.22, 0), 1.0],
	["arm_r", Vector3(0.1, 0.62, 0.12), Vector3(0.27, 1.22, 0), 1.0],
	["leg_l", Vector3(0.15, 0.92, 0.17), Vector3(-0.1, 0.46, 0), 1.0],
	["leg_r", Vector3(0.15, 0.92, 0.17), Vector3(0.1, 0.46, 0), 1.0],
]
const ZONE_NAMES := {head = "HEAD", thorax = "THORAX", stomach = "STOMACH", arm_l = "L ARM", arm_r = "R ARM", leg_l = "L LEG", leg_r = "R LEG"}

var model := DamageModel.new()
var _status: Label3D
var _body: Node3D
var _reset_timer := 0.0
var _idle := 0.0


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.86, 0.62, 0.22)
	var joint := StandardMaterial3D.new()
	joint.albedo_color = Color(0.2, 0.2, 0.22)
	for z: Array in ZONES:
		var hb := Hitbox.new()
		hb.zone = z[0]
		hb.gel_factor = z[3]
		hb.receiver = self
		hb.set_meta("material", "dummy")
		hb.position = z[2]
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = z[1]
		cs.shape = shape
		hb.add_child(cs)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = z[1]
		mi.mesh = mesh
		mi.material_override = skin
		hb.add_child(mi)
		_body.add_child(hb)
	# Black crash-test joint bands, purely visual.
	for band: Array in [[Vector3(0.42, 0.03, 0.27), Vector3(0, 1.2, 0)], [Vector3(0.36, 0.03, 0.24), Vector3(0, 0.93, 0)], [Vector3(0.12, 0.05, 0.12), Vector3(0, 1.53, 0)]]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = band[0]
		b.mesh = bm
		b.material_override = joint
		b.position = band[1]
		_body.add_child(b)
	_status = Label3D.new()
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.position = Vector3(0, 2.0, 0)
	_status.font_size = 40
	_status.outline_size = 10
	add_child(_status)
	_update_status()


func take_hit(info: Dictionary) -> void:
	if model.dead:
		return
	var zone: String = info.zone
	var dmg: float = info.damage
	model.apply(zone, dmg)
	_idle = 0.0
	if info.get("weapon", "") == "blade":
		var what: String = ("stab, %s deep" % Units.inches(info.depth_mm)) if info.kind == "stab" else ("slash, %s long" % Units.inches(info.length_mm))
		_float_text("-%d %s\n%s" % [roundi(dmg), ZONE_NAMES.get(zone, zone), what], info.position)
	else:
		var ftlb := AmmoType.j_to_ftlb(info.deposited)
		var outcome := "through" if info.result == "penetrated" else "stopped"
		_float_text("-%d %s\n%d ft-lb, %s" % [roundi(dmg), ZONE_NAMES.get(zone, zone), roundi(ftlb), outcome], info.position)
	if model.dead:
		_reset_timer = 3.0
		_body.rotation_degrees.x = -80.0  # topple backwards
		_body.position = Vector3(0, 0.15, 0.6)
	_update_status()


func _process(delta: float) -> void:
	if _reset_timer > 0.0:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			_reset()
	else:
		_idle += delta
		if _idle > 10.0 and not _is_full():
			_reset()


func _is_full() -> bool:
	for z: String in model.hp:
		if model.hp[z] < DamageModel.ZONES[z].max:
			return false
	return true


func _reset() -> void:
	model.reset()
	_body.rotation_degrees = Vector3.ZERO
	_body.position = Vector3.ZERO
	_idle = 0.0
	_update_status()


func _update_status() -> void:
	if model.dead:
		_status.text = "DOWN"
		_status.modulate = Color(1, 0.3, 0.3)
		return
	var hurt := []
	for z: String in model.hp:
		var mx: float = DamageModel.ZONES[z].max
		if model.hp[z] < mx:
			hurt.append("%s %d" % [ZONE_NAMES[z], roundi(model.hp[z])])
	_status.text = "  ".join(hurt) if hurt.size() > 0 else ""
	_status.modulate = Color(1, 0.85, 0.5)


func _float_text(text: String, at: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 34
	l.outline_size = 8
	l.modulate = Color(1, 0.35, 0.25)
	l.no_depth_test = true
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	host.add_child(l)
	l.global_position = at + Vector3(0, 0.25, 0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 0.6, 0), 1.8)
	tw.tween_property(l, "modulate:a", 0.0, 1.8).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)
