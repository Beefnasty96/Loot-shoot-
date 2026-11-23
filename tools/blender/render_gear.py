"""Renders gear on the base body in rest pose (fit check).

Usage: python3 render_gear.py <body.blend> <gear_dir> <out.png> item1,item2,...
"""
import math
import os
import sys

import bpy
from mathutils import Vector

body, gear_dir, out, items = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(",")
bpy.ops.wm.open_mainfile(filepath=os.path.abspath(body))
sc = bpy.context.scene
COLORS = {"tshirt": (0.55, 0.55, 0.5), "jacket": (0.3, 0.33, 0.22), "pants": (0.25, 0.3, 0.42), "boots": (0.25, 0.18, 0.12),
          "gloves": (0.1, 0.1, 0.1), "beanie": (0.15, 0.18, 0.12), "vest": (0.35, 0.33, 0.25), "cap": (0.2, 0.25, 0.35), "backpack": (0.35, 0.3, 0.2)}
skin = bpy.data.materials["BodySkin"]
next(n for n in skin.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.75, 0.55, 0.42, 1)
for it in items:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(os.path.abspath(gear_dir), it, it + ".glb"))
    tex = bpy.data.images.load(os.path.join(os.path.abspath(gear_dir), it, it + "_detail.png"))
    tex.colorspace_settings.name = "Non-Color"
    for ob in set(bpy.data.objects) - before:
        if ob.type == "MESH":
            m = bpy.data.materials.new(it)
            m.use_nodes = True
            nt = m.node_tree
            bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            ti = nt.nodes.new("ShaderNodeTexImage"); ti.image = tex
            sep = nt.nodes.new("ShaderNodeSeparateColor"); nt.links.new(ti.outputs["Color"], sep.inputs[0])
            mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"; mul.inputs["Factor"].default_value = 1
            mul.inputs[6].default_value = (*COLORS.get(it, (0.5, 0.5, 0.5)), 1); nt.links.new(sep.outputs[0], mul.inputs[7])
            dark = nt.nodes.new("ShaderNodeMix"); dark.data_type = "RGBA"
            nt.links.new(sep.outputs[1], dark.inputs["Factor"]); nt.links.new(mul.outputs[2], dark.inputs[6]); dark.inputs[7].default_value = (0.06, 0.06, 0.06, 1)
            nt.links.new(dark.outputs[2], bsdf.inputs["Base Color"])
            ob.data.materials.clear(); ob.data.materials.append(m)
# Hide body regions the outfit covers.
HIDES = {"tshirt": ["torso", "upper_arms"], "jacket": ["torso", "upper_arms", "forearms"], "pants": ["hips", "thighs", "shins"],
         "boots": ["feet"], "gloves": ["hands"]}
for it in items:
    for r in HIDES.get(it, []):
        o = bpy.data.objects.get("Body_" + r)
        if o: o.hide_render = True
sc.render.engine = "CYCLES"; sc.cycles.samples = 16; sc.cycles.device = "CPU"
sc.render.resolution_x = 700; sc.render.resolution_y = 800
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.52, 0.55, 1)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3
sun.rotation_euler = (math.radians(50), 0, math.radians(30)); sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 2.0
cam.location = Vector((2.4, -3.8, 1.2)); cam.rotation_euler = (Vector((0, 0, 0.92)) - cam.location).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = os.path.abspath(out)
bpy.ops.render.render(write_still=True)
cam.location = Vector((-2.4, 3.8, 1.2)); cam.rotation_euler = (Vector((0, 0, 0.92)) - cam.location).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = os.path.abspath(out).replace(".png", "_back.png")
bpy.ops.render.render(write_still=True)
print("rendered")
