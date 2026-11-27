class_name TexturePool
extends RefCounted
## Texture files you drop into assets/textures/ join the pool that generated
## levels pick walls, floors, ceilings, siding, roofs and so on from.
##
##   assets/textures/common/<category>/        every map type
##   assets/textures/<map type id>/<category>/ only that map type (e.g. suburban_house)
##
## Categories are the folders in CATEGORIES (e.g. walls, floors/carpet, roofs).
## Uploaded textures are mixed in with the built-in procedural ones, one entry
## each, so the more you add the more often they come up.
##
## File names:
##   oak_planks.png             repeats every DEFAULT size for its category
##   oak_planks@4ft.png         one repeat covers 4 ft (also in, m, cm: @48in, @1.2m, @30cm)
##   oak_planks_normal.png      (or _n) normal map for oak_planks (any size tag on either file)
## Formats: png, jpg, jpeg, webp. Square, tileable, power-of-two (512/1024/2048) works best.
## tools/textures/import_presets.py (run by the APK build) imports them with
## mipmaps and mobile (ETC2/ASTC) compression.

const DEFAULT_ROOT := "res://assets/textures"
const EXTS := ["png", "jpg", "jpeg", "webp"]
## category -> [default size of one repeat (m), roughness]
const CATEGORIES := {
	"walls": [1.0, 0.9],
	"ceilings": [0.6, 1.0],
	"floors/carpet": [0.6, 1.0],
	"floors/wood": [1.2, 0.5],
	"floors/tile": [0.6, 0.3],
	"floors/vinyl": [0.6, 0.5],
	"exterior/siding": [1.2, 0.7],
	"roofs": [1.2, 1.0],
	"ground/lawn": [1.5, 1.0],
	"ground/concrete": [1.2, 0.95],
	"ground/asphalt": [1.2, 0.95],
	"fences": [1.2, 0.85],
	"furniture/wood": [0.6, 0.6],
	"furniture/fabric": [0.5, 0.95],
	"counters": [0.6, 0.4],
}

static var _cache := {}          ## file path -> Material (shared across level loads)

var map_id := ""
var root := DEFAULT_ROOT


func _init(id := "", root_dir := DEFAULT_ROOT) -> void:
	map_id = id
	root = root_dir


## Texture files for a category: common/ first, then this map type's folder, each sorted by name.
func files(category: String) -> Array[String]:
	var out: Array[String] = []
	var dirs := [root.path_join("common").path_join(category)]
	if map_id != "":
		dirs.append(root.path_join(map_id).path_join(category))
	for d: String in dirs:
		if not DirAccess.dir_exists_absolute(d):
			continue
		var names := Array(ResourceLoader.list_directory(d))
		names.sort()
		for n: String in names:
			if n.ends_with("/") or n.get_extension().to_lower() not in EXTS:
				continue
			if _is_normal_map(n):
				continue
			out.append(d.path_join(n))
	return out


## Materials made from the uploaded files (no built-ins).
func materials(category: String) -> Array[Material]:
	var out: Array[Material] = []
	for path in files(category):
		var m := material_for(path, category)
		if m:
			out.append(m)
	return out


## Built-in materials plus uploaded ones.
func pool(category: String, builtins: Array = []) -> Array:
	var out: Array = builtins.duplicate()
	out.append_array(materials(category))
	return out


## One material for a category: a built-in or an uploaded one, chosen with rng.
func pick(category: String, builtins: Array, rng: RandomNumberGenerator) -> Material:
	var all := pool(category, builtins)
	if all.is_empty():
		return null
	return all[rng.randi() % all.size()]


func material_for(path: String, category: String) -> Material:
	if _cache.has(path):
		return _cache[path]
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("TexturePool: couldn't load %s" % path)
		return null
	var defaults: Array = CATEGORIES.get(category, [1.0, 0.85])
	var size := parse_size(path.get_file())
	if size <= 0.0:
		size = defaults[0]
	var m := StandardMaterial3D.new()
	m.resource_name = path.get_file().get_basename()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / size
	m.roughness = defaults[1]
	var nmap := _find_normal(path)
	if nmap != "":
		var nt := load(nmap) as Texture2D
		if nt:
			m.normal_enabled = true
			m.normal_texture = nt
	_cache[path] = m
	return m


## "@4ft", "@48in", "@1.2m", "@30cm" in a file name -> metres (0 if none).
static func parse_size(file_name: String) -> float:
	var base := file_name.get_basename()
	var at := base.rfind("@")
	if at < 0:
		return 0.0
	var tag := base.substr(at + 1).to_lower()
	for suffix in ["_normal", "_n"]:
		if tag.ends_with(suffix):
			tag = tag.substr(0, tag.length() - suffix.length())
	var units := {"ft": 0.3048, "in": 0.0254, "cm": 0.01, "m": 1.0}
	for u: String in ["ft", "in", "cm", "m"]:
		if tag.ends_with(u):
			var num := tag.substr(0, tag.length() - u.length())
			if num.is_valid_float():
				return num.to_float() * units[u]
	return 0.0


static func _stem(file_name: String) -> String:
	## Name without extension, size tag or normal suffix: "oak@4ft_normal.png" -> "oak".
	var b := file_name.get_basename()
	for suffix in ["_normal", "_n"]:
		if b.ends_with(suffix):
			b = b.substr(0, b.length() - suffix.length())
	var at := b.rfind("@")
	if at >= 0:
		b = b.substr(0, at)
	for suffix in ["_normal", "_n"]:
		if b.ends_with(suffix):
			b = b.substr(0, b.length() - suffix.length())
	return b


static func _is_normal_map(file_name: String) -> bool:
	var b := file_name.get_basename()
	var at := b.rfind("@")
	var parts := [b] if at < 0 else [b, b.substr(0, at)]
	for p: String in parts:
		if p.ends_with("_normal") or p.ends_with("_n"):
			return true
	return false


func _find_normal(path: String) -> String:
	var d := path.get_base_dir()
	var stem := _stem(path.get_file())
	for n: String in ResourceLoader.list_directory(d):
		if n.get_extension().to_lower() in EXTS and _is_normal_map(n) and _stem(n) == stem:
			return d.path_join(n)
	return ""


## Every category folder, for making the empty tree (tools and tests).
static func category_dirs(map_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id in ["common"] + map_ids:
		for c: String in CATEGORIES:
			out.append(String(id).path_join(c))
	return out
