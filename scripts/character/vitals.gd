class_name Vitals
extends Node
## The player's body: the same DamageModel, wounds and bleeding as everyone
## else, plus what that does to you. Hurt legs slow you and stop you sprinting,
## hurt arms and blood loss shake your aim, pain jolts the view (painkillers
## dull it), losing blood greys out your vision, and at 40% lost you're dead.
##
## Medicine (D-pad up, uses what's in your pockets/rig/pack, takes a few seconds,
## no shooting meanwhile):
##   IFAK         tourniquet / chest seal / gauze: stops every bleed, arterial too
##   car kit      bandages: stops light bleeds, patches up 15 HP
##   painkillers  pain mostly gone for 2 minutes

signal hurt(info: Dictionary)
signal died(cause: String)
signal treated(text: String)

const MED_TIME := {ifak = 5.0, medkit = 4.0, painkillers = 1.5}

var player: Player
var damage := DamageModel.new()
var pain := 0.0
var painkiller_time := 0.0
var dead := false
var cause := ""
var flash := 0.0                  ## Red hit flash 0..1 for the HUD.
var using := ""                   ## Item being used right now ("" = none).
var use_left := 0.0
var _use_item: InvItem
var _use_grid: InvGrid


func _ready() -> void:
	damage.set_body_mass(player.character.body_mass_kg())


func take_hit(info: Dictionary) -> void:
	if dead:
		return
	var wound: Dictionary = info.wound if info.has("wound") else DamageModel.make_wound(info)
	damage.add_wound(wound)
	Ballistics.blood.hit(info, wound)
	info.bleed = ("ARTERIAL BLEED " if wound.heavy else "bleed ") + "%.1f ml/s" % wound.rate
	damage.apply(info.zone, info.damage)
	pain = clampf(pain + info.damage / 35.0, 0.0, 1.0)
	flash = 1.0
	_cancel_use()
	hurt.emit(info)
	if damage.dead:
		_die("killed (%s)" % String(info.zone).replace("_", " "))


func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 2.5)
	if dead:
		return
	painkiller_time = maxf(0.0, painkiller_time - delta)
	if not damage.wounds.is_empty():
		var before := damage.blood_ml
		damage.tick(delta)
		_drips(delta, before - damage.blood_ml)
		if damage.dead:
			_die("bled out")
			return
	var base := clampf((maxf(damage.hurt("thorax"), damage.hurt("stomach")) + damage.hurt("head") + maxf(damage.hurt("leg_l"), damage.hurt("leg_r")) + maxf(damage.hurt("arm_l"), damage.hurt("arm_r"))) * 0.5, 0.0, 0.8)
	pain = move_toward(pain, base, delta * 0.12)
	if using != "":
		use_left -= delta
		if use_left <= 0.0:
			_finish_use()


var _drip_acc := 0.0


func _drips(_delta: float, ml: float) -> void:
	_drip_acc += ml
	if _drip_acc >= 2.0:
		var p := player.global_position + Vector3(randf_range(-0.15, 0.15), 1.0, randf_range(-0.15, 0.15))
		Ballistics.blood.drip(p, _drip_acc)
		_drip_acc = 0.0


## Pain you actually feel (painkillers take most of it away).
func felt_pain() -> float:
	return pain * (0.25 if painkiller_time > 0.0 else 1.0)


## 0..1: how much blood loss is greying out your vision.
func shock() -> float:
	return damage.shock()


func speed_factor() -> float:
	return damage.mobility()


func can_sprint() -> bool:
	return maxf(damage.hurt("leg_l"), damage.hurt("leg_r")) < 0.5 and damage.shock() < 0.5 and using == ""


## Extra spread/sway from arm wounds, pain and blood loss (0 = steady).
func shake() -> float:
	return clampf(1.0 - damage.steadiness() + felt_pain() * 0.3, 0.0, 1.0)


func bleeding() -> String:
	if damage.is_bleeding_heavily():
		return "ARTERIAL BLEED"
	return "BLEEDING" if damage.bleed_rate() > 0.05 else ""


# ------------------------------------------------------------------ medicine

## Pick the right thing for what's wrong and start using it. Returns what was started, or why not.
func use_meds() -> String:
	if dead or using != "":
		return ""
	var want: Array = []
	if damage.is_bleeding_heavily():
		want = ["ifak"]
	elif damage.bleed_rate() > 0.05:
		want = ["medkit", "ifak"]
	elif _hp_missing() > 10.0:
		want = ["medkit"]
	if felt_pain() > 0.3 and painkiller_time <= 0.0:
		want.append("painkillers")
	if want.is_empty():
		return "Nothing to treat"
	for id: String in want:
		var found := _find(id)
		if not found.is_empty():
			_use_item = found.item
			_use_grid = found.grid
			using = id
			use_left = MED_TIME[id]
			return "Using %s..." % _use_item.def.short_name
	return "No %s on you" % ("IFAK (arterial bleed!)" if want[0] == "ifak" else ItemDB.get_def(want[0]).short_name)


func _find(id: String) -> Dictionary:
	for g: InvGrid in player.character.equipment.grids(true):
		for e: Dictionary in g.entries:
			if (e.item as InvItem).def.id == id:
				return {item = e.item, grid = g}
	return {}


func _hp_missing() -> float:
	var m := 0.0
	for z: String in DamageModel.ZONES:
		m += DamageModel.ZONES[z].max - damage.hp[z]
	return m


func _finish_use() -> void:
	var id := using
	using = ""
	if _use_grid == null or not _use_grid.remove(_use_item):
		return
	match id:
		"ifak":
			var n := damage.treat(true)
			treated.emit("IFAK: %d bleed%s stopped" % [n, "" if n == 1 else "s"])
		"medkit":
			var n := damage.treat(false)
			_heal(15.0)
			treated.emit("Bandaged %d bleed%s, +15 HP" % [n, "" if n == 1 else "s"])
		"painkillers":
			painkiller_time = 120.0
			treated.emit("Painkillers: pain dulled for 2 min")


func _heal(amount: float) -> void:
	# Worst zones first.
	var zones: Array = DamageModel.ZONES.keys()
	zones.sort_custom(func(a, b): return damage.hp[a] / DamageModel.ZONES[a].max < damage.hp[b] / DamageModel.ZONES[b].max)
	for z: String in zones:
		var need: float = DamageModel.ZONES[z].max - damage.hp[z]
		var give := minf(need, amount)
		damage.hp[z] += give
		amount -= give
		if amount <= 0.0:
			break


func _cancel_use() -> void:
	using = ""
	use_left = 0.0


func _die(why: String) -> void:
	if dead:
		return
	dead = true
	cause = why
	_cancel_use()
	died.emit(why)
