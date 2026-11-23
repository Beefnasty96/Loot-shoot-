"""Builds the shared human base body from the source FBX.

Usage:  python3 body_build.py <source.fbx> <out_dir>
Writes <out_dir>/body.blend, body.glb, textures/body_masks_a.png, textures/body_masks_b.png

What it does
1. Cleans the low-poly base mesh (T-pose, 1.83 m, facing -Y; +X is the character's LEFT).
2. Replaces the paddle hands with low-poly five-finger hands.
3. Builds a humanoid skeleton named after Godot's SkeletonProfileHumanoid, so
   animations can be retargeted onto it later.
4. Skins it: automatic (heat) weights for the body, rigid weights for palms/fingers.
5. Lays out UVs (extra resolution for the head) and paints appearance masks from
   the 3D shape: skin shading, brows, scalp hair, beard, underwear, eye whites, irises, lips.
   A Godot shader tints these per character (skin tone, hair/eye colour, beard...).
6. Splits the body into regions (Body_head, Body_torso, ...). Clothing hides the
   regions it covers, which prevents skin poking through and saves triangles.
"""
import math
import os
import sys

import bpy  # must come first: it provides bmesh and mathutils
import bmesh
import numpy as np
from mathutils import Vector
from PIL import Image

SRC = os.path.abspath(sys.argv[1])
OUT = os.path.abspath(sys.argv[2])
TEX = os.path.join(OUT, "textures")
TEX_SIZE = 512
WRIST_X = 0.694

REGIONS = ["head", "neck", "torso", "upper_arms", "forearms", "hands", "hips", "thighs", "shins", "feet"]


# ----------------------------------------------------------------------------- helpers

def activate(ob, *others):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in others:
        o.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def octa_segment(bm, p0, p1, w0, w1, up, ext0=0.0, ext1=0.0):
    """Tapered hexagonal prism between two points. Returns its new BMVerts."""
    p0, p1 = Vector(p0), Vector(p1)
    a = (p1 - p0).normalized()
    side = a.cross(Vector(up)).normalized()
    upv = side.cross(a).normalized()
    ring = [(0.5, 0.0), (0.27, 0.5), (-0.27, 0.5), (-0.5, 0.0), (-0.27, -0.5), (0.27, -0.5)]
    start, end = p0 - a * ext0, p1 + a * ext1
    vs = [bm.verts.new(start + side * (cx * w0) + upv * (cy * w0 * 0.85)) for cx, cy in ring]
    vs += [bm.verts.new(end + side * (cx * w1) + upv * (cy * w1 * 0.85)) for cx, cy in ring]
    n = len(ring)
    bm.faces.new(list(reversed(vs[:n])))
    bm.faces.new(vs[n:])
    for i in range(n):
        bm.faces.new([vs[i], vs[(i + 1) % n], vs[n + (i + 1) % n], vs[n + i]])
    return vs


# ----------------------------------------------------------------------------- hands

FINGERS = [
    # name, knuckle y, lengths (proximal, intermediate, distal), width, spread (deg, + = toward little finger)
    ("Index", -0.035, (0.038, 0.023, 0.018), 0.021, -3.0),
    ("Middle", -0.012, (0.042, 0.025, 0.019), 0.0215, 0.0),
    ("Ring", 0.010, (0.040, 0.024, 0.018), 0.020, 3.0),
    ("Little", 0.030, (0.031, 0.018, 0.015), 0.017, 7.0),
]
THUMB = [(0.712, -0.030, 1.400), (0.745, -0.058, 1.393), (0.772, -0.075, 1.389), (0.799, -0.087, 1.386)]
THUMB_W = (0.021, 0.019, 0.017, 0.015)
PHALANX = ("Proximal", "Intermediate", "Distal")


def build_hands(bm):
    """Cut off the paddles at the wrist, extrude palms, add finger pieces.
    Returns ({bone: [BMVert]}, [(bone, head, tail, parent)])."""
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if abs(v.co.x) > WRIST_X + 0.006], context="VERTS")
    rig_map, bones = {}, []
    for s, side in ((1.0, "Left"), (-1.0, "Right")):
        edges = [e for e in bm.edges if e.is_boundary and all(s * v.co.x > WRIST_X - 0.01 for v in e.verts)]
        palm_verts = []

        def extrude(edges_in, x, cy, cz, hw_new, hh_new):
            verts = list({v for e in edges_in for v in e.verts})
            c = sum((v.co for v in verts), Vector()) / len(verts)
            hw = max(abs(v.co.y - c.y) for v in verts) or 1e-3
            hh = max(abs(v.co.z - c.z) for v in verts) or 1e-3
            res = bmesh.ops.extrude_edge_only(bm, edges=edges_in)
            new_v = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
            new_e = [g for g in res["geom"] if isinstance(g, bmesh.types.BMEdge) and g.is_boundary]
            for v in new_v:
                u, w = (v.co.y - c.y) / hw, (v.co.z - c.z) / hh
                v.co = Vector((s * x, cy + u * hw_new, cz + w * hh_new))
            palm_verts.extend(new_v)
            return new_e

        e1 = extrude(edges, 0.718, -0.012, 1.408, 0.041, 0.017)
        e2 = extrude(e1, 0.812, -0.006, 1.405, 0.046, 0.012)
        bmesh.ops.holes_fill(bm, edges=e2, sides=0)
        hand = f"{side}Hand"
        rig_map[hand] = palm_verts

        # Four fingers, slightly curved down at rest.
        for name, ky, lengths, width, spread in FINGERS:
            p = Vector((s * 0.800, ky, 1.404))
            pts = [p]
            for i, ln in enumerate(lengths):
                droop = math.radians(4 + 4 * i)
                d = Vector((s * math.cos(math.radians(spread)) * math.cos(droop), math.sin(math.radians(spread)), -math.sin(droop)))
                p = p + d * ln
                pts.append(p)
            parent = hand
            for i in range(3):
                bname = f"{side}{name}{PHALANX[i]}"
                w0, w1 = width * (1 - 0.06 * i), width * (1 - 0.06 * (i + 1))
                vs = octa_segment(bm, pts[i], pts[i + 1], w0, w1, (0, 0, 1), ext0=w0 * 0.3, ext1=w1 * (0.5 if i == 2 else 0.3))
                rig_map[bname] = vs
                bones.append((bname, pts[i], pts[i + 1] + (pts[i + 1] - pts[i]).normalized() * (0.006 if i == 2 else 0.0), parent))
                parent = bname

        # Thumb: metacarpal sits in the palm, two visible phalanges.
        tp = [Vector((s * x, y, z)) for x, y, z in THUMB]
        parent = hand
        for i, bname in enumerate(("ThumbMetacarpal", "ThumbProximal", "ThumbDistal")):
            full = f"{side}{bname}"
            vs = octa_segment(bm, tp[i], tp[i + 1], THUMB_W[i], THUMB_W[i + 1], (0, -0.3, 1), ext0=THUMB_W[i] * 0.3, ext1=THUMB_W[i + 1] * (0.5 if i == 2 else 0.3))
            rig_map[full] = vs
            bones.append((full, tp[i], tp[i + 1], parent))
            parent = full
    return rig_map, bones


# ----------------------------------------------------------------------------- skeleton

def body_bones():
    b = [
        ("Root", (0, 0, 0), (0, 0, 0.12), None),
        ("Hips", (0, 0.0, 0.93), (0, 0, 1.03), "Root"),
        ("Spine", (0, 0, 1.03), (0, 0, 1.15), "Hips"),
        ("Chest", (0, 0, 1.15), (0, 0, 1.29), "Spine"),
        ("UpperChest", (0, 0, 1.29), (0, 0, 1.47), "Chest"),
        ("Neck", (0, 0.005, 1.47), (0, 0, 1.57), "UpperChest"),
        ("Head", (0, 0, 1.57), (0, 0, 1.83), "Neck"),
    ]
    for s, side in ((1.0, "Left"), (-1.0, "Right")):
        b += [
            (f"{side}Shoulder", (s * 0.03, 0, 1.44), (s * 0.17, 0, 1.435), "UpperChest"),
            (f"{side}UpperArm", (s * 0.17, 0, 1.435), (s * 0.44, 0.005, 1.42), f"{side}Shoulder"),
            (f"{side}LowerArm", (s * 0.44, 0.005, 1.42), (s * WRIST_X, 0, 1.41), f"{side}UpperArm"),
            (f"{side}Hand", (s * WRIST_X, 0, 1.41), (s * 0.800, -0.006, 1.405), f"{side}LowerArm"),
            (f"{side}UpperLeg", (s * 0.095, 0, 0.93), (s * 0.15, -0.005, 0.50), "Hips"),
            (f"{side}LowerLeg", (s * 0.15, -0.005, 0.50), (s * 0.185, 0.02, 0.085), f"{side}UpperLeg"),
            (f"{side}Foot", (s * 0.185, 0.02, 0.085), (s * 0.19, -0.09, 0.025), f"{side}LowerLeg"),
            (f"{side}Toes", (s * 0.19, -0.09, 0.025), (s * 0.195, -0.165, 0.02), f"{side}Foot"),
        ]
    return b


def build_armature(bones):
    data = bpy.data.armatures.new("HumanRig")
    rig = bpy.data.objects.new("HumanRig", data)
    bpy.context.scene.collection.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name, head, tail, _ in bones:
        e = data.edit_bones.new(name)
        e.head, e.tail = Vector(head), Vector(tail)
        e.roll = 0.0
        eb[name] = e
    for name, _, _, parent in bones:
        if parent:
            eb[name].parent = eb[parent]
            # Connect only where the child starts at the parent's tail (keeps the chain tidy).
            if (eb[name].head - eb[parent].tail).length < 1e-4:
                eb[name].use_connect = True
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


# ----------------------------------------------------------------------------- regions

def region_of(c):
    ax, z = abs(c.x), c.z
    if z > 1.25 and ax > WRIST_X - 0.004:
        return "hands"
    if z > 1.25 and ax > 0.2:
        return "upper_arms" if ax < 0.44 else "forearms"
    if z > 1.575:
        return "head"
    if z > 1.47 and ax < 0.1:
        return "neck"
    if z >= 0.985:
        return "torso"
    if z >= 0.80:
        return "hips"
    if z >= 0.50:
        return "thighs"
    if z >= 0.10:
        return "shins"
    return "feet"


# ----------------------------------------------------------------------------- texture painting

def smooth_band(x, lo, hi, soft):
    return np.clip((x - lo) / soft + 0.5, 0, 1) * np.clip((hi - x) / soft + 0.5, 0, 1)


def paint(P, n):
    """P: (N,3) surface points, n: face normal. Returns (N, 8) channels:
    a: shade, brows, scalp, beard   b: underwear, eye white, iris, lips."""
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    ax = np.abs(x)
    N = len(P)
    out = np.zeros((N, 8), np.float32)
    rng = np.random.default_rng(int(abs(P[0, 0] * 1e5)) % 100000)
    noise = rng.normal(0, 0.02, N)
    shade = 0.84 + 0.16 * (n[2] * 0.5 + 0.5) + noise
    # Darker under the jaw and at the neck front, in the armpits and between the legs.
    shade -= 0.10 * smooth_band(z, 1.52, 1.585, 0.02) * (n[1] < 0)
    shade -= 0.06 * (n[2] < -0.5)
    # Nose: shadow down its sides and under the tip.
    hf = (z > 1.64) & (z < 1.705) & (n[1] < -0.2)
    shade -= 0.09 * (hf & (ax > 0.007) & (ax < 0.016) & (z < 1.69))
    shade -= 0.12 * ((z > 1.655) & (z < 1.664) & (ax < 0.014) & (n[1] < -0.2))
    out[:, 0] = np.clip(shade, 0, 1)

    head = z > 1.575
    front = n[1] < -0.25
    # Brows: arched strokes above the eyes.
    arch = 1.728 + 0.004 * (1 - ((ax - 0.031) / 0.018) ** 2)
    out[:, 1] = (head & front & (ax > 0.011) & (ax < 0.05) & (np.abs(z - arch) < 0.0035)).astype(np.float32)
    # Scalp hair: crown, back and sides above the ears; soft hairline.
    scalp = np.clip((z - 1.742) / 0.008, 0, 1)
    back = np.clip((y + 0.04) / 0.02, 0, 1) * np.clip((z - 1.63) / 0.02, 0, 1)
    sides = np.clip((ax - 0.062) / 0.01, 0, 1) * np.clip((z - 1.70) / 0.015, 0, 1)
    out[:, 2] = np.clip(np.maximum(scalp, np.maximum(back, sides)), 0, 1) * head
    # Beard: jaw, chin, cheeks, moustache; not on the lips. Speckled like stubble.
    beard = smooth_band(z, 1.58, 1.668, 0.006) * np.clip((-y - 0.02) / 0.03, 0, 1)
    beard *= 1 - np.clip(1 - (((x / 0.021) ** 2) + ((z - 1.643) / 0.006) ** 2), 0, 1)
    beard *= np.where((z > 1.652) & (ax > 0.03), 0.0, 1.0)  # keep cheeks above the moustache clear
    out[:, 3] = np.clip(beard * (0.8 + rng.normal(0, 0.15, N)), 0, 1) * (z > 1.57)

    # Underwear (boxer briefs).
    legcut = np.where(ax < 0.055, 0.83, 0.865)
    out[:, 4] = ((z > legcut) & (z < 0.985)).astype(np.float32)
    # Eyes and lips (front of the face only).
    ef = head & (n[1] < -0.2)
    e = ((ax - 0.033) / 0.0125) ** 2 + ((z - 1.708) / 0.0058) ** 2
    out[:, 5] = (ef & (e < 1.0)).astype(np.float32)
    iris = ((ax - 0.033) ** 2 + (z - 1.708) ** 2) < 0.0047 ** 2
    out[:, 6] = (ef & iris).astype(np.float32)
    lips = ((x / 0.021) ** 2 + ((z - 1.643) / 0.0058) ** 2) < 1.0
    out[:, 7] = (ef & lips).astype(np.float32)
    return out


def rasterize(objs, size):
    img = np.zeros((size, size, 8), np.float32)
    cover = np.zeros((size, size), bool)
    for ob in objs:
        me = ob.data
        me.calc_loop_triangles()
        uvl = me.uv_layers.active.data
        mw = ob.matrix_world
        for tri in me.loop_triangles:
            uv = np.array([[uvl[l].uv[0] * size, (1 - uvl[l].uv[1]) * size] for l in tri.loops])
            ps = np.array([tuple(mw @ me.vertices[i].co) for i in tri.vertices])
            n = np.array(tuple((mw.to_3x3() @ tri.normal).normalized()))
            x0, y0 = np.floor(uv.min(0)).astype(int) - 1
            x1, y1 = np.ceil(uv.max(0)).astype(int) + 1
            x0, y0 = max(x0, 0), max(y0, 0)
            x1, y1 = min(x1, size - 1), min(y1, size - 1)
            if x1 < x0 or y1 < y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            px = np.stack([gx.ravel(), gy.ravel()], 1)
            a, b, c = uv
            v0, v1 = b - a, c - a
            den = v0[0] * v1[1] - v1[0] * v0[1]
            if abs(den) < 1e-9:
                continue
            d = px - a
            l1 = (d[:, 0] * v1[1] - v1[0] * d[:, 1]) / den
            l2 = (v0[0] * d[:, 1] - d[:, 0] * v0[1]) / den
            l0 = 1 - l1 - l2
            inside = (l0 >= -0.02) & (l1 >= -0.02) & (l2 >= -0.02)
            if not inside.any():
                continue
            P = l0[inside, None] * ps[0] + l1[inside, None] * ps[1] + l2[inside, None] * ps[2]
            vals = paint(P, n)
            ix = (px[inside, 0] - 0.5).astype(int)
            iy = (px[inside, 1] - 0.5).astype(int)
            img[iy, ix] = vals
            cover[iy, ix] = True
    # Dilate a few pixels so mipmaps don't bleed background into seams.
    for _ in range(4):
        grow = ~cover
        acc = np.zeros_like(img)
        cnt = np.zeros((size, size), np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            sh = np.roll(np.roll(img, dy, 0), dx, 1)
            sc = np.roll(np.roll(cover, dy, 0), dx, 1)
            acc += sh * sc[..., None]
            cnt += sc
        fill = grow & (cnt > 0)
        img[fill] = acc[fill] / cnt[fill, None]
        cover |= fill
    return img


def save_rgba(arr, path):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA").save(path)


# ----------------------------------------------------------------------------- main

def main():
    os.makedirs(TEX, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=SRC)
    body = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    body.name = "Body"
    body.data.name = "Body"

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    rig_map, finger_bones = build_hands(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.verts.index_update()
    rigid = {bone: [v.index for v in vs] for bone, vs in rig_map.items()}
    bm.to_mesh(body.data)
    bm.free()
    for p in body.data.polygons:
        p.use_smooth = False

    # Skeleton + skinning.
    rig = build_armature(body_bones() + finger_bones)
    activate(rig, body)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    rigid_set = set()
    for bone, idxs in rigid.items():
        rigid_set.update(idxs)
    for vg in body.vertex_groups:
        vg.remove(list(rigid_set))
    for bone, idxs in rigid.items():
        vg = body.vertex_groups.get(bone) or body.vertex_groups.new(name=bone)
        vg.add(idxs, 1.0, "REPLACE")
    # Any vertex heat weighting missed goes to the nearest bone.
    bone_segs = {b.name: (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local) for b in rig.data.bones}
    missed = 0
    for v in body.data.vertices:
        if sum(g.weight for g in v.groups) < 1e-4:
            best, bd = None, 1e9
            for name, (h, t) in bone_segs.items():
                ht = t - h
                k = max(0.0, min(1.0, (v.co - h).dot(ht) / max(ht.length_squared, 1e-9)))
                dist = (v.co - (h + ht * k)).length
                if dist < bd:
                    best, bd = name, dist
            (body.vertex_groups.get(best) or body.vertex_groups.new(name=best)).add([v.index], 1.0, "REPLACE")
            missed += 1
    activate(body)
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    print(f"skinned: {len(body.vertex_groups)} groups, {missed} vertices fell back to nearest bone")

    # UVs: smart project, then give the head 3x the texel density and repack.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    me = body.data
    uvl = me.uv_layers.active.data
    head_loops = [li for p in me.polygons if p.center.z > 1.5 and abs(p.center.x) < 0.12 for li in p.loop_indices]
    for li in head_loops:
        uvl[li].uv = uvl[li].uv * 3.0
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin=0.008)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Appearance masks.
    img = rasterize([body], TEX_SIZE)
    save_rgba(img[..., 0:4], os.path.join(TEX, "body_masks_a.png"))
    save_rgba(img[..., 4:8], os.path.join(TEX, "body_masks_b.png"))

    # Preview material in Blender (Godot replaces it with the appearance shader).
    mat = bpy.data.materials.new("BodySkin")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.8, 0.6, 0.45, 1)
    bsdf.inputs["Roughness"].default_value = 0.8

    # Split into regions.
    region_mats = {}
    for r in REGIONS:
        m = mat.copy()
        m.name = f"region_{r}"
        region_mats[r] = m
        me.materials.append(m)
    index = {r: i for i, r in enumerate(REGIONS)}
    for p in me.polygons:
        p.material_index = index[region_of(p.center)]
    activate(body)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    total = 0
    for ob in list(bpy.context.scene.objects):
        if ob.type != "MESH":
            continue
        used = {ob.data.materials[p.material_index].name for p in ob.data.polygons}
        if not used:
            bpy.data.objects.remove(ob)
            continue
        region = used.pop().replace("region_", "")
        ob.name = f"Body_{region}"
        ob.data.name = ob.name
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        total += tris
        print(f"  {ob.name:<18} {tris:>5} tris")
    print(f"  TOTAL {total} tris, {len(rig.data.bones)} bones")

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "body.blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT, "body.glb"), export_format="GLB",
        export_yup=True, export_skins=True, export_animations=False, export_materials="PLACEHOLDER",
    )
    print("wrote body.blend, body.glb, masks")


if __name__ == "__main__":
    main()
