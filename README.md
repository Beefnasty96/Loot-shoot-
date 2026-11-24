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

**Phones (e.g. Galaxy S25 Ultra):** with no gamepad connected, an on-screen Xbox-layout controller appears: floating move stick on the left half (L3 beside it = sprint), drag anywhere on the right half to look (also while holding RT, so you can fire and steer with one thumb), RT fire, LT aim (tap = stays on, hold = while held), LB/RB lean, A B X Y, the D-pad, R3 view, View (inventory) and Menu (pause). It disappears the moment a gamepad connects or is used, and comes back when it disconnects; on the Thor it never shows. The HUD readouts move to the top corners while it's up.

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
godot --headless --fixed-fps 60 -s tools/tests/blood_test.gd      # wound bleed rates, arterial bleeds, clotting, bleeding out, blood decals
godot --headless --fixed-fps 60 -s tools/tests/wounded_test.gd    # limp, limp arm, clutching wounds, hunching, going down, shock
godot --headless --fixed-fps 60 -s tools/tests/knife_test.gd      # Ka-Bar: switching, stab/slash wounds, clothing, blade blood, spurts
godot --headless --fixed-fps 60 -s tools/tests/shoot_house_test.gd # house: rooms, doors, walls vs bullets, windows
godot --headless --fixed-fps 60 -s tools/tests/enemy_ai_test.gd   # navmesh, sight, hearing, doors, shooting, knife, cover, meds, death
godot --headless --fixed-fps 60 -s tools/tests/weapon_mod_test.gd # guns as items, attachment tree, stats, models, light, suppressor + hearing, drops
godot --headless --fixed-fps 60 -s tools/tests/touch_test.gd      # on-screen controller: stick, look, fire, aim toggle, buttons, hides for a gamepad
```

## Bodies and hit reactions

Physics runs on Jolt. Every person weighs 78 kg × height³ (about 143–205 lb) plus what they wear and carry, spread over 14 ragdoll bodies by real body-segment shares (head 8%, trunk 50%, thigh 10% ...). A vest or loaded backpack makes the chest heavier, boots the feet, and so on.

A hit pushes with the momentum the bullet lost plus 0.02 kg·m/s per joule it left behind. Alive, the struck part flinches by its own mass (an arm jerks more than a chest) and the person staggers by their total mass. Dead, they go limp and the push goes into the part that was hit; corpses keep their hitboxes, so you can still shoot them around.

## Blood and bleeding

Every bullet that hits a person opens a wound with a bleed rate in ml/s. The rate depends on the wound channel (an expanded hollow point bleeds about 2x ball), how long the channel is, the area hit (chest and belly bleed most) and whether it went through (two holes). Some hits open a major vessel, more often with bigger wound channels: an arterial bleed of 10–35 ml/s that doesn't clot. Light bleeds clot over a few minutes. People carry 70 ml of blood per kg; at 20% lost they start to sag, and at 40% lost they collapse and die.

What you see: entry and exit holes and a stain that spreads on clothes as the wound bleeds (both follow the body and the ragdoll), mist at the entry, spray and a splatter on the wall behind exit wounds, drips that pool where someone stands or lies (sized by volume, about 2 mm deep), and puddles that darken as they dry. The debug hit list (D-pad down) shows each wound's bleed rate. `DamageModel.treat()` is ready for bandages, tourniquets and IFAKs once enemies can shoot back.

## Acting wounded

Shot but alive, people show it (CharacterModel `hurt`/`pain`/`shock`/`kneel`/`sit`/`clutch`, driven by Npc from its DamageModel):
- **Leg:** weight shifts onto the good leg, the hurt foot rests on its toes, and they limp. A leg at 70% damage puts them on one knee. Both legs hurt, or one leg gone, puts them on the ground, propped up on a hand.
- **Arm:** the arm hangs limp and the other hand holds the wound.
- **Torso:** they hunch over with a hand pressed on the wound and curl toward it.
- **Pain:** spikes with each hit, then settles: fast breathing and trembling.
- **Blood loss (shock):** skin goes pale and the head droops. They sink to a knee, then to the floor, before bleeding out.
- `DamageModel.mobility()` and `steadiness()` give move-speed and aim penalties for the AI (and the player later).

## Ka-Bar and blade wounds

Y swaps between the 1911 and a USMC Ka-Bar (tools/blender/kabar_build.py: 7 in clip-point blade, 1.5 in wide, stacked leather handle; 1 lb with the sheath). With the knife out, R2 slashes (alternating forehand and backhand) and L2 + R2 stabs. Each attack has a wind-up, a short live window and a recovery. While the blade moves, rays sweep its arc (`Melee`).

- **Stab:** a 60 J thrust drives the blade up to its full 7 in. Clothing soaks some of it up (`Melee.CUT_RESIST`: T-shirt 2 J, jacket 8 J, vest 6 J). Ribs can deflect the point and the skull stops it. Damage and the chance of hitting a vessel or organ grow with depth: a full-depth chest stab does about 36 HP and opens a vessel close to half the time.
- **Slash:** about 3/4 in deep in bare skin along a 3½–7½ in cut, but only a scratch through a jacket. It does little damage (10–14 HP) but bleeds freely and is slow to clot. It's worst across the throat, forearms and wrists.
- **Blood:** a stab leaves a slit and gushes as the blade comes out. A slash leaves a long cut and throws blood off along the swing onto walls and the floor. Arterial bleeds (gunshot or blade) spurt with the heartbeat. The blade gets bloodier with each hit.

## Shoot house (test level)

Main menu > "Play (shoot house)". It's a 1995 suburban ranch house built in code (`scripts/levels/shoot_house.gd` on `LevelKit`): 64 x 32 ft with an attached two-car garage, a lawn, driveway, street, a fenced back yard and a deck.

- **Rooms:** kitchen, dining nook, foyer, living room, laundry, two bedrooms and an office along the front; a hallway; then the family room (wood paneling, brick fireplace), a bathroom, a kid's room and the master bedroom with its own bathroom. Builder-grade 1995 details: popcorn ceilings, beige and mauve carpet, almond appliances, oak cabinets, a geese wallpaper border, floral sofas and CRT TVs.
- **Construction is real to bullets:** interior walls are 2x4 and drywall (a .45 goes through), exterior walls are siding, OSB, batts and drywall, interior doors are hollow-core and the front door is solid. Brick, porcelain, appliance steel and the car stop or slow rounds by their material. Windows break and stay broken.
- **Doors:** A opens a door away from you and closes it.
- **Performance:** static meshes are merged per material in 5 m cells (`LevelKit.batch_meshes`), about 600 draw calls down to about 200.

## Enemy AI

The shoot house has five armed occupants (`scripts/ai/enemy.gd`, built on `Npc`): pistol "holders" covering the front door and the master bedroom door, pistol "pushers" patrolling the kitchen/dining and family/hall, and a knife man waiting by the kid's-room door. The HUD counts them down and times you; the house is clear when they're all dead or can't fight.

- **Sight:** a vision cone (almost all round once alert), with line of sight through glass but not walls or closed doors. Awareness builds faster the closer you are and slower if you're crouched.
- **Hearing:** gunshots through walls (close ones give away where you are) and running footsteps within a few meters. A round cracking close by makes them take cover.
- **States:** idle/patrol, then suspicious, investigate, combat, cover, search, and back to idle. Holders hold their spot; pushers come and find you.
- **Shooting:** a reaction delay when they first spot you, then aimed pairs. The error grows with distance, your movement, their own movement, and their wounds (hurt arms, blood loss, pain). They carry real magazines (lootable from the body), reload behind cover and drop the gun when they die.
- **Knife enemies:** they rush you and stab or slash with the same blade model as your Ka-Bar.
- **Movement:** a navmesh is baked from the level at load. Doors are on their own physics layer, so paths go through doorways and the AI opens doors on the way. Wounded enemies limp and go down like anyone else, and they still shoot from the floor if their arms work.

## Your body

You have the same hitboxes, DamageModel, wounds and bleeding as everyone else (`Vitals`). Hurt legs slow you and stop you sprinting. Hurt arms, pain and blood loss widen your spread and shake your aim. Losing blood greys out your vision, and at 40% lost you die. The HUD shows a body diagram (bottom left) with your bleed status and blood level.

D-pad up treats you with what you carry, taking a few seconds with no shooting meanwhile. The IFAK stops every bleed (arterial too), the car kit bandages light bleeds and gives +15 HP, and painkillers dull the pain for 2 minutes. You start with an IFAK in your pocket. When you die, your body ragdolls, the camera pulls back, and you can choose A to try again or Y for the main menu.

## Guns, knives and attachments (WeaponDB)

Weapons are inventory items. You have three weapon slots: Primary (for long guns), Holster and Sheath. Enemies have the same slots and drop their weapon on death, magazine, chambered round and parts included. Guns lie on the floor as their models; A picks one up, straight into an empty slot. Y cycles through what you carry, or leaves you unarmed if you carry nothing.

Everything is data in `scripts/weapons/weapon_db.gd`:
- **Adding a gun** is one `WEAPONS` entry: kind, slot, caliber, action, rpm, barrel length, weight, size, ergonomics, recoil, accuracy, model, sound and slots. Each slot lists the part types it accepts, whether it's required, the default part, the attach point and the model node it rides on (e.g. the slide).
- **Adding an attachment** is one `PARTS` entry plus a model (`tools/blender/parts_build.py`). A part can change weight, size, ergonomics, recoil, barrel length (which sets velocity), loudness, aim speed, glowing sights, a light, muzzle length, muzzle flash and the gunshot sound. It can also bring slots of its own.
- **Builds are a tree**, like Tarkov. The 1911's threaded barrel brings a muzzle slot for the suppressor, and the rail adapter brings a tactical slot for the light. Magazines plug into a slot that accepts a magazine family, so the same well takes 7- and 8-round 1911 magazines.
- **Stats:** `WeaponDB.stats(gun)` adds up the whole build. `WeaponDB.assemble(gun, model)` builds the part models on the first-person gun, the third-person gun, enemy guns and guns lying on the floor.

In the inventory, drop a magazine or part on a gun (in a grid or in your holster) to fit it; a magazine swaps with the one inside. Y on a gun opens it up: the slot tree with the totals (weight, ergonomics, recoil, barrel length and velocity, loudness). Required parts (barrel, grips, sights) can only be swapped, not left empty. A longer gun (with a suppressor) takes more squares.

1911 parts so far (the range's "Gun parts" bench): a threaded 5.5 in barrel, a .45 suppressor, a dust-cover rail adapter, an M3-style weapon light, wraparound rubber grips, tritium night sights and 8-round magazines.
- **Suppressor:** shots are about 30% as loud. Enemies hear them at about a third of the distance, there's no muzzle flash, and recoil is 12% softer, but the gun is slower to handle.
- **Light:** D-pad down turns it on; hold D-pad down for the bullet-path readout.
