"""Builds a USMC Ka-Bar fighting/utility knife (1219C2 pattern).

Usage:  python3 kabar_build.py <asset_dir>
Writes <asset_dir>/kabar.blend, <asset_dir>/kabar.glb and textures.

Real dimensions: 11 7/8 in overall, 7 in clip-point blade (1095 steel,
black parkerized), 1.5 in wide, 0.165 in thick, a long fuller, a straight
oval-ended guard, a stacked-leather-washer handle with grooves, and a steel
pommel with the tang peened over it. About 11 oz (0.31 kg).

Same space as m1911_build.py / arms_build.py (millimetres -> metres, +Y forward,
+Z up, +X right), with the handle on the 1911 grip line: put kabar.glb under the
same parent as arms.glb and the knife sits in the right hand, blade up out of
the fist, edge toward the fingers. Knife-local coordinates used below:
a = mm along the knife from the guard face (+ toward the tip, - toward the
pommel), w = mm across (+ spine, - edge), x = mm sideways.
"""
import math
import os
import sys

import bpy  # must come first: it provides bmesh and mathutils
import numpy as np
from mathutils import Vector
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import m1911_build as mb  # noqa: E402
from m1911_build import GRIP_ANGLE, from_data, gp, material, reset  # noqa: E402

ASSET_DIR = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
TEX_DIR = ASSET_DIR
mb.TEX_DIR = TEX_DIR

BLADE = 178.0          # 7 in
WIDTH = 38.0           # 1.5 in
THICK = 4.2            # 0.165 in
CLIP_START = 112.0     # where the clip (swedge) begins on the spine
FULLER = (14.0, 106.0)
HANDLE = 112.0         # stacked leather
POMMEL = 12.0

U = Vector((math.sin(GRIP_ANGLE), math.cos(GRIP_ANGLE)))     # up the grip line (y, z)
N = Vector((-math.cos(GRIP_ANGLE), math.sin(GRIP_ANGLE)))    # across, toward the back of the grip
P0 = Vector(gp(-9.0, 22.0))                                  # guard face, just above the fist


def K(a, w, x):
    """Knife-local -> world mm."""
    p = P0 + U * a + N * w
    return (x, p.x, p.y)


# --------------------------------------------------------------------- textures

def make_textures():
    rng = np.random.default_rng(1942)
    # Parkerized steel: near-black, fine mottled grain.
    p = np.zeros((128, 128, 3), np.float32) + np.array([30, 31, 31], np.float32)
    p += rng.normal(0, 4.0, (128, 128, 1))
    p += np.repeat(np.repeat(rng.normal(0, 3.0, (16, 16, 1)), 8, 0), 8, 1)
    Image.fromarray(np.clip(p, 0, 255).astype(np.uint8)).save(os.path.join(TEX_DIR, "kabar_parkerized.png"))
    # Sharpened edge: bright steel with grind scratches along the edge.
    e = np.zeros((64, 64, 3), np.float32) + np.array([150, 152, 155], np.float32)
    e += rng.normal(0, 10.0, (64, 1, 1))
    e += rng.normal(0, 4.0, (64, 64, 1))
    Image.fromarray(np.clip(e, 0, 255).astype(np.uint8)).save(os.path.join(TEX_DIR, "kabar_edge.png"))
    # Stacked leather: brown washers (V runs along the handle) with dark grooves and lacquer variation.
    rows, rh, w = 7, 32, 64                              # one texture row per modelled washer
    h = rows * rh
    leather = np.zeros((h, w, 3), np.float32)
    base = np.array([96, 56, 30], np.float32)
    for r in range(rows):
        tint = rng.uniform(0.85, 1.12)
        leather[r * rh:(r + 1) * rh] = base * tint
        for sub in range(1, 4):                          # thin washer seams inside each groove band
            leather[r * rh + sub * rh // 4] *= 0.75
        leather[r * rh:r * rh + 3] = base * 0.3          # deep groove
        leather[(r + 1) * rh - 3:(r + 1) * rh] = base * 0.3
    leather += rng.normal(0, 6.0, (h, w, 1))
    leather += np.repeat(rng.normal(0, 5.0, (h // 4, w // 4, 1)), 4, 0).repeat(4, 1)
    Image.fromarray(np.clip(leather, 0, 255).astype(np.uint8)).save(os.path.join(TEX_DIR, "kabar_leather.png"))


# --------------------------------------------------------------------- blade

def edge_w(a):
    """Edge line: straight, then the belly sweeps up to the tip."""
    if a <= 118.0:
        return -WIDTH / 2.0 + 2.0 * (a / 118.0)
    t = (a - 118.0) / (BLADE - 118.0)
    return lerp(-WIDTH / 2.0 + 2.0, -5.0, 1.0 - (1.0 - t) ** 2.2)


def spine_w(a):
    """Spine line: straight, then the concave clip down to the tip."""
    if a <= CLIP_START:
        return WIDTH / 2.0
    t = (a - CLIP_START) / (BLADE - CLIP_START)
    return lerp(WIDTH / 2.0, -5.0, t ** 1.35)


def lerp(a, b, t):
    return a + (b - a) * t


def blade():
    # Across-blade stations: fraction from edge (0) to spine (1) and half thickness.
    stations = [0.0, 0.07, 0.38, 0.48, 0.70, 0.80, 1.0]
    rows = []
    a_steps = [0.0, 6.0, 12.0] + list(np.linspace(18.0, BLADE - 4.0, 18)) + [BLADE]
    for a in a_steps:
        we, ws = edge_w(a), spine_w(a)
        if a >= BLADE:
            we = ws = -5.0
        in_fuller = FULLER[0] < a < FULLER[1]
        swedge = max(0.0, (a - CLIP_START) / (BLADE - CLIP_START))
        row = []
        for f in stations:
            w = lerp(we, ws, f)
            if f == 0.0:
                h = 0.15
            elif f <= 0.07:
                h = 0.6                                  # the sharpened bevel
            elif f <= 0.38:
                h = lerp(0.6, THICK / 2.0, (f - 0.07) / 0.31)   # flat grind
            elif 0.48 <= f <= 0.70 and in_fuller:
                h = THICK / 2.0 - 0.9                    # fuller groove
            else:
                h = THICK / 2.0
            if f >= 0.8:
                h = lerp(h, 0.25, swedge if f == 1.0 else swedge * 0.5)   # sharpened clip
            h *= 1.0 - 0.85 * max(0.0, (a - 150.0) / (BLADE - 150.0)) ** 1.5   # thins to the point
            row.append((w, max(h, 0.12)))
        rows.append((a, row))

    verts, faces_steel, faces_edge = [], [], []
    ns = len(stations)
    for a, row in rows:
        for w, h in row:
            verts.append(K(a, w, h))
        for w, h in row:
            verts.append(K(a, w, -h))
    stride = 2 * ns
    for i in range(len(rows) - 1):
        o0, o1 = i * stride, (i + 1) * stride
        for side in (0, ns):
            for j in range(ns - 1):
                q = [o0 + side + j, o1 + side + j, o1 + side + j + 1, o0 + side + j + 1]
                if side:
                    q.reverse()
                (faces_edge if j == 0 else faces_steel).append(q)
        # spine strip and edge strip close the solid
        faces_steel.append([o0 + ns - 1, o1 + ns - 1, o1 + 2 * ns - 1, o0 + 2 * ns - 1][::-1])
        faces_edge.append([o0, o0 + ns, o1 + ns, o1][::-1])
    # base cap (hidden in the guard)
    faces_steel.append(list(range(ns)) + list(range(2 * ns - 1, ns - 1, -1)))
    steel = material("Kabar_Parkerized", (0.12, 0.12, 0.12), "kabar_parkerized.png", rough=0.62, metal=0.55)
    edge = material("Kabar_Edge", (0.6, 0.6, 0.62), "kabar_edge.png", rough=0.3, metal=0.9)
    ob = from_data("Blade", verts, faces_steel + faces_edge, steel)
    ob.data.materials.append(edge)
    nsteel = len(faces_steel)
    for k, poly in enumerate(ob.data.polygons):
        poly.material_index = 0 if k < nsteel else 1
    return ob


# --------------------------------------------------------------------- guard, handle, pommel

def oval_ring(a, rw, rx, cw=0.0, seg=12):
    return [K(a, cw + rw * math.cos(2 * math.pi * i / seg), rx * math.sin(2 * math.pi * i / seg)) for i in range(seg)]


def loft(name, sections, mat, seg=12, cap=True):
    """Sections: list of (a, rw, rx, cw) ovals lofted together."""
    verts, faces = [], []
    for a, rw, rx, cw in sections:
        verts += oval_ring(a, rw, rx, cw, seg)
    for i in range(len(sections) - 1):
        for j in range(seg):
            faces.append([i * seg + j, i * seg + (j + 1) % seg, (i + 1) * seg + (j + 1) % seg, (i + 1) * seg + j])
    if cap:
        faces.append(list(range(seg))[::-1])
        last = (len(sections) - 1) * seg
        faces.append(list(range(last, last + seg)))
    return from_data(name, verts, faces, mat)


def guard():
    steel = bpy.data.materials["Kabar_Parkerized"]
    # A flat bar across the blade with rounded ends: octagon in (w, x), 6 mm along the knife.
    pts = []
    for i in range(16):
        ang = 2 * math.pi * i / 16
        w = math.cos(ang)
        x = math.sin(ang)
        pts.append((w * 37.0 if abs(w) > 0.3 else w * 37.0, x * 4.6))
    verts = [K(0.0, w, x) for w, x in pts] + [K(-6.0, w, x) for w, x in pts]
    n = len(pts)
    faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))]
    faces += [[i, n + i, n + (i + 1) % n, (i + 1) % n] for i in range(n)]
    return from_data("Guard", verts, faces, steel)


def handle():
    leather = material("Kabar_Leather", (0.45, 0.26, 0.14), "kabar_leather.png", rough=0.5, metal=0.0)
    spacer = material("Kabar_Spacer", (0.05, 0.05, 0.05), None, rough=0.7, metal=0.0)
    ob_sp = loft("SpacerTop", [(-6.0, 15.0, 11.5, 0.0), (-9.0, 15.0, 11.5, 0.0)], spacer)
    # Grooved stack: each washer bulges slightly; the handle swells in the middle and narrows to the pommel.
    secs = []
    n_wash = 7
    for k in range(n_wash):
        a0 = -9.0 - k * (HANDLE / n_wash)
        a1 = a0 - HANDLE / n_wash
        swell = 1.0 + 0.08 * math.sin(math.pi * (k + 0.5) / n_wash)
        for t, bump in [(0.0, 0.94), (0.18, 1.0), (0.82, 1.0), (1.0, 0.94)]:
            secs.append((lerp(a0, a1, t), 16.0 * swell * bump, 12.5 * swell * bump, 0.0))
    ob_h = loft("Handle", secs, leather)
    # UVs: V along the handle so the washer texture lines up with the grooves.
    me = ob_h.data
    uv = me.uv_layers.new(name="UVMap")
    a_top, a_bot = -9.0, -9.0 - HANDLE
    seg = 12
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            ring, j = divmod(vi, seg)
            a = secs[min(ring, len(secs) - 1)][0]
            uv.data[li].uv = (j / seg, (a - a_bot) / (a_top - a_bot))
    ob_sp2 = loft("SpacerBottom", [(a_bot, 15.0, 11.5, 0.0), (a_bot - 2.5, 15.0, 11.5, 0.0)], spacer)
    return [ob_sp, ob_h, ob_sp2]


def pommel():
    steel = bpy.data.materials["Kabar_Parkerized"]
    a0 = -9.0 - HANDLE - 2.5
    secs = [(a0, 15.5, 12.0, 0.0), (a0 - 4.0, 16.5, 12.8, 0.0), (a0 - 9.0, 15.0, 11.5, 0.0), (a0 - POMMEL, 9.0, 7.0, 0.0)]
    ob = loft("Pommel", secs, steel)
    nut = loft("TangPeen", [(a0 - POMMEL, 4.0, 4.0, 0.0), (a0 - POMMEL - 2.0, 2.5, 2.5, 0.0)], steel, seg=8)
    return [ob, nut]


def build():
    reset()
    make_textures()
    parts = [blade(), guard()] + handle() + pommel()
    # Smooth shading on the round parts only.
    for ob in parts:
        if ob.name in ("Handle", "Pommel", "SpacerTop", "SpacerBottom"):
            for p in ob.data.polygons:
                p.use_smooth = True
    root = bpy.data.objects.new("Kabar", None)
    bpy.context.scene.collection.objects.link(root)
    for ob in parts:
        ob.parent = root
    tris = sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in parts)
    print(f"Ka-Bar: {tris} tris")


if __name__ == "__main__":
    build()
    blend = os.path.join(ASSET_DIR, "kabar.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    bpy.ops.export_scene.gltf(filepath=os.path.join(ASSET_DIR, "kabar.glb"), export_format="GLB", export_apply=True, export_yup=True)
    print("wrote", blend, "and kabar.glb")
