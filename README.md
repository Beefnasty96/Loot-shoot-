# Loot Shoot

Tactical roguelike shooter for the AYN Thor, built in Godot 4.7. Clear procedurally generated buildings, loot them, extract.

Design doc: https://claude.ai/artifact/98AoDBrsEHESiDWXZy5zdc

## Install on the Thor

Every push to `main` builds an APK automatically (GitHub Actions, about 5 minutes).

1. On the Thor, open https://github.com/Beefnasty96/Loot-shoot-/releases/latest
2. Tap **LootShoot.apk** to download, then open it and install (allow your browser to install apps if asked).
3. New builds install over the old one.

## Current step: test gym (v0.1)

A grey-box yard with cover, a firing lane with 10/20/30 m markers, a two-room house with a roof, and stairs to a platform.

| Thor control | Action |
| --- | --- |
| Left stick | Move |
| Right stick | Look |
| L3 | Sprint (third person, standing still: swap shoulder) |
| R3 | First / third person |
| L2 | Aim (zoom, always first person) |
| L1 / R1 | Lean |
| B | Crouch |
| Start | Pause + controls |

PC testing: WASD, mouse, V view, Shift sprint, C shoulder, Q/E lean, Ctrl crouch, right mouse aim, Esc pause.

## Layout

- `scenes/gym.tscn` – test gym (built in `scripts/gym.gd`)
- `scripts/player.gd` – movement, camera rig, first/third person
- `scripts/hud.gd` – HUD and pause panel
- `scripts/input_setup.gd` – all control bindings
- `.github/workflows/android.yml` – APK build + release
