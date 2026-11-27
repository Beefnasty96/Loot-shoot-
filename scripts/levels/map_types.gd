class_name MapTypes
extends RefCounted
## The kinds of level a mission can be generated on. Each map type is a
## MissionLevel scene that builds a fresh layout every time it loads (from a
## random seed, or a given one to rebuild a layout). Only "ready" types are
## picked; the rest are planned and show as coming soon.

const TYPES := [
	{id = "suburban_house", name = "Suburban house", scene = "res://scenes/suburban_house.tscn", ready = true},
	{id = "bank", name = "Bank", scene = "", ready = false},
	{id = "school", name = "School", scene = "", ready = false},
	{id = "capitol", name = "Capitol building", scene = "", ready = false},
	{id = "car_shop", name = "Car shop", scene = "", ready = false},
	{id = "mall", name = "Mall", scene = "", ready = false},
	{id = "museum", name = "Museum", scene = "", ready = false},
	{id = "airplane", name = "Airplane", scene = "", ready = false},
]


static func available() -> Array:
	return TYPES.filter(func(t): return t.ready)


static func get_type(id: String) -> Dictionary:
	for t: Dictionary in TYPES:
		if t.id == id:
			return t
	return {}


## Pick the map type for the next level.
static func pick(rng: RandomNumberGenerator = null) -> Dictionary:
	var a := available()
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return a[rng.randi() % a.size()]
