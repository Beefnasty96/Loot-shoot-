# Level textures

Drop texture files in here and generated levels add them to the pool they pick
walls, floors, ceilings and the rest from. No code changes needed: the next APK
build picks them up.

```
assets/textures/
  common/           used by every map type
  suburban_house/   only the suburban house
  bank/  school/  capitol/  car_shop/  mall/  museum/  airplane/   (map types to come)
```

Inside each, one folder per surface:

| Folder | What it's used for | Default repeat |
|---|---|---|
| `walls/` | interior wall finish (paint, wallpaper, paneling) | 3.3 ft |
| `ceilings/` | ceilings | 2 ft |
| `floors/carpet/` | carpeted rooms (bedrooms, living, halls) | 2 ft |
| `floors/wood/` | hardwood (foyers, dining rooms) | 4 ft |
| `floors/tile/` | bathrooms | 2 ft |
| `floors/vinyl/` | kitchens, laundry | 2 ft |
| `exterior/siding/` | outside walls | 4 ft |
| `roofs/` | roofing | 4 ft |
| `ground/lawn/` | grass | 5 ft |
| `ground/concrete/` | driveways, walks, slabs | 4 ft |
| `ground/asphalt/` | the street | 4 ft |
| `fences/` | yard fences | 4 ft |
| `furniture/wood/` | wood finish on furniture and cabinets | 2 ft |
| `furniture/fabric/` | sofas, chairs (upholstery) | 1.6 ft |
| `counters/` | kitchen countertops | 2 ft |

Not every map type uses every folder yet (the suburban house uses all of them).

## File names

- `oak_planks.png`: one repeat uses the folder's default size.
- `oak_planks@4ft.png`: one repeat covers 4 ft. Also `@48in`, `@1.2m`, `@30cm`.
- `oak_planks_normal.png` (or `_n`): a normal map for `oak_planks`. It's optional.

Formats: PNG, JPG or WebP. Seamless (tileable) images work best, square with a
power-of-two size (512, 1024 or 2048 px; larger ones are scaled down to 2048).

Each uploaded texture is one more choice alongside the built-in ones, so the
more you add to a folder, the more often uploads come up.

The APK build runs `tools/textures/import_presets.py` so uploads are imported
for 3D: mipmaps on, mobile compression, normal maps as normal maps. If you add
files through the Godot editor, run it once yourself:
`python3 tools/textures/import_presets.py`.
