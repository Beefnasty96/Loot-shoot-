class_name ImpactFX
extends Node3D
## Bullet holes, impact puffs/sparks, impact sounds, breakable glass.
## Everything is pooled and capped so a long fight stays cheap on the Thor.

const MAX_DECALS := 80
const MAX_PARTICLES := 20
const DECAL_CULL := 0xFFFFF & ~(2 | 4)  ## Never project onto the player's own model or viewmodel.
const SOUNDS := {
	"dust": "res://assets/audio/impact_hard.wav",
	"spark": "res://assets/audio/impact_metal.wav",
	"wood": "res://assets/audio/impact_wood.wav",
	"glass": "res://assets/audio/impact_glass.wav",
	"flesh": "res://assets/audio/impact_flesh.wav",
	"dummy": "res://assets/audio/impact_flesh.wav",
	"ricochet": "res://assets/audio/ricochet.wav",
}

var _decals: Array[Decal] = []
var _particles: Array[Node] = []
var _hole_tex: ImageTexture
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _next_player := 0


func _ready() -> void:
	_hole_tex = _make_hole_texture()
	for key: String in SOUNDS:
		var path: String = SOUNDS[key]
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	for i in 8:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_db = 3.0
		add_child(p)
		_players.append(p)


func spawn(info: Dictionary) -> void:
	var props := BallisticMaterials.get_props(info.material)
	var normal: Vector3 = info.normal
	var pos: Vector3 = info.position
	var result: String = info.result
	var person := info.collider is Hitbox
	if result != "disintegrated" and not person:
		_decal(pos, normal, info.collider, props.fx)
	if info.exit_pos != null:
		var dir: Vector3 = (info.exit_pos - pos).normalized()
		if not person:
			_decal(info.exit_pos, dir, info.collider, props.fx, 1.3)
			_puff(info.exit_pos, dir, props, 0.6)
	if not person:
		_puff(pos, normal, props, 1.0)
	_sound("ricochet" if result == "ricochet" else String(props.fx), pos)
	if props.get("breakable", false) and result != "ricochet":
		_break(info.collider)


func _decal(pos: Vector3, normal: Vector3, collider: Object, fx: String, scale := 1.0) -> void:
	var d := Decal.new()
	d.texture_albedo = _hole_tex
	d.size = Vector3(0.026, 0.06, 0.026) * scale
	d.cull_mask = DECAL_CULL
	if fx == "flesh":
		d.modulate = Color(0.5, 0.08, 0.06)
	elif fx == "dummy":
		d.modulate = Color(0.35, 0.25, 0.15)
	elif fx == "spark":
		d.modulate = Color(0.75, 0.75, 0.8)
	add_child(d)
	var y := normal.normalized()
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	d.global_transform = Transform3D(Basis(x, y, z).rotated(y, randf() * TAU), pos)
	_decals.append(d)
	if _decals.size() > MAX_DECALS:
		_decals.pop_front().queue_free()


func _puff(pos: Vector3, normal: Vector3, props: Dictionary, strength: float) -> void:
	if _particles.size() >= MAX_PARTICLES:
		var old: Node = _particles.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int(10 * strength)
	p.lifetime = 0.55
	p.direction = normal
	p.spread = 30.0
	p.gravity = Vector3(0, -4.0, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	quad.material = m
	p.mesh = quad
	var c: Color = props.color
	if props.fx == "spark":
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3(0, -9.8, 0)
		p.lifetime = 0.3
		quad.size = Vector2(0.012, 0.012)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(c, 0.9))
	ramp.set_color(1, Color(c, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.global_position = pos + normal * 0.01
	p.emitting = true
	_particles.append(p)
	p.finished.connect(func():
		_particles.erase(p)
		p.queue_free())


func _sound(key: String, pos: Vector3) -> void:
	if not _streams.has(key):
		return
	var pl := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	pl.stream = _streams[key]
	pl.pitch_scale = randf_range(0.9, 1.1)
	pl.global_position = pos
	pl.play()


## Glass shatters: hide it and turn off its collision, then restore it a few seconds later (shooting range).
func _break(collider: Object) -> void:
	var body := collider as CollisionObject3D
	if body == null or body.get_meta("broken", false):
		return
	body.set_meta("broken", true)
	var old_layer := body.collision_layer
	body.collision_layer = 0
	body.visible = false
	if body.get_meta("stay_broken", false):   # house windows stay broken
		return
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(body):
			body.collision_layer = old_layer
			body.visible = true
			body.set_meta("broken", false))


func _make_hole_texture() -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length() / (s / 2.0)
			var a := 0.0
			var v := 0.05
			if d < 0.35:
				a = 1.0
			elif d < 1.0:
				a = (1.0 - (d - 0.35) / 0.65) * 0.55
				v = 0.25
			img.set_pixel(x, y, Color(v, v, v, a))
	return ImageTexture.create_from_image(img)
