extends SceneTree
## Uploaded level textures: files in assets/textures/<common|map type>/<surface>/
## join the pools generated levels pick from (size tags, normal maps, per-map
## folders). Uses the fixture tree in tools/tests/fixtures/textures.
## Run: godot --headless --fixed-fps 60 -s tools/tests/texture_pool_test.gd

const POOL := "res://scripts/levels/texture_pool.gd"
const FIX := "res://tools/tests/fixtures/textures"
var fails := 0
var f := 0
var rs
var tries := 0
var found := false


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	var P = load(POOL)
	check(absf(P.parse_size("oak@4ft.png") - 1.2192) < 1e-4 and absf(P.parse_size("oak@48in.png") - 1.2192) < 1e-4, "@4ft and @48in both mean 4 ft")
	check(absf(P.parse_size("tile@30cm_normal.png") - 0.3) < 1e-6 and absf(P.parse_size("x@1.5m.jpg") - 1.5) < 1e-6, "@30cm and @1.5m work, also on normal maps")
	check(P.parse_size("plain.png") == 0.0 and P.parse_size("bad@lots.png") == 0.0, "no tag (or a bad one) = the folder's default size")
	var house = P.new("suburban_house", FIX)
	var bank = P.new("bank", FIX)
	var walls: Array = house.files("walls")
	check(walls.size() == 1 and walls[0].get_file() == "test_stripes@4ft.png", "walls: the texture is found, its _normal file isn't counted as one (%s)" % str(walls))
	var m: StandardMaterial3D = house.material_for(walls[0], "walls")
	check(m != null and m.albedo_texture != null and absf(m.uv1_scale.x - 1.0 / 1.2192) < 1e-4, "a 4 ft tag sets the repeat to 4 ft")
	check(m.normal_enabled and m.normal_texture != null, "and the matching _normal file is used as its normal map")
	var carpet: Array = house.materials("floors/carpet")
	check(carpet.size() == 1 and absf(carpet[0].uv1_scale.x - 1.0 / 0.6) < 1e-4 and carpet[0].roughness == 1.0, "no tag: carpet's default size and roughness")
	check(house.files("roofs").size() == 1 and bank.files("roofs").size() == 0, "a map type's own folder only feeds that map type")
	check(bank.files("walls").size() == 2 and house.files("walls").size() == 1, "common/ feeds every map type (bank walls: common + bank = 2)")
	var b1 := StandardMaterial3D.new()
	var b2 := StandardMaterial3D.new()
	var b3 := StandardMaterial3D.new()
	check(house.files("ceilings").is_empty() and house.pool("ceilings", [b1]) == [b1], "an empty folder leaves the built-ins as they are")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for i in 200:
		var pick: Material = house.pick("floors/carpet", [b1, b2, b3], rng)
		seen[{b1: "b1", b2: "b2", b3: "b3"}.get(pick, "upload")] = true
	check(seen.size() == 4, "uploads are mixed in with the built-ins (%s)" % str(seen.keys()))
	var real = P.new("suburban_house")
	print("      real tree: %d uploaded wall textures" % real.files("walls").size())
	_load_house()


func _load_house() -> void:
	if rs:
		rs.free()
	tries += 1
	rs = load("res://scenes/suburban_house.tscn").instantiate()
	rs.layout_seed = 40 + tries
	rs.spawn_enemies = false
	rs.textures = load(POOL).new("suburban_house", FIX)
	root.add_child(rs)
	f = 0


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		var stripes: Material = rs.textures.material_for(rs.textures.files("walls")[0], "walls")
		if tries == 1:
			check(stripes in rs._paint, "a generated house puts uploaded wall textures in its paint pool (%d choices)" % rs._paint.size())
		for mi in rs.find_children("*", "MeshInstance3D", true, false):
			if mi.material_override == stripes:
				found = true
		if found or tries >= 6:
			check(found, "and some room's walls use it (house #%d)" % rs.layout_seed)
			print("%d failure(s)" % fails)
			quit(1 if fails else 0)
		else:
			_load_house()
	return false
