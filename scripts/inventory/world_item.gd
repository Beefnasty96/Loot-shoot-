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
	if (item.def.is_weapon() or item.def.is_mag()) and item.def.scene_path != "" and ResourceLoader.exists(item.def.scene_path):
		# Guns, knives and magazines that have a model lie on the floor as themselves, parts and all.
		var m: Node3D = (load(item.def.scene_path) as PackedScene).instantiate()
		add_child(m)
		if item.def.is_weapon():
			WeaponDB.assemble(item, m)
		# On its side. A knife's handle is modelled on the pistol-grip line: lay that flat first.
		var flat := Basis(Vector3.RIGHT, deg_to_rad(-72.0)) if item.def.weapon_kind == "knife" else Basis()
		m.basis = Basis(Vector3.FORWARD, PI / 2.0) * flat
		var long_gun := item.def.weapon_kind == "rifle"
		m.position.y = 0.022 if long_gun else (0.013 if item.def.is_mag() else 0.015)   # the stock is the widest part
		_ring(0.45 if long_gun else 0.22)
		return
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
	_ring()


## A faint marker so small items are easy to spot.
func _ring(radius := 0.0) -> void:
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius if radius > 0.0 else maxf(item.def.size.x, item.def.size.y) * CELL_M * 0.6
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
	var eq := p.character.equipment
	if item.def.is_weapon() and eq.get_weapon(item.def.weapon_slot) == null:
		eq.arm(item)            # straight into the empty holster/sheath
		queue_free()
		return
	if eq.store(item):
		queue_free()
	else:
		p.firearm._notify("No room for the %s." % item.def.display_name)
