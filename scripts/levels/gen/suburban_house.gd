class_name SuburbanHouse
extends MissionLevel
## Map type "suburban_house": a new house every time the level loads.
##
## Two families of plan, both real-world builder layouts from the late '80s-'90s:
##   ranch      single storey, 54-70 ft wide: a public wing (foyer, living,
##              kitchen, dining, family) and a private wing down a hallway
##              (bedrooms, hall bath, laundry, office, master suite + bath).
##   colonial   two storeys, 34-44 ft wide: two-storey foyer with a straight
##              stair, living / dining / office / kitchen / family / powder room
##              downstairs, bedrooms, hall bath and master suite upstairs.
## Either may have an attached two-car garage (door into the house), mirrored
## left/right. Room sizes, which rooms exist, where every door and window goes,
## materials and every piece of furniture come from the layout seed, so a seed
## rebuilds the same house (tests and bug reports) and 0 rolls a new one.
##
## The plan is a set of rectangles that tile the footprint; walls are made
## wherever two rooms meet (or a room meets the outside), with the openings the
## plan's connections ask for, so every room is reachable from the front door.
## Furniture is placed against walls / in the middle, keeping clear of door swings
## and windows, and a piece that would cut a room off from one of its doors is
## not placed (checked on a walkability grid).

const FLOOR_T := 0.3                     ## Joists + subfloor between storeys.
const FH := CEILING + FLOOR_T            ## Floor to floor, 9 ft.
const STEPS := 14
const TREAD := 10.0 * IN
const RISE := FH / STEPS                 ## ~7.7 in.
const STAIR_W := 36.0 * IN
const RUN := STEPS * TREAD               ## Horizontal length of the flight.
const CELL := 0.15                       ## Walkability grid for furniture placement.
const CLEAR := 0.3                       ## Body clearance on that grid.
const EPS := 0.01

## Map registry entry.
const MAP_ID := "suburban_house"

var style := "ranch"
var stories := 1
## Every room: {name, kind, floor, x0, z0, x1, z1, group, openings[], spots[]}.
var plan: Array = []
var fx0 := 0.0
var fx1 := 0.0
var fz0 := 0.0
var fz1 := 0.0
var garage := {}
var stair := {}
var front_door_pos := Vector3.ZERO
var summary := ""

var _mirror := false
var _conns: Array = []
var _ext_open: Array = []                ## Exterior openings: {room, side, c, w, kind, ...}
var _f: Furniture
var _paint: Array = []
var _plain_paint: Material
var _siding: StandardMaterial3D
var _trim_col := Color.WHITE
var _counts := {}


func build() -> void:
	_rng.seed = layout_seed
	clear_text = "HOUSE CLEAR"
	if textures == null:
		textures = TexturePool.new(MAP_ID)
	_f = Furniture.new(self, _rng)
	_materials()
	_environment()
	if _rng.randf() < 0.5:
		_plan_ranch()
	else:
		_plan_colonial()
	_resolve_connections()
	_windows()
	_build_structure()
	_build_stair()
	_furnish_all()
	_lot()
	_neighbours()
	floor_y = 0.0
	var gx0: float = garage.get("x0", fx0)
	var gx1: float = garage.get("x1", fx1)
	nav_aabb = AABB(Vector3(minf(fx0, gx0) - 4.0, -1.0, fz0 - 4.0), Vector3(maxf(fx1, gx1) - minf(fx0, gx0) + 8.0, stories * FH + 2.0, 15.0 - fz0 + 4.0))
	player_start = Vector3(front_door_pos.x, 0.05, 15.0)
	player_yaw = 0.0
	var beds := 0
	for r: Dictionary in plan:
		if r.kind in ["bedroom", "master"] and r.group != "master_b":
			beds += 1
	summary = "%s, %d bed%s%s" % ["Two-storey colonial" if stories == 2 else "Ranch", beds, "s" if beds != 1 else "", ", attached garage" if not garage.is_empty() else ""]
	label3d("SUBURBAN HOUSE  #%d\n%s" % [layout_seed, summary], Vector3(front_door_pos.x, 2.4, 12.4), 40)


# ================================================================== plan

## Seeded shuffle (Array.shuffle() uses the global RNG, which would break "same seed, same house").
func _shuffle(a: Array, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = _rng
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _ux(u: float) -> float:
	return fx1 - u if _mirror else fx0 + u


## A room from plan coordinates (u along the width from the garage end, z world).
func _room(name: String, kind: String, fl: int, u0: float, u1: float, z0: float, z1: float, group := "") -> Dictionary:
	var a := _ux(u0)
	var b := _ux(u1)
	var r := {name = name, kind = kind, floor = fl, x0 = minf(a, b), x1 = maxf(a, b), z0 = z0, z1 = z1, group = group, openings = [], spots = [], items = []}
	plan.append(r)
	return r


func _name(kind: String) -> String:
	var n: int = _counts.get(kind, 0) + 1
	_counts[kind] = n
	if kind == "bedroom":
		return "bedroom%d" % (n + 1)      # the master is bedroom 1
	return kind if n == 1 else "%s%d" % [kind, n]


func _connect(a: Dictionary, b: Dictionary, kind: String, w: float, door := {}, at := NAN) -> void:
	for cn: Dictionary in _conns:
		if (cn.a == a and cn.b == b) or (cn.a == b and cn.b == a):
			return
	_conns.append({a = a, b = b, kind = kind, w = w, door = door, at = at})


func _door_to(a: Dictionary, b: Dictionary) -> void:
	var bath: bool = a.kind in ["bath", "master_bath", "powder"] or b.kind in ["bath", "master_bath", "powder"]
	_connect(a, b, "door", 0.71 if bath else 0.76, {label = "bathroom door" if bath else "door", is_open = _rng.randf() < 0.35})


## Split `length` into pieces for `kinds` with [min, max] widths each, randomised.
func _split(length: float, kinds: Array, ranges: Dictionary) -> Array:
	var lo := 0.0
	var hi := 0.0
	for k: String in kinds:
		lo += ranges[k][0]
		hi += ranges[k][1]
	if length < lo - EPS or length > hi + EPS:
		return []
	var w: Array = []
	var t := clampf((length - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
	for k: String in kinds:
		w.append(lerpf(ranges[k][0], ranges[k][1], clampf(t + _rng.randf_range(-0.15, 0.15), 0.0, 1.0)))
	# Scale the slack back to the exact length, staying inside the ranges.
	for _i in 8:
		var s := 0.0
		for x: float in w:
			s += x
		var err := length - s
		if absf(err) < 0.001:
			break
		var room := 0.0
		for i in w.size():
			room += (ranges[kinds[i]][1] - w[i]) if err > 0 else (w[i] - ranges[kinds[i]][0])
		if room < 0.001:
			break
		for i in w.size():
			var r: float = (ranges[kinds[i]][1] - w[i]) if err > 0 else (w[i] - ranges[kinds[i]][0])
			w[i] += err * r / room
	return w


const PRIVATE := {
	bedroom = [2.7, 4.8], bath = [1.7, 2.7], laundry = [1.6, 2.4], office = [2.4, 3.6],
}


## Rooms for a run of a private row: returns [[kind, width], ...] or [] if nothing fits.
func _private_run(length: float, want: Array) -> Array:
	for _t in 60:
		var kinds: Array = want.duplicate()
		_shuffle(kinds)
		var w := _split(length, kinds, PRIVATE)
		if not w.is_empty():
			var out: Array = []
			for i in kinds.size():
				out.append([kinds[i], w[i]])
			return out
	return []


## Fill two private rows (and an optional third run) with bedrooms + one bath (+ maybe laundry / office).
## runs: [[u0, u1, z0, z1, floor, hall_room], ...]. Returns false if no mix fits.
func _fill_private(runs: Array, fl_extra: Array) -> bool:
	for _attempt in 200:
		var pools: Array = []
		var baths := 0
		var beds := 0
		var ok := true
		for run: Array in runs:
			var L: float = run[1] - run[0]
			if L < 1.6:
				pools.append([])
				continue
			var n := clampi(int(round(L / _rng.randf_range(3.0, 4.4))), 1, 3)
			var kinds: Array = []
			for i in n:
				kinds.append("bedroom")
			pools.append(kinds)
		# One hall bath somewhere, extras where they fit.
		var ri := _rng.randi() % pools.size()
		if pools[ri].is_empty():
			continue
		pools[ri][_rng.randi() % pools[ri].size()] = "bath"
		for extra: String in fl_extra:
			var rj := _rng.randi() % pools.size()
			if pools[rj].size() >= 2 and _rng.randf() < 0.8:
				var idx: int = _rng.randi() % pools[rj].size()
				if pools[rj][idx] == "bedroom":
					pools[rj][idx] = extra
		var fits: Array = []
		for i in runs.size():
			if pools[i].is_empty():
				fits.append([])
				continue
			var f := _private_run(runs[i][1] - runs[i][0], pools[i])
			if f.is_empty():
				ok = false
				break
			fits.append(f)
		if not ok:
			continue
		for f: Array in fits:
			for p: Array in f:
				if p[0] == "bath":
					baths += 1
				if p[0] == "bedroom":
					beds += 1
		if baths != 1 or beds < 1:
			continue
		for i in runs.size():
			var run: Array = runs[i]
			var u: float = run[0]
			for p: Array in fits[i]:
				var r := _room(_name(p[0]), p[0], run[4], u, u + p[1], run[2], run[3])
				_door_to(run[5], r)
				u += p[1]
		return true
	return false


## Master suite at one end of a row: bedroom (L-shaped: two rects, no wall between) + bath + walk-in.
func _master_suite(u0: float, u1: float, z0: float, z1: float, fl: int, hall: Dictionary, hall_side_is_z1: bool) -> void:
	var depth := z1 - z0
	var bw := _rng.randf_range(1.8, 2.3)          # bath width along the row
	var bd := clampf(_rng.randf_range(2.1, 2.5), 1.8, depth - 1.3)   # bath depth from the outside wall
	var bath_at_u0 := _rng.randf() < 0.5
	var bu0 := u0 if bath_at_u0 else u1 - bw
	var bu1 := bu0 + bw
	# Outside side of the row is the one away from the hall.
	var bz0 := z0 if hall_side_is_z1 else z1 - bd
	var bz1 := bz0 + bd
	var a := _room("master", "master", fl, u0 + bw if bath_at_u0 else u0, u1 if bath_at_u0 else u1 - bw, z0, z1, "master")
	var bz_in0 := bz1 if hall_side_is_z1 else z0
	var bz_in1 := z1 if hall_side_is_z1 else bz0
	var b := _room("master_closet", "master_closet", fl, bu0, bu1, bz_in0, bz_in1, "master")
	var mb := _room("master_bath", "master_bath", fl, bu0, bu1, bz0, bz1)
	_door_to(hall, a)
	_door_to(b if _rng.randf() < 0.6 else a, mb)


func _garage_plan(gw: float, gd: float) -> void:
	var a := _ux(-gw)
	var b := _ux(0.0)
	garage = {x0 = minf(a, b), x1 = maxf(a, b), z0 = fz1 - gd, z1 = fz1}


func _plan_ranch() -> void:
	style = "ranch"
	stories = 1
	var W := _rng.randf_range(16.5, 21.0)
	var D := _rng.randf_range(9.2, 10.6)
	_mirror = _rng.randf() < 0.5
	fz1 = _rng.randf_range(3.8, 5.6)
	fz0 = fz1 - D
	fx0 = -W * _rng.randf_range(0.4, 0.55)
	fx1 = fx0 + W
	var dh := _rng.randf_range(1.1, 1.3)
	var df := _rng.randf_range(3.6, 4.4)
	var zb := fz0 + (D - df - dh)        # top of the back row
	var zh := zb + dh                    # front edge of the hall
	var wp := W * _rng.randf_range(0.44, 0.52)
	# Public wing: the front rooms run the full depth down to the back row.
	var fw := _rng.randf_range(1.8, 2.3)
	var arrangements := [
		[["kitchen", "foyer", "living"], ["dining", "family"]],
		[["living", "foyer", "dining"], ["kitchen", "family"]],
		[["dining", "foyer", "living"], ["kitchen", "family"]],
		[["living", "foyer"], ["kitchen", "dining"]],
	]
	var arr: Array = arrangements[_rng.randi() % arrangements.size()]
	var front: Array = []
	var others: int = arr[0].size() - 1
	var rest := wp - fw
	var widths: Array = []
	if others == 2:
		var t := _rng.randf_range(0.42, 0.58)
		widths = [rest * t, fw, rest * (1.0 - t)] if arr[0][1] == "foyer" else [rest * t, rest * (1.0 - t), fw]
	else:
		widths = [rest, fw]
	var u := 0.0
	for i in arr[0].size():
		var k: String = arr[0][i]
		front.append(_room(_name(k), k, 0, u, u + widths[i], zb, fz1))
		u += widths[i]
	var back: Array = []
	var t2 := _rng.randf_range(0.4, 0.6)
	back.append(_room(_name(arr[1][0]), arr[1][0], 0, 0.0, wp * t2, fz0, zb))
	back.append(_room(_name(arr[1][1]), arr[1][1], 0, wp * t2, wp, fz0, zb))
	for i in front.size() - 1:
		_connect(front[i], front[i + 1], "open", _rng.randf_range(1.0, 1.6) if "foyer" in [front[i].kind, front[i + 1].kind] else _rng.randf_range(1.4, 2.2))
	if _rng.randf() < 0.6:
		_connect(back[0], back[1], "open", _rng.randf_range(1.4, 2.4))
	for b: Dictionary in back:
		var best: Dictionary = {}
		var best_o := 0.0
		for f: Dictionary in front:
			var o := minf(f.x1, b.x1) - maxf(f.x0, b.x0)
			if f.kind != "foyer" and o > best_o:
				best_o = o
				best = f
		if best_o > 1.3:
			_connect(best, b, "open", minf(best_o - 0.4, _rng.randf_range(1.2, 2.4)))
		else:
			_connect(b, back[0] if b == back[1] else back[1], "open", 1.4)
	# Private wing down the hall.
	var hall := _room("hall", "hall", 0, wp, W, zb, zh)
	_connect(front[front.size() - 1], hall, "open", dh - 0.15 if front[front.size() - 1].kind == "foyer" else minf(dh - 0.15, 1.0))
	var lp := W - wp
	var mw := _rng.randf_range(4.8, 5.6)
	var master_back := _rng.randf() < 0.7
	var runs: Array
	if master_back:
		_master_suite(W - mw, W, fz0, zb, 0, hall, true)
		runs = [[wp, W - mw, fz0, zb, 0, hall], [wp, W, zh, fz1, 0, hall]]
	else:
		_master_suite(W - mw, W, zh, fz1, 0, hall, false)
		runs = [[wp, W, fz0, zb, 0, hall], [wp, W - mw, zh, fz1, 0, hall]]
	if not _fill_private(runs, ["laundry", "office"]):
		push_warning("suburban house: private wing didn't fit, using a plain split")
		for run: Array in runs:
			var r := _room(_name("bedroom"), "bedroom", 0, run[0], run[1], run[2], run[3])
			_door_to(hall, r)
	if _rng.randf() < 0.85:
		_garage_plan(_rng.randf_range(6.4, 7.2), minf(_rng.randf_range(6.4, 7.2), D - 0.5))
		var gfront: Dictionary = front[0]
		_ext_door_from_garage(gfront)


func _plan_colonial() -> void:
	style = "colonial"
	stories = 2
	var W := _rng.randf_range(10.6, 13.4)
	var D := _rng.randf_range(9.6, 10.8)
	_mirror = _rng.randf() < 0.5
	fz1 = _rng.randf_range(3.8, 5.6)
	fz0 = fz1 - D
	fx0 = -W * _rng.randf_range(0.4, 0.6)
	fx1 = fx0 + W
	var dh := _rng.randf_range(1.2, 1.4)
	var df := _rng.randf_range(RUN + 1.15, RUN + 1.45)    # a landing in front of the first step
	var zb := fz0 + (D - df - dh)
	var zh := zb + dh
	var fw := _rng.randf_range(2.4, 2.8)
	var left := 0.0
	if _rng.randf() > 0.25 and W - fw - 6.0 > 0.0:
		left = _rng.randf_range(3.0, W - fw - 3.0)
	var stair_low_u := _rng.randf() < 0.5     # stair lane against the foyer's low-u wall
	# ---- ground floor
	var hall := _room("hall", "hall", 0, 0.0, W, zb, zh)
	var foyer := _room("foyer", "foyer", 0, left, left + fw, zh, fz1)
	var segs: Array = []
	if left > 0.0:
		segs.append([0.0, left])
	segs.append([left + fw, W])
	var pub: Array = ["living", "dining", "office"]
	_shuffle(pub)
	pub.erase("living")
	pub.insert(0 if _rng.randf() < 0.6 else 1, "living")
	var pi := 0
	for s: Array in segs:
		var L: float = s[1] - s[0]
		if L > 6.4 and segs.size() == 1:
			var t := _rng.randf_range(0.45, 0.58)
			for part in [[s[0], s[0] + L * t], [s[0] + L * t, s[1]]]:
				var k: String = pub[pi]
				pi += 1
				var r := _room(_name(k), k, 0, part[0], part[1], zh, fz1)
				if k == "office":
					_connect(hall, r, "door", 0.81, {label = "door"})
				else:
					_connect(hall, r, "open", minf(part[1] - part[0] - 0.5, _rng.randf_range(1.2, 1.8)))
		else:
			var k: String = pub[pi]
			pi += 1
			var r := _room(_name(k), k, 0, s[0], s[1], zh, fz1)
			if k == "office":
				_connect(hall, r, "door", 0.81, {label = "door"})
			else:
				_connect(hall, r, "open", minf(L - 0.5, _rng.randf_range(1.2, 1.8)))
			var low_side: bool = s[1] <= left + EPS
			if k != "office" and low_side != stair_low_u and _rng.randf() < 0.6:
				_connect(foyer, r, "open", _rng.randf_range(1.0, 1.4))
	# Back row: kitchen + family (+ powder room / laundry).
	var kinds: Array = ["kitchen", "family"]
	if _rng.randf() < 0.5:
		kinds.reverse()
	var small: Array = ["powder"]
	if _rng.randf() < 0.55:
		small.append("laundry")
	var small_w := 0.0
	var small_ws: Array = []
	for k: String in small:
		var w := _rng.randf_range(1.5, 1.9) if k == "powder" else _rng.randf_range(1.7, 2.1)
		small_ws.append(w)
		small_w += w
	var big := W - small_w
	var t3 := _rng.randf_range(0.45, 0.58)
	var at_start := _rng.randf() < 0.5
	var u := 0.0
	var back: Array = []
	if at_start:
		for i in small.size():
			var r := _room(_name(small[i]), small[i], 0, u, u + small_ws[i], fz0, zb)
			_door_to(hall, r)
			u += small_ws[i]
	for k: String in kinds:
		var w := big * (t3 if k == kinds[0] else 1.0 - t3)
		var r := _room(_name(k), k, 0, u, u + w, fz0, zb)
		_connect(hall, r, "open", minf(w - 0.6, _rng.randf_range(1.4, 2.2)))
		back.append(r)
		u += w
	_connect(back[0], back[1], "open", _rng.randf_range(1.6, 2.6))
	if not at_start:
		for i in small.size():
			var r := _room(_name(small[i]), small[i], 0, u, u + small_ws[i], fz0, zb)
			_door_to(hall, r)
			u += small_ws[i]
	# Stair: in the foyer's stair lane, rising toward the hall.
	var lane_u0 := left if stair_low_u else left + fw - STAIR_W
	var a := _ux(lane_u0)
	var b := _ux(lane_u0 + STAIR_W)
	stair = {x0 = minf(a, b), x1 = maxf(a, b), z_top = zh, z_base = zh + RUN, foyer = foyer}
	var walk_u0 := left + STAIR_W if stair_low_u else left
	var walk_c := _ux(walk_u0 + (fw - STAIR_W) / 2.0)
	_connect(foyer, hall, "open", fw - STAIR_W - 0.25, {}, walk_c)
	front_door_pos = Vector3(walk_c, 0, fz1)
	_ext_open.append({room = foyer, side = "zmax", c = walk_c, w = 0.97, kind = "door", door = _front_door()})
	# ---- upper floor
	var uhall := _room("upstairs hall", "hall", 1, 0.0, W, zb, zh)
	var void_r := _room("open to below", "void", 1, left, left + fw, zh, fz1)
	_connect(void_r, uhall, "open", STAIR_W + 0.25, {edge = true}, (stair.x0 + stair.x1) / 2.0)
	var mw := _rng.randf_range(4.8, 5.6)
	var master_end_hi := _rng.randf() < 0.5
	var runs: Array = []
	if master_end_hi:
		_master_suite(W - mw, W, fz0, zb, 1, uhall, true)
		runs.append([0.0, W - mw, fz0, zb, 1, uhall])
	else:
		_master_suite(0.0, mw, fz0, zb, 1, uhall, true)
		runs.append([mw, W, fz0, zb, 1, uhall])
	if left > 0.0:
		runs.append([0.0, left, zh, fz1, 1, uhall])
	runs.append([left + fw, W, zh, fz1, 1, uhall])
	if not _fill_private(runs, [] if "laundry" in small else ["laundry"]):
		push_warning("suburban house: upstairs didn't fit, using a plain split")
		for run: Array in runs:
			var r := _room(_name("bedroom"), "bedroom", 1, run[0], run[1], run[2], run[3])
			_door_to(uhall, r)
	if _rng.randf() < 0.8:
		_garage_plan(_rng.randf_range(6.4, 7.2), clampf(_rng.randf_range(6.4, 7.2), df + dh + 0.3, D - 0.4))
		_ext_door_from_garage(hall)


func _front_door() -> Dictionary:
	var cols := [Color(0.12, 0.28, 0.2), Color(0.45, 0.08, 0.1), Color(0.1, 0.15, 0.3), Color(0.95, 0.94, 0.9), Color(0.35, 0.22, 0.12)]
	return {ballistic = "solid_door", color = cols[_rng.randi() % cols.size()], thickness = 0.045, label = "front door"}


## Door from the garage into `r` (on the house wall the garage is built against).
func _ext_door_from_garage(r: Dictionary) -> void:
	var side := "xmax" if _mirror else "xmin"
	var lo := maxf(r.z0, garage.z0) + 0.6
	var hi: float = r.z1 - 0.6
	if hi <= lo and r.kind != "hall":
		return
	_ext_open.append({room = r, side = side, c = _rng.randf_range(lo, hi) if r.kind != "hall" else (r.z0 + r.z1) / 2.0, w = 0.86, kind = "door",
		door = {ballistic = "solid_door", color = Color(0.95, 0.94, 0.9), thickness = 0.045, label = "garage door"}, garage = true})


# ================================================================== openings

## The edge two rooms share: {axis = "x" (a line x = c) | "z", c, lo, hi, side_a, side_b} or {}.
func _shared(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.floor != b.floor:
		return {}
	for p in [[a.x1, b.x0, "xmax", "xmin"], [a.x0, b.x1, "xmin", "xmax"]]:
		if absf(p[0] - p[1]) < EPS:
			var lo := maxf(a.z0, b.z0)
			var hi := minf(a.z1, b.z1)
			if hi - lo > 0.05:
				return {axis = "x", c = p[0], lo = lo, hi = hi, side_a = p[2], side_b = p[3]}
	for p in [[a.z1, b.z0, "zmax", "zmin"], [a.z0, b.z1, "zmin", "zmax"]]:
		if absf(p[0] - p[1]) < EPS:
			var lo := maxf(a.x0, b.x0)
			var hi := minf(a.x1, b.x1)
			if hi - lo > 0.05:
				return {axis = "z", c = p[0], lo = lo, hi = hi, side_a = p[2], side_b = p[3]}
	return {}


func _resolve_connections() -> void:
	for cn: Dictionary in _conns:
		var s := _shared(cn.a, cn.b)
		if s.is_empty():
			push_warning("suburban house: %s and %s don't touch" % [cn.a.name, cn.b.name])
			continue
		var span: float = s.hi - s.lo
		var w: float = minf(cn.w, span - (0.0 if cn.door.get("edge", false) else 0.3))
		if w < 0.6:
			push_warning("suburban house: no room for a door between %s and %s" % [cn.a.name, cn.b.name])
			continue
		var margin := 0.0 if cn.door.get("edge", false) else 0.15
		var lo: float = s.lo + w / 2.0 + margin
		var hi: float = s.hi - w / 2.0 - margin
		var c: float
		if not is_nan(cn.at):
			c = clampf(cn.at, lo, hi)
		elif cn.kind == "door":
			# Doors go near a corner, like they do (furniture fits the long walls).
			var r := _rng.randf()
			c = lo if r < 0.4 else (hi if r < 0.8 else _rng.randf_range(lo, hi))
		else:
			c = _rng.randf_range(lo, hi)
		cn.s = s
		cn.c = c
		cn.w = w
		cn.a.openings.append({side = s.side_a, c = c, w = w, kind = cn.kind})
		cn.b.openings.append({side = s.side_b, c = c, w = w, kind = cn.kind})


func _side_span(r: Dictionary, side: String) -> Vector2:
	return Vector2(r.x0, r.x1) if side in ["zmin", "zmax"] else Vector2(r.z0, r.z1)


func _on_boundary(r: Dictionary, side: String) -> bool:
	match side:
		"xmin": return absf(r.x0 - fx0) < EPS
		"xmax": return absf(r.x1 - fx1) < EPS
		"zmin": return absf(r.z0 - fz0) < EPS
		"zmax": return absf(r.z1 - fz1) < EPS
	return false


## Windows in every outside wall, plus the sliding door to the back yard.
func _windows() -> void:
	# Back door: a slider from the kitchen / family / dining room.
	if true:
		var cands: Array = []
		for r: Dictionary in plan:
			if r.floor == 0 and r.kind in ["kitchen", "family", "dining"] and _on_boundary(r, "zmin") and r.x1 - r.x0 > 2.6:
				cands.append(r)
		if not cands.is_empty():
			var r: Dictionary = cands[_rng.randi() % cands.size()]
			var c := _rng.randf_range(r.x0 + 1.2, r.x1 - 1.2)
			_ext_open.append({room = r, side = "zmin", c = c, w = 1.8, kind = "window", sill = 0.0, head = DOOR_H, slider = true})
	if front_door_pos == Vector3.ZERO:
		for r: Dictionary in plan:
			if r.kind == "foyer":
				var c := _rng.randf_range(r.x0 + 0.65, r.x1 - 0.65)
				front_door_pos = Vector3(c, 0, fz1)
				_ext_open.append({room = r, side = "zmax", c = c, w = 0.97, kind = "door", door = _front_door()})
	for r: Dictionary in plan:
		for side: String in ["xmin", "xmax", "zmin", "zmax"]:
			if not _on_boundary(r, side):
				continue
			var span := _side_span(r, side)
			var lo := span.x + 0.35
			var hi := span.y - 0.35
			var taken: Array = []
			for o: Dictionary in _ext_open:
				if o.room == r and o.side == side:
					taken.append(Vector2(o.c - o.w / 2.0 - 0.3, o.c + o.w / 2.0 + 0.3))
			# The garage wall has no windows where the garage is.
			if not garage.is_empty() and r.floor == 0 and side == ("xmax" if _mirror else "xmin"):
				hi = minf(hi, garage.z0 - 0.35)
			var L := hi - lo
			if L < 0.8:
				continue
			var kind: String = r.kind
			var n := 1
			var w := 1.0
			var sill := 36.0 * IN
			var head := 82.0 * IN
			match kind:
				"bath", "powder", "master_bath", "laundry":
					w = 0.7
					sill = 1.4
				"hall", "master_closet":
					if _rng.randf() < 0.5:
						continue
					w = 0.6
				"kitchen":
					w = 1.4
					sill = 42.0 * IN
				"living", "family":
					if side == "zmax" and L > 3.0:
						w = _rng.randf_range(2.0, 2.6)
						sill = 0.55
					else:
						n = clampi(int(L / 2.6), 1, 2)
				"void":
					w = 1.0
					sill = 0.6
				"foyer":
					w = 0.35       # sidelight
					sill = 0.3
				_:
					n = clampi(int(L / 2.8), 1, 2)
					w = _rng.randf_range(0.9, 1.2)
			if kind == "garage":
				continue
			for i in n:
				var c := lo + L * (i + 0.5) / n
				var ww := minf(w, L / n - 0.2)
				var clash := false
				for t: Vector2 in taken:
					if c + ww / 2.0 > t.x and c - ww / 2.0 < t.y:
						clash = true
				if clash and kind == "foyer":
					# sidelight goes beside the door instead
					for o: Dictionary in _ext_open:
						if o.room == r and o.side == side and o.kind == "door":
							c = o.c + (o.w / 2.0 + 0.3) * (1.0 if o.c - r.x0 < r.x1 - o.c else -1.0)
							clash = c - ww / 2.0 < span.x + 0.15 or c + ww / 2.0 > span.y - 0.15
				if clash or ww < 0.3:
					continue
				_ext_open.append({room = r, side = side, c = c, w = ww, kind = "window", sill = sill, head = head})
	for o: Dictionary in _ext_open:
		o.room.openings.append({side = o.side, c = o.c, w = o.w, kind = o.kind, sill = o.get("sill", 0.0)})


# ================================================================== structure

func _materials() -> void:
	# Built-in procedural finishes, plus any uploaded textures (TexturePool) in the same pools.
	var paints := [Color(0.88, 0.85, 0.78), Color(0.9, 0.88, 0.84), Color(0.85, 0.82, 0.72), Color(0.82, 0.86, 0.84), Color(0.9, 0.84, 0.8), Color(0.83, 0.84, 0.9)]
	var builtin_paint: Array = []
	for i in paints.size():
		builtin_paint.append(textured("paint_%d" % i, img_noise(paints[i], 0.015, 16, 2 + i), 1.0, 0.9))
	_paint = textures.pool("walls", builtin_paint)
	_plain_paint = builtin_paint[0]
	var sidings := [Color(0.84, 0.82, 0.72), Color(0.92, 0.92, 0.9), Color(0.62, 0.68, 0.74), Color(0.85, 0.8, 0.55), Color(0.62, 0.68, 0.56), Color(0.75, 0.7, 0.62)]
	var builtin_siding: Array = []
	for sc: Color in sidings:
		builtin_siding.append(textured("siding_%s" % sc.to_html(), img_boards(sc, sc.darkened(0.25), 8), 0.8, 0.7))
	_siding = textures.pick("exterior/siding", builtin_siding, _rng)
	_mats["siding"] = _siding
	var builtin_roof: Array = []
	for shingle: Color in [Color(0.3, 0.28, 0.27), Color(0.25, 0.22, 0.2), Color(0.35, 0.32, 0.28), Color(0.2, 0.22, 0.25)]:
		builtin_roof.append(textured("shingles_%s" % shingle.to_html(), img_boards(shingle, shingle.darkened(0.4), 10, false, 64, 0.06), 1.0, 1.0))
	_mats["shingles"] = textures.pick("roofs", builtin_roof, _rng)
	ceiling_material = textures.pick("ceilings", [textured("popcorn", img_noise(Color(0.9, 0.89, 0.86), 0.05, 32, 4), 0.5, 1.0)], _rng)


func _room_paint(r: Dictionary) -> Material:
	return _paint[absi(hash(r.name + str(layout_seed))) % _paint.size()]


func _ext_layers(r: Dictionary) -> Array:
	return [[0.016, "drywall", _room_paint(r)], [EXT_WALL - 0.016, "exterior_sheathing", _siding]]


func _int_layers(r: Dictionary) -> Array:
	return [[INT_WALL, "drywall_partition", _room_paint(r)]]


func _wall_along(axis: String, c: float, lo: float, hi: float, layers: Array, inside: float, openings: Array, height := CEILING) -> void:
	var ops: Array = []
	for o: Dictionary in openings:
		var d := o.duplicate()
		d.at = o.c - lo
		ops.append(d)
	if axis == "z":
		wall(Vector2(lo, c), Vector2(hi, c), layers, inside, ops, height)
	else:
		wall(Vector2(c, lo), Vector2(c, hi), layers, inside, ops, height)


func _build_structure() -> void:
	var carpet_cols := [Color(0.72, 0.66, 0.56), Color(0.6, 0.47, 0.5), Color(0.3, 0.48, 0.48), Color(0.34, 0.4, 0.56), Color(0.55, 0.55, 0.5), Color(0.45, 0.5, 0.4)]
	var carpets: Array = []
	for c: Color in carpet_cols:
		carpets.append(textured("carpet_%s" % c.to_html(), img_noise(c, 0.04, 32, 11), 0.4, 1.0))
	carpets = textures.pool("floors/carpet", carpets)
	var vinyl: Material = textures.pick("floors/vinyl", [textured("vinyl", img_checker(Color(0.86, 0.82, 0.7), Color(0.75, 0.68, 0.55)), 0.6, 0.5)], _rng)
	var tile: Material = textures.pick("floors/tile", [textured("tile", img_checker(Color(0.93, 0.93, 0.9), Color(0.88, 0.88, 0.86), 32, 4), 0.6, 0.3)], _rng)
	var oak: Material = textures.pick("floors/wood", [textured("oak_floor", img_boards(Color(0.62, 0.45, 0.26), Color(0.45, 0.3, 0.17), 8, true), 0.9, 0.5)], _rng)
	var concrete: Material = textures.pick("ground/concrete", [textured("concrete", img_noise(Color(0.68, 0.67, 0.64), 0.04, 32, 8), 1.2, 0.95)], _rng)
	var subfloor := flat("floor_band", Color(0.8, 0.78, 0.72), 0.9)
	var house_carpet: Material = carpets[_rng.randi() % carpets.size()]
	# Slab under everything (the lawn underneath is what you stand on at ground level).
	box(Vector3(fx1 - fx0, 0.02, fz1 - fz0), Vector3((fx0 + fx1) / 2.0, 0.0, (fz0 + fz1) / 2.0), concrete, "concrete", 0.0, false)
	for fl in stories:
		floor_y = fl * FH
		var here: Array = plan.filter(func(r): return r.floor == fl)
		for r: Dictionary in here:
			if r.kind == "void":
				room(r.x0, r.z0, r.x1, r.z1, null, true, 0.9)
				continue
			var fm: Material = house_carpet
			match r.kind:
				"kitchen", "laundry", "dining": fm = vinyl if r.kind != "dining" or _rng.randf() < 0.5 else oak
				"bath", "master_bath", "powder": fm = tile
				"foyer": fm = oak if _rng.randf() < 0.6 else tile
				"bedroom": fm = carpets[_rng.randi() % carpets.size()]
			var ceil: bool = not (r.kind == "foyer" and stories == 2)
			room(r.x0, r.z0, r.x1, r.z1, fm, ceil, 0.0 if r.group == "master" and r.kind == "master_closet" else (0.6 if r.kind in ["hall", "master_closet", "powder", "laundry"] else 0.9))
			if fl == 1:
				# The floor under it (joists + subfloor), which is the ceiling of the room below.
				box(Vector3(r.x1 - r.x0, FLOOR_T, r.z1 - r.z0), Vector3((r.x0 + r.x1) / 2.0, -FLOOR_T / 2.0, (r.z0 + r.z1) / 2.0), subfloor, "wood")
		# Walls between rooms.
		for i in here.size():
			for j in range(i + 1, here.size()):
				var a: Dictionary = here[i]
				var b: Dictionary = here[j]
				var s := _shared(a, b)
				if s.is_empty():
					continue
				if a.group != "" and a.group == b.group:
					a.openings.append({side = s.side_a, c = (s.lo + s.hi) / 2.0, w = s.hi - s.lo, kind = "group"})
					b.openings.append({side = s.side_b, c = (s.lo + s.hi) / 2.0, w = s.hi - s.lo, kind = "group"})
					continue
				var ops: Array = []
				for cn: Dictionary in _conns:
					if cn.has("c") and ((cn.a == a and cn.b == b) or (cn.a == b and cn.b == a)):
						ops.append({c = cn.c, w = cn.w, kind = cn.kind, door = cn.door})
				var kinds := [a.kind, b.kind]
				if "void" in kinds and "hall" in kinds:
					_railing(s, ops)
					continue
				_wall_along(s.axis, s.c, s.lo, s.hi, _int_layers(a), 1.0, ops)
		# Outside walls.
		for r: Dictionary in here:
			for side: String in ["xmin", "xmax", "zmin", "zmax"]:
				if not _on_boundary(r, side):
					continue
				var span := _side_span(r, side)
				var lo := span.x
				var hi := span.y
				var t := EXT_WALL / 2.0
				if side in ["zmin", "zmax"]:
					if absf(lo - fx0) < EPS: lo -= t
					if absf(hi - fx1) < EPS: hi += t
				else:
					if absf(lo - fz0) < EPS: lo += t
					if absf(hi - fz1) < EPS: hi -= t
				var ops: Array = []
				for o: Dictionary in _ext_open:
					if o.room == r and o.side == side:
						ops.append(o)
				var inside := 1.0 if side in ["xmin", "zmin"] else -1.0
				var line: float = {xmin = fx0, xmax = fx1, zmin = fz0, zmax = fz1}[side]
				var h := FH if (stories == 2 and fl == 0) else CEILING
				_wall_along("z" if side in ["zmin", "zmax"] else "x", line, lo, hi, _ext_layers(r), inside, ops, h)
	floor_y = 0.0
	# Ceiling slab and roof over the top storey.
	var top := (stories - 1) * FH + CEILING
	box(Vector3(fx1 - fx0, 0.05, fz1 - fz0), Vector3((fx0 + fx1) / 2.0, top + 0.045, (fz0 + fz1) / 2.0), _plain_paint, "drywall")
	gable_roof(fx0, fz0, fx1, fz1, top + 0.07, _rng.randf_range(22.0, 32.0), _mats["shingles"])
	_shutters()
	if not garage.is_empty():
		_build_garage()


## A guard rail (36 in) along an edge open to the floor below, with gaps for `ops`.
func _railing(s: Dictionary, ops: Array) -> void:
	var white := flat("trim", Color(0.95, 0.94, 0.9), 0.5)
	var cuts: Array = []
	for o: Dictionary in ops:
		cuts.append(Vector2(o.c - o.w / 2.0, o.c + o.w / 2.0))
	cuts.sort_custom(func(p, q): return p.x < q.x)
	var pieces: Array = []
	var cur: float = s.lo
	for c: Vector2 in cuts:
		if c.x > cur:
			pieces.append(Vector2(cur, c.x))
		cur = maxf(cur, c.y)
	if cur < s.hi:
		pieces.append(Vector2(cur, s.hi))
	var h := 36.0 * IN
	for p: Vector2 in pieces:
		var L := p.y - p.x
		var mid := (p.x + p.y) / 2.0
		var pos := Vector3(mid, h, s.c) if s.axis == "z" else Vector3(s.c, h, mid)
		box(Vector3(L, 0.07, 0.09) if s.axis == "z" else Vector3(0.09, 0.07, L), pos, _f.wood, "wood")
		# Collision for the whole height so nobody walks off the edge, balusters to look at.
		_solid_body(Vector3(L, h, 0.05) if s.axis == "z" else Vector3(0.05, h, L), pos - Vector3(0, h / 2.0, 0), "wood")
		var n := int(L / 0.12)
		for i in n:
			var q := p.x + L * (i + 0.5) / n
			box(Vector3(0.03, h, 0.03), (Vector3(q, h / 2.0, s.c) if s.axis == "z" else Vector3(s.c, h / 2.0, q)), white, "wood", 0.0, false)


## Collision only, at the storey being built.
func _solid_body(size: Vector3, pos: Vector3, ballistic: String) -> void:
	var body := StaticBody3D.new()
	body.set_meta("material", ballistic)
	body.position = pos + Vector3(0, floor_y, 0)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _shutters() -> void:
	var cols := [Color(0.1, 0.12, 0.11), Color(0.15, 0.2, 0.32), Color(0.32, 0.1, 0.1), Color(0.2, 0.3, 0.22)]
	var c: Color = cols[_rng.randi() % cols.size()]
	var shutter := textured("shutter_%s" % c.to_html(), img_boards(c, c.darkened(0.6), 12), 0.4)
	for o: Dictionary in _ext_open:
		if o.side != "zmax" or o.kind != "window" or o.w < 0.8 or o.room.kind == "foyer":
			continue
		var y: float = o.room.floor * FH + (o.sill + o.head) / 2.0
		for side in [-1.0, 1.0]:
			box(Vector3(0.38, o.head - o.sill, 0.03), Vector3(o.c + side * (o.w / 2.0 + 0.24), y, fz1 + EXT_WALL / 2.0 + 0.02), shutter, "wood", 0.0, false)
	var porch := OmniLight3D.new()
	porch.position = Vector3(front_door_pos.x + 0.65, 2.0, fz1 + 0.3)
	porch.light_color = Color(1, 0.85, 0.6)
	porch.light_energy = 0.6
	porch.omni_range = 4.0
	add_child(porch)


func _build_garage() -> void:
	floor_y = 0.0
	var g := garage
	var paint: Material = _plain_paint
	var ext := [[0.016, "drywall", paint], [EXT_WALL - 0.016, "exterior_sheathing", _siding]]
	var t := EXT_WALL / 2.0
	var outer_x: float = g.x0 if not _mirror else g.x1
	var house_x: float = g.x1 if not _mirror else g.x0
	var sgn := -1.0 if not _mirror else 1.0       # from the house toward the outer wall
	# Front (with the overhead door) and back walls, stopping at the house's outside face.
	var a := minf(outer_x - sgn * t, house_x + sgn * t)
	var b := maxf(outer_x - sgn * t, house_x + sgn * t)
	var door_w := minf(16.0 * FT, (b - a) - 0.8)
	var dc := (a + b) / 2.0
	_wall_along("z", g.z1, a, b, ext, -1.0, [{c = dc, w = door_w, kind = "open", head = 7.0 * FT}])
	_wall_along("z", g.z0, a, b, ext, 1.0, [])
	_wall_along("x", outer_x, g.z0 + t, g.z1 - t, ext, -sgn, [{c = (g.z0 + g.z1) / 2.0, w = 0.86, kind = "window"}] if _rng.randf() < 0.6 else [])
	var gdoor := textured("garage_door", img_boards(Color(0.93, 0.93, 0.9), Color(0.7, 0.7, 0.68), 4), 0.55, 0.5)
	box(Vector3(door_w, 7.0 * FT, 0.05), Vector3(dc, 7.0 * FT / 2.0, g.z1), gdoor, "appliance")
	box(Vector3(g.x1 - g.x0, 0.05, g.z1 - g.z0), Vector3((g.x0 + g.x1) / 2.0, CEILING + 0.045, (g.z0 + g.z1) / 2.0), paint, "drywall")
	# The overhang stops at the house wall (on a two-storey house it would poke into the upstairs).
	var ov := 0.3
	var t2 := EXT_WALL / 2.0
	if _mirror:
		gable_roof(g.x0 + ov + t2, g.z0, g.x1, g.z1, CEILING + 0.07, 22.0, _mats["shingles"], ov)
	else:
		gable_roof(g.x0, g.z0, g.x1 - ov - t2, g.z1, CEILING + 0.07, 22.0, _mats["shingles"], ov)
	room(g.x0, g.z0, g.x1, g.z1, flat("garage_floor", Color(0.55, 0.55, 0.53)), false, 0.7)
	var gr := {name = "garage", kind = "garage", floor = 0, x0 = g.x0, z0 = g.z0, x1 = g.x1, z1 = g.z1, group = "", openings = [], spots = [], items = []}
	for o: Dictionary in _ext_open:
		if o.get("garage", false):
			gr.openings.append({side = "xmin" if _mirror else "xmax", c = o.c, w = o.w, kind = "door"})
	gr.openings.append({side = "zmax", c = dc, w = door_w, kind = "open"})
	plan.append(gr)


## The flight from the foyer up to the hall: solid treads (collision) under an
## invisible ramp along the nosings, so feet and the AI's navmesh both see a slope.
func _build_stair() -> void:
	if stair.is_empty():
		return
	floor_y = 0.0
	var x0: float = stair.x0
	var x1: float = stair.x1
	var zt: float = stair.z_top
	var zb: float = stair.z_base
	var tread := textured("stair_carpet", img_noise(Color(0.62, 0.56, 0.48), 0.04, 32, 21), 0.4, 1.0)
	var riser := flat("trim", Color(0.95, 0.94, 0.9), 0.5)
	var w := x1 - x0
	var cx := (x0 + x1) / 2.0
	for i in STEPS:
		var top := (i + 1) * RISE
		var zf := zb - i * TREAD            # front edge (nosing) of this tread
		var zback := zt
		box(Vector3(w, top, zf - zback), Vector3(cx, top / 2.0, (zf + zback) / 2.0), tread, "wood")
		box(Vector3(w, RISE - 0.02, 0.01), Vector3(cx, top - RISE / 2.0, zf + 0.004), riser, "wood", 0.0, false)
	# Ramp through the nosings, 1 cm proud.
	var z_lo := zb + TREAD
	var z_hi := zt + TREAD
	var L := Vector2(z_lo - z_hi, FH).length()
	var ang := atan2(FH, z_lo - z_hi)
	var thick := 0.04
	var mid := Vector3(cx, FH / 2.0 + 0.01, (z_lo + z_hi) / 2.0) - Vector3(0, cos(ang), sin(ang)) * (thick / 2.0) * Vector3(0, 1, 1)
	var ramp := StaticBody3D.new()
	ramp.set_meta("material", "wood")
	ramp.position = mid
	ramp.rotation.x = ang        # rises toward -Z
	var sh := BoxShape3D.new()
	sh.size = Vector3(w, thick, L)
	var cs := CollisionShape3D.new()
	cs.shape = sh
	ramp.add_child(cs)
	add_child(ramp)
	# Handrail on the open side.
	var foyer: Dictionary = stair.foyer
	var open_x := x1 if absf(x0 - foyer.x0) < EPS else x0
	# Starts at the newel on the second tread, so the foot of the stair stays open on both sides.
	# Ends a tread short of the top so it doesn't hang over the landing.
	var skip := 0.75
	var skip_top := 0.45
	var rail := StaticBody3D.new()
	rail.set_meta("material", "wood")
	rail.position = Vector3(open_x, FH / 2.0 + 0.5, (z_lo + z_hi) / 2.0) + Vector3(0, sin(ang), -cos(ang)) * ((skip - skip_top) / 2.0)
	rail.rotation.x = ang
	L -= skip + skip_top
	var rs := BoxShape3D.new()
	rs.size = Vector3(0.05, 0.9, L)
	var rcs := CollisionShape3D.new()
	rcs.shape = rs
	rail.add_child(rcs)
	add_child(rail)
	var rm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, L)
	rm.mesh = bm
	rm.material_override = _f.wood
	rm.position = Vector3(0, 0.42, 0)
	rail.add_child(rm)
	for i in range(2, STEPS):
		var zf := zb - i * TREAD - TREAD / 2.0
		var y0 := (i + 1) * RISE
		box(Vector3(0.03, 0.88, 0.03), Vector3(open_x, y0 + 0.44, zf), riser, "wood", 0.0, false)
	box(Vector3(0.1, 1.05, 0.1), Vector3(open_x, 2 * RISE + 0.52, zb - 1.5 * TREAD), _f.wood, "wood", 0.0, false)     # newel post
	foyer.items.append(Rect2(x0, zt, w, zb - zt + 0.05))
	foyer.keepout = [Rect2(x0 - 0.1, zb, w + 0.2, 0.9)]


# ================================================================== furniture

func _inner(r: Dictionary) -> Rect2:
	return Rect2(r.x0 + 0.08, r.z0 + 0.08, r.x1 - r.x0 - 0.16, r.z1 - r.z0 - 0.16)


## Keep-out rects: a door / opening's swing and the walk through it.
func _keepouts(r: Dictionary) -> Array:
	var out: Array = r.get("keepout", []).duplicate()
	for o: Dictionary in r.openings:
		if o.kind == "window":
			if o.get("sill", 1.0) < 0.3:       # slider
				out.append(_strip(r, o.side, o.c - o.w / 2.0 - 0.2, o.c + o.w / 2.0 + 0.2, 1.0))
			continue
		var depth := 0.6 if o.kind == "group" else 1.0
		out.append(_strip(r, o.side, o.c - o.w / 2.0 - 0.15, o.c + o.w / 2.0 + 0.15, depth))
	return out


## A rect `depth` into the room along `side` between a..b (coords along that side).
func _strip(r: Dictionary, side: String, a: float, b: float, depth: float) -> Rect2:
	match side:
		"zmin": return Rect2(a, r.z0, b - a, depth)
		"zmax": return Rect2(a, r.z1 - depth, b - a, depth)
		"xmin": return Rect2(r.x0, a, depth, b - a)
		_: return Rect2(r.x1 - depth, a, depth, b - a)


func _windows_on(r: Dictionary, side: String) -> Array:
	var out: Array = []
	for o: Dictionary in r.openings:
		if o.kind == "window" and o.side == side:
			out.append(Vector2(o.c - o.w / 2.0 - 0.1, o.c + o.w / 2.0 + 0.1))
	return out


func _grid_setup(r: Dictionary) -> void:
	var inner := _inner(r)
	var cols := maxi(1, int(inner.size.x / CELL))
	var rows := maxi(1, int(inner.size.y / CELL))
	r.gw = cols
	r.gh = rows
	var g := PackedByteArray()
	g.resize(cols * rows)
	g.fill(0)
	var m := CLEAR - 0.08
	for y in rows:
		for x in cols:
			var px := inner.position.x + (x + 0.5) * CELL
			var pz := inner.position.y + (y + 0.5) * CELL
			if px < inner.position.x + m or px > inner.end.x - m or pz < inner.position.y + m or pz > inner.end.y - m:
				g[y * cols + x] = 1
	r.grid = g
	# Doorway cells are always open, even next to the wall (that's where you come in).
	r.entries = []
	for o: Dictionary in r.openings:
		if o.kind == "window":
			continue
		var p: Vector2
		match o.side:
			"zmin": p = Vector2(o.c, r.z0 + 0.45)
			"zmax": p = Vector2(o.c, r.z1 - 0.45)
			"xmin": p = Vector2(r.x0 + 0.45, o.c)
			_: p = Vector2(r.x1 - 0.45, o.c)
		r.entries.append(p)
	for it: Rect2 in r.items:
		_grid_mark(r, it, 1)


func _cell_of(r: Dictionary, p: Vector2) -> Vector2i:
	var inner := _inner(r)
	return Vector2i(clampi(int((p.x - inner.position.x) / CELL), 0, r.gw - 1), clampi(int((p.y - inner.position.y) / CELL), 0, r.gh - 1))


func _grid_mark(r: Dictionary, rect: Rect2, v: int) -> void:
	var grown := rect.grow(CLEAR)
	var a := _cell_of(r, grown.position)
	var b := _cell_of(r, grown.end)
	var g: PackedByteArray = r.grid
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			g[y * r.gw + x] = v
	r.grid = g


## Every doorway of the room can still reach every other one.
func _connected(r: Dictionary) -> bool:
	var entries: Array = r.entries
	if entries.size() == 0:
		r.reach = PackedByteArray()
		return true
	var g: PackedByteArray = r.grid
	var W: int = r.gw
	var H: int = r.gh
	var seen := PackedByteArray()
	seen.resize(W * H)
	seen.fill(0)
	var start := _cell_of(r, entries[0])
	var q: Array[int] = [start.y * W + start.x]
	seen[q[0]] = 1
	var count := 0
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		count += 1
		var x := i % W
		var y := i / W
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if seen[j] == 0 and g[j] == 0:
				seen[j] = 1
				q.append(j)
	r.reach = seen
	for e: Vector2 in entries:
		var c := _cell_of(r, e)
		if seen[c.y * W + c.x] == 0:
			return false
	# And leave a fair bit of floor to move around on.
	var free := 0
	for v in g:
		if v == 0:
			free += 1
	return count >= free * 0.6 or count > 60


func _overlaps(rect: Rect2, list: Array, pad := 0.0) -> bool:
	for o: Rect2 in list:
		if rect.grow(pad).intersects(o, false) and rect.grow(pad).intersection(o).get_area() > 0.0005:
			return true
	return false


## Put piece `fn` (w along the wall, d deep) in room r.
## opts: sides (Array), tall, corner, center, rot, args (extra builder args), near (Rect2 to sit in front of).
func _place(r: Dictionary, fn: String, w: float, d: float, opts := {}) -> Dictionary:
	var inner := _inner(r)
	var tries: int = opts.get("tries", 24)
	var keep := _keepouts(r)
	for _t in tries:
		var side: String
		var rot := 0.0
		var rect: Rect2
		var centre: Vector2
		if opts.has("at"):
			rect = opts.at
			centre = rect.get_center()
			rot = opts.get("rot", 0.0)
			side = opts.get("side", "")
		elif opts.get("center", false):
			var vertical: bool = opts.get("rot", -1.0) == 90.0 or (opts.get("rot", -1.0) == -1.0 and inner.size.y > inner.size.x and _rng.randf() < 0.7)
			var sw := d if vertical else w
			var sd := w if vertical else d
			var mx := (inner.size.x - sw) / 2.0 - 0.5
			var mz := (inner.size.y - sd) / 2.0 - 0.5
			if mx < 0.0 or mz < 0.0:
				return {}
			centre = inner.get_center() + Vector2(_rng.randf_range(-mx, mx) * 0.5, _rng.randf_range(-mz, mz) * 0.5)
			rect = Rect2(centre - Vector2(sw, sd) / 2.0, Vector2(sw, sd))
			rot = 90.0 if vertical else 0.0
		else:
			var sides: Array = opts.get("sides", ["xmin", "xmax", "zmin", "zmax"])
			side = sides[_rng.randi() % sides.size()]
			var along := Vector2(inner.position.x, inner.end.x) if side in ["zmin", "zmax"] else Vector2(inner.position.y, inner.end.y)
			if along.y - along.x < w:
				continue
			var t: float
			if opts.get("corner", false):
				t = along.x + w / 2.0 if _rng.randf() < 0.5 else along.y - w / 2.0
			else:
				t = _rng.randf_range(along.x + w / 2.0, along.y - w / 2.0)
			match side:
				"zmin":
					rect = Rect2(t - w / 2.0, inner.position.y, w, d); rot = 0.0
				"zmax":
					rect = Rect2(t - w / 2.0, inner.end.y - d, w, d); rot = 180.0
				"xmin":
					rect = Rect2(inner.position.x, t - w / 2.0, d, w); rot = 90.0
				"xmax":
					rect = Rect2(inner.end.x - d, t - w / 2.0, d, w); rot = 270.0
			centre = rect.get_center()
		if not inner.encloses(rect.grow(-0.005)):
			continue
		if _overlaps(rect, keep) or _overlaps(rect, r.items, -0.01):
			continue
		if opts.get("tall", false) and side != "":
			var bad := false
			for win: Vector2 in _windows_on(r, side):
				var a := rect.position.x if side in ["zmin", "zmax"] else rect.position.y
				var b := rect.end.x if side in ["zmin", "zmax"] else rect.end.y
				if b > win.x and a < win.y:
					bad = true
			if bad:
				continue
		var before: PackedByteArray = r.grid.duplicate()
		_grid_mark(r, rect, 1)
		if not _connected(r):
			r.grid = before
			continue
		r.items.append(rect)
		var n := Node3D.new()
		n.position = Vector3(centre.x, r.floor * FH, centre.y)
		n.rotation_degrees.y = rot
		add_child(n)
		var args: Array = [n, w, d]
		args.append_array(opts.get("args", []))
		_f.callv(fn, args)
		return {rect = rect, side = side, rot = rot, node = n}
	return {}


## Something on the wall (posters, pictures): no footprint, kept off doors and windows.
func _hang(r: Dictionary, fn: String, w: float, args: Array = []) -> void:
	for _t in 12:
		var side: String = ["xmin", "xmax", "zmin", "zmax"][_rng.randi() % 4]
		var span := _side_span(r, side)
		if span.y - span.x < w + 0.6:
			continue
		var t := _rng.randf_range(span.x + w / 2.0 + 0.3, span.y - w / 2.0 - 0.3)
		var bad := false
		for o: Dictionary in r.openings:
			if o.side == side and absf(o.c - t) < o.w / 2.0 + w / 2.0 + 0.1:
				bad = true
		if bad:
			continue
		var inset := 0.065
		var n := Node3D.new()
		match side:
			"zmin": n.position = Vector3(t, 0, r.z0 + inset); n.rotation_degrees.y = 0.0
			"zmax": n.position = Vector3(t, 0, r.z1 - inset); n.rotation_degrees.y = 180.0
			"xmin": n.position = Vector3(r.x0 + inset, 0, t); n.rotation_degrees.y = 90.0
			"xmax": n.position = Vector3(r.x1 - inset, 0, t); n.rotation_degrees.y = 270.0
		n.position.y = r.floor * FH
		add_child(n)
		var a: Array = [n, w]
		a.append_array(args)
		_f.callv(fn, a)
		return


## Flat things with no footprint (rugs) on a world rect.
func _decor(r: Dictionary, fn: String, rect: Rect2, rot: float) -> void:
	rect = rect.intersection(_inner(r))
	var n := Node3D.new()
	n.position = Vector3(rect.get_center().x, r.floor * FH, rect.get_center().y)
	var along_x := int(rot) % 180 == 0
	add_child(n)
	n.rotation_degrees.y = rot
	_f.callv(fn, [n, rect.size.x if along_x else rect.size.y, rect.size.y if along_x else rect.size.x])


## In front of a placed piece (coffee table before the sofa, rug under it).
func _front_of(p: Dictionary, gap: float, w: float, d: float) -> Rect2:
	var rc: Rect2 = p.rect
	var c := rc.get_center()
	match p.side:
		"zmin": return Rect2(c.x - w / 2.0, rc.end.y + gap, w, d)
		"zmax": return Rect2(c.x - w / 2.0, rc.position.y - gap - d, w, d)
		"xmin": return Rect2(rc.end.x + gap, c.y - w / 2.0, d, w)
		_: return Rect2(rc.position.x - gap - d, c.y - w / 2.0, d, w)


func _opposite(side: String) -> String:
	return {xmin = "xmax", xmax = "xmin", zmin = "zmax", zmax = "zmin"}.get(side, "zmin")


func _beside(p: Dictionary, w: float, d: float, which: float) -> Dictionary:
	## Rect next to piece p along its wall (which = -1/+1), same wall.
	var rc: Rect2 = p.rect
	match p.side:
		"zmin": return {rect = Rect2((rc.position.x - w - 0.05) if which < 0 else rc.end.x + 0.05, rc.position.y, w, d), rot = 0.0}
		"zmax": return {rect = Rect2((rc.position.x - w - 0.05) if which < 0 else rc.end.x + 0.05, rc.end.y - d, w, d), rot = 180.0}
		"xmin": return {rect = Rect2(rc.position.x, (rc.position.y - w - 0.05) if which < 0 else rc.end.y + 0.05, d, w), rot = 90.0}
		_: return {rect = Rect2(rc.end.x - d, (rc.position.y - w - 0.05) if which < 0 else rc.end.y + 0.05, d, w), rot = 270.0}


func _ext_sides(r: Dictionary) -> Array:
	return ["xmin", "xmax", "zmin", "zmax"].filter(func(s): return _on_boundary(r, s) and not (r.floor == 0 and not garage.is_empty() and s == ("xmax" if _mirror else "xmin") and r.z0 < garage.z1 and r.z1 > garage.z0))


func _furnish_all() -> void:
	for r: Dictionary in plan:
		if r.kind == "void":
			continue
		_grid_setup(r)
		floor_y = r.floor * FH
		match r.kind:
			"living": _living(r)
			"family": _family(r)
			"kitchen": _kitchen(r)
			"dining": _dining(r)
			"bedroom": _bedroom(r)
			"master": _master(r)
			"master_closet": _walk_in(r)
			"bath", "master_bath", "powder": _bath(r)
			"laundry": _laundry(r)
			"office": _office(r)
			"foyer": _foyer(r)
			"hall": _hall(r)
			"garage": _garage_stuff(r)
		_spots(r)
	floor_y = 0.0


func _living(r: Dictionary) -> void:
	var sofa := _place(r, "sofa", _rng.randf_range(1.9, 2.3), 0.9)
	if not sofa.is_empty():
		var ct := _front_of(sofa, 0.45, _rng.randf_range(1.0, 1.2), 0.6)
		_place(r, "coffee_table", ct.size.x if sofa.side in ["zmin", "zmax"] else ct.size.y, ct.size.y if sofa.side in ["zmin", "zmax"] else ct.size.x, {at = ct, rot = sofa.rot, tries = 1})
		_decor(r, "rug", ct.grow(0.45), sofa.rot)
		for s in [-1.0, 1.0]:
			if _rng.randf() < 0.6:
				var b := _beside(sofa, 0.5, 0.5, s)
				_place(r, "end_table", 0.5, 0.5, {at = b.rect, rot = b.rot, tries = 1})
		var opp := _opposite(sofa.side)
		if _rng.randf() < 0.5:
			_place(r, "entertainment_centre", 1.6, 0.5, {sides = [opp], tall = true})
		else:
			_place(r, "tv_stand", _rng.randf_range(1.0, 1.4), 0.45, {sides = [opp]})
	if _rng.randf() < 0.7:
		_place(r, "recliner", 0.9, 0.95)
	if _rng.randf() < 0.4:
		_place(r, "sofa", 1.5, 0.85)
	if _rng.randf() < 0.35 and not _ext_sides(r).is_empty():
		_place(r, "fireplace", 1.8, 0.55, {sides = _ext_sides(r), tall = true})
	if _rng.randf() < 0.2:
		_place(r, "piano", 1.5, 0.6, {tall = true})
	if _rng.randf() < 0.5:
		_place(r, "bookshelf", _rng.randf_range(0.8, 1.2), 0.32, {tall = true})
	if _rng.randf() < 0.6:
		_place(r, "plant", 0.4, 0.4, {corner = true})
	if _rng.randf() < 0.5:
		_place(r, "floor_lamp", 0.35, 0.35, {corner = true})
	if _rng.randf() < 0.5:
		_fan(r)
	for i in _rng.randi_range(1, 2):
		_hang(r, "picture", _rng.randf_range(0.5, 0.8))


func _family(r: Dictionary) -> void:
	if _rng.randf() < 0.5 and not _ext_sides(r).is_empty():
		_place(r, "fireplace", 1.8, 0.55, {sides = _ext_sides(r), tall = true})
	var sofa := _place(r, "sofa", _rng.randf_range(2.0, 2.4), 0.9)
	if not sofa.is_empty():
		var opp := _opposite(sofa.side)
		_place(r, "tv_stand", _rng.randf_range(1.0, 1.4), 0.45, {sides = [opp]})
		var ct := _front_of(sofa, 0.45, 1.1, 0.6)
		_place(r, "coffee_table", 1.1, 0.6, {at = ct, rot = sofa.rot, tries = 1})
		_decor(r, "rug", ct.grow(0.45), sofa.rot)
	if _rng.randf() < 0.6:
		_place(r, "sofa", _rng.randf_range(1.5, 2.0), 0.9)
	if _rng.randf() < 0.5:
		_place(r, "recliner", 0.9, 0.95)
	if _rng.randf() < 0.3:
		_place(r, "beanbag", 0.75, 0.75)
	if _rng.randf() < 0.6:
		_place(r, "bookshelf", _rng.randf_range(0.8, 1.2), 0.32, {tall = true})
	if _rng.randf() < 0.4:
		_place(r, "plant", 0.4, 0.4, {corner = true})
	if _rng.randf() < 0.6:
		_fan(r)
	_hang(r, "picture", _rng.randf_range(0.5, 0.8))


func _kitchen(r: Dictionary) -> void:
	# Sink counter under a window if there is one.
	var ext := _ext_sides(r)
	var win_side := ""
	for s: String in ext:
		if not _windows_on(r, s).is_empty():
			win_side = s
	if win_side != "":
		var w: Vector2 = _windows_on(r, win_side)[0]
		var cx := (w.x + w.y) / 2.0
		var L := _rng.randf_range(2.2, 3.2)
		var inner := _inner(r)
		var rect: Rect2
		var rot := 0.0
		match win_side:
			"zmin": rect = Rect2(cx - L / 2.0, inner.position.y, L, 0.62); rot = 0.0
			"zmax": rect = Rect2(cx - L / 2.0, inner.end.y - 0.62, L, 0.62); rot = 180.0
			"xmin": rect = Rect2(inner.position.x, cx - L / 2.0, 0.62, L); rot = 90.0
			_: rect = Rect2(inner.end.x - 0.62, cx - L / 2.0, 0.62, L); rot = 270.0
		rect = rect.intersection(inner)
		var L2 := rect.size.x if win_side in ["zmin", "zmax"] else rect.size.y
		_place(r, "counter", L2, 0.62, {at = rect, rot = rot, tries = 1, args = [false, true]})
	_place(r, "fridge", 0.8, 0.75, {tall = true, corner = true})
	var st := _place(r, "stove", 0.76, 0.66, {})
	if not st.is_empty():
		for s in [-1.0, 1.0]:
			var b := _beside(st, _rng.randf_range(0.6, 1.2), 0.62, s)
			var up := _rng.randf() < 0.7
			_place(r, "counter", b.rect.size.x if st.side in ["zmin", "zmax"] else b.rect.size.y, 0.62, {at = b.rect, rot = b.rot, tries = 1, args = [up, false], tall = up, side = st.side})
	for i in 2:
		_place(r, "counter", _rng.randf_range(1.0, 2.0), 0.62, {args = [true, false], tall = true})
	var inner2 := _inner(r)
	if minf(inner2.size.x, inner2.size.y) > 3.6:
		_place(r, "island", _rng.randf_range(1.2, 1.8), 0.9, {center = true})
	elif inner2.get_area() > 12.0:
		_place(r, "dining_set", 1.6, 1.9, {center = true})


func _dining(r: Dictionary) -> void:
	var inner := _inner(r)
	var long := maxf(inner.size.x, inner.size.y)
	var short := minf(inner.size.x, inner.size.y)
	var w := clampf(long - 1.6, 1.4, 2.8)
	var d := clampf(short - 1.2, 1.7, 2.1)
	_place(r, "dining_set", w, d, {center = true, rot = 0.0 if inner.size.x >= inner.size.y else 90.0})
	if _rng.randf() < 0.6:
		_place(r, "hutch", _rng.randf_range(1.2, 1.5), 0.45, {tall = true})
	if _rng.randf() < 0.5:
		_place(r, "sideboard", _rng.randf_range(1.2, 1.6), 0.45)
	if _rng.randf() < 0.4:
		_place(r, "plant", 0.4, 0.4, {corner = true})
	_hang(r, "picture", _rng.randf_range(0.6, 0.9))


func _bedroom(r: Dictionary) -> void:
	var inner := _inner(r)
	var small := minf(inner.size.x, inner.size.y) < 3.1
	var kid := _rng.randf() < 0.5
	var bed_w := 0.99 if small or (kid and _rng.randf() < 0.6) else 1.37
	if _rng.randf() < 0.12 and kid:
		_place(r, "crib", 0.75, 1.35)
	var bed := _place(r, "bed", bed_w, 1.95)
	if not bed.is_empty():
		var b := _beside(bed, 0.45, 0.4, -1.0 if _rng.randf() < 0.5 else 1.0)
		_place(r, "nightstand", 0.45, 0.4, {at = b.rect, rot = b.rot, tries = 1})
	if _rng.randf() < 0.6:
		_place(r, "closet", _rng.randf_range(1.5, 2.0), 0.65, {tall = true})
	_place(r, "dresser", _rng.randf_range(0.9, 1.3), 0.48)
	if _rng.randf() < 0.45:
		_place(r, "desk", 1.1, 0.95)
	if kid:
		if _rng.randf() < 0.6:
			if _rng.randf() < 0.5:
				_place(r, "toy_chest", 0.8, 0.45)
			else:
				_place(r, "beanbag", 0.75, 0.75)
		for i in _rng.randi_range(1, 3):
			_hang(r, "poster", 0.55, [Color.from_hsv(_rng.randf(), 0.7, 0.8)])
	else:
		if _rng.randf() < 0.4:
			_place(r, "bookshelf", 0.8, 0.3, {tall = true})
		_hang(r, "picture", 0.6)


func _master(r: Dictionary) -> void:
	var king := _rng.randf() < 0.35 and minf(_inner(r).size.x, _inner(r).size.y) > 3.6
	var bw := 1.93 if king else 1.52
	var bed := _place(r, "bed", bw, 2.03)
	if not bed.is_empty():
		for s in [-1.0, 1.0]:
			var b := _beside(bed, 0.5, 0.42, s)
			_place(r, "nightstand", 0.5, 0.42, {at = b.rect, rot = b.rot, tries = 1})
		_place(r, "dresser", _rng.randf_range(1.3, 1.7), 0.5, {sides = [_opposite(bed.side)]})
	if _rng.randf() < 0.4:
		_place(r, "dresser", 1.2, 0.5)
	if _rng.randf() < 0.4:
		_place(r, "armoire", 1.0, 0.6, {tall = true})
	if _rng.randf() < 0.35:
		_place(r, "gun_safe", 0.75, 0.6, {tall = true, corner = true})
	if _rng.randf() < 0.3:
		_place(r, "recliner", 0.9, 0.95)
	if _rng.randf() < 0.6:
		_fan(r)
	_hang(r, "picture", _rng.randf_range(0.6, 0.9))


func _walk_in(r: Dictionary) -> void:
	for i in 3:
		_place(r, "closet", _rng.randf_range(1.0, 1.6), 0.6, {tall = true})
	if _rng.randf() < 0.4:
		_place(r, "shelving", 0.9, 0.45, {tall = true})


func _bath(r: Dictionary) -> void:
	var inner := _inner(r)
	if r.kind != "powder":
		var shower: bool = r.kind == "master_bath" and _rng.randf() < 0.5
		if shower:
			_place(r, "shower", 0.9, 0.9, {corner = true, tall = true})
		else:
			var long := maxf(inner.size.x, inner.size.y)
			var sides: Array = ["zmin", "zmax"] if inner.size.x >= inner.size.y else ["xmin", "xmax"]
			_place(r, "tub", minf(1.52, long - 0.05), 0.76, {corner = true, sides = sides})
	_place(r, "toilet", 0.5, 0.7)
	var vw := 1.5 if r.kind == "master_bath" and maxf(inner.size.x, inner.size.y) > 2.6 else (0.6 if r.kind == "powder" else 0.9)
	_place(r, "vanity", vw, 0.55)


func _laundry(r: Dictionary) -> void:
	var w := _place(r, "washer", 0.69, 0.68)
	if not w.is_empty():
		var b := _beside(w, 0.69, 0.68, -1.0 if _rng.randf() < 0.5 else 1.0)
		_place(r, "washer", 0.69, 0.68, {at = b.rect, rot = b.rot, tries = 1})   # the dryer
	if _rng.randf() < 0.5:
		_place(r, "utility_sink", 0.6, 0.55)
	if garage.is_empty():
		_place(r, "water_heater", 0.6, 0.6, {tall = true, corner = true})
	if _rng.randf() < 0.5:
		_place(r, "shelving", 0.9, 0.4, {tall = true})


func _office(r: Dictionary) -> void:
	_place(r, "desk", _rng.randf_range(1.3, 1.6), 1.05)
	_place(r, "filing_cabinet", 0.45, 0.6, {tall = true})
	for i in _rng.randi_range(1, 2):
		_place(r, "bookshelf", _rng.randf_range(0.8, 1.0), 0.32, {tall = true})
	if _rng.randf() < 0.4:
		_place(r, "gun_safe", 0.75, 0.6, {tall = true, corner = true})
	_hang(r, "picture", 0.5)


func _foyer(r: Dictionary) -> void:
	if _rng.randf() < 0.5:
		_place(r, "coat_rack", 0.4, 0.4, {corner = true})
	if _rng.randf() < 0.7:
		_place(r, ["bench", "sideboard"][_rng.randi() % 2], _rng.randf_range(0.8, 1.1), 0.4)
	if _rng.randf() < 0.3:
		_place(r, "plant", 0.4, 0.4, {corner = true})
	_hang(r, "picture", 0.5)


func _hall(r: Dictionary) -> void:
	for i in _rng.randi_range(0, 2):
		_hang(r, "picture", _rng.randf_range(0.4, 0.6))


func _garage_stuff(r: Dictionary) -> void:
	var inner := _inner(r)
	var cars := _rng.randi_range(0, 2)
	var lanes: Array = [inner.position.x + inner.size.x * 0.27, inner.position.x + inner.size.x * 0.73]
	_shuffle(lanes)
	for i in cars:
		var cx: float = lanes[i]
		var rect := Rect2(cx - 0.95, inner.end.y - 4.9 - _rng.randf_range(0.2, 0.6), 1.9, 4.8)
		_place(r, "car", 1.9, 4.8, {at = rect, rot = 0.0, tries = 1})
	_place(r, "workbench", _rng.randf_range(1.8, 2.4), 0.6, {sides = ["zmin"]})
	_place(r, "shelving", 1.2, 0.45, {tall = true})
	if _rng.randf() < 0.5:
		_place(r, "tool_chest", 0.7, 0.45)
	if _rng.randf() < 0.6:
		_place(r, "mower", 0.55, 0.9)
	if _rng.randf() < 0.35:
		_place(r, "chest_freezer", 1.1, 0.65)
	_place(r, "water_heater", 0.6, 0.6, {tall = true, corner = true})
	for i in _rng.randi_range(0, 3):
		_place(r, "boxes", _rng.randf_range(0.4, 0.6), _rng.randf_range(0.35, 0.5))


func _fan(r: Dictionary) -> void:
	var n := Node3D.new()
	n.position = Vector3((r.x0 + r.x1) / 2.0, r.floor * FH, (r.z0 + r.z1) / 2.0)
	add_child(n)
	_f.ceiling_fan(n)


## Free floor spots (for the AI): cells clear of furniture and reachable from the doors.
func _spots(r: Dictionary) -> void:
	_connected(r)
	var g: PackedByteArray = r.grid
	var reach: PackedByteArray = r.get("reach", PackedByteArray())
	var inner := _inner(r)
	var best := Vector3.ZERO
	var best_d := INF
	var c := inner.get_center()
	var spots: Array = []
	for y in r.gh:
		for x in r.gw:
			if g[y * r.gw + x] != 0 or (reach.size() == g.size() and reach[y * r.gw + x] == 0):
				continue
			# A bit more room than walking past needs.
			var ok := true
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= r.gw or ny >= r.gh or g[ny * r.gw + nx] != 0:
					ok = false
			if not ok:
				continue
			var p := Vector3(inner.position.x + (x + 0.5) * CELL, r.floor * FH, inner.position.y + (y + 0.5) * CELL)
			spots.append(p)
			var dd := Vector2(p.x, p.z).distance_to(c)
			if dd < best_d:
				best_d = dd
				best = p
	if spots.is_empty():
		best = Vector3(c.x, r.floor * FH, c.y)
		spots.append(best)
	r.spots = spots
	if r.kind != "void":
		rooms[r.name] = best


# ================================================================== outside

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.7, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.72, 0.85)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(_rng.randf_range(-55, -35), _rng.randf_range(-60, 60), 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


func _lot() -> void:
	floor_y = 0.0
	var lawn: Material = textures.pick("ground/lawn", [textured("lawn", img_noise(Color(0.3, 0.45, 0.2), 0.06, 32, 7), 1.5, 1.0)], _rng)
	var concrete: Material = textures.pick("ground/concrete", [textured("concrete", img_noise(Color(0.68, 0.67, 0.64), 0.04, 32, 8), 1.2, 0.95)], _rng)
	var asphalt: Material = textures.pick("ground/asphalt", [textured("asphalt", img_noise(Color(0.22, 0.22, 0.23), 0.05, 32, 9), 1.0, 0.95)], _rng)
	box(Vector3(120, 1, 80), Vector3(0, -0.5, -8), lawn, "concrete")
	if not garage.is_empty():
		var gw: float = garage.x1 - garage.x0
		box(Vector3(gw - 0.3, 0.02, 12.0 - fz1 - 0.75), Vector3((garage.x0 + garage.x1) / 2.0, 0.005, (fz1 + 11.25) / 2.0), concrete, "concrete", 0.0, false)
	var fdx := front_door_pos.x
	box(Vector3(1.0, 0.02, 12.0 - fz1 - 0.75), Vector3(fdx, 0.006, (fz1 + 11.25) / 2.0), concrete, "concrete", 0.0, false)
	box(Vector3(1.6, 0.03, 1.4), Vector3(fdx, 0.008, fz1 + 0.7), concrete, "concrete", 0.0, false)
	box(Vector3(120, 0.02, 1.5), Vector3(0, 0.007, 12.0), concrete, "concrete", 0.0, false)
	box(Vector3(120, 0.02, 8.0), Vector3(0, 0.004, 17.5), asphalt, "concrete", 0.0, false)
	var yellow := flat("lane", Color(0.85, 0.7, 0.2))
	for i in 17:
		box(Vector3(2.0, 0.005, 0.12), Vector3(-56.0 + i * 7.0, 0.016, 17.5), yellow, "concrete", 0.0, false)
	box(Vector3(120, 0.12, 0.2), Vector3(0, 0.06, 13.4), flat("curb", Color(0.6, 0.6, 0.58)), "concrete", 0.0, false)
	# Back yard: privacy fence, deck off the slider.
	var lx0 := minf(fx0, garage.get("x0", fx0)) - 2.0
	var lx1 := maxf(fx1, garage.get("x1", fx1)) + 2.0
	var fence: Material = textures.pick("fences", [textured("fence", img_boards(Color(0.6, 0.48, 0.32), Color(0.4, 0.3, 0.2), 8, true), 1.2)], _rng)
	var fy := 6.0 * FT
	var back := fz0 - _rng.randf_range(7.0, 10.0)
	box(Vector3(lx1 - lx0, fy, 0.05), Vector3((lx0 + lx1) / 2.0, fy / 2.0, back), fence, "wood")
	for x in [lx0, lx1]:
		box(Vector3(0.05, fy, fz0 - back + 1.0), Vector3(x, fy / 2.0, (back + fz0 + 1.0) / 2.0), fence, "wood")
	var deck := textured("deck", img_boards(Color(0.55, 0.42, 0.28), Color(0.35, 0.25, 0.15), 8, true), 0.9)
	for o: Dictionary in _ext_open:
		if o.get("slider", false):
			box(Vector3(_rng.randf_range(4.0, 5.5), 0.04, 3.2), Vector3(o.c, 0.02, fz0 - 1.6), deck, "wood", 0.0, false)
			cylinder(0.3, 0.6, Vector3(o.c + 1.6, 0.6, fz0 - 2.4), flat("grill", Color(0.08, 0.08, 0.08), 0.4, 0.3), "sheet_metal")
	var bark := flat("bark", Color(0.3, 0.22, 0.15))
	var leaves := flat("leaves", Color(0.2, 0.38, 0.16), 1.0)
	for i in _rng.randi_range(2, 4):
		var t := Vector3(_rng.randf_range(lx0, lx1), 0, _rng.randf_range(back + 1.5, fz0 - 2.0)) if i % 2 == 0 else Vector3(_rng.randf_range(lx0, lx1), 0, _rng.randf_range(fz1 + 2.5, 10.5))
		if absf(t.x - fdx) < 2.0 or (not garage.is_empty() and t.x > garage.x0 - 1.5 and t.x < garage.x1 + 1.5 and t.z > fz1):
			continue
		cylinder(0.18, 3.0, t + Vector3(0, 1.5, 0), bark, "wood")
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = _rng.randf_range(1.6, 2.2)
		sm.height = 3.2
		sm.radial_segments = 10
		sm.rings = 6
		crown.mesh = sm
		crown.material_override = leaves
		crown.position = t + Vector3(0, 4.0, 0)
		add_child(crown)
	cylinder(0.05, 1.1, Vector3(fdx + 2.2, 0.55, 11.5), flat("post", Color(0.3, 0.3, 0.3)), "wood")
	box(Vector3(0.2, 0.22, 0.48), Vector3(fdx + 2.2, 1.2, 11.5), flat("mailbox", Color(0.12, 0.12, 0.12), 0.4, 0.5), "sheet_metal")
	# Hedges under the front windows.
	var hedge := flat("hedge", Color(0.16, 0.32, 0.14), 1.0)
	for o: Dictionary in _ext_open:
		if o.side == "zmax" and o.kind == "window" and o.room.floor == 0 and o.w > 0.8:
			box(Vector3(o.w + 0.6, 0.8, 0.7), Vector3(o.c, 0.4, fz1 + 0.55), hedge, "upholstery")


## Neighbouring houses as closed shells for a sense of street.
func _neighbours() -> void:
	var lx0 := minf(fx0, garage.get("x0", fx0))
	var lx1 := maxf(fx1, garage.get("x1", fx1))
	var cols := [Color(0.75, 0.78, 0.82), Color(0.82, 0.76, 0.62), Color(0.9, 0.9, 0.88), Color(0.6, 0.66, 0.58), Color(0.78, 0.7, 0.6)]
	var i := 0
	for side in [-1.0, 1.0]:
		var w := _rng.randf_range(12.0, 18.0)
		var x: float = (lx0 - 8.0 - w / 2.0) if side < 0 else (lx1 + 8.0 + w / 2.0)
		var c: Color = cols[_rng.randi() % cols.size()]
		var h := CEILING if _rng.randf() < 0.5 else FH + CEILING
		var sid := textured("siding_n%d_%s" % [i, c.to_html()], img_boards(c, c.darkened(0.25), 8), 0.8, 0.7)
		box(Vector3(w, h, 10.0), Vector3(x, h / 2.0, 0.0), sid, "exterior_sheathing")
		gable_roof(x - w / 2.0, -5.0, x + w / 2.0, 5.0, h, 25.0, _mats["shingles"])
		box(Vector3(0.95, DOOR_H, 0.05), Vector3(x, DOOR_H / 2.0, 5.02), flat("ndoor", Color(0.95, 0.94, 0.9)), "solid_door")
		i += 1


# ================================================================== occupants

func _spawn_enemies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed * 7 + 3
	var pool: Array = plan.filter(func(r): return r.kind not in ["void", "hall", "master_closet"] and r.spots.size() > 4)
	var n := rng.randi_range(4, 6) if stories == 1 else rng.randi_range(5, 7)
	n = mini(n, pool.size())
	_shuffle(pool, rng)
	# Someone always covers the front door from the foyer or the room next to it.
	var first: Dictionary = {}
	for r: Dictionary in pool:
		if r.kind in ["foyer", "living"] and r.floor == 0:
			first = r
			break
	if not first.is_empty():
		pool.erase(first)
		pool.insert(0, first)
	if stories == 2:
		var up: Array = pool.filter(func(r): return r.floor == 1)
		var down: Array = pool.filter(func(r): return r.floor == 0)
		var want_up := maxi(2, n / 2)
		pool = [pool[0]]
		for r in up.slice(0, want_up):
			pool.append(r)
		for r in down:
			if r != pool[0]:
				pool.append(r)
	var knives := 1 if n >= 5 else 0
	for i in n:
		var r: Dictionary = pool[i % pool.size()]
		var spots: Array = r.spots
		var at: Vector3 = spots[rng.randi() % spots.size()] + Vector3(0, 0.05, 0)
		var look := Vector3((r.x0 + r.x1) / 2.0, at.y, (r.z0 + r.z1) / 2.0)
		var doors: Array = r.openings.filter(func(o): return o.kind != "window")
		if not doors.is_empty():
			var o: Dictionary = doors[0]
			look = _opening_point(r, o) + Vector3(0, at.y, 0)
		if i == 0:
			look = Vector3(front_door_pos.x, 0, fz1)
		var role := "holder" if (i == 0 or rng.randf() < 0.5) else "pusher"
		var weapon := "pistol"
		if knives > 0 and i == n - 1:
			weapon = "knife"
			role = "holder"
		var patrol: Array[Vector3] = []
		if role == "pusher":
			patrol.append(rooms[r.name])
			var same: Array = plan.filter(func(q): return q.floor == r.floor and q != r and rooms.has(q.name) and q.kind != "garage")
			_shuffle(same, rng)
			for q in same.slice(0, 2):
				patrol.append(rooms[q.name])
		add_enemy(at, look, weapon, role, patrol, rng)


func _opening_point(r: Dictionary, o: Dictionary) -> Vector3:
	match o.side:
		"zmin": return Vector3(o.c, 0, r.z0)
		"zmax": return Vector3(o.c, 0, r.z1)
		"xmin": return Vector3(r.x0, 0, o.c)
		_: return Vector3(r.x1, 0, o.c)
