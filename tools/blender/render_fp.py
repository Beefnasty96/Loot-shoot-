"""First-person preview: arms + weapon seen from the player's eye.

Usage: python3 render_fp.py <arms.blend> <weapon.blend> <out_dir> [samples] [rifle]
Renders hip.png (hip-fire view), aim.png (looking down the sights) and side.png.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

arms_blend, weapon_blend, out_dir = sys.argv[1:4]
samples = int(sys.argv[4]) if len(sys.argv) > 4 else 24
os.makedirs(out_dir, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.abspath(arms_blend))
scene = bpy.context.scene
with bpy.data.libraries.load(os.path.abspath(weapon_blend)) as (src, dst):
    dst.objects = list(src.objects)
for ob in dst.objects:
    if ob is not None:
        scene.collection.objects.link(ob)

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = samples
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.45, 0.5, 0.56, 1)
bg.inputs["Strength"].default_value = 0.7

sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 2.5
sun.rotation_euler = (math.radians(50), math.radians(-25), math.radians(20))
scene.collection.objects.link(sun)

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.lens_unit = "FOV"
cam.data.sensor_fit = "VERTICAL"  # Godot fov is vertical
cam.data.clip_start = 0.01


def shot(name, eye_mm, look_mm, fov_deg):
    eye, look = Vector(eye_mm) * 0.001, Vector(look_mm) * 0.001
    cam.location = eye
    cam.rotation_euler = (look - eye).to_track_quat("-Z", "Y").to_euler()
    cam.data.angle = math.radians(fov_deg)
    scene.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


# Eye positions relative to the gun (mm, gun space). Godot fov 75 is vertical.
# Hip: gun sits low-right of the eye. Aim: eye on the sight line.
if len(sys.argv) > 5 and sys.argv[5] == "rifle":
    # M4A1 (m4_build.py): rear aperture at y -119, z 64.
    shot("hip", (-118, -215, 130), (-118, 2000, 130), 75)
    shot("aim", (0, -209, 64), (0, 2000, 64), 55)
    shot("side", (-900, 40, 0), (0, 40, -40), 45)
    shot("right", (900, 40, 0), (0, 40, -40), 45)
    shot("below", (300, 40, -500), (0, 40, -40), 55)
else:
    shot("hip", (-80, -235, 88), (-80, 2000, 88), 75)
    shot("aim", (0, -300, 20.2), (0, 2000, 20.2), 50)
    shot("side", (-700, -90, 0), (0, -90, -40), 38)
    shot("below", (250, -60, -380), (0, -60, -40), 45)
