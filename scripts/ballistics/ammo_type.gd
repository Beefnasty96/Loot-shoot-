class_name AmmoType
extends Resource
## One cartridge load. Stored in SI units; helpers convert to grains / fps / ft-lbs.
##
## Terminal behaviour is described by published 10% ballistic-gel results, which
## the simulation scales by velocity and by each material's "gel equivalence".

enum Construction { FMJ, JHP, SOLID_COPPER, LEAD, FRANGIBLE }

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
