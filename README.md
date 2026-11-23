# Loot Shoot

Tactical roguelike shooter for the AYN Thor, built in Godot 4.7. Clear procedurally generated buildings, loot them, extract.

Design doc: https://claude.ai/artifact/98AoDBrsEHESiDWXZy5zdc

## Install on the Thor

Every push to `main` builds an APK automatically (GitHub Actions, about 5 minutes).

1. On the Thor, open https://github.com/Beefnasty96/Loot-shoot-/releases/latest
2. Tap **LootShoot.apk** to download, then open it and install (allow your browser to install apps if asked).
3. New builds install over the old one.

## Current step: shooting range (v0.4)

The game opens on a main menu (Play / Settings / Quit; Settings has look sensitivity, field of view, invert look, bullet paths and **Credits**). The shooting range is a grey-box yard with cover, a firing lane with target dummies at 25/50/75 ft, a **barrier test row** (1/2 in drywall stud wall, 3/4 in plywood, 1/4 in glass, car door, 1/8 in and 1/4 in steel, 4 in brick, 6 in concrete) with a dummy behind each, a brick house with a drywall partition (dummy hiding behind it), and stairs to a platform.

| Thor control | Action |
| --- | --- |
| R2 | Fire (semi-auto) |
| X | Reload (hold: check magazine) |
| D-pad left / right | Load for your **next** magazine |
| D-pad down | Bullet paths + ballistics readout |
| Select | Inventory |
| A | Search crate or body / pick up item / use (mirror: new look) |
| Left stick | Move |
| Right stick | Look |
| L3 | Sprint (third person, standing still: swap shoulder) |
| R3 | First / third person |
| L2 | Aim (zoom, always first person) |
| L1 / R1 | Lean |
| B | Crouch |
| Start | Pause + controls |

PC testing: WASD, mouse, V view, Shift sprint, C shoulder, Q/E lean, Ctrl crouch, right mouse aim, Esc pause.

All measurements shown in game are US units (feet, inches, pounds, fps, ft-lbs); the engine works in metres internally (`scripts/units.gd`).

## Characters and gear

Everyone (player in third person, NPCs) is the same **base body** (`assets/characters/base/body.glb`, ~1.5k tris) built from the source mesh by `tools/blender/body_build.py`:

- Five-finger hands, 53-bone skeleton named after Godot's humanoid profile (animation retargeting later).
- Split into regions (`Body_head`, `Body_torso`, `Body_upper_arms`, `Body_forearms`, `Body_hands`, `Body_hips`, `Body_thighs`, `Body_shins`, `Body_feet`, `Body_neck`). Gear hides the regions it covers.
- Appearance masks (skin shading, brows, scalp hair, beard, underwear, eyes, lips) tinted by `shaders/body.gdshader` from an `Appearance` (skin tone, hair/eye colour, bald/hair, beard, height).

Gear (`scripts/character/`):

| Piece | Role |
| --- | --- |
| `GearItem` | Definition: slot, SKINNED (clothes on the body's skeleton) or RIGID (on a bone), hidden regions, weight, storage litres, colour choices; armour fields reserved |
| `GearDB` | Catalogue |
| `GearInstance` | One copy: colour, condition, contents (for bags) |
| `Equipment` | Slots: head, face, shirt, jacket, vest, hands, legs, feet, back, belt, accessory; totals weight/storage |
| `CharacterModel` | Builds the visuals: rebinds clothes to the character's skeleton, mounts rigid items on bones, hides covered regions, applies appearance, procedural pose (IK arms/legs, walk, crouch, aim) |

Test gear (built by `tools/blender/gear_build.py`): T-shirt, field jacket, cargo pants, work boots, gloves, beanie, chest rig, baseball cap, 25 L daypack. 

## Inventory (grid, Tarkov-style)

Press **Select** (or **A** at a crate). Worn gear on the left, the storage your gear gives you in the middle, an open container on the right.

- **Storage comes from what you wear.** Cargo pants: 4 pockets + 2 cargo pockets. Field jacket: 2 chest + 2 hand pockets. Chest rig: 4 mag pouches, 2 utility, 1 admin pouch. Daypack: 4x5 main compartment. T-shirt/underwear: nothing.
- **Items have a shape** (width x height squares) and can be rotated. Ammo stacks to 50. Magazines remember their rounds. Gear can be stored with its contents.
- **Weight matters:** worn gear + contents + pistol. Up to 55 lb no penalty; 55-99 lb slower; over 99 lb overweight (no sprint, much slower). Same rule (`Encumbrance`) will apply to enemies.
- **Reloads use real magazines** from your rig and pockets (not the backpack); the empty goes back where the full one was. D-pad left/right picks which load to reach for. Drop loose rounds on a magazine to load it; Y on a magazine unloads it.

| Controller | Inventory action |
| --- | --- |
| D-pad / left stick | Move cursor |
| A | Pick up / put down (on a slot: equip) |
| Y | Rotate held item / unload magazine |
| X | Quick move (crate <-> you; wearables from the crate go straight on) |
| B / Select | Close |

Touch: drag and drop, or tap to pick up and tap to drop.

**The right-hand panel** is whatever you're searching:
- a **container** (A at a crate),
- a **body** (A at someone you've killed): their equipment slots plus their rig/pockets/backpack. Take anything, including what they're wearing; X on a worn item puts it straight on you if your slot is free,
- otherwise the **Ground**: items lying within ~8 ft show up here, and anything you put here is dropped at your feet when you close. Dropped items lie in the world; stand over one and press A to pick it up.

The range's random people (`Npc`) have hitboxes on their bones, the same body-part damage as the dummies, and random loot in whatever pockets their clothes have.

Code: `scripts/inventory/` (ItemDef, ItemDB, InvItem, InvGrid, Encumbrance, LootContainer, WorldItem), `scripts/character/npc.gd`, `scripts/ui/inventory_screen.gd`. Icons: `tools/blender/render_icons.py` (gear, magazine) and `tools/icons/draw_icons.py` (loot, ammo).

## Ballistics

Every bullet is simulated: G1 drag (Cd from the G1 table x sectional density / BC) + gravity each physics tick, so drop and velocity loss follow the real load. Sights are zeroed at 25 yd for 230gr ball.

On impact a bullet either ricochets (shallow angle on hard surfaces), turns to dust (frangible on hard surfaces), or penetrates: the thickness it crosses is measured from the geometry, converted to gel-equivalent millimetres for that material, and compared with what the bullet can still penetrate at its current speed (scaled from published 10% gel results). It stops inside (all energy delivered) or exits slower, possibly deflected. Hollow points expand in flesh above their opening speed, may plug in drywall/wood, and get crushed shut by steel/glass. Damage = energy deposited in the body part + tissue crushed by the (expanded) diameter.

| Load (.45 ACP, 5" barrel) | Muzzle | Energy | Gel | Notes |
| --- | --- | --- | --- | --- |
| 230gr FMJ | 835 fps | 356 ft-lb | ~30" | Deep, narrow, overpenetrates, best on hard barriers |
| 230gr JHP (bonded) | 890 fps | 404 ft-lb | ~13" / .87" | Expands; 17.5" when crushed by steel |
| 185gr JHP +P | 1050 fps | 453 ft-lb | ~15" / .72" | Flatter, more recoil |
| 185gr Solid Copper HP +P | 1000 fps | 411 ft-lb | ~14" / .76" | Rarely plugs, tough through barriers |
| 200gr Lead SWC | 850 fps | 321 ft-lb | ~24" | Practice load, smears on hard targets |
| 155gr Frangible | 1100 fps | 416 ft-lb | ~8" | Dust on steel/masonry: no ricochets |

Data: `scripts/ballistics/ammo_db.gd`. Materials: `scripts/ballistics/materials.gd`.

## Weapons

| Weapon | Status | Preview |
| --- | --- | --- |
| M1911 (.45 ACP) | Fires all six loads; 7+1, reloads, slide lock, mag check | `assets/weapons/m1911/preview.png` |

Models are built by script with Blender's Python module, so they can be rebuilt or tweaked exactly:

```
pip install bpy numpy pillow
python3 tools/blender/m1911_textures.py assets/weapons/m1911/textures
python3 tools/blender/m1911_build.py assets/weapons/m1911
python3 tools/blender/render_preview.py assets/weapons/m1911/m1911.blend /tmp/renders
python3 tools/blender/arms_build.py assets/viewmodels/arms     # gloved first-person arms, rigged
python3 tools/blender/body_build.py assets/characters/base/source/base_mesh.fbx assets/characters/base
python3 tools/blender/gear_build.py assets/characters/base/body.blend assets/gear
python3 tools/blender/render_gear.py assets/characters/base/body.blend assets/gear /tmp/fit.png tshirt,pants,boots
python3 tools/blender/render_fp.py assets/viewmodels/arms/arms.blend assets/weapons/m1911/m1911.blend /tmp/fp
```

First-person arms: 1,120 tris, 34 bones (forearm, hand, 3 per finger), rigid skinning. Rest pose = two-handed 1911 grip; they share the gun's coordinate space, so both .glb files line up under one parent.

The `.blend` file is also committed if you want to open it in Blender.

## Layout

- `scenes/shooting_range.tscn` – shooting range (built in `scripts/shooting_range.gd`)
- `scripts/player.gd` – movement, camera rig, first/third person
- `scripts/viewmodel.gd` – first-person arms + gun: hip/aim/sprint poses, sway, bob, wall pull-back
- `scripts/weapons/firearm.gd` – 1911 logic: chamber/magazine, ammo selection, reload, aim/zero, spread, recoil, slide/hammer animation, flash, brass
- `scripts/ballistics/` – ammo data, materials, flight + terminal simulation, impact effects
- `scripts/combat/` – damage model, hitboxes, target dummies
- `tools/audio/synth_sfx.py` – generates the placeholder sound effects
- `scripts/hud.gd` – HUD and pause panel
- `scripts/input_setup.gd` – all control bindings
- `.github/workflows/android.yml` – APK build + release

## Tests

Headless checks (run from the repo root with Godot 4.7):

```
godot --headless --import
godot --headless -s tools/tests/flight_gel_test.gd   # velocity/energy/drop at 25/50/100 yd + gel depth per load
godot --headless -s tools/tests/barrier_test.gd      # every load vs every barrier, then gel behind
godot --headless --fixed-fps 60 -s tools/tests/fire_test.gd  # firing, slide lock, reload, mag check, 25 yd zero
godot --headless --fixed-fps 60 -s tools/tests/inventory_test.gd  # grids, stacking, mag loading, reload from pockets, weight
godot --headless --fixed-fps 60 -s tools/tests/loot_test.gd       # drop/pick up from the ground, shoot + search a body, take their backpack
godot --headless --fixed-fps 60 -s tools/tests/ragdoll_test.gd    # body + gear mass, flinch, FMJ vs JHP push, ragdolls settle, corpses take hits
```

## Bodies and hit reactions

Physics runs on Jolt. Every person weighs 78 kg × height³ (about 143–205 lb) plus what they wear and carry, spread over 14 ragdoll bodies by real body-segment shares (head 8%, trunk 50%, thigh 10% ...). A vest or loaded backpack makes the chest heavier, boots the feet, and so on.

A hit pushes with the momentum the bullet lost plus 0.02 kg·m/s per joule it left behind. Alive, the struck part flinches by its own mass (an arm jerks more than a chest) and the person staggers by their total mass. Dead, they go limp and the push goes into the part that was hit; corpses keep their hitboxes, so you can still shoot them around.
