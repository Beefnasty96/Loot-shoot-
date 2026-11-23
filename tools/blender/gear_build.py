"""Builds wearable test gear that fits the base body.

Usage:  python3 gear_build.py <body.blend> <gear_dir>
Writes <gear_dir>/<id>/<id>.glb and <id>_detail.png for each item.

Two kinds of gear:
- SKINNED (clothes): made from the body's own surface (selected regions + height
  limits), pushed outward along the normals. They keep the body's bone weights,
  so they bend exactly like the body. Exported with the skeleton.
- RIGID (hats, bags): modelled in rest-pose world space, exported without a
  skeleton. The game attaches them to a bone (Head, UpperChest...).

Each item gets a small detail texture: R = shading/seams (multiplied by the
item's main colour), G = secondary mask (soles, cuffs, straps; second colour).
"""
import math
import os
import sys

import bpy  # must come first
import bmesh
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_build as bb  # noqa: E402  (rasterizer)

BODY = os.path.abspath(sys.argv[1])
OUT = os.path.abspath(sys.argv[2])
TEX_SIZE = 256

# id, regions to copy, (z_min, z_max) face-centre limits, inflate (m), (|x| min, |x| max) limits
SKINNED = [
    ("tshirt", ["torso", "upper_arms", "hips"], (0.90, 1.58), 0.007, None),
    ("jacket", ["torso", "upper_arms", "forearms", "hips"], (0.86, 1.58), 0.016, (0.0, 0.68)),
    ("pants", ["hips", "thighs", "shins", "torso"], (0.10, 1.03), 0.009, None),
    ("boots", ["feet", "shins"], (-1.0, 0.27), 0.012, None),
    ("gloves", ["hands", "forearms"], (-1.0, 9.0), 0.0035, (0.63, 9.0)),
    ("beanie", ["head"], (1.715, 9.0), 0.010, None),
    ("vest", ["torso"], (1.04, 1.46), 0.032, (0.0, 0.19)),
]


def rng_noise(n, seed, s=0.03):
    return np.random.default_rng(seed).normal(0, s, n)


# ----------------------------------------------------------------- detail painters (P: (N,3), n: normal)

def paint_tshirt(P, n):
    x, y, z = P.T
    r = 0.82 + 0.12 * (n[2] * 0.5 + 0.5) + rng_noise(len(P), 1, 0.015)
    r -= 0.18 * (np.abs(z - 1.455) < 0.008)                     # collar rib
    r -= 0.15 * (np.abs(np.abs(x) - 0.43) < 0.006)              # sleeve hems
    r -= 0.12 * (z < 0.915)                                      # bottom hem
    return np.stack([np.clip(r, 0, 1), np.zeros(len(P))], 1)


def paint_jacket(P, n):
    x, y, z = P.T
    r = 0.78 + 0.15 * (n[2] * 0.5 + 0.5) + rng_noise(len(P), 2, 0.02)
    front = y < -0.05
    r -= 0.25 * (front & (np.abs(x) < 0.006) & (z > 0.9))       # zip line
    r -= 0.15 * (front & (np.abs(np.abs(x) - 0.08) < 0.004) & (z > 1.0) & (z < 1.12))   # pocket flaps
    r -= 0.12 * (np.abs(np.abs(x) - 0.43) < 0.005)              # elbow seams
    g = ((z < 0.885) | (np.abs(x) > 0.64) | (z > 1.5)).astype(np.float32)  # hem, cuffs, collar
    return np.stack([np.clip(r, 0, 1), g], 1)


def paint_pants(P, n):
    x, y, z = P.T
    r = 0.80 + 0.12 * (n[2] * 0.5 + 0.5) + rng_noise(len(P), 3, 0.02)
    r -= 0.2 * (np.abs(x) < 0.006) * (z > 0.8)                  # fly / centre seam
    side = np.abs(np.abs(x) - 0.2) < 0.012
    r -= 0.12 * ((np.abs(y) < 0.01) & (z < 0.9))                # outer leg seams
    pocket = (np.abs(np.abs(x) - 0.17) < 0.05) & (np.abs(z - 0.62) < 0.07) & (np.abs(y) < 0.06)
    r -= 0.1 * pocket * (np.abs(z - 0.69) < 0.006)              # cargo pocket flap line
    g = (z > 0.98).astype(np.float32)                            # waistband
    return np.stack([np.clip(r, 0, 1), g], 1)


def paint_boots(P, n):
    x, y, z = P.T
    r = 0.75 + 0.2 * (n[2] * 0.5 + 0.5) + rng_noise(len(P), 4, 0.02)
    r -= 0.2 * (np.abs(z - 0.25) < 0.008)                       # top cuff
    laces = (y < -0.04) & (z > 0.05) & (z < 0.24) & (np.abs((z * 400) % 2 - 1) < 0.35)
    r -= 0.25 * laces
    g = (z < 0.028).astype(np.float32)                           # sole
    return np.stack([np.clip(r, 0, 1), g], 1)


def paint_gloves(P, n):
    x, y, z = P.T
    r = 0.8 + 0.15 * (n[2] * 0.5 + 0.5) + rng_noise(len(P), 5, 0.02)
    g = ((np.abs(x) > 0.735) & (np.abs(x) < 0.81) & (n[2] > 0.3)).astype(np.float32)  # knuckle pad
    r -= 0.15 * (np.abs(np.abs(x) - 0.665) < 0.006)             # cuff strap
    return np.stack([np.clip(r, 0, 1), g], 1)


def paint_beanie(P, n):
    x, y, z = P.T
    rib = 0.06 * np.sin(np.arctan2(y + 0.045, x) * 40)
    r = 0.8 + rib + rng_noise(len(P), 6, 0.02)
    g = (z < 1.755).astype(np.float32)                           # folded cuff
    return np.stack([np.clip(r, 0, 1), g], 1)


def paint_vest(P, n):
    x, y, z = P.T
    r = 0.78 + 0.15 * (n[2] * 0.5 + 0.5) + rng_noise(len(P), 7, 0.02)
    rows = (np.abs((z * 40) % 1 - 0.5) < 0.08) & (np.abs(x) < 0.15)  # MOLLE webbing rows
    r -= 0.2 * rows
    g = ((y < -0.1) & (np.abs(x) < 0.12) & (z > 1.08) & (z < 1.22)).astype(np.float32)  # mag pouches
    return np.stack([np.clip(r, 0, 1), g], 1)


def paint_cap(P, n):
    x, y, z = P.T
    r = 0.8 + 0.12 * (n[2] * 0.5 + 0.5) + rng_noise(len(P), 8, 0.02)
    seams = np.abs(np.sin(np.arctan2(y + 0.045, x) * 3)) < 0.06
    r -= 0.18 * seams * (z > 1.76)
    g = (y < -0.15).astype(np.float32)                           # brim
    return np.stack([np.clip(r, 0, 1), g], 1)


def paint_backpack(P, n):
    x, y, z = P.T
    r = 0.78 + 0.15 * (n[2] * 0.5 + 0.5) + rng_noise(len(P), 9, 0.02)
    r -= 0.25 * ((np.abs(z - 1.32) < 0.006) & (y > 0.3))        # top pocket zip
    g = ((y < 0.15) | (np.abs(x) > 0.165)).astype(np.float32)    # straps + side pockets
    return np.stack([np.clip(r, 0, 1), g], 1)


PAINTERS = {"tshirt": paint_tshirt, "jacket": paint_jacket, "pants": paint_pants, "boots": paint_boots,
            "gloves": paint_gloves, "beanie": paint_beanie, "vest": paint_vest, "cap": paint_cap, "backpack": paint_backpack}


# ----------------------------------------------------------------- build helpers

def select_only(*objs):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def smart_uv(ob):
    select_only(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def write_detail(ob, item_id):
    painter = PAINTERS[item_id]
    old = bb.paint
    bb.paint = lambda P, n: np.concatenate([painter(P, n), np.zeros((len(P), 6), np.float32)], 1)
    img = bb.rasterize([ob], TEX_SIZE)
    bb.paint = old
    rgba = np.zeros((TEX_SIZE, TEX_SIZE, 4), np.float32)
    rgba[..., 0] = img[..., 0]
    rgba[..., 1] = img[..., 1]
    rgba[..., 2] = img[..., 0]
    rgba[..., 3] = 1.0
    folder = os.path.join(OUT, item_id)
    os.makedirs(folder, exist_ok=True)
    bb.save_rgba(rgba, os.path.join(folder, f"{item_id}_detail.png"))


def make_material(item_id):
    m = bpy.data.materials.new(f"{item_id}_mat")
    m.use_nodes = True
    return m


def build_skinned(rig, item_id, regions, zlim, inflate, xlim):
    parts = []
    for r in regions:
        src = bpy.data.objects.get(f"Body_{r}")
        if src is None:
            continue
        dup = src.copy()
        dup.data = src.data.copy()
        bpy.context.scene.collection.objects.link(dup)
        parts.append(dup)
    select_only(*parts)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = item_id
    ob.data.name = item_id
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    kill = [f for f in bm.faces if not (zlim[0] <= f.calc_center_median().z <= zlim[1])
            or (xlim is not None and not (xlim[0] <= abs(f.calc_center_median().x) <= xlim[1]))]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * inflate
    if item_id == "boots":
        for v in bm.verts:
            if v.co.z < 0.02:
                v.co.z = -0.004  # flat sole slightly below the foot
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.materials.clear()
    ob.data.materials.append(make_material(item_id))
    for p in ob.data.polygons:
        p.use_smooth = False
    smart_uv(ob)
    return ob


def build_cap():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.05], context="VERTS")
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.093, v.co.y * 0.112 - 0.045, max(v.co.z, 0.0) * 0.085 + 1.742))
    # Brim: a flat curved plate at the front.
    brim = []
    for i in range(6):
        a = math.radians(-70 + i * 28)
        inner = Vector((math.sin(a) * 0.09, -0.045 - math.cos(a) * 0.108, 1.745))
        outer = Vector((math.sin(a) * 0.1, -0.045 - math.cos(a) * 0.19, 1.735))
        brim.append((bm.verts.new(inner), bm.verts.new(outer)))
    for i in range(5):
        bm.faces.new([brim[i][0], brim[i + 1][0], brim[i + 1][1], brim[i][1]])
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary and all(v.co.z > 1.74 and v.co.y > -0.15 for v in e.verts)], sides=0)
    me = bpy.data.meshes.new("cap")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("cap", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(make_material("cap"))
    smart_uv(ob)
    return ob


def build_backpack():
    bm = bmesh.new()

    def box(x0, x1, y0, y1, z0, z1, bevel=0.0):
        r = bmesh.ops.create_cube(bm, size=1.0)
        vs = r["verts"]
        for v in vs:
            v.co = Vector(((x0 + x1) / 2 + v.co.x * (x1 - x0), (y0 + y1) / 2 + v.co.y * (y1 - y0), (z0 + z1) / 2 + v.co.z * (z1 - z0)))
        if bevel:
            bmesh.ops.bevel(bm, geom=[e for e in bm.edges if all(v in vs for v in e.verts)], offset=bevel, segments=1, affect="EDGES")

    box(-0.16, 0.16, 0.15, 0.33, 0.98, 1.45, 0.03)          # main bag
    box(-0.13, 0.13, 0.30, 0.38, 1.04, 1.28, 0.02)          # front pocket
    box(0.16, 0.2, 0.18, 0.3, 1.0, 1.2, 0.01)               # side pockets
    box(-0.2, -0.16, 0.18, 0.3, 1.0, 1.2, 0.01)
    for s in (1, -1):                                       # shoulder straps over the top and down the chest
        box(s * 0.07, s * 0.12, 0.0, 0.16, 1.45, 1.49)
        box(s * 0.07, s * 0.12, -0.14, -0.11, 1.12, 1.47)
        box(s * 0.07, s * 0.12, -0.11, 0.0, 1.44, 1.49)
    me = bpy.data.meshes.new("backpack")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("backpack", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(make_material("backpack"))
    for p in me.polygons:
        p.use_smooth = False
    smart_uv(ob)
    return ob


def export(objs, item_id, with_rig):
    folder = os.path.join(OUT, item_id)
    os.makedirs(folder, exist_ok=True)
    select_only(*objs)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(folder, f"{item_id}.glb"), export_format="GLB", use_selection=True,
        export_yup=True, export_skins=with_rig, export_animations=False, export_materials="PLACEHOLDER",
    )


def main():
    bpy.ops.wm.open_mainfile(filepath=BODY)
    rig = bpy.data.objects["HumanRig"]
    for item_id, regions, zlim, inflate, xlim in SKINNED:
        ob = build_skinned(rig, item_id, regions, zlim, inflate, xlim)
        write_detail(ob, item_id)
        export([ob, rig], item_id, True)
        print(f"{item_id:<9} skinned {sum(len(p.vertices) - 2 for p in ob.data.polygons):>5} tris")
        bpy.data.objects.remove(ob)
    for item_id, builder in (("cap", build_cap), ("backpack", build_backpack)):
        ob = builder()
        write_detail(ob, item_id)
        export([ob], item_id, False)
        print(f"{item_id:<9} rigid   {sum(len(p.vertices) - 2 for p in ob.data.polygons):>5} tris")
        bpy.data.objects.remove(ob)


if __name__ == "__main__":
    main()
