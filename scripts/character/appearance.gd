class_name Appearance
extends Resource
## How a person looks underneath their gear. Randomize() makes a new civilian.

const SKIN_TONES := [
	Color(0.96, 0.80, 0.69), Color(0.90, 0.72, 0.58), Color(0.80, 0.60, 0.45), Color(0.70, 0.50, 0.36),
	Color(0.58, 0.40, 0.28), Color(0.45, 0.30, 0.20), Color(0.34, 0.22, 0.15), Color(0.26, 0.17, 0.12),
]
const HAIR := [
	Color(0.06, 0.05, 0.05), Color(0.16, 0.10, 0.06), Color(0.30, 0.19, 0.10), Color(0.48, 0.33, 0.18),
	Color(0.72, 0.58, 0.36), Color(0.45, 0.18, 0.08), Color(0.55, 0.55, 0.55), Color(0.85, 0.85, 0.82),
]
const EYES := [Color(0.25, 0.16, 0.08), Color(0.35, 0.22, 0.1), Color(0.25, 0.4, 0.6), Color(0.3, 0.45, 0.3), Color(0.4, 0.4, 0.42)]
const UNDERWEAR := [Color(0.3, 0.32, 0.35), Color(0.12, 0.12, 0.13), Color(0.2, 0.25, 0.4), Color(0.75, 0.75, 0.72)]

@export var skin_tone := Color(0.8, 0.6, 0.45)
@export var hair_color := Color(0.16, 0.1, 0.06)
@export var eye_color := Color(0.3, 0.22, 0.1)
@export var underwear_color := Color(0.3, 0.32, 0.35)
@export_range(0.0, 1.0) var scalp_hair := 1.0   ## 0 bald, 1 short hair.
@export_range(0.0, 1.0) var beard := 0.0        ## 0 clean-shaven, ~0.4 stubble, 1 full beard.
@export_range(0.0, 1.0) var brows := 1.0
@export_range(0.9, 1.1) var height := 1.0       ## Uniform scale of the whole body.


func randomize(rng: RandomNumberGenerator) -> Appearance:
	skin_tone = SKIN_TONES[rng.randi() % SKIN_TONES.size()].lerp(SKIN_TONES[rng.randi() % SKIN_TONES.size()], rng.randf() * 0.3)
	var hair: Color = HAIR[rng.randi() % HAIR.size()]
	hair_color = hair
	eye_color = EYES[rng.randi() % EYES.size()]
	underwear_color = UNDERWEAR[rng.randi() % UNDERWEAR.size()]
	scalp_hair = 0.0 if rng.randf() < 0.15 else rng.randf_range(0.75, 1.0)
	var b := rng.randf()
	beard = 0.0 if b < 0.45 else (rng.randf_range(0.25, 0.45) if b < 0.75 else rng.randf_range(0.8, 1.0))
	brows = rng.randf_range(0.75, 1.0)
	height = rng.randf_range(0.94, 1.06)
	return self
