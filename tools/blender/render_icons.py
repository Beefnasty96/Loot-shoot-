"""Renders inventory icons (transparent PNG, 64 px per grid square) for gear, the magazine and weapons.

Usage: python3 render_icons.py <repo_root>
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(sys.argv[1])
OUT = os.path.join(ROOT, "assets", "icons")
CELL = 64

# id: (footprint w,h, view direction (from), tint, keep only +X half)
GEAR = {
    "tshirt": ((2, 2), (0.0, -1, 0.15), (0.5, 0.52, 0.45), False),
    "jacket": ((3, 3), (0.25, -1, 0.15), (0.33, 0.36, 0.22), False),
    "pants": ((2, 3), (0.2, -1, 0.1), (0.55, 0.5, 0.36), False),
    "boots": ((2, 2), (1, -0.6, 0.35), (0.36, 0.24, 0.15), True),
    "gloves": ((1, 1), (0.2, -0.3, 1), (0.15, 0.15, 0.15), True),
    "beanie": ((1, 1), (0.3, -1, 0.4), (0.33, 0.36, 0.22), False),
    "vest": ((3, 3), (0.2, -1, 0.15), (0.5, 0.4, 0.27), False),
    "cap": ((2, 1), (0.6, -1, 0.4), (0.16, 0.2, 0.33), False),
    "backpack": ((4, 4), (-0.4, 1, 0.25), (0.62, 0.53, 0.38), False),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 12
    sc.cycles.device = "CPU"
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(40), math.radians(-20), math.radians(30))
    sc.collection.objects.link(sun)
    return sc


def tint(ob, color, tex_path):
    m = bpy.data.materials.new("icon")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.8
    if tex_path and os.path.exists(tex_path):
        ti = nt.nodes.new("ShaderNodeTexImage")
        ti.image = bpy.data.images.load(tex_path)
        ti.image.colorspace_settings.name = "Non-Color"
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(ti.outputs["Color"], sep.inputs[0])
        mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        mul.inputs[6].default_value = (*color, 1)
        nt.links.new(sep.outputs[0], mul.inputs[7])
        acc = nt.nodes.new("ShaderNodeMix"); acc.data_type = "RGBA"
        nt.links.new(sep.outputs[1], acc.inputs["Factor"])
        nt.links.new(mul.outputs[2], acc.inputs[6])
        acc.inputs[7].default_value = (0.07, 0.07, 0.07, 1)
        nt.links.new(acc.outputs[2], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*color, 1)
    ob.data.materials.clear()
    ob.data.materials.append(m)


def frame_and_render(sc, objs, view, footprint, path):
    for o in objs:
        o.data.update()
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre = (lo + hi) / 2
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    d = Vector(view).normalized()
    cam.location = centre + d * 5.0
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    # Fit: project the box corners onto the camera plane.
    inv = cam.matrix_world.inverted()
    bpy.context.view_layer.update()
    inv = cam.matrix_world.inverted()
    local = [inv @ p for p in pts]
    wx = max(p.x for p in local) - min(p.x for p in local)
    wy = max(p.y for p in local) - min(p.y for p in local)
    aspect = footprint[0] / footprint[1]
    sc.render.resolution_x = footprint[0] * CELL
    sc.render.resolution_y = footprint[1] * CELL
    cam.data.sensor_fit = "AUTO"
    cam.data.ortho_scale = max(wx, wy * aspect) * 1.12 if aspect >= 1 else max(wy, wx / aspect) * 1.12
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("icon", os.path.basename(path))


def main():
    os.makedirs(OUT, exist_ok=True)
    for gid, (fp, view, color, half) in GEAR.items():
        sc = reset()
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets", "gear", gid, gid + ".glb"))
        for o in [o for o in sc.objects if o.type == "MESH" and o.name.startswith("Icosphere")]:
            bpy.data.objects.remove(o)  # the importer's bone-display shape
        meshes = [o for o in sc.objects if o.type == "MESH"]
        for o in meshes:
            o.modifiers.clear()
            o.parent = None
            if half:
                bm = bmesh.new()
                bm.from_mesh(o.data)
                bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.x < 0], context="VERTS")
                bm.to_mesh(o.data)
                bm.free()
            tint(o, color, os.path.join(ROOT, "assets", "gear", gid, gid + "_detail.png"))
        for o in [o for o in sc.objects if o.type == "ARMATURE"]:
            bpy.data.objects.remove(o)
        frame_and_render(sc, meshes, view, fp, os.path.join(OUT, gid + ".png"))

    # Magazine: the Magazine part of the 1911.
    sc = reset()
    with bpy.data.libraries.load(os.path.join(ROOT, "assets", "weapons", "m1911", "m1911.blend")) as (src, dst):
        dst.objects = ["Magazine"]
    mag = dst.objects[0]
    sc.collection.objects.link(mag)
    mag.parent = None
    frame_and_render(sc, [mag], (1, 0.15, 0.1), (1, 1), os.path.join(OUT, "mag_1911.png"))


def weapons():
    """The whole 1911 from the right side (2x1) and the Ka-Bar laid flat (3x1)."""
    for wid, blend, fp, rot_x in [("m1911", "m1911/m1911.blend", (2, 1), 0.0), ("kabar", "kabar/kabar.blend", (3, 1), -72.0)]:
        sc = reset()
        with bpy.data.libraries.load(os.path.join(ROOT, "assets", "weapons", blend)) as (src, dst):
            dst.objects = list(src.objects)
        meshes = []
        for o in dst.objects:
            if o is None:
                continue
            sc.collection.objects.link(o)
            if o.type == "MESH":
                meshes.append(o)
        bpy.context.view_layer.update()
        for o in meshes:
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
        if rot_x != 0.0:
            from mathutils import Matrix
            r = Matrix.Rotation(math.radians(rot_x), 4, "X")
            for o in meshes:
                o.matrix_world = r @ o.matrix_world
        frame_and_render(sc, meshes, (1, 0.0, 0.08), fp, os.path.join(OUT, wid + ".png"))


PARTS = {  # id: footprint, view direction
    "barrel_1911_threaded": ((2, 1), (1, 0.0, 0.15)),
    "supp_45": ((2, 1), (1, 0.0, 0.15)),
    "grips_1911_rubber": ((1, 1), (1, 0.0, 0.1)),
    "sights_1911_night": ((1, 1), (0.6, -1.0, 0.5)),
    "rail_1911": ((1, 1), (1, 0.3, -0.4)),
    "light_m3": ((1, 1), (1, 0.4, 0.2)),
}


def parts():
    for pid, (fp, view) in PARTS.items():
        sc = reset()
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets", "weapons", "parts", pid + ".glb"))
        meshes = [o for o in sc.objects if o.type == "MESH"]
        bpy.context.view_layer.update()
        for o in meshes:
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
        if pid == "grips_1911_rubber":   # one panel is enough for the icon
            for o in [o for o in meshes if o.name.endswith("L") or "RidgeL" in o.name]:
                bpy.data.objects.remove(o)
            meshes = [o for o in sc.objects if o.type == "MESH"]
        frame_and_render(sc, meshes, view, fp, os.path.join(OUT, pid + ".png"))
    # Stock parts use the whole-gun picture's look: simple stand-ins.
    import shutil
    shutil.copy(os.path.join(OUT, "barrel_1911_threaded.png"), os.path.join(OUT, "barrel_1911_gi.png"))


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[2] == "weapons":
        weapons()
        parts()
    else:
        main()
        weapons()
        parts()
