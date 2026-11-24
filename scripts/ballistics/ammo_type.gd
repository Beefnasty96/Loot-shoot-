class_name AmmoType
extends Resource
## One cartridge load. Stored in SI units; helpers convert to grains / fps / ft-lbs.
##
## Terminal behaviour is described by published 10% ballistic-gel results, which
## the simulation scales by velocity and by each material's "gel equivalence".

enum Construction { FMJ, JHP, SOLID_COPPER, LEAD, FRANGIBLE, PENETRATOR }

const GRAIN_KG := 6.479891e-5
const FPS_MS := 0.3048
const INCH_M := 0.0254
const J_TO_FTLB := 0.737562

@export var id := ""
@export var display_name := ""
@export var short_name := ""
@export var caliber := ".45 ACP"
@export var construction: Construction = Construction.FMJ
@export var mass_grains := 230.0
@export var muzzle_fps := 830.0          ## From the reference barrel length below.
@export var reference_barrel_in := 5.0
@export var bc_g1 := 0.17
@export var diameter_in := 0.452
@export var expanded_in := 0.452          ## Recovered diameter after expansion in gel.
@export var expand_min_fps := 0.0         ## Below this impact speed a hollow point won't open. 0 = never expands.
@export var gel_expanded_in := 0.0        ## Gel penetration when it expands, at muzzle velocity.
@export var gel_unexpanded_in := 30.0     ## Gel penetration when it doesn't (FMJ, plugged or crushed JHP).
@export var clog_chance := 0.0            ## Chance soft barriers (drywall, wood) plug the hollow point.
@export var hard_barrier_factor := 1.0    ## >1 = loses more on steel/glass/masonry (soft lead, hollow noses).
@export var ricochet_factor := 1.0        ## Scales each material's ricochet angle.
@export var disintegrates_on_hard := false
@export var plus_p := false
@export var dispersion_moa := 0.0         ## The load's own group size (extreme spread, MOA); adds to the gun's.
@export var vel_sd_fps := 0.0             ## Shot-to-shot muzzle velocity spread (1 standard deviation).
@export var fps_per_inch := 0.0           ## Velocity gained/lost per inch of barrel vs the reference. 0 = 1.8% of muzzle (pistol).
# --- Rifle bullets: they fly nose-first through the first few inches of tissue, then
#     turn sideways (yaw). Fast enough and they break apart (fragment) as they turn.
#     gel_unexpanded_in is then the tumbling penetration beyond the neck (and through soft barriers).
@export var yaw_neck_in := 0.0            ## Inches of tissue before it yaws. 0 = not a yawing rifle bullet.
@export var gel_nose_in := 0.0            ## Penetration it would have if it stayed nose-first: sets the (low) drag before the yaw.
@export var hard_ref_in := 0.0            ## Gel-equivalent penetration nose-first into hard barriers (steel, glass, masonry).
@export var frag_min_fps := 0.0           ## Fragments if it hits at least this fast. 0 = never.
@export var split_min_fps := 0.0          ## Between this and frag_min_fps it breaks in two instead. 0 = no such band.
@export var gel_frag_in := 0.0            ## Penetration beyond the neck when it fragments (at reference velocity).
@export var frag_wound_ratio := 1.0       ## Wound channel vs bore, fragmenting.
@export var tumble_wound_ratio := 1.0     ## Wound channel vs bore, yawed but in one piece.
@export var frag_retained := 1.0          ## Mass fraction of the largest piece after fragmenting.
@export var tracer := false
@export var tracer_range_m := 0.0         ## Burn-out distance of the trace.
@export var notes := ""


func mass_kg() -> float:
	return mass_grains * GRAIN_KG


func muzzle_ms() -> float:
	return muzzle_fps * FPS_MS


func diameter_m() -> float:
	return diameter_in * INCH_M


func area_m2() -> float:
	return PI * pow(diameter_m() * 0.5, 2.0)


## Sectional density in lb/in², the unit ballistic coefficients are quoted in.
func sectional_density() -> float:
	return (mass_grains / 7000.0) / (diameter_in * diameter_in)


## Muzzle velocity multiplier for a barrel of `barrel_in` inches.
func velocity_factor(barrel_in: float) -> float:
	var per_in := fps_per_inch if fps_per_inch > 0.0 else 0.018 * muzzle_fps
	return clampf(1.0 + per_in * (barrel_in - reference_barrel_in) / muzzle_fps, 0.6, 1.4)


func yaws() -> bool:
	return yaw_neck_in > 0.0


func expands() -> bool:
	return expand_min_fps > 0.0


func energy_j(speed_ms: float) -> float:
	return 0.5 * mass_kg() * speed_ms * speed_ms


func muzzle_energy_ftlb() -> float:
	return energy_j(muzzle_ms()) * J_TO_FTLB


static func ms_to_fps(v: float) -> float:
	return v / FPS_MS


static func j_to_ftlb(e: float) -> float:
	return e * J_TO_FTLB
