"""Renders preview images of a weapon .blend (right, left, 3/4 and top views).

Usage: python3 render_preview.py <file.blend> <out_dir> [samples]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

blend, out_dir = sys.argv[1], sys.argv[2]
samples = int(sys.argv[3]) if len(sys.argv) > 3 else 32
os.makedirs(out_dir, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.abspath(blend))
scene = bpy.context.scene

# Bounds of all meshes -> framing.
lo = Vector((1e9, 1e9, 1e9))
hi = -lo
for ob in scene.objects:
    if ob.type == "MESH":
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
center = (lo + hi) / 2
size = max(hi - lo)

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = samples
try:
    scene.cycles.use_denoising = True
except AttributeError:
    pass
scene.render.resolution_x = 1280
scene.render.resolution_y = 860
scene.render.film_transparent = False
scene.view_settings.view_transform = "Standard"

world = bpy.data.worlds.new("PreviewWorld")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs["Color"].default_value = (0.32, 0.33, 0.35, 1)
bg.inputs["Strength"].default_value = 0.6


def light(name, kind, loc, energy, size_=0.3):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    if kind == "AREA":
        ld.size = size_
    ob = bpy.data.objects.new(name, ld)
    scene.collection.objects.link(ob)
    ob.location = center + Vector(loc)
    direction = center - ob.location
    ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return ob


light("Key", "AREA", (0.35, 0.25, 0.45), 9)
light("KeyL", "AREA", (-0.35, 0.1, 0.4), 5)
light("Rim", "AREA", (0.0, -0.45, 0.25), 4)

cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

views = {
    "right": ((1, 0, 0), True),
    "left": ((-1, 0, 0), True),
    "three_quarter": ((0.75, 0.55, 0.38), False),
    "rear_quarter": ((-0.55, -0.75, 0.35), False),
}
for name, (direction, ortho) in views.items():
    d = Vector(direction).normalized()
    cam.location = center + d * size * 3.0
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = size * 1.25
    else:
        cam_data.type = "PERSP"
        cam_data.lens = 70
    scene.render.filepath = os.path.join(out_dir, f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)
