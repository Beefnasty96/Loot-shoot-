"""Builds a low-poly M1911 (.45 ACP) with Blender's Python module (bpy).

Finish (after a reference photo of a modern stainless Government Model):
brushed stainless flats with the brushing running lengthwise, a bead-blasted
top rib and small parts, rosewood double-diamond grips with slotted screws,
and roll-marked lettering on the slide and frame (generic markings, no maker
names). Textures come from m1911_textures.py.

Usage:  python3 m1911_build.py <asset_dir>
Writes <asset_dir>/m1911.blend and <asset_dir>/m1911.glb (textures read from <asset_dir>/textures).

Conventions
- Modelled in millimetres from real dimensions, stored in metres (S = 0.001).
- Blender axes: +Y = muzzle direction, +Z = up, +X = the pistol's right side.
  glTF export turns this into Godot's -Z forward, +Y up.
- Bore axis runs along Y at x = 0, z = 0. Origin (0,0,0) is on the bore axis
  roughly above the trigger.
- Moving parts are separate nodes so they can be animated in Godot:
  Slide, Barrel, Hammer, Trigger, Magazine. Marker nodes: Muzzle, SightRear,
  SightFront, EjectionPort.
"""
import math
import os
import sys

import bpy  # must come first: it provides bmesh and mathutils
import bmesh
from mathutils import Matrix, Vector

ASSET_DIR = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
TEX_DIR = os.path.join(ASSET_DIR, "textures")
S = 0.001  # mm -> m

GRIP_ANGLE = math.radians(18.0)
D = Vector((-math.sin(GRIP_ANGLE), -math.cos(GRIP_ANGLE)))  # down the grip (y, z)
N = Vector((-math.cos(GRIP_ANGLE), math.sin(GRIP_ANGLE)))   # across the grip, toward the back
F0 = Vector((-22.0, -28.0))                                  # top of the front strap
GRIP_DEPTH = 44.0
GRIP_LEN = 88.0


def gp(t, s=0.0):
    """Point on the grip: t mm down the front strap, s mm back across the grip."""
    p = F0 + D * t + N * s
    return (p.x, p.y)


def front(t):
    return gp(t, 0.0)


def rear(t):
    return gp(t, GRIP_DEPTH)


def t_at_z(z, s=0.0):
    """Grip distance t where a line at offset s reaches height z."""
    start = F0 + N * s
    return (z - start.y) / D.y


# --------------------------------------------------------------------- scene helpers

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, tex=None, rough=0.55, metal=0.25, alpha=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if tex:
        img = bpy.data.images.load(os.path.join(TEX_DIR, tex))
        node = nodes.new("ShaderNodeTexImage")
        node.image = img
        node.interpolation = "Linear"  # bilinear, like early-2000s PC games
        m.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha:
            m.node_tree.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
            if hasattr(m, "surface_render_method"):
                m.surface_render_method = "BLENDED"
            if hasattr(m, "blend_method"):
                m.blend_method = "BLEND"
    return m


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def from_data(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) * S for v in verts], [], faces)
    me.update()
    ob = link(bpy.data.objects.new(name, me))
    me.materials.append(mat)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return ob


def prism_yz(name, pts, x0, x1, mat):
    """Side-profile polygon (y, z) extruded across X from x0 to x1."""
    n = len(pts)
    verts = [(x0, y, z) for y, z in pts] + [(x1, y, z) for y, z in pts]
    faces = [list(range(n)), list(range(n, 2 * n))]
    faces += [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
    return from_data(name, verts, faces, mat)


def prism_xz(name, pts, y0, y1, mat):
    """Cross-section polygon (x, z) extruded along Y from y0 to y1."""
    n = len(pts)
    verts = [(x, y0, z) for x, z in pts] + [(x, y1, z) for x, z in pts]
    faces = [list(range(n)), list(range(n, 2 * n))]
    faces += [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
    return from_data(name, verts, faces, mat)


def box(name, x0, x1, y0, y1, z0, z1, mat):
    return prism_xz(name, [(x0, z0), (x1, z0), (x1, z1), (x0, z1)], y0, y1, mat)


def cyl_y(name, r, y0, y1, cx, cz, mat, seg=12):
    pts = [(cx + r * math.cos(2 * math.pi * i / seg), cz + r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
    return prism_xz(name, pts, y0, y1, mat)


def cyl_x(name, r, x0, x1, cy, cz, mat, seg=10):
    pts = [(cy + r * math.cos(2 * math.pi * i / seg), cz + r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
    return prism_yz(name, pts, x0, x1, mat)


def grip_box(name, t0, t1, s0, s1, x0, x1, mat):
    """Box aligned with the grip angle."""
    corners = [gp(t0, s0), gp(t0, s1), gp(t1, s1), gp(t1, s0)]
    return prism_yz(name, corners, x0, x1, mat)


def activate(ob):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def cut(ob, cutter):
    """Boolean difference; the cut faces take the cutter's material."""
    mod = ob.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    try:
        mod.solver = "EXACT"
    except TypeError:
        pass
    try:
        mod.material_mode = "TRANSFER"
    except (AttributeError, TypeError):
        pass
    cutter.hide_set(True)
    activate(ob)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return ob


def join(objs, name):
    activate(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def smart_uv(ob):
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def uv_box(ob, scale_mm=70.0):
    """Planar UVs per face from its dominant axis, with u along the gun (Y) wherever possible, so the
    brushed-steel texture's streaks run lengthwise like real polished flats."""
    me = ob.data
    uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co / S
            if ax == 0:
                u, v = co.y, co.z
            elif ax == 2:
                u, v = co.y, co.x
            else:
                u, v = co.z, co.x
            uv.data[li].uv = (u / scale_mm, v / scale_mm)


def decal(name, x, y0, y1, z0, z1, mat, right=True):
    """A flat quad just off a side face carrying a transparent texture (roll marks).
    Text reads rear-to-front on the right side, front-to-rear on the left (as stamped)."""
    if right:
        verts = [(x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)]
        uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
    else:
        verts = [(x, y1, z0), (x, y0, z0), (x, y0, z1), (x, y1, z1)]
        uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
    ob = from_data(name, verts, [[0, 1, 2, 3]], mat)
    uv = ob.data.uv_layers.new(name="UVMap")
    for li, c in zip(ob.data.polygons[0].loop_indices, uvs):
        uv.data[li].uv = c
    return ob


def set_pivot(ob, pivot_mm):
    """Move the object's origin to a pivot point (for animation) without moving the mesh."""
    p = Vector(pivot_mm) * S
    ob.data.transform(Matrix.Translation(-p))
    ob.location = p


def empty(name, loc_mm, parent):
    e = link(bpy.data.objects.new(name, None))
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = 0.01
    e.location = Vector(loc_mm) * S
    e.parent = parent
    return e


# --------------------------------------------------------------------- the pistol

def build():
    reset()
    # Low metallic on purpose: the game has no reflection probes, and fully metallic surfaces go dark
    # without something to reflect. Bright albedo + low roughness reads as polished stainless.
    steel = material("Stainless", (0.7, 0.71, 0.73), "stainless_brushed.png", rough=0.32, metal=0.12)
    matte = material("StainlessMatte", (0.6, 0.61, 0.63), "stainless_matte.png", rough=0.6, metal=0.08)
    steel_mag = material("SteelMag", (0.23, 0.24, 0.26), "steel_mag.png", rough=0.45, metal=0.35)
    wood = material("Rosewood", (0.44, 0.17, 0.1), "grip_rosewood.png", rough=0.45, metal=0.0)
    marks_slide = material("RollMarkSlide", (0.15, 0.15, 0.16), "rollmark_slide.png", rough=0.7, metal=0.0, alpha=True)
    marks_frame = material("RollMarkFrame", (0.15, 0.15, 0.16), "rollmark_frame.png", rough=0.7, metal=0.0, alpha=True)
    black = material("Bore", (0.02, 0.02, 0.02), None, rough=0.9, metal=0.0)
    white = material("SightDot", (0.92, 0.92, 0.88), None, rough=0.6, metal=0.0)

    # ---------------- Frame (receiver, trigger guard, grip, mainspring housing)
    t_guard = t_at_z(-48.0)
    t_rear_top = t_at_z(-10.0, GRIP_DEPTH)
    frame_profile = [
        (103, -10), (103, -28),                      # dust cover front
        (20, -28), (19.5, -34), (17, -41), (12, -46), (6, -48),  # trigger guard front curve
        front(t_guard),                              # guard bottom meets the front strap
        front(GRIP_LEN), rear(GRIP_LEN),             # grip bottom
        rear(t_rear_top),                            # up the mainspring housing
    ]
    frame = prism_yz("Frame", frame_profile, -10.5, 10.5, steel)
    # Trigger guard opening (rear edge sits 1 mm inside the front strap line).
    t30, t44 = t_at_z(-30.0), t_at_z(-44.0)
    opening = [
        (14.5, -30), (14.5, -38), (10.5, -42.5), (6, -44),
        (front(t44)[0] - 1.0, -44), (front(t30)[0] - 1.0, -30),
    ]
    cut(frame, prism_yz("cut_guard", opening, -20, 20, steel))
    # Slight flat on the frame top so the slide rails read as a separate part.
    parts = [frame]

    # Grip safety with beavertail.
    gs = [
        (rear(t_rear_top)[0], -10.0),
        *[(-77.0 + 5.0 * math.cos(math.radians(a)), -14.5 + 5.0 * math.sin(math.radians(a))) for a in range(90, 271, 30)],
        gp(10, GRIP_DEPTH + 2.0), gp(34, GRIP_DEPTH + 2.0), gp(34, GRIP_DEPTH - 0.5), gp(-1, GRIP_DEPTH - 0.5),
    ]
    parts.append(prism_yz("GripSafety", gs, -9.5, 9.5, steel))

    # Thumb safety (left side), slide stop (left), slide stop pin (right), magazine release (left).
    parts.append(prism_yz("ThumbSafety", [(-62, -11), (-53, -11), (-47.5, -13), (-52, -15.5), (-60, -16), (-63.5, -14)], -13.8, -10.5, matte))
    parts.append(cyl_x("ThumbSafetyPivot", 3.2, -12.0, -10.5, -59, -13.5, matte))
    parts.append(prism_yz("SlideStop", [(-21, -11), (7, -11), (11, -13.5), (8, -16.5), (-18, -15.5), (-23, -13)], -13.2, -10.5, matte))
    parts.append(cyl_x("SlideStopPin", 2.6, 10.5, 11.6, 8, -16, matte))
    tb = t_at_z(-35.0)
    parts.append(cyl_x("MagRelease", 4.0, -15.8, -10.0, front(tb)[0] - 5.0, -33.0, matte, seg=10))
    # Plunger tube (left, between the thumb safety and slide stop) and the pins that show on the right.
    parts.append(cyl_y("PlungerTube", 2.6, -46.0, -24.0, -11.6, -12.6, matte, seg=8))
    parts.append(cyl_x("SafetyPin", 2.0, 10.5, 11.3, -59, -13.5, matte, seg=8))
    parts.append(cyl_x("HammerPin", 2.0, 10.5, 11.3, -63, -7.0, matte, seg=8))
    parts.append(cyl_x("SearPin", 1.8, 10.5, 11.3, -51, -9.5, matte, seg=8))
    parts.append(cyl_x("MSHPin", 1.6, 10.5, 11.2, *rear(GRIP_LEN - 8.0), matte, seg=8))
    # Roll marks on the right of the frame.
    parts.append(decal("FrameMarks", 10.56, -40.0, 0.0, -21.5, -15.9, marks_frame))

    # Grip panels: thick slabs with a chamfered outer face and a UV map made
    # for the double-diamond texture (u across the grip, v down the grip).
    t_top, t_bot = t_at_z(-37.0), GRIP_LEN - 6.0
    for side, sx in (("R", 1.0), ("L", -1.0)):
        inner = [gp(t_top, 3.5), gp(t_top, GRIP_DEPTH - 3.5), gp(t_bot, GRIP_DEPTH - 3.5), gp(t_bot, 3.5)]
        outer = [gp(t_top + 1.5, 5.0), gp(t_top + 1.5, GRIP_DEPTH - 5.0), gp(t_bot - 1.5, GRIP_DEPTH - 5.0), gp(t_bot - 1.5, 5.0)]
        verts = [(10.0 * sx, y, z) for y, z in inner] + [(14.5 * sx, y, z) for y, z in outer]
        faces = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
        panel = from_data("Grip" + side, verts, faces, wood)
        me = panel.data
        uv = me.uv_layers.new(name="UVMap")
        span_t = (t_bot - 1.5) - (t_top + 1.5)
        span_s = (GRIP_DEPTH - 5.0) - 5.0
        for poly in me.polygons:
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co / S
                rel = Vector((co.y, co.z)) - F0
                t = rel.dot(D)
                s = rel.dot(N)
                u = (s - 5.0) / span_s
                if sx < 0:  # mirror on the left so the texture reads front-to-back on both sides
                    u = 1.0 - u
                v = 1.0 - (t - (t_top + 1.5)) / span_t
                uv.data[li].uv = (u, v)
        parts.append(panel)

    for p in parts:
        if p.data.uv_layers.get("UVMap") is None:
            uv_box(p)
    frame = join(parts, "Frame")

    # ---------------- Slide
    slide_xs = [(-11.5, -10), (11.5, -10), (11.5, 9), (10.2, 13), (6.5, 15.4), (-6.5, 15.4), (-10.2, 13), (-11.5, 9)]
    slide = prism_xz("Slide", slide_xs, -66, 128, steel)
    nose = box("SlideNose", -11.5, 11.5, 104, 128, -28, -10.2, steel)
    # Ejection port (right side) and rear cocking serrations (both sides).
    cut(slide, box("cut_port", 6.0, 20.0, 4.0, 36.0, -1.5, 11.0, steel))
    grooves = []
    for i in range(10):
        y0 = -62.0 + i * 2.6
        grooves.append(box(f"g_r{i}", 10.6, 14.0, y0, y0 + 1.2, -8.5, 9.5, steel))
        grooves.append(box(f"g_l{i}", -14.0, -10.6, y0, y0 + 1.2, -8.5, 9.5, steel))
    cut(slide, join(grooves, "cut_serrations"))
    # Sights: a ramped front blade, a dovetailed rear with a square notch.
    front_sight = prism_yz("FrontSight", [(114.5, 14.5), (123.5, 14.5), (121.0, 17.0), (117.5, 20.5), (115.0, 20.5)], -1.5, 1.5, matte)
    rear_sight = box("RearSight", -7.0, 7.0, -62, -54, 14.0, 19.5, matte)
    cut(rear_sight, box("cut_notch", -1.6, 1.6, -63, -53, 16.5, 21.0, steel))
    dot = box("FrontDot", -0.8, 0.8, 114.6, 115.2, 18.0, 19.6, white)
    # Barrel bushing and recoil spring plug on the nose.
    bushing = cyl_y("Bushing", 9.6, 126, 129.5, 0, 0, steel, seg=16)
    cut(bushing, cyl_y("cut_bushing", 7.6, 120, 135, 0, 0, steel, seg=16))
    plug = cyl_y("RecoilPlug", 6.4, 126, 130.5, 0, -19, steel, seg=12)
    slide_parts = [slide, nose, front_sight, rear_sight, bushing, plug]
    for p in slide_parts:
        uv_box(p)
    marks_s = decal("SlideMarks", 11.56, 42.0, 100.0, -1.0, 3.6, marks_slide)
    slide = join(slide_parts + [dot, marks_s], "Slide")
    # The top rib is bead-blasted (no glare down the sights); the brushed flats are the sides.
    mi = list(slide.data.materials).index(bpy.data.materials["StainlessMatte"]) if "StainlessMatte" in [m.name for m in slide.data.materials] else None
    if mi is None:
        slide.data.materials.append(matte)
        mi = len(slide.data.materials) - 1
    st = slide.data.materials.find("Stainless")
    for poly in slide.data.polygons:
        if poly.material_index == st and poly.normal.z > 0.55:
            poly.material_index = mi

    # ---------------- Barrel (visible at the muzzle and through the ejection port)
    barrel = cyl_y("Barrel", 7.4, -20, 131, 0, 0, steel, seg=16)
    cut(barrel, cyl_y("cut_bore", 5.7, 95, 140, 0, 0, black, seg=16))
    hood = box("BarrelHood", -7.4, 7.4, -20, 22, 0, 9.0, steel)
    uv_box(barrel)
    uv_box(hood)
    barrel = join([barrel, hood], "Barrel")

    # ---------------- Hammer (cocked), pivot on the hammer pin
    hammer = prism_yz("Hammer", [(-62.5, -12.5), (-60, -6), (-62, 3), (-66.5, 8.5), (-73, 10), (-74.5, 7.5), (-69, 4.5), (-67, -8)], -3.2, 3.2, matte)
    uv_box(hammer)
    set_pivot(hammer, (0, -63.0, -7.0))

    # ---------------- Trigger (long trigger shoe), slides straight back
    trigger = prism_yz("Trigger", [(-7, -29), (-2, -29), (-1.2, -36), (-2.2, -43.2), (-6, -43.6), (-6.8, -36)], -4.0, 4.0, matte)
    uv_box(trigger)

    # ---------------- Magazine (single stack, 7 rounds) inside the grip
    mag_body = grip_box("MagBody", 2.0, 86.0, 7.0, 37.0, -7.0, 7.0, steel_mag)
    mag_base = grip_box("MagBase", 86.0, 90.0, 5.0, 41.0, -8.5, 8.5, steel_mag)
    round_top = cyl_y("TopRound", 5.6, -58, -29, 0, -24.0, material("Brass", (0.75, 0.55, 0.22), None, 0.4, 0.6), seg=10)
    for p in (mag_body, mag_base, round_top):
        uv_box(p)
    magazine = join([mag_body, mag_base, round_top], "Magazine")

    # ---------------- Hierarchy + markers
    root = link(bpy.data.objects.new("M1911", None))
    for ob in (frame, slide, barrel, hammer, trigger, magazine):
        ob.parent = root
    empty("Muzzle", (0, 131.5, 0), root)
    empty("SightRear", (0, -58, 19.5), root)
    empty("SightFront", (0, 119, 20.5), root)
    empty("EjectionPort", (13, 20, 5), root)

    # Flat shading suits the early-2000s look and keeps hard edges crisp.
    for ob in (frame, slide, barrel, hammer, trigger, magazine):
        for poly in ob.data.polygons:
            poly.use_smooth = False
    return root


def report():
    total = 0
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            me = ob.data
            tris = sum(len(p.vertices) - 2 for p in me.polygons)
            total += tris
            print(f"  {ob.name:<10} {tris:>5} tris  mats={[m.name for m in me.materials]}")
    print(f"  TOTAL      {total:>5} tris")


if __name__ == "__main__":
    build()
    report()
    blend = os.path.join(ASSET_DIR, "m1911.blend")
    bpy.ops.file.make_paths_relative() if bpy.data.filepath else None
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile()
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(ASSET_DIR, "m1911.glb"),
        export_format="GLB",
        export_apply=True,
        export_yup=True,
    )
    print("wrote", blend, "and m1911.glb")
