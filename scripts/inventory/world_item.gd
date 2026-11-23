class_name WorldItem
extends Node3D
## An item lying in the world. Walk up and press A to pick it up, or open the
## inventory nearby: it shows in the Ground panel.

const CELL_M := 0.11   ## Size of one grid square on the floor.

var item: InvItem
var _sprite: Sprite3D


static func spawn(it: InvItem, at: Vector3, parent: Node) -> WorldItem:
	var w := WorldItem.new()
	w.item = it
	parent.add_child(w)
	w.global_position = _floor_point(w, at)
	w.rotation.y = randf() * TAU
	return w


static func _floor_point(node: Node3D, at: Vector3) -> Vector3:
	var space := node.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3) + Vector3.UP * 0.01 if not hit.is_empty() else at


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("world_item")
	_sprite = Sprite3D.new()
	_sprite.axis = Vector3.AXIS_Y          # lies flat on the floor
	_sprite.double_sided = true
	_sprite.shaded = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var path := item.def.icon_path
	if ResourceLoader.exists(path):
		_sprite.texture = load(path)
		_sprite.pixel_size = CELL_M / 64.0
	add_child(_sprite)
	# A faint marker so small items are easy to spot.
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = maxf(item.def.size.x, item.def.size.y) * CELL_M * 0.6
	disc.bottom_radius = disc.top_radius
	disc.height = 0.004
	disc.radial_segments = 12
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.85, 0.5, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = m
	ring.mesh = disc
	ring.position.y = -0.005
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func prompt() -> String:
	var n := item.def.display_name
	if item.def.max_stack > 1:
		n += " (%d)" % item.count
	return "A: pick up " + n


func use(p: Player) -> void:
	if p.character.equipment.store(item):
		queue_free()
	else:
		p.firearm._notify("No room for the %s." % item.def.display_name)
