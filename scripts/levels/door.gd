class_name Door
extends Node3D
## A hinged door: A opens/closes it, it swings away from whoever opens it, and
## people (the AI later) can open it on the way through. The panel is a moving
## body, so it blocks you and bullets go through it by its ballistic material
## (hollow-core interior door or solid exterior door).

const SWING_SPEED := 2.6        ## rad/s
const OPEN_ANGLE := deg_to_rad(95.0)

var width := 0.76
var height := 2.03
var thickness := 0.035
var ballistic := "hollow_door"
var color := Color(0.93, 0.91, 0.86)
var is_open := false
var label := "door"

var _angle := 0.0
var _target := 0.0
var _hinge: Node3D
var _panel: AnimatableBody3D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("door")
	_hinge = Node3D.new()
	_hinge.position = Vector3(-width / 2.0, 0.0, 0.0)   # hinge on the local -X edge
	add_child(_hinge)
	_panel = AnimatableBody3D.new()
	_panel.sync_to_physics = false
	_panel.set_meta("material", ballistic)
	_panel.position = Vector3(width / 2.0, height / 2.0, 0.0)
	_hinge.add_child(_panel)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width - 0.01, height - 0.01, thickness)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_panel.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	mi.material_override = m
	_panel.add_child(mi)
	# Brass knob, both sides.
	var knob_m := StandardMaterial3D.new()
	knob_m.albedo_color = Color(0.78, 0.62, 0.25)
	knob_m.metallic = 0.8
	knob_m.roughness = 0.35
	for side in [-1.0, 1.0]:
		var k := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.028
		sm.height = 0.05
		k.mesh = sm
		k.material_override = knob_m
		k.position = Vector3(width / 2.0 - 0.07, -height / 2.0 + 0.92, side * (thickness / 2.0 + 0.03))
		_panel.add_child(k)
	_angle = OPEN_ANGLE * (1.0 if is_open else 0.0)
	_target = _angle
	_hinge.rotation.y = _angle


func _physics_process(delta: float) -> void:
	if is_equal_approx(_angle, _target):
		return
	_angle = move_toward(_angle, _target, SWING_SPEED * delta)
	_hinge.rotation.y = _angle


## Open away from `from` (world position), or close.
func toggle(from: Vector3) -> void:
	if is_open:
		close()
	else:
		open_from(from)


func open_from(from: Vector3) -> void:
	var local := to_local(from)
	# Swing away from the person: they stand on +Z -> door swings to -Z.
	_target = OPEN_ANGLE if local.z > 0.0 else -OPEN_ANGLE   # +angle swings the panel toward -Z
	is_open = true


func close() -> void:
	_target = 0.0
	is_open = false


## Middle of the doorway (for AI paths and interaction distance).
func interact_point() -> Vector3:
	return global_transform * Vector3(0.0, 1.0, 0.0)


func prompt() -> String:
	return "A: %s %s" % ["close" if is_open else "open", label]


func use(user: Node3D) -> void:
	toggle(user.global_position)
