"""Builds a low-poly 30-round STANAG magazine (5.56 NATO, USGI aluminium) with bpy.

Sized from a real USGI 30-rounder and fitted to the game's M4A1 (m4_import.py places
it in the magazine well, where the source model's magazine was):
- ~7.1 in from the feed lips to the bottom of the floorplate,
- 0.88 in (22.4 mm) wide, 0.95 in over the stiffening ribs,
- 2.5 in (63 mm) front to back,
- straight for the top 2.6 in (the part that sits in the well), then curving forward
  (the bottom ends up ~20 mm ahead of the top),
- two stiffening ribs down each side, a dimpled base, a black steel floorplate with
  its front tab, a tan anti-tilt follower and the top round (staggered left).

Local space: +Y forward (toward the muzzle), +Z up, origin at the top centre of the
feed lips. Usage:  python3 stanag_build.py <asset_dir>  (writes stanag.blend / stanag.glb)
"""
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector
from PIL import Image

S = 0.001
WIDTH = 22.4
DEPTH = 63.0
TOP_STRAIGHT = 66.0      # mm of straight body below the lips
CURVE_LEN = 101.0        # mm of curved body below that
CURVE_DEG = 15.0         # how far the bottom has turned forward
FLOOR_T = 7.5


def _material(name, color, rough, metal, tex=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if tex:
        t = m.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(tex)
        t.image.pack()
        m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return m


def _texture(path):
    """Dry-film grey-green with fine speckle and faint horizontal machining."""
    rng = np.random.default_rng(30)
    img = np.zeros((64, 64, 3), np.float32) + np.array([88, 92, 82], np.float32)
    img += rng.normal(0, 3.0, (64, 64, 1)) + rng.normal(0, 1.5, (64, 1, 1)).transpose(1, 0, 2)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(path)


def _spine(n_curve=6):
    """Centre line points (y, z) with the body's forward angle at each, top to bottom."""
    pts = [(0.0, 0.0, 0.0), (0.0, -TOP_STRAIGHT, 0.0)]
    y, z = 0.0, -TOP_STRAIGHT
    step = CURVE_LEN / n_curve
    for i in range(1, n_curve + 1):
        a = math.radians(CURVE_DEG * i / n_curve)
        am = math.radians(CURVE_DEG * (i - 0.5) / n_curve)
        y += step * math.sin(am)
        z -= step * math.cos(am)
        pts.append((y, z, a))
    return pts


def _ring(y, z, a, hw, hd, ch):
    """Chamfered rectangle across the body at a spine point, tilted by the curve angle."""
    fwd = Vector((0.0, math.cos(a), -math.sin(a)))   # across the body, toward the front
    out = []
    for px, pd in [(-hw + ch, -hd), (hw - ch, -hd), (hw, -hd + ch), (hw, hd - ch), (hw - ch, hd), (-hw + ch, hd), (-hw, hd - ch), (-hw, -hd + ch)]:
        p = Vector((px, y, z)) + fwd * pd
        out.append(p)
    return out


def _mesh(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata([v * S for v in verts], [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return ob


def _loft(name, rings, mat):
    n = len(rings[0])
    verts = [v for r in rings for v in r]
    faces = [list(range(n)), [len(verts) - n + i for i in range(n)]]
    for k in range(len(rings) - 1):
        a, b = k * n, (k + 1) * n
        faces += [[a + i, a + (i + 1) % n, b + (i + 1) % n, b + i] for i in range(n)]
    return _mesh(name, verts, faces, mat)


def _box(name, c, size, mat, a=0.0):
    """Box centred at c (mm), size (x, across-depth, height), tilted forward by angle a."""
    fwd = Vector((0.0, math.cos(a), -math.sin(a)))
    up = Vector((0.0, math.sin(a), math.cos(a)))
    sx, sd, sh = size[0] / 2, size[1] / 2, size[2] / 2
    verts = []
    for dz in (-sh, sh):
        for dx, dd in ((-sx, -sd), (sx, -sd), (sx, sd), (-sx, sd)):
            verts.append(Vector(c) + Vector((dx, 0, 0)) + fwd * dd + up * dz)
    faces = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
    return _mesh(name, verts, faces, mat)


def _uv(ob, scale=40.0):
    me = ob.data
    uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co / S
            u, v = ((co.y, co.z), (co.x, co.z), (co.x, co.y))[ax]
            uv.data[li].uv = (u / scale, v / scale)


def build_stanag(tex_dir):
    """Builds the magazine; returns the joined object (metres, origin at the top of the lips)."""
    os.makedirs(tex_dir, exist_ok=True)
    tex = os.path.join(tex_dir, "stanag_body.png")
    _texture(tex)
    body_m = _material("StanagBody", (0.36, 0.38, 0.33), 0.7, 0.15, tex)
    floor_m = _material("StanagFloor", (0.06, 0.06, 0.065), 0.55, 0.3)
    foll_m = _material("StanagFollower", (0.62, 0.55, 0.38), 0.75, 0.0)
    brass = _material("StanagBrass", (0.75, 0.55, 0.22), 0.4, 0.5)
    copper = _material("StanagBullet", (0.6, 0.35, 0.2), 0.45, 0.4)

    spine = _spine()
    hw, hd = WIDTH / 2, DEPTH / 2
    rings = []
    for i, (y, z, a) in enumerate(spine):
        # The feed lips narrow in at the very top.
        if i == 0:
            rings.append(_ring(y, z - 0.0, a, hw - 1.6, hd - 3.0, 2.0))
            rings.append(_ring(y, z - 9.0, a, hw, hd, 2.0))
        else:
            rings.append(_ring(y, z, a, hw, hd, 2.0))
    parts = [_loft("Body", rings, body_m)]
    # Stiffening ribs: raised strips down both sides, following the curve.
    for side in (-1, 1):
        for dd, w in ((-hd + 15.0, 6.0), (hd - 17.0, 6.0)):
            rr = []
            for (y, z, a) in spine[1:]:
                fwd = Vector((0.0, math.cos(a), -math.sin(a)))
                base = Vector((side * hw, y, z)) + fwd * dd
                rr.append([base + fwd * (-w / 2), base + fwd * (w / 2),
                           base + Vector((side * 0.9, 0, 0)) + fwd * (w / 2 - 1.0), base + Vector((side * 0.9, 0, 0)) + fwd * (-w / 2 + 1.0)])
            top = Vector((side * hw, 0.0, -24.0))
            rr.insert(0, [r - Vector((0, 0, 0)) for r in [top + Vector((0, dd - w / 2, 0)), top + Vector((0, dd + w / 2, 0)),
                                                         top + Vector((side * 0.9, dd + w / 2 - 1.0, 0)), top + Vector((side * 0.9, dd - w / 2 + 1.0, 0))]])
            parts.append(_loft(f"Rib{side}{dd}", rr, body_m))
    # Floorplate: a bit bigger than the body, with the front tab.
    yb, zb, ab = spine[-1]
    up = Vector((0.0, math.sin(ab), math.cos(ab)))
    fwd = Vector((0.0, math.cos(ab), -math.sin(ab)))
    c = Vector((0.0, yb, zb)) - up * (FLOOR_T / 2 - 1.0)
    parts.append(_box("Floorplate", c, (WIDTH + 3.0, DEPTH + 4.0, FLOOR_T), floor_m, ab))
    parts.append(_box("FloorTab", c + fwd * (hd + 3.5) - up * 1.0, (WIDTH - 6.0, 4.0, FLOOR_T - 2.0), floor_m, ab))
    # Follower (tan) just visible between the lips, and the top round on the left.
    parts.append(_box("Follower", Vector((0.0, 0.0, -3.0)), (WIDTH - 5.0, DEPTH - 8.0, 2.0), foll_m))
    case_c = Vector((-2.6, -6.0, -2.4))
    seg = 10
    ring = lambda yy, r: [Vector((case_c.x + r * math.cos(2 * math.pi * k / seg), yy, case_c.z + r * math.sin(2 * math.pi * k / seg))) for k in range(seg)]
    case = _loft("Case", [ring(-hd + 4.0, 4.7), ring(hd - 26.0, 4.7), ring(hd - 22.0, 3.1), ring(hd - 17.0, 3.1)], brass)
    bullet = _loft("Bullet", [ring(hd - 17.0, 2.85), ring(hd - 10.0, 2.4), ring(hd - 3.0, 0.8)], copper)
    parts += [case, bullet]
    for p in parts:
        _uv(p)
        for poly in p.data.polygons:
            poly.use_smooth = False
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    mag = bpy.context.view_layer.objects.active
    mag.name = mag.data.name = "Magazine"
    return mag


if __name__ == "__main__":
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mag = build_stanag(os.path.join(out, "textures"))
    root = bpy.data.objects.new("STANAG", None)
    bpy.context.scene.collection.objects.link(root)
    mag.parent = root
    tris = sum(len(p.vertices) - 2 for p in mag.data.polygons)
    lo = Vector([min((v.co[i] for v in mag.data.vertices)) for i in range(3)])
    hi = Vector([max((v.co[i] for v in mag.data.vertices)) for i in range(3)])
    print(f"STANAG: {tris} tris, {(hi.z - lo.z) / 0.0254:.2f} in tall, {(hi.x - lo.x) / 0.0254:.2f} in wide, {(hi.y - lo.y) / 0.0254:.2f} in front-back")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "stanag.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "stanag.glb"), export_format="GLB", export_yup=True)
    print("wrote stanag.blend / stanag.glb")
