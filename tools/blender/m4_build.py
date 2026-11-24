"""Builds a low-poly M4A1 carbine (5.56 NATO) with Blender's Python module (bpy).

M4A1 with a rail system: flat-top upper with a Picatinny rail, a four-rail (RIS)
handguard, a folding rear sight (BUIS) lined up with the A2 front sight post,
14.5 in barrel with an A2 birdcage, six-position collapsible stock, 30-round
STANAG magazine. Black anodized aluminium receivers, phosphate (parkerized)
barrel and front sight, black polymer furniture. Generic government markings,
no maker names. Textures are generated here (numpy + PIL).

Usage:  python3 m4_build.py <asset_dir>
Writes <asset_dir>/m4a1.blend, <asset_dir>/m4a1.glb and textures in <asset_dir>/textures.

Conventions (same as m1911_build.py)
- Millimetres from real dimensions, stored in metres (S = 0.001).
- Blender axes: +Y = muzzle, +Z = up, +X = right. glTF export -> Godot -Z forward.
- Bore axis along Y at x = 0, z = 0. Origin is on the bore above the trigger.
- Sight line: rear aperture centre and front post tip both at z = SIGHT_Z.
- Moving parts are separate nodes for Godot: Bolt (carrier, seen through the
  ejection port), ChargingHandle, DustCover (hinge at its bottom edge), Selector
  (pivot on its pin), Trigger, Magazine. Markers: Muzzle, SightRear, SightFront,
  EjectionPort.
"""
import math
import os
import sys

import bpy  # must come first: it provides bmesh and mathutils
import numpy as np
from mathutils import Vector
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import m1911_build as mb  # noqa: E402
from m1911_build import (S, box, cut, cyl_x, cyl_y, decal, empty, from_data, join, link,  # noqa: E402
                         material, prism_xz, prism_yz, reset, set_pivot, uv_box)

ASSET_DIR = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
TEX_DIR = os.path.join(ASSET_DIR, "textures")
mb.TEX_DIR = TEX_DIR

SIGHT_Z = 64.0          # sight line height above the bore (mm)
REAR_SIGHT_Y = -119.0
FRONT_POST_Y = 284.0
MUZZLE_Y = 447.0
RAIL_TOP = 24.0         # top of the Picatinny rails above the bore (receiver and handguard line up)

# Pistol grip (A2 style, 25 deg): front strap line from F0 going down the grip.
GRIP_ANGLE = math.radians(25.0)
GD = Vector((-math.sin(GRIP_ANGLE), -math.cos(GRIP_ANGLE)))   # down the grip (y, z)
GN = Vector((-math.cos(GRIP_ANGLE), math.sin(GRIP_ANGLE)))    # across, toward the back
GF0 = Vector((-74.0, -47.0))
GRIP_DEPTH = 32.0
GRIP_LEN = 98.0


def ggp(t, s=0.0):
    """Grip coordinates (t down the front strap, s back across the grip) -> (y, z)."""
    p = GF0 + GD * t + GN * s
    return (p.x, p.y)


# --------------------------------------------------------------------- textures

def make_textures():
    os.makedirs(TEX_DIR, exist_ok=True)
    rng = np.random.default_rng(556)

    def save(name, img):
        Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(TEX_DIR, name))

    # Black anodized aluminium: very dark grey, fine speckle, faint machining lines.
    a = np.zeros((128, 128, 3), np.float32) + np.array([38, 38, 40], np.float32)
    a += rng.normal(0, 2.2, (128, 128, 1)) + rng.normal(0, 1.2, (128, 1, 1))
    save("anodized.png", a)
    # Phosphate (parkerized) steel: grey-black with a faint green cast, mottled.
    p = np.zeros((128, 128, 3), np.float32) + np.array([44, 46, 42], np.float32)
    blot = rng.normal(0, 1.0, (16, 16, 1)).repeat(8, 0).repeat(8, 1)
    p += blot * 3.0 + rng.normal(0, 3.5, (128, 128, 1))
    save("phosphate.png", p)
    # Polymer furniture: black, stippled.
    q = np.zeros((128, 128, 3), np.float32) + np.array([30, 30, 31], np.float32)
    q += (rng.random((128, 128, 1)) > 0.82) * 9.0 + rng.normal(0, 1.5, (128, 128, 1))
    save("polymer.png", q)
    # Magazine: dry-film grey-green aluminium with the ribs as darker bands.
    m = np.zeros((128, 64, 3), np.float32) + np.array([62, 64, 58], np.float32)
    m[:, 20:24] -= 14
    m[:, 40:44] -= 14
    m += rng.normal(0, 2.5, (128, 64, 1))
    save("mag.png", m)
    # Bolt carrier: phosphate with a bit of shine from wear.
    b = np.zeros((64, 64, 3), np.float32) + np.array([58, 58, 58], np.float32)
    b += rng.normal(0, 4.0, (64, 64, 1)) + rng.normal(0, 5.0, (64, 1, 1))
    save("carrier.png", b)
    # White-filled engraving on a transparent background.
    font = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

    def marks(name, lines, size, px):
        img = Image.new("L", size, 0)
        d = ImageDraw.Draw(img)
        y = 2
        f = ImageFont.truetype(font, px)
        for text in lines:
            d.text((4, y), text, fill=255, font=f)
            y += int(px * 1.3)
        img = img.filter(ImageFilter.GaussianBlur(0.35))
        rgba = Image.new("RGBA", size, (200, 200, 196, 0))
        rgba.putalpha(img.point(lambda v: int(v * 0.8)))
        rgba.save(os.path.join(TEX_DIR, name))

    marks("marks_lower.png", ["PROPERTY OF U.S. GOVT.", "M4A1 CARBINE", "CAL. 5.56 MM", "W 1004471"], (256, 128), 18)
    # Selector markings: arranged round the pivot (SAFE forward, SEMI up, AUTO back), left side.
    img = Image.new("L", (128, 64), 0)
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(font, 14)
    d.text((2, 30), "SAFE", fill=255, font=f)     # front (decal u runs front->rear on the left)
    d.text((46, 0), "SEMI", fill=255, font=f)
    d.text((88, 30), "AUTO", fill=255, font=f)
    img = img.filter(ImageFilter.GaussianBlur(0.35))
    rgba = Image.new("RGBA", (128, 64), (220, 220, 215, 0))
    rgba.putalpha(img.point(lambda v: int(v * 0.85)))
    rgba.save(os.path.join(TEX_DIR, "marks_selector.png"))


# --------------------------------------------------------------------- helpers

def loft(name, sections, mat):
    """Join a list of closed (x, y, z) rings with quads; caps at both ends."""
    n = len(sections[0])
    verts = [v for ring in sections for v in ring]
    faces = [list(range(n))[::-1], [len(verts) - n + i for i in range(n)]]
    for k in range(len(sections) - 1):
        a, b = k * n, (k + 1) * n
        faces += [[a + i, a + (i + 1) % n, b + (i + 1) % n, b + i] for i in range(n)]
    return from_data(name, verts, faces, mat)


def rail(name, axis, y0, y1, base_in, mat, ribs=True):
    """Picatinny rail along Y. `axis` = which side it faces: 'top', 'bottom', 'left', 'right'.
    base_in = distance from the bore where its base starts (top surface ends at RAIL_TOP)."""
    pieces = []
    # (u = across the rail, w = out from the bore) -> (x, z)
    def to_xz(u, w):
        return {"top": (u, w), "bottom": (-u, -w), "right": (w, -u), "left": (-w, u)}[axis]

    def block(nm, u0, u1, w0, w1, a, b):
        pts = [to_xz(u0, w0), to_xz(u1, w0), to_xz(u1, w1), to_xz(u0, w1)]
        return prism_xz(nm, pts, a, b, mat)

    pieces.append(block(name + "_base", -7.5, 7.5, base_in, RAIL_TOP - 5.0, y0, y1))
    pieces.append(block(name + "_head", -10.6, 10.6, RAIL_TOP - 5.0, RAIL_TOP - 3.0, y0, y1))
    if ribs:
        y = y0 + 1.0
        i = 0
        while y + 5.2 <= y1 - 0.5:
            pieces.append(block(f"{name}_rib{i}", -10.6, 10.6, RAIL_TOP - 3.0, RAIL_TOP, y, y + 5.2))
            y += 10.0
            i += 1
    for p in pieces:
        uv_box(p, 40.0)
    return join(pieces, name)


# --------------------------------------------------------------------- the carbine

def build():
    reset()
    make_textures()
    anod = material("Anodized", (0.16, 0.16, 0.17), "anodized.png", rough=0.55, metal=0.1)
    park = material("Phosphate", (0.19, 0.2, 0.18), "phosphate.png", rough=0.75, metal=0.1)
    poly = material("Polymer", (0.12, 0.12, 0.125), "polymer.png", rough=0.8, metal=0.0)
    magm = material("MagFinish", (0.27, 0.28, 0.25), "mag.png", rough=0.7, metal=0.1)
    carrier = material("Carrier", (0.25, 0.25, 0.25), "carrier.png", rough=0.4, metal=0.3)
    black = material("Interior", (0.015, 0.015, 0.015), None, rough=0.95, metal=0.0)
    brass = material("Brass", (0.75, 0.55, 0.22), None, rough=0.4, metal=0.5)
    copper = material("BulletCopper", (0.6, 0.35, 0.2), None, rough=0.45, metal=0.4)
    rubber = material("Rubber", (0.08, 0.08, 0.08), None, rough=0.95, metal=0.0)
    marks_lower = material("MarksLower", (0.8, 0.8, 0.78), "marks_lower.png", rough=0.7, metal=0.0, alpha=True)
    marks_sel = material("MarksSelector", (0.85, 0.85, 0.82), "marks_selector.png", rough=0.7, metal=0.0, alpha=True)

    # ================= Upper receiver (flat-top) =================
    up_xs = [(-11.5, -17), (11.5, -17), (11.5, 8), (9, 13), (-9, 13), (-11.5, 8)]
    upper = prism_xz("UpperBody", up_xs, -150, 88, anod)
    # Ejection port (right) - the cut walls are dark interior.
    cut(upper, box("cut_port", 7.5, 20, -2, 52, -7.5, 7.5, black))
    # Bore channel at the front for the barrel extension (and so the chamber reads dark).
    cut(upper, cyl_y("cut_front", 9.6, 60, 95, 0, 0, black, seg=12))
    ups = [upper]
    ups.append(rail("UpperRail", "top", -148, 86, 12.0, anod))
    # Forward assist (right rear) and the brass deflector bump behind the port.
    ups.append(cyl_y("FwdAssistBody", 6.5, -125, -96, 13.0, 4.0, anod, seg=10))
    ups.append(cyl_y("FwdAssistButton", 5.0, -134, -125, 13.5, 4.0, anod, seg=10))
    ups.append(prism_yz("Deflector", [(-28, -5), (-6, -5), (-6, 10), (-18, 10)], 11.5, 16.5, anod))
    # Barrel nut collar at the front.
    ups.append(cyl_y("BarrelNut", 16.5, 86, 92, 0, 0, anod, seg=12))
    for p in ups:
        if p.data.uv_layers.get("UVMap") is None:
            uv_box(p, 60.0)
    upper = join(ups, "Upper")

    # ================= Lower receiver =================
    low_profile = [(-152, -17), (75, -17), (75, -30), (73, -72), (66, -76), (10, -76), (6, -50),
                   (-115, -47), (-138, -40), (-152, -30)]
    lower = prism_yz("LowerBody", low_profile, -10.5, 10.5, anod)
    well = prism_yz("MagWell", [(8, -40), (74, -40), (72, -74), (66, -79), (11, -79), (8, -52)], -13.0, 13.0, anod)
    cut(well, box("cut_well", -11.2, 11.2, 11, 70, -85, -30, black))
    lws = [lower, well]
    # Trigger guard (bottom bar + front post), takedown and pivot pins, bolt catch, mag release.
    lws.append(box("GuardBar", -4.5, 4.5, -78, 6, -65, -61, anod))
    lws.append(box("GuardRear", -4.5, 4.5, -80, -73, -65, -47, anod))
    lws.append(cyl_x("PivotPin", 3.2, -11.6, 11.6, 62, -22, anod, seg=8))
    lws.append(cyl_x("TakedownPin", 3.2, -11.6, 11.6, -132, -22, anod, seg=8))
    lws.append(box("BoltCatch", -12.8, -10.4, -4, 14, -34, -21, anod))
    lws.append(cyl_x("MagRelease", 5.0, 10.4, 13.5, 3, -36, anod, seg=10))
    lws.append(box("MagReleaseGuard", 10.4, 13.0, -8, 14, -46, -42, anod))
    # Buffer tube (receiver extension) and castle nut.
    lws.append(cyl_y("BufferTube", 14.5, -335, -150, 0, -2, anod, seg=12))
    lws.append(cyl_y("CastleNut", 17.0, -160, -152, 0, -2, anod, seg=12))
    for p in lws:
        if p.data.uv_layers.get("UVMap") is None:
            uv_box(p, 60.0)
    lws.append(decal("LowerMarks", -13.06, 16.0, 70.0, -74.0, -46.0, marks_lower, right=False))
    lws.append(decal("SelectorMarks", -10.56, -86.0, -40.0, -40.0, -15.0, marks_sel, right=False))
    lower = join(lws, "Lower")

    # ================= Pistol grip (A2, polymer, finger bump) =================
    front_pts = [ggp(0), ggp(22), (ggp(30)[0] + 3.0, ggp(30)[1]), ggp(38), ggp(60), ggp(80), ggp(GRIP_LEN)]
    back_pts = [ggp(GRIP_LEN, GRIP_DEPTH), ggp(60, GRIP_DEPTH + 1.0), (-109.3, -47.0)]
    grip = prism_yz("Grip", front_pts + back_pts, -12.0, 12.0, poly)
    uv_box(grip, 50.0)

    # ================= Stock (six-position, collapsible) =================
    # Upper part hugs the buffer tube; the lower edge sweeps down to the toe of the butt.
    stock_top = prism_yz("StockTop", [(-264, 16), (-264, -20), (-376, -20), (-376, 18)], -16.0, 16.0, poly)
    stock_brace = prism_yz("StockBrace", [(-290, -18), (-346, -88), (-362, -100), (-376, -100), (-376, -18)], -19.0, 19.0, poly)
    cut(stock_brace, prism_yz("cut_stock", [(-318, -30), (-350, -70), (-366, -70), (-366, -30)], -30.0, 30.0, poly))
    stock_parts = [stock_top, stock_brace, box("ButtPad", -19.5, 19.5, -384, -376, -102, 20, rubber),
                   box("StockLever", -6, 6, -300, -268, -26, -18, poly)]
    for p in stock_parts:
        uv_box(p, 50.0)
    stock = join(stock_parts, "Stock")

    # ================= Quad rail handguard (RIS) =================
    ap = 17.0                       # octagon apothem
    rv = ap / math.cos(math.radians(22.5))
    octa = [(rv * math.cos(math.radians(22.5 + 45 * k)), rv * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]
    hg = prism_xz("HandguardBody", octa, 92, 264, anod)
    cut(hg, cyl_y("cut_hg", 12.0, 80, 280, 0, 0, black, seg=12))
    hgs = [hg]
    for side in ("top", "bottom", "left", "right"):
        hgs.append(rail("Rail_" + side, side, 94, 262, ap - 1.0, anod))
    hgs.append(cyl_y("HGEndCap", 15.0, 262, 268, 0, 0, anod, seg=12))
    for p in hgs:
        if p.data.uv_layers.get("UVMap") is None:
            uv_box(p, 60.0)
    handguard = join(hgs, "Handguard")

    # ================= Barrel, front sight base, flash hider =================
    barrel = cyl_y("BarrelTube", 8.4, 88, 300, 0, 0, park, seg=12)
    bparts = [barrel, cyl_y("BarrelFront", 7.4, 300, 407, 0, 0, park, seg=12)]
    # A2 front sight base: collar on the barrel, tower, protective ears, post.
    bparts.append(cyl_y("FSBCollar", 12.5, 268, 300, 0, 0, park, seg=12))
    bparts.append(box("FSBBlock", -10, 10, 268, 300, -12, 10, park))
    bparts.append(prism_yz("FSBTower", [(270, 8), (300, 8), (294, 40), (276, 40)], -7.0, 7.0, park))
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 4.5, sx * 7.5))
        bparts.append(prism_yz(f"FSBEar{sx}", [(278, 38), (291, 38), (290, SIGHT_Z + 6), (280, SIGHT_Z + 6)], x0, x1, park))
    bparts.append(box("FSBBridge", -7.5, 7.5, 279, 290, 37, 42, park))
    bparts.append(box("FrontPost", -1.1, 1.1, FRONT_POST_Y - 1.4, FRONT_POST_Y + 1.4, 40, SIGHT_Z, black))
    bparts.append(box("BayonetLug", -3.5, 3.5, 276, 292, -21, -11, park))
    # Birdcage: closed bottom, slots on top and sides.
    fh = cyl_y("FlashHider", 11.0, 405, MUZZLE_Y, 0, 0, park, seg=12)
    cut(fh, box("cut_fh_t", -1.6, 1.6, 412, 441, 4, 14, black))
    cut(fh, box("cut_fh_r", 4, 14, 412, 441, -1.6, 1.6, black))
    cut(fh, box("cut_fh_l", -14, -4, 412, 441, -1.6, 1.6, black))
    cut(fh, cyl_y("cut_bore", 5.0, 420, 460, 0, 0, black, seg=10))
    bparts.append(fh)
    for p in bparts:
        if p.data.uv_layers.get("UVMap") is None:
            uv_box(p, 50.0)
    barrel = join(bparts, "Barrel")

    # ================= Folding rear sight (up), on the receiver rail =================
    rs_base = box("BUISBase", -12, 12, REAR_SIGHT_Y - 12, REAR_SIGHT_Y + 10, RAIL_TOP - 5.5, RAIL_TOP + 6.0, anod)
    # Leaf: a narrow stem up to a round aperture ring (reads as a ghost ring at cheek weld).
    stem = box("BUISStem", -4.5, 4.5, REAR_SIGHT_Y - 2.0, REAR_SIGHT_Y + 2.0, RAIL_TOP + 5.0, SIGHT_Z - 5.5, anod)
    ring = cyl_y("BUISRing", 6.5, REAR_SIGHT_Y - 2.0, REAR_SIGHT_Y + 2.0, 0, SIGHT_Z, anod, seg=12)
    cut(ring, cyl_y("cut_aperture", 3.6, REAR_SIGHT_Y - 6, REAR_SIGHT_Y + 6, 0, SIGHT_Z, black, seg=12))
    ears = [box(f"BUISEar{sx}", *sorted((sx * 8.5, sx * 10.5)), REAR_SIGHT_Y - 3, REAR_SIGHT_Y + 3, RAIL_TOP + 5.0, SIGHT_Z + 10.0, anod)
            for sx in (-1, 1)]
    rs = [rs_base, stem, ring] + ears + [cyl_x("BUISKnob", 5.0, 12, 17, REAR_SIGHT_Y + 1, RAIL_TOP + 1.0, anod, seg=10)]
    for p in rs:
        if p.data.uv_layers.get("UVMap") is None:
            uv_box(p, 40.0)
    rear_sight = join(rs, "RearSight")

    # ================= Moving parts =================
    # Bolt carrier: fills the ejection port when forward; slides back 75 mm.
    bolt = box("BoltBody", -8.0, 9.6, -130, 50, -7.0, 7.5, carrier)
    bolt_parts = [bolt, cyl_y("BoltHead", 6.0, 50, 58, 2.0, 0.0, carrier, seg=10),
                  box("CarrierCut", 9.0, 9.7, -5, 20, -2.5, 2.5, black)]   # the cam pin window
    for p in bolt_parts:
        if p.data.uv_layers.get("UVMap") is None:
            uv_box(p, 40.0)
    bolt = join(bolt_parts, "Bolt")

    # Charging handle: T-handle at the back of the upper, latch on the left.
    ch = [box("CHBar", -21.0, 21.0, -160, -150.5, 9.0, 15.0, anod), box("CHShaft", -5, 5, -150.5, -138, 10.0, 14.0, anod),
          prism_yz("CHLatch", [(-160, 9), (-148, 9), (-148, 16), (-160, 16)], -25.0, -21.0, anod)]
    for p in ch:
        uv_box(p, 40.0)
    charging = join(ch, "ChargingHandle")

    # Dust cover: closed over the port, hinged along its bottom edge.
    dust = box("DustCover", 11.6, 12.9, -3, 53, -8.0, 8.0, anod)
    uv_box(dust, 40.0)
    set_pivot(dust, (12.2, 25.0, -8.0))

    # Selector lever (left), pointing forward = SAFE; pivot on its pin.
    sel_parts = [cyl_x("SelPivot", 4.5, -13.2, -10.5, -63, -27, anod, seg=10),
                 prism_yz("SelLever", [(-63, -29.5), (-46, -28.5), (-44, -27), (-46, -25.5), (-63, -24.5)], -14.5, -12.6, anod)]
    for p in sel_parts:
        uv_box(p, 30.0)
    selector = join(sel_parts, "Selector")
    set_pivot(selector, (-12.0, -63.0, -27.0))

    # Trigger: curved blade, pivots/slides a few mm.
    trigger = prism_yz("Trigger", [(-36, -47), (-31.5, -47), (-31, -54), (-33.5, -61), (-37.5, -60.5), (-36.5, -54)], -3.2, 3.2, anod)
    uv_box(trigger, 20.0)

    # STANAG magazine: curved 30-rounder, lofted along its spine.
    secs = []
    spine = []
    for k in range(7):
        t = k / 6.0
        z = -22.0 - t * 190.0
        y = 40.0 + 34.0 * t * t          # curves forward toward the bottom
        dy = 2 * 34.0 * t / 190.0         # tangent slope dy/d(-z)
        spine.append((y, z, dy))
    for y, z, dy in spine:
        ang = math.atan(dy)
        hy = 30.0                         # half front-back
        # rectangle perpendicular to the spine (rotate the y half-width by the curve angle)
        oy, oz = hy * math.cos(ang), hy * math.sin(ang)
        hx = 10.6
        secs.append([(-hx, y - oy, z + oz), (hx, y - oy, z + oz), (hx, y + oy, z - oz), (-hx, y + oy, z - oz)])
    mag_body = loft("MagBody", secs, magm)
    uv_box(mag_body, 60.0)
    yb, zb, dyb = spine[-1]
    angb = math.atan(dyb)
    floor = prism_yz("MagFloor", [(yb - 33 * math.cos(angb), zb + 33 * math.sin(angb)),
                                  (yb + 33 * math.cos(angb), zb - 33 * math.sin(angb)),
                                  (yb + 33 * math.cos(angb) - 8 * math.sin(angb), zb - 33 * math.sin(angb) - 8 * math.cos(angb)),
                                  (yb - 33 * math.cos(angb) - 8 * math.sin(angb), zb + 33 * math.sin(angb) - 8 * math.cos(angb))],
                     -12.4, 12.4, poly)
    uv_box(floor, 40.0)
    case = cyl_y("TopCase", 4.7, 16, 61, 0, -19.5, brass, seg=10)
    bullet = cyl_y("TopBullet", 2.85, 61, 75, 0, -19.5, copper, seg=8)
    uv_box(case, 30.0)
    uv_box(bullet, 30.0)
    magazine = join([mag_body, floor, case, bullet], "Magazine")

    # ================= Hierarchy + markers =================
    root = link(bpy.data.objects.new("M4A1", None))
    meshes = (upper, lower, grip, stock, handguard, barrel, rear_sight, bolt, charging, dust, selector, trigger, magazine)
    for ob in meshes:
        ob.parent = root
        for p in ob.data.polygons:
            p.use_smooth = False
    empty("Muzzle", (0, MUZZLE_Y + 1.0, 0), root)
    empty("SightRear", (0, REAR_SIGHT_Y, SIGHT_Z), root)
    empty("SightFront", (0, FRONT_POST_Y, SIGHT_Z), root)
    empty("EjectionPort", (14, 25, 2), root)
    return root


def report():
    total = 0
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
            total += tris
            print(f"  {ob.name:<15} {tris:>5} tris")
    print(f"  TOTAL           {total:>5} tris")


if __name__ == "__main__":
    build()
    report()
    blend = os.path.join(ASSET_DIR, "m4a1.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_mainfile()
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(ASSET_DIR, "m4a1.glb"),
        export_format="GLB",
        export_apply=True,
        export_yup=True,
    )
    print("wrote", blend, "and m4a1.glb")
