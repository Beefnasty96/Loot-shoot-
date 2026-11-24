"""Turns the source M4A1 model (assets/weapons/m4a1/source/M4A1_New.blend) into the game's M4A1.

Usage:  python3 m4_import.py <source.blend> <asset_dir>
Writes <asset_dir>/m4a1.blend, <asset_dir>/m4a1.glb and <asset_dir>/m4_dims.json
(grip and handguard geometry, read by arms_build.py rifle and used for WeaponDB's rig).

What it does to the source model:
- Real size. Scaled uniformly so the barrel is 14.5 in from the bolt face to the
  muzzle crown. Then the stock is slid out to its last notch, so the overall length
  is 33.0 in (838 mm). Fully collapsed it would be 29.75 in (756 mm), 3.25 in further in.
- Quad rail. The round handguards and heat shields are replaced with a four-rail
  (RIS-style) handguard between the delta ring and the front cap. Its top rail is
  level with the flat-top rail; side and bottom rails are the same distance out.
- Game nodes. Parts are joined and renamed for the game: Bolt (bolt + carrier),
  ChargingHandle, Selector, Trigger, Magazine (+ follower), RearSight (the detachable
  carry handle with its sight), Handguard. The magazine is replaced by our STANAG
  (stanag_build.py), seated in the well where the source's sat. Markers: Muzzle, SightRear, SightFront,
  EjectionPort. The loose display cartridge is removed. The dust cover keeps its
  open position (DustCoverOpen; not animated).

Conventions as in m1911_build.py: +Y muzzle, +Z up, +X right, bore on the Y axis.
glTF export turns this into Godot's -Z forward.
"""
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

SRC = os.path.abspath(sys.argv[1])
OUT = os.path.abspath(sys.argv[2])

IN = 0.0254
BARREL = 14.5 * IN          # bolt face to muzzle crown
OAL_EXTENDED = 33.0 * IN    # stock on its last notch
OAL_RETRACTED = 29.75 * IN

bpy.ops.wm.open_mainfile(filepath=SRC, load_ui=False, use_scripts=False)
scene = bpy.context.scene
O = bpy.data.objects


def world_verts(ob):
    return [ob.matrix_world @ v.co for v in ob.data.vertices]


def bounds(obs):
    vs = [v for ob in obs for v in world_verts(ob)]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def activate(obs):
    for o in scene.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


def join(names, new_name):
    obs = [O[n] for n in names if n in O]
    activate(obs)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = new_name
    ob.data.name = new_name
    return ob


def apply_modifiers(ob):
    activate([ob])
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


# ------------------------------------------------------------------ clean up
for n in ["M855 - light AP", "handguard_upper", "handguard_lower", "heeatshield"]:
    if n in O:
        bpy.data.objects.remove(O[n], do_unlink=True)
for ob in list(scene.objects):
    if ob.type == "MESH":
        apply_modifiers(ob)

# ------------------------------------------------------------------ real size
bolt_face = max(v.y for v in world_verts(O["bolt"]))
muzzle_crown = max(v.y for v in world_verts(O["barrel"]))
s = BARREL / (muzzle_crown - bolt_face)
for ob in scene.objects:
    if ob.parent is None:
        ob.location = ob.location * s
        ob.scale = ob.scale * s
activate([o for o in scene.objects if o.type == "MESH"])
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# Stock out to the last notch: overall length 33 in.
meshes = [o for o in scene.objects if o.type == "MESH"]
lo, hi = bounds(meshes)
muzzle_y = hi.y
butt_y = lo.y
extend = OAL_EXTENDED - (muzzle_y - butt_y)
O["buttstock"].location.y -= extend
lo, hi = bounds(meshes)

# ------------------------------------------------------------------ quad rail
fin = bpy.data.materials["finish"]
rail_top = max(v.z for v in world_verts(O["upper"]))          # flat-top rail height over the bore
y0 = max(v.y for v in world_verts(O["handguard_cap_rear"])) - 0.001
y1 = min(v.y for v in world_verts(O["handguard_cap_front"])) + 0.001
R = rail_top                                                   # all four rails the same distance out
AP = R - 0.0075                                                # octagon body apothem


def mesh_from(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    me.materials.append(fin)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return ob


def prism(name, pts_xz, a, b):
    n = len(pts_xz)
    verts = [(x, a, z) for x, z in pts_xz] + [(x, b, z) for x, z in pts_xz]
    faces = [list(range(n)), list(range(n, 2 * n))] + [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
    return mesh_from(name, verts, faces)


rv = AP / math.cos(math.radians(22.5))
pieces = [prism("HG_body", [(rv * math.cos(math.radians(22.5 + 45 * k)), rv * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)], y0, y1)]
for side in ("top", "bottom", "left", "right"):
    def xz(u, w, side=side):
        return {"top": (u, w), "bottom": (-u, -w), "right": (w, -u), "left": (-w, u)}[side]

    def block(nm, u0, u1, w0, w1, a, b):
        return prism(nm, [xz(u0, w0), xz(u1, w0), xz(u1, w1), xz(u0, w1)], a, b)

    pieces.append(block(f"HG_{side}_base", -0.0075, 0.0075, AP - 0.001, R - 0.005, y0 + 0.002, y1 - 0.002))
    pieces.append(block(f"HG_{side}_head", -0.0106, 0.0106, R - 0.005, R - 0.003, y0 + 0.002, y1 - 0.002))
    y = y0 + 0.004
    i = 0
    while y + 0.0052 <= y1 - 0.003:   # Picatinny: 5.23 mm ribs on 10 mm centres
        pieces.append(block(f"HG_{side}_rib{i}", -0.0106, 0.0106, R - 0.003, R, y, y + 0.0052))
        y += 0.010
        i += 1
handguard = pieces[0]
activate(pieces)
bpy.ops.object.join()
handguard = bpy.context.view_layer.objects.active
handguard.name = handguard.data.name = "Handguard"
activate([handguard])
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.cube_project(cube_size=0.05)
bpy.ops.object.mode_set(mode="OBJECT")

# ------------------------------------------------------------------ game nodes
rlo, rhi = bounds([O["rear_sight"]])
ap_y = (rlo.y + rhi.y) / 2.0          # the flip aperture, before it's joined to the carry handle
join(["bolt_carrier", "bolt"], "Bolt")
# Magazine: our STANAG model (stanag_build.py) in place of the source's, seated where it sat:
# feed lips at the same height, centred front-to-back on the same spot in the well.
src_mag = world_verts(O["magazine"])
mag_top = max(v.z for v in src_mag)
top_band = [v for v in src_mag if v.z > mag_top - 0.02]
mag_y = (min(v.y for v in top_band) + max(v.y for v in top_band)) / 2.0
for n in ("magazine", "follower"):
    bpy.data.objects.remove(O[n], do_unlink=True)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stanag_build  # noqa: E402
stanag = stanag_build.build_stanag(os.path.join(OUT, "textures"))
stanag.location = (0.0, mag_y, mag_top)
join(["carryhandle", "rear_sight_base", "rear_sight"], "RearSight")
O["charging_handle"].name = "ChargingHandle"
O["selector"].name = "Selector"
O["trigger"].name = "Trigger"
O["dustcover"].name = "DustCoverOpen"

# Sight line: rear aperture centre and the front post tip.
gb = [v for v in world_verts(O["gas_block"]) if abs(v.x) < 0.0016]
post = max(gb, key=lambda v: v.z)
sight_z = post.z
# The aperture: the hole in the rear sight leaf. Take the middle of the leaf's vertical extent
# and line it up with the post tip (the sight is zeroed: aperture centre, post tip, target).
rear_sight = Vector((0.0, ap_y, sight_z))
front_sight = Vector((0.0, post.y, sight_z))

root = bpy.data.objects.new("M4A1", None)
scene.collection.objects.link(root)
for ob in list(scene.objects):
    if ob.type == "MESH" and ob.parent is None:
        mw = ob.matrix_world.copy()
        ob.parent = root
        ob.matrix_world = mw
    if ob.type == "MESH":
        for p in ob.data.polygons:
            p.use_smooth = False


def empty(name, loc):
    e = bpy.data.objects.new(name, None)
    scene.collection.objects.link(e)
    e.location = loc
    e.parent = root
    return e


meshes = [o for o in scene.objects if o.type == "MESH"]
lo, hi = bounds(meshes)
empty("Muzzle", (0.0, hi.y + 0.001, 0.0))
empty("SightRear", rear_sight)
empty("SightFront", front_sight)
dc = world_verts(O["DustCoverOpen"])
empty("EjectionPort", (0.024, sum(v.y for v in dc) / len(dc), 0.004))


# ------------------------------------------------------------------ measurements
def ray(origin, direction):
    hit, loc, n, idx, ob, _ = scene.ray_cast(bpy.context.evaluated_depsgraph_get(), origin, direction)
    return loc if hit and ob.name == "grip" else None


def trigger_face():
    """(y, z) of the front of the trigger blade, where the finger pad goes."""
    tv = [v for v in world_verts(O["Trigger"]) if abs(v.z - (TRIG_Z)) < 0.003]
    return [max(v.y for v in tv), TRIG_Z]


TRIG_Z = min(v.z for v in world_verts(O["Trigger"])) + 0.011   # a finger's width up from the tip of the blade
bpy.context.view_layer.update()
grip_pts = []
glo, ghi = bounds([O["grip"]])
for k in range(1, 10):
    z = ghi.z - (ghi.z - glo.z) * k / 10.0
    f = ray(Vector((0, glo.y + 0.12, z)), Vector((0, -1, 0)))
    b = ray(Vector((0, glo.y - 0.05, z)), Vector((0, 1, 0)))
    if f and b:
        grip_pts.append((z, f.y, b.y))
top, bot = grip_pts[1], grip_pts[-2]
angle = math.degrees(math.atan2(top[1] - bot[1], top[0] - bot[0]))   # lean of the front strap from vertical
mag_lo, mag_hi = bounds([O["Magazine"]])
no_mag = [o for o in meshes if o.name != "Magazine"]
nlo, nhi = bounds(no_mag)
flat = [o for o in meshes if o.name not in ("Magazine", "RearSight")]
flo, fhi = bounds(flat)
dims = {
    "scale": s, "stock_extended_by_m": extend,
    "overall_length_in": (hi.y - lo.y) / IN, "overall_length_retracted_in": (hi.y - lo.y - (OAL_EXTENDED - OAL_RETRACTED)) / IN,
    "barrel_in": BARREL / IN,
    "height_with_mag_in": (hi.z - lo.z) / IN, "height_no_mag_in": (nhi.z - nlo.z) / IN,
    "height_flattop_no_mag_in": (fhi.z - flo.z) / IN,
    "width_in": (hi.x - lo.x) / IN,
    "rail_top_m": R, "handguard_y": [y0, y1],
    "sight_rear": list(rear_sight), "sight_front": list(front_sight), "sight_height_in": sight_z / IN,
    "grip_front_top": [top[1], top[0]], "grip_front_bottom": [bot[1], bot[0]],
    "grip_depth_m": sum(p[1] - p[2] for p in grip_pts[1:-1]) / max(1, len(grip_pts) - 2),
    "grip_angle_deg": angle, "grip_bottom_z": glo.z, "grip_width_m": ghi.x - glo.x,
    "trigger": list(bounds([O["Trigger"]])[0]) + list(bounds([O["Trigger"]])[1]),
    "magazine": [list(mag_lo), list(mag_hi)],
    "selector": list(O["Selector"].matrix_world.translation),
    "trigger_face": trigger_face(),
}
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "m4_dims.json"), "w") as fh:
    json.dump(dims, fh, indent=1)
for k, v in dims.items():
    print(f"  {k}: {v}")
total = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
print(f"  TOTAL tris {total}")

blend = os.path.join(OUT, "m4a1.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "m4a1.glb"), export_format="GLB", export_apply=True, export_yup=True)
print("wrote", blend, "and m4a1.glb")
