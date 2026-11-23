class_name DamageModel
extends RefCounted
## Per-zone health shared by the player, NPCs and test dummies.
## Damage comes from the energy a bullet deposits plus the tissue its
## (possibly expanded) diameter crushes. Head or thorax at zero = dead.
##
## Bleeding: every hole is a wound. Its bleed rate (ml/s) comes from the size of
## the wound channel (an expanded hollow point bleeds ~2-3x a ball round), how
## long the channel is, how vascular the area is, and whether it went through
## (two holes). Some hits open a major vessel: an arterial bleed that doesn't
## clot. Light bleeds slowly clot. Losing 40% of your blood kills.

const ZONES := {
	"head": {max = 35.0, lethal = true},
	"thorax": {max = 85.0, lethal = true},
	"stomach": {max = 70.0, lethal = false},
	"arm_l": {max = 60.0, lethal = false},
	"arm_r": {max = 60.0, lethal = false},
	"leg_l": {max = 65.0, lethal = false},
	"leg_r": {max = 65.0, lethal = false},
}

## Relative blood supply of each zone (light bleeds) and chance a hit opens a major vessel.
const VASCULAR := {head = 1.4, thorax = 1.8, stomach = 1.5, arm_l = 0.7, arm_r = 0.7, leg_l = 1.0, leg_r = 1.0}
const ARTERY_CHANCE := {head = 0.05, thorax = 0.20, stomach = 0.12, arm_l = 0.06, arm_r = 0.06, leg_l = 0.10, leg_r = 0.10}
const BLOOD_ML_PER_KG := 70.0
const CLOT_TIME := 120.0        ## s: light bleeds fall to 1/e of their rate in this long.
const LETHAL_LOSS := 0.4        ## Fraction of blood volume.
const DEAD_SEEP := 0.15         ## After death the heart stops: wounds only seep, and that tails off.

var hp: Dictionary = {}
var dead := false
var cause := ""                 ## "wound" or "blood loss"
var blood_max := 5000.0
var blood_ml := 5000.0
var wounds: Array[Dictionary] = []
var _dead_time := 0.0


func _init() -> void:
	reset()


func reset() -> void:
	dead = false
	cause = ""
	wounds.clear()
	blood_ml = blood_max
	for z: String in ZONES:
		hp[z] = ZONES[z].max


## deposited_j: energy left in this zone. wound_ratio: current diameter / caliber.
static func damage_for(deposited_j: float, wound_ratio: float) -> float:
	return 12.0 * wound_ratio + deposited_j * 0.085 * sqrt(wound_ratio)


func apply(zone: String, damage: float) -> void:
	if not hp.has(zone):
		return
	hp[zone] = maxf(0.0, hp[zone] - damage)
	if hp[zone] <= 0.0 and ZONES[zone].lethal:
		_kill("wound")
	# Total health pooled below 0 also kills (many limb hits).
	var total := 0.0
	for z: String in hp:
		total += hp[z]
	if total <= 0.0:
		_kill("wound")


func _kill(why: String) -> void:
	if not dead:
		dead = true
		cause = why


func set_body_mass(kg: float) -> void:
	blood_max = kg * BLOOD_ML_PER_KG
	blood_ml = blood_max


## Open a wound from a ballistic hit (needs zone, result, wound_ratio, thickness_mm/depth_mm).
static func make_wound(info: Dictionary, rng := RandomNumberGenerator.new()) -> Dictionary:
	var zone: String = info.get("zone", "thorax")
	var ratio: float = info.get("wound_ratio", 1.0)
	var through: bool = info.get("result", "") == "penetrated"
	var path_cm: float = (info.get("thickness_mm", 0.0) if through else info.get("depth_mm", 0.0)) / 10.0
	var artery_p: float = ARTERY_CHANCE.get(zone, 0.1) * clampf(ratio, 1.0, 2.0) * clampf(path_cm / 20.0, 0.3, 1.0)
	var heavy := rng.randf() < artery_p
	var rate: float
	if heavy:
		rate = rng.randf_range(10.0, 25.0) * sqrt(ratio) * (1.4 if zone == "thorax" else 1.0)
	else:
		rate = 0.9 * VASCULAR.get(zone, 1.0) * ratio * ratio * clampf(path_cm / 10.0, 0.4, 2.0) * (1.5 if through else 1.0)
	return {zone = zone, bone = info.get("bone", ""), rate = rate, heavy = heavy, through = through, lost = 0.0}


func add_wound(w: Dictionary) -> void:
	if dead:
		w.rate *= DEAD_SEEP
	wounds.append(w)


## Advance bleeding by `delta` seconds. Returns ml lost this step.
func tick(delta: float) -> float:
	var lost := 0.0
	var seep := 1.0
	if dead:
		_dead_time += delta
		seep = exp(-_dead_time / 25.0)
	for w: Dictionary in wounds:
		if w.rate <= 0.001:
			continue
		var r: float = w.rate * seep
		var ml := minf(r * delta, blood_ml)
		w.lost += ml
		lost += ml
		blood_ml -= ml
		if not w.heavy:
			w.rate *= exp(-delta / CLOT_TIME)
	if not dead and blood_fraction() <= 1.0 - LETHAL_LOSS:
		_kill("blood loss")
	return lost


## 0..1 of a zone's health lost.
func hurt(zone: String) -> float:
	return 1.0 - hp.get(zone, 1.0) / ZONES[zone].max if ZONES.has(zone) else 0.0


## Blood loss as 0 (fine) .. 1 (about to pass out): starts at 10% lost, full at 35%.
func shock() -> float:
	return clampf((1.0 - blood_fraction() - 0.1) / 0.25, 0.0, 1.0)


## Movement speed multiplier from leg wounds and blood loss (for AI and the player).
func mobility() -> float:
	var legs := maxf(hurt("leg_l"), hurt("leg_r"))
	var m := 1.0 - legs * 0.6 - minf(hurt("leg_l"), hurt("leg_r")) * 0.3
	return clampf(m * (1.0 - shock() * 0.5), 0.0, 1.0)


## Aim steadiness 0..1 from arm wounds, pain and blood loss.
func steadiness() -> float:
	var arms := maxf(hurt("arm_l"), hurt("arm_r"))
	return clampf(1.0 - arms * 0.5 - shock() * 0.4 - hurt("head") * 0.3, 0.1, 1.0)


func bleed_rate() -> float:
	var r := 0.0
	for w: Dictionary in wounds:
		r += w.rate
	return r


func blood_fraction() -> float:
	return blood_ml / blood_max if blood_max > 0.0 else 1.0


func is_bleeding_heavily() -> bool:
	for w: Dictionary in wounds:
		if w.heavy and w.rate > 0.0:
			return true
	return false


## Medical treatment: stop light bleeds; `heavy_too` (tourniquet/chest seal) also stops arterial ones.
func treat(heavy_too: bool) -> int:
	var n := 0
	for w: Dictionary in wounds:
		if w.rate > 0.0 and (heavy_too or not w.heavy):
			w.rate = 0.0
			n += 1
	return n
