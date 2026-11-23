# Loot Shoot

Tactical roguelike shooter for the AYN Thor, built in Godot 4.7. Clear procedurally generated buildings, loot them, extract.

Design doc: https://claude.ai/artifact/98AoDBrsEHESiDWXZy5zdc

## Install on the Thor

Every push to `main` builds an APK automatically (GitHub Actions, about 5 minutes).

1. On the Thor, open https://github.com/Beefnasty96/Loot-shoot-/releases/latest
2. Tap **LootShoot.apk** to download, then open it and install (allow your browser to install apps if asked).
3. New builds install over the old one.

## Current step: test gym (v0.3) - real ballistics

A grey-box yard with cover, a firing lane with target dummies at 10/20/30 m, a **barrier test row** (drywall stud wall, 19 mm plywood, 6 mm glass, car door, 3 mm and 6 mm steel, 100 mm brick, 150 mm concrete) with a dummy behind each, a brick house with a drywall partition (dummy hiding behind it), and stairs to a platform.

| Thor control | Action |
| --- | --- |
| R2 | Fire (semi-auto) |
| X | Reload (hold: check magazine) |
| D-pad left / right | Load for your **next** magazine |
| D-pad down | Bullet paths + ballistics readout |
| Left stick | Move |
| Right stick | Look |
| L3 | Sprint (third person, standing still: swap shoulder) |
| R3 | First / third person |
| L2 | Aim (zoom, always first person) |
| L1 / R1 | Lean |
| B | Crouch |
| Start | Pause + controls |

PC testing: WASD, mouse, V view, Shift sprint, C shoulder, Q/E lean, Ctrl crouch, right mouse aim, Esc pause.

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
python3 tools/blender/render_fp.py assets/viewmodels/arms/arms.blend assets/weapons/m1911/m1911.blend /tmp/fp
```

First-person arms: 1,120 tris, 34 bones (forearm, hand, 3 per finger), rigid skinning. Rest pose = two-handed 1911 grip; they share the gun's coordinate space, so both .glb files line up under one parent.

The `.blend` file is also committed if you want to open it in Blender.

## Layout

- `scenes/gym.tscn` – test gym (built in `scripts/gym.gd`)
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
```
