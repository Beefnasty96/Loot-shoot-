"""Preview renders of the base body: appearance masks (front/side/face) and a bent pose to check skinning.

Usage: python3 render_body.py <body.blend> <out_dir>
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

blend, out = os.path.abspath(sys.argv[1]), sys.argv[2]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=blend)
sc = bpy.context.scene
tex_dir = os.path.join(os.path.dirname(blend), "textures")

# Preview shader approximating the in-game one: skin tone x shade, brown hair, blue eyes, grey underwear.
mat = bpy.data.materials["BodySkin"]
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
ia = nt.nodes.new("ShaderNodeTexImage"); ia.image = bpy.data.images.load(os.path.join(tex_dir, "body_masks_a.png")); ia.image.colorspace_settings.name = "Non-Color"
ib = nt.nodes.new("ShaderNodeTexImage"); ib.image = bpy.data.images.load(os.path.join(tex_dir, "body_masks_b.png")); ib.image.colorspace_settings.name = "Non-Color"
sa = nt.nodes.new("ShaderNodeSeparateColor"); nt.links.new(ia.outputs["Color"], sa.inputs[0])
sb = nt.nodes.new("ShaderNodeSeparateColor"); nt.links.new(ib.outputs["Color"], sb.inputs[0])


def mix(col_in, col_b, fac_socket):
    m = nt.nodes.new("ShaderNodeMix"); m.data_type = "RGBA"
    nt.links.new(fac_socket, m.inputs["Factor"])
    if isinstance(col_in, tuple): m.inputs[6].default_value = col_in
    else: nt.links.new(col_in, m.inputs[6])
    m.inputs[7].default_value = col_b
    return m.outputs[2]


skin = nt.nodes.new("ShaderNodeMix"); skin.data_type = "RGBA"; skin.blend_type = "MULTIPLY"; skin.inputs["Factor"].default_value = 1.0
skin.inputs[6].default_value = (0.78, 0.55, 0.40, 1); nt.links.new(sa.outputs[0], skin.inputs[7])
c = skin.outputs[2]
c = mix(c, (0.25, 0.15, 0.08, 1), sa.outputs[1])   # brows
c = mix(c, (0.25, 0.15, 0.08, 1), sa.outputs[2])   # scalp
alpha_beard = nt.nodes.new("ShaderNodeMath"); alpha_beard.operation = "MULTIPLY"; alpha_beard.inputs[1].default_value = 0.6
nt.links.new(ia.outputs["Alpha"], alpha_beard.inputs[0])
c = mix(c, (0.25, 0.15, 0.08, 1), alpha_beard.outputs[0])
c = mix(c, (0.3, 0.32, 0.35, 1), sb.outputs[0])    # underwear
c = mix(c, (0.9, 0.9, 0.88, 1), sb.outputs[1])     # eye white
c = mix(c, (0.15, 0.3, 0.55, 1), sb.outputs[2])    # iris
c = mix(c, (0.6, 0.3, 0.3, 1), ib.outputs["Alpha"])  # lips
nt.links.new(c, bsdf.inputs["Base Color"])

sc.render.engine = "CYCLES"; sc.cycles.samples = 16; sc.cycles.device = "CPU"
sc.render.resolution_x = 800; sc.render.resolution_y = 800
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.52, 0.55, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3
sun.rotation_euler = (math.radians(50), 0, math.radians(30)); sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"


def shot(name, loc, target, scale):
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = scale
    sc.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


shot("front", (0, -5, 0.92), (0, 0, 0.92), 2.0)
shot("back", (0, 5, 0.92), (0, 0, 0.92), 2.0)
shot("face", (0.25, -2, 1.68), (0, 0, 1.68), 0.38)
shot("hand", (0.74, -0.3, 1.9), (0.74, -0.02, 1.4), 0.28)

# Pose test: arms down and forward, one knee bent, fingers curled.
rig = bpy.data.objects["HumanRig"]
pb = rig.pose.bones
for side, s in (("Left", 1), ("Right", -1)):
    pb[f"{side}UpperArm"].rotation_mode = "XYZ"
    pb[f"{side}UpperArm"].rotation_euler = Euler((0, 0, 0))
for b in pb:
    b.rotation_mode = "QUATERNION"
import mathutils
def rot_world(bone, axis, deg):
    # rotate a pose bone around a world axis through its head
    m = rig.matrix_world @ bone.matrix
    R = mathutils.Matrix.Rotation(math.radians(deg), 4, axis)
    t = m.to_translation()
    new = mathutils.Matrix.Translation(t) @ R @ mathutils.Matrix.Translation(-t) @ m
    bone.matrix = rig.matrix_world.inverted() @ new
    bpy.context.view_layer.update()
rot_world(pb["LeftUpperArm"], "Y", 70)
rot_world(pb["RightUpperArm"], "Y", -70)
rot_world(pb["LeftLowerArm"], "Z", 50)
rot_world(pb["RightLowerArm"], "Z", -50)
rot_world(pb["LeftUpperLeg"], "X", 40)
rot_world(pb["LeftLowerLeg"], "X", -70)
for side in ("Left", "Right"):
    for f in ("Index", "Middle", "Ring", "Little"):
        for ph in ("Proximal", "Intermediate", "Distal"):
            b = pb[f"{side}{f}{ph}"]
            ax = b.matrix.to_3x3() @ Vector((1, 0, 0))
            rot_world(b, (rig.matrix_world.to_3x3() @ ax).normalized(), 55)
shot("posed", (2.2, -3.6, 1.0), (0, 0, 0.95), 2.1)
