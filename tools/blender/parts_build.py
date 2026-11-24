"""Builds weapon attachments as separate .glb files (one per part).

Usage:  python3 parts_build.py <repo_root>
Writes assets/weapons/parts/<id>.glb (+ textures).

Same space as m1911_build.py (mm -> m, +Y forward, +Z up, +X right; exported Y-up so
Godot sees -Z forward). Two kinds of part:
  - "on the gun":   modelled where they sit on the 1911 (grips, sights, barrel, rail
                    adapter); placed at the gun's origin.
  - "on a mount":   modelled around their own mount point at the origin (suppressor
                    screws on at its rear face, a light clamps on at its top centre);
                    placed at the attach point of the slot they go in.
"""
import math
import os
import sys

import bpy  # must come first: it provides bmesh and mathutils
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import m1911_build as mb  # noqa: E402
from m1911_build import GRIP_DEPTH, box, cyl_y, from_data, gp, material, reset, t_at_z, GRIP_LEN  # noqa: E402

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
OUT = os.path.join(ROOT, "assets", "weapons", "parts")
os.makedirs(OUT, exist_ok=True)
mb.TEX_DIR = OUT


def textures():
    rng = np.random.default_rng(7)
    # Pebbled black rubber.
    r = np.zeros((64, 64, 3), np.float32) + 28
    r += rng.normal(0, 7.0, (64, 64, 1))
    Image.fromarray(np.clip(r, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "rubber.png"))
    # Matte black anodised aluminium.
    a = np.zeros((32, 32, 3), np.float32) + 22
    a += rng.normal(0, 2.0, (32, 32, 1))
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "anodised.png"))


def export(name, objs):
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", export_apply=True, export_yup=True, use_selection=True)
    print("part", name)


def emissive(name, color, strength=3.0):
    m = material(name, color, None, rough=0.4, metal=0.0)
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    return m


def threaded_barrel():
    reset()
    steel = material("BarrelSS", (0.62, 0.62, 0.6), None, rough=0.3, metal=0.9)    # stainless
    objs = [cyl_y("BarrelExt", 7.4, 129.5, 141.0, 0, 0, steel, seg=16)]
    for i in range(5):                                                               # thread rings
        y = 132.0 + i * 1.8
        objs.append(cyl_y("Thread%d" % i, 7.9, y, y + 0.8, 0, 0, steel, seg=16))
    export("barrel_1911_threaded", objs)


def suppressor():
    reset()
    alu = material("Anodised", (0.09, 0.09, 0.09), "anodised.png", rough=0.55, metal=0.3)
    objs = [
        cyl_y("Collar", 10.0, 0.0, 10.0, 0, 0, alu, seg=16),
        cyl_y("Tube", 17.0, 8.0, 185.0, 0, 0, alu, seg=20),
        cyl_y("EndCap", 15.0, 185.0, 188.0, 0, 0, alu, seg=20),
    ]
    for i in range(3):                                                               # grip flats
        y = 20.0 + i * 6.0
        objs.append(cyl_y("Ring%d" % i, 17.6, y, y + 2.0, 0, 0, alu, seg=20))
    export("supp_45", objs)


def rubber_grips():
    reset()
    rub = material("Rubber", (0.12, 0.12, 0.12), "rubber.png", rough=0.95, metal=0.0)
    t_top, t_bot = t_at_z(-37.0) - 1.0, GRIP_LEN - 4.5
    objs = []
    for side, sx in (("R", 1.0), ("L", -1.0)):
        pts = [gp(t_top, 2.5), gp(t_top, GRIP_DEPTH - 2.0), gp(t_bot, GRIP_DEPTH - 2.0), gp(t_bot, 2.5)]
        verts = [(10.2 * sx, y, z) for y, z in pts] + [(15.4 * sx, y, z) for y, z in pts]
        faces = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
        objs.append(from_data("Grip" + side, verts, faces, rub))
        for k in range(6):                                                           # finger-groove ridges on the front strap side
            t = t_top + 10 + k * 11
            a, b = gp(t, 2.0), gp(t + 4, 2.0)
            objs.append(box("Ridge%s%d" % (side, k), 10.2 * sx - 0.1 if sx > 0 else -15.6, 15.6 if sx > 0 else -10.1, min(a[0], b[0]) - 1.5, max(a[0], b[0]), min(a[1], b[1]), max(a[1], b[1]), rub))
    export("grips_1911_rubber", objs)


def night_sights():
    reset()
    steel = material("SightSteel", (0.08, 0.08, 0.09), None, rough=0.5, metal=0.4)
    tritium = emissive("Tritium", (0.35, 1.0, 0.35), 4.0)
    ring = material("SightRing", (0.95, 0.95, 0.9), None, rough=0.5, metal=0.0)
    objs = [
        box("FrontPost", -1.7, 1.7, 114.0, 123.5, 14.5, 21.0, steel),
        box("FrontRing", -1.0, 1.0, 113.6, 114.0, 17.6, 19.8, ring),
        box("FrontVial", -0.6, 0.6, 113.4, 113.8, 18.1, 19.3, tritium),
        box("RearBlockL", -7.5, -1.8, -62.5, -53.5, 14.0, 20.0, steel),
        box("RearBlockR", 1.8, 7.5, -62.5, -53.5, 14.0, 20.0, steel),
        box("RearBase", -7.5, 7.5, -62.5, -53.5, 14.0, 16.4, steel),
    ]
    for sx in (-4.6, 4.6):
        objs.append(box("RearVial%.0f" % sx, sx - 0.6, sx + 0.6, -62.9, -62.5, 17.3, 18.5, tritium))
    export("sights_1911_night", objs)


def rail_adapter():
    reset()
    alu = material("Anodised", (0.09, 0.09, 0.09), "anodised.png", rough=0.55, metal=0.3)
    objs = [
        box("Clamp", -11.2, 11.2, 24.0, 98.0, -32.0, -27.0, alu),       # hugs the dust cover
        box("Rail", -10.6, 10.6, 30.0, 96.0, -36.0, -32.0, alu),
    ]
    for i in range(6):                                                    # Picatinny slots
        y = 34.0 + i * 10.0
        objs.append(box("Slot%d" % i, -10.7, 10.7, y, y + 5.0, -37.0, -35.6, alu))
    objs.append(box("GuardStrap", -11.0, 11.0, 18.0, 25.0, -42.0, -27.0, alu))   # wraps the trigger guard front
    export("rail_1911", objs)


def weapon_light():
    reset()
    alu = material("Anodised", (0.09, 0.09, 0.09), "anodised.png", rough=0.55, metal=0.3)
    lens = emissive("Lens", (1.0, 0.97, 0.85), 2.0)
    objs = [
        box("RailClamp", -10.5, 10.5, -14.0, 16.0, -7.0, 0.0, alu),
        cyl_y("Body", 11.5, -26.0, 40.0, 0, -17.0, alu, seg=16),
        cyl_y("Bezel", 13.5, 34.0, 44.0, 0, -17.0, alu, seg=16),
        cyl_y("LensDisk", 12.0, 44.0, 44.6, 0, -17.0, lens, seg=16),
        box("Switch", -6.0, 6.0, -30.0, -24.0, -22.0, -12.0, alu),
    ]
    export("light_m3", objs)


if __name__ == "__main__":
    textures()
    threaded_barrel()
    suppressor()
    rubber_grips()
    night_sights()
    rail_adapter()
    weapon_light()
