"""Builds low-poly first-person arms (gloves + sleeves) gripping the M1911.

Usage:  python3 arms_build.py <asset_dir>
Writes <asset_dir>/arms.blend, <asset_dir>/arms.glb and textures in <asset_dir>/textures.

- Same space as m1911_build.py: millimetres -> metres, +Y = muzzle, +Z = up,
  +X = right. Place arms.glb and m1911.glb under the same parent and they line up.
- Rest pose = the two-handed 1911 grip. Other grips/animations are bone poses on top.
- Rigid skinning (each piece follows exactly one bone), like early-2000s viewmodels.
  Bones per side: Forearm, Hand, Thumb1-3, Index1-3, Middle1-3, Ring1-3, Pinky1-3.
"""
import math
import os
import sys

import bpy  # must come first: it provides bmesh and mathutils
import bmesh
import numpy as np
from mathutils import Vector
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import m1911_build as mb  # noqa: E402
from m1911_build import GRIP_DEPTH, S, activate, gp, link, material, reset  # noqa: E402

ASSET_DIR = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
TEX_DIR = os.path.join(ASSET_DIR, "textures")
mb.TEX_DIR = TEX_DIR  # material() loads textures from here


# --------------------------------------------------------------------- textures

def make_textures():
    os.makedirs(TEX_DIR, exist_ok=True)
    rng = np.random.default_rng(45)
    # Glove: dark synthetic fabric with faint stitching rows.
    g = np.zeros((64, 64, 3), np.float32) + np.array([34, 34, 36], np.float32)
    g += rng.normal(0, 3.0, (64, 64, 1))
    g[::16, :] += 10
    Image.fromarray(np.clip(g, 0, 255).astype(np.uint8)).save(os.path.join(TEX_DIR, "glove.png"))
    # Knuckle guard: slightly lighter moulded plastic.
    k = np.zeros((32, 32, 3), np.float32) + np.array([52, 52, 55], np.float32)
    k += rng.normal(0, 2.0, (32, 32, 1))
    Image.fromarray(np.clip(k, 0, 255).astype(np.uint8)).save(os.path.join(TEX_DIR, "knuckle.png"))
    # Sleeve: olive drab twill weave.
    ys, xs = np.mgrid[0:128, 0:128]
    weave = (((xs + ys) // 2) % 4 < 2).astype(np.float32)
    s = np.zeros((128, 128, 3), np.float32) + np.array([78, 82, 52], np.float32)
    s += weave[..., None] * 7.0 + rng.normal(0, 3.0, (128, 128, 1))
    Image.fromarray(np.clip(s, 0, 255).astype(np.uint8)).save(os.path.join(TEX_DIR, "sleeve.png"))


# --------------------------------------------------------------------- geometry helpers

def G(t, s, x):
    """Grip coordinates (t down the front strap, s back across the grip, x sideways) -> world mm."""
    y, z = gp(t, s)
    return Vector((x, y, z))


def grip_center(t):
    return G(t, GRIP_DEPTH / 2.0, 0.0)


class Builder:
    """Collects mesh pieces, each bound rigidly to one bone, into a single skinned mesh."""

    def __init__(self):
        self.verts, self.faces, self.face_mat, self.vert_bone = [], [], [], []
        self.mats = {}
        self.bones = {}   # name -> (head, tail, parent)

    def mat_index(self, mat):
        if mat.name not in self.mats:
            self.mats[mat.name] = (len(self.mats), mat)
        return self.mats[mat.name][0]

    def add(self, verts, faces, mat, bone):
        base = len(self.verts)
        self.verts += [Vector(v) for v in verts]
        self.vert_bone += [bone] * len(verts)
        mi = self.mat_index(mat)
        for f in faces:
            self.faces.append([base + i for i in f])
            self.face_mat.append(mi)

    def bone(self, name, head, tail, parent=None):
        self.bones[name] = (Vector(head), Vector(tail), parent)

    def segment(self, p0, p1, w0, h0, w1, h1, up, mat, bone, ext0=0.0, ext1=0.0):
        """Tapered octagonal prism from p0 to p1. `up` points to the back of the finger/hand."""
        p0, p1 = Vector(p0), Vector(p1)
        a = (p1 - p0).normalized()
        side = a.cross(Vector(up)).normalized()
        upv = side.cross(a).normalized()
        ring = [(0.5, 0.3), (0.3, 0.5), (-0.3, 0.5), (-0.5, 0.3), (-0.5, -0.3), (-0.3, -0.5), (0.3, -0.5), (0.5, -0.3)]
        start, end = p0 - a * ext0, p1 + a * ext1
        verts = [start + side * (cx * w0) + upv * (cy * h0) for cx, cy in ring]
        verts += [end + side * (cx * w1) + upv * (cy * h1) for cx, cy in ring]
        n = len(ring)
        faces = [list(range(n))[::-1], list(range(n, 2 * n))]
        faces += [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
        self.add(verts, faces, mat, bone)

    def block(self, corners, mat, bone):
        """8 corners: bottom 4 then top 4 (same winding)."""
        faces = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
        self.add(corners, faces, mat, bone)

    def finger(self, side, name, pts, widths, up_fn, mat, parent):
        """Three phalanges through 4 points; one bone per phalanx."""
        prev = parent
        for i in range(3):
            bname = f"{name}{i + 1}.{side}"
            p0, p1 = pts[i], pts[i + 1]
            w0, w1 = widths[i], widths[i + 1]
            up = up_fn((p0 + p1) / 2)
            self.segment(p0, p1, w0, w0 * 0.85, w1, w1 * 0.85, up, mat, bname,
                         ext0=w0 * 0.25, ext1=(w1 * 0.45 if i == 2 else w1 * 0.25))
            self.bone(bname, p0, p1, prev)
            prev = bname

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata([v * S for v in self.verts], [], self.faces)
        me.update()
        for mi, mat in sorted(self.mats.values(), key=lambda m: m[0]):
            me.materials.append(mat)
        for poly, mi in zip(me.polygons, self.face_mat):
            poly.material_index = mi
            poly.use_smooth = False
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        ob = link(bpy.data.objects.new(name, me))

        # Armature.
        arm_data = bpy.data.armatures.new(name + "Rig")
        rig = link(bpy.data.objects.new(name + "Rig", arm_data))
        activate(rig)
        bpy.ops.object.mode_set(mode="EDIT")
        ebones = {}
        for bname, (head, tail, _parent) in self.bones.items():
            eb = arm_data.edit_bones.new(bname)
            eb.head, eb.tail = head * S, tail * S
            ebones[bname] = eb
        for bname, (_h, _t, parent) in self.bones.items():
            if parent:
                ebones[bname].parent = ebones[parent]
        bpy.ops.object.mode_set(mode="OBJECT")

        # Rigid weights.
        groups = {b: ob.vertex_groups.new(name=b) for b in self.bones}
        for vi, b in enumerate(self.vert_bone):
            groups[b].add([vi], 1.0, "REPLACE")
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
        ob.parent = rig

        activate(ob)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.cube_project(cube_size=0.06)
        bpy.ops.object.mode_set(mode="OBJECT")
        return rig, ob


# --------------------------------------------------------------------- the arms

def build_arms():
    glove = material("Glove", (0.13, 0.13, 0.14), "glove.png", rough=0.85, metal=0.0)
    knuckle = material("KnuckleGuard", (0.2, 0.2, 0.21), "knuckle.png", rough=0.6, metal=0.0)
    sleeve = material("Sleeve", (0.3, 0.32, 0.2), "sleeve.png", rough=0.9, metal=0.0)
    b = Builder()

    def outward(t):
        """Back-of-finger direction for a finger wrapped around the grip at height t."""
        return lambda mid: (mid - grip_center(t)).normalized()

    # ================= RIGHT HAND (firing hand) =================
    # Wrist sits behind and below the grip; the palm covers the right grip panel.
    r_wrist = G(66, 84, 20)
    r_elbow = Vector((140, -360, -190))
    r_knuckles = G(38, -4, 30)
    b.bone("Forearm.R", r_elbow, r_wrist)
    b.bone("Hand.R", r_wrist, r_knuckles, "Forearm.R")
    # Sleeve + glove cuff.
    b.segment(r_elbow, r_wrist + (r_elbow - r_wrist).normalized() * 45, 80, 70, 70, 62, (0.3, 0, 1), sleeve, "Forearm.R")
    b.segment(r_wrist + (r_elbow - r_wrist).normalized() * 55, r_wrist, 62, 52, 56, 46, (0.3, 0, 1), glove, "Forearm.R")
    # Palm: knuckle edge at the front of the grip, heel back toward the wrist.
    # Palm: rounded slab on the right panel, knuckle edge at the front of the grip.
    b.segment(G(44, 60, 27), G(44, -6, 28), 84, 26, 86, 24, (1, 0, 0), glove, "Hand.R")
    # Heel / back of hand wrapping behind the back strap toward the wrist.
    b.segment(G(46, 50, 22), r_wrist, 70, 32, 58, 46, (1, 0, 0.2), glove, "Hand.R")
    # Knuckle guard on the back of the hand.
    b.segment(G(44, 24, 41), G(44, -3, 41), 66, 6, 70, 6, (1, 0, 0), knuckle, "Hand.R")

    # Thumb: wraps behind the grip under the beavertail and lies along the left side on the safety.
    thumb = [G(10, 58, 14), Vector((-12, -70, -22)), Vector((-20, -46, -16)), Vector((-20, -24, -14))]
    b.finger("R", "Thumb", thumb, [26, 22, 20, 18], lambda mid: Vector((-0.6, 0, 0.8)), glove, "Hand.R")

    # Index finger: along the right side of the frame, into the guard, pad on the trigger face.
    index = [G(5, -4, 22), Vector((15, 3, -36)), Vector((-1, 8, -39)), Vector((-8, 0, -40))]
    b.finger("R", "Index", index, [19, 18, 16, 15], lambda mid: Vector((0.3, 0.2, 1)).normalized(), glove, "Hand.R")

    # Middle, ring, pinky wrap around the front strap below the trigger guard.
    for name, t, w in (("Middle", 31, 20), ("Ring", 51, 19), ("Pinky", 70, 16)):
        pts = [G(t, -2, 24), G(t, -14, -12), G(t + 1, 6, -24), G(t + 1, 22, -21)]
        b.finger("R", name, pts, [w, w * 0.95, w * 0.88, w * 0.8], outward(t), glove, "Hand.R")

    # ================= LEFT HAND (support hand) =================
    # Palm on the left grip panel over the right fingertips; fingers wrap the front over the right hand.
    l_wrist = G(78, 82, -34)
    l_elbow = Vector((-190, -350, -230))
    l_knuckles = G(54, -6, -40)
    b.bone("Forearm.L", l_elbow, l_wrist)
    b.bone("Hand.L", l_wrist, l_knuckles, "Forearm.L")
    b.segment(l_elbow, l_wrist + (l_elbow - l_wrist).normalized() * 45, 80, 70, 70, 62, (-0.3, 0, 1), sleeve, "Forearm.L")
    b.segment(l_wrist + (l_elbow - l_wrist).normalized() * 55, l_wrist, 62, 52, 56, 46, (-0.3, 0, 1), glove, "Forearm.L")
    b.segment(G(58, 56, -38), G(58, -8, -38), 70, 24, 72, 22, (-1, 0, 0), glove, "Hand.L")
    b.segment(G(62, 48, -36), l_wrist, 64, 28, 56, 46, (-1, 0, 0.2), glove, "Hand.L")
    b.segment(G(58, 20, -51), G(58, -5, -51), 56, 6, 58, 6, (-1, 0, 0), knuckle, "Hand.L")

    # Support thumb points forward along the left side of the frame, under the right thumb.
    thumb_l = [G(30, 50, -28), Vector((-26, -54, -30)), Vector((-23, -30, -27)), Vector((-21, -7, -26))]
    b.finger("L", "Thumb", thumb_l, [26, 22, 20, 18], lambda mid: Vector((-0.8, 0, 0.6)), glove, "Hand.L")

    # Fingers wrap around the front, outside the right hand's fingers.
    for name, t, w in (("Index", 27, 18), ("Middle", 45, 19), ("Ring", 62, 18), ("Pinky", 78, 15)):
        pts = [G(t, -4, -32), G(t, -30, -6), G(t, -22, 22), G(t, -2, 31)]
        b.finger("L", name, pts, [w, w * 0.95, w * 0.88, w * 0.8], outward(t), glove, "Hand.L")

    return b.build("Arms")


if __name__ == "__main__":
    reset()
    make_textures()
    rig, arms = build_arms()
    tris = sum(len(p.vertices) - 2 for p in arms.data.polygons)
    print(f"Arms: {tris} tris, {len(rig.data.bones)} bones")
    blend = os.path.join(ASSET_DIR, "arms.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile()
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(ASSET_DIR, "arms.glb"),
        export_format="GLB",
        export_yup=True,
        export_skins=True,
        export_animations=False,
    )
    print("wrote", blend, "and arms.glb")
