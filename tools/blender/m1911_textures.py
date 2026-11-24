"""Generates the small retro textures for the M1911 (run with plain python3).

Usage: python3 m1911_textures.py <output_dir>
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image

out = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(1911)


def steel(name, base, size=128):
    """Blued steel: dark base, fine noise, faint lengthwise brushing."""
    img = np.zeros((size, size, 3), np.float32) + np.array(base, np.float32)
    img += rng.normal(0, 2.5, (size, size, 1))
    streaks = rng.normal(0, 2.0, (1, size, 1))  # constant along one axis = brushed look
    img += streaks
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(out, name))


def wood_grip(name, w=128, h=288):
    """Walnut double-diamond grip panel. u = front->back, v = top->bottom of the panel."""
    img = np.zeros((h, w, 3), np.float32)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = xs / (w - 1), ys / (h - 1)

    # Walnut with wavy grain running along the panel.
    grain = np.sin((u * 26.0) + np.sin(v * 9.0) * 1.6 + np.sin(v * 31.0) * 0.25)
    base = np.array([96, 52, 28], np.float32)
    img[:] = base
    img += (grain[..., None] * 10.0)
    img += rng.normal(0, 3.0, (h, w, 1))

    # Checkering: two crossing line sets (diamond grid), darker grooves.
    aspect = h / w
    a = (u * 22.0 + v * aspect * 22.0 * 0.55) % 1.0
    b = (u * 22.0 - v * aspect * 22.0 * 0.55) % 1.0
    groove = (np.minimum(a, 1 - a) < 0.13) | (np.minimum(b, 1 - b) < 0.13)
    checker = groove.astype(np.float32)

    # Smooth areas: border and the two diamonds around the screws.
    border = (u < 0.07) | (u > 0.93) | (v < 0.04) | (v > 0.96)
    smooth = border.copy()
    for cv in (0.16, 0.84):
        diamond = (np.abs(u - 0.5) / 0.30 + np.abs(v - cv) / 0.12) < 1.0
        smooth |= diamond
    img -= (checker * (~smooth))[..., None] * 34.0
    # Slight darkening at the edges (fake bevel shading, very 2003).
    edge = np.minimum(np.minimum(u, 1 - u) * 6, np.minimum(v, 1 - v) * 14).clip(0, 1)
    img *= (0.75 + 0.25 * edge)[..., None]

    # Slotted screw heads.
    for cv in (0.16, 0.84):
        du, dv = (u - 0.5), (v - cv) * aspect
        r = np.sqrt(du ** 2 + dv ** 2)
        head = r < 0.11
        img[head] = np.array([70, 72, 76], np.float32) + (0.11 - r[head, None]) * 300
        slot = head & (np.abs(du + dv * 0.3) < 0.018)
        img[slot] = np.array([25, 25, 27], np.float32)
        rim = (r >= 0.11) & (r < 0.125)
        img[rim] *= 0.6

    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(out, name))


steel("steel_blued.png", (44, 46, 52))
steel("steel_mag.png", (58, 60, 66), size=64)
wood_grip("grip_walnut.png")
print("textures written to", out)


# ------------------------------------------------------------------ stainless Government Model look
# (matches a modern stainless 1911: brushed flats, bead-blasted top, rosewood double-diamonds)

def stainless_brushed(name, size=256):
    """Bright brushed stainless. Streaks run along u (the UVs put u along the gun's length)."""
    img = np.zeros((size, size, 3), np.float32) + np.array([150, 152, 156], np.float32)
    img += rng.normal(0, 2.0, (size, size, 1))
    img += rng.normal(0, 5.0, (size, 1, 1))                       # long brush lines
    img += np.repeat(rng.normal(0, 3.0, (size // 8, 1, 1)), 8, 0)  # broader bands
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(out, name))


def stainless_matte(name, size=128):
    """Bead-blasted stainless (slide top, hammer, small parts): flat grey, fine speckle."""
    img = np.zeros((size, size, 3), np.float32) + np.array([140, 142, 146], np.float32)
    img += rng.normal(0, 4.0, (size, size, 1))
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(out, name))


def rosewood_grip(name, w=128, h=288):
    """Rosewood double-diamond panel: red-brown with dark streaky grain, checkering, smooth
    diamonds around the slotted screws, smooth border."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = xs / (w - 1), ys / (h - 1)
    img = np.zeros((h, w, 3), np.float32) + np.array([92, 34, 22], np.float32)
    grain = np.sin(u * 40.0 + np.sin(v * 7.0) * 2.2 + np.sin(v * 23.0 + u * 5.0) * 0.6)
    img += grain[..., None] * np.array([7, 3, 2], np.float32)
    streak = (np.sin(u * 13.0 + np.sin(v * 5.0) * 1.3) > 0.82).astype(np.float32)
    img -= streak[..., None] * np.array([16, 8, 5], np.float32)    # dark rosewood streaks
    img += rng.normal(0, 3.0, (h, w, 1))
    aspect = h / w
    a = (u * 26.0 + v * aspect * 26.0 * 0.55) % 1.0
    b = (u * 26.0 - v * aspect * 26.0 * 0.55) % 1.0
    groove = ((np.minimum(a, 1 - a) < 0.14) | (np.minimum(b, 1 - b) < 0.14)).astype(np.float32)
    border = (u < 0.06) | (u > 0.94) | (v < 0.035) | (v > 0.965)
    smooth = border.copy()
    for cv in (0.17, 0.83):
        smooth |= (np.abs(u - 0.5) / 0.34 + np.abs(v - cv) / 0.13) < 1.0
    img -= (groove * (~smooth))[..., None] * 26.0
    img += (smooth & ~border)[..., None] * 10.0                       # polished diamonds catch light
    edge = np.minimum(np.minimum(u, 1 - u) * 7, np.minimum(v, 1 - v) * 16).clip(0, 1)
    img *= (0.7 + 0.3 * edge)[..., None]
    for cv in (0.17, 0.83):                                          # slotted screws
        du, dv = (u - 0.5), (v - cv) * aspect
        r = np.sqrt(du ** 2 + dv ** 2)
        head = r < 0.1
        img[head] = np.array([168, 170, 174], np.float32) - r[head, None] * 300
        img[head & (np.abs(du * 0.9 - dv * 0.45) < 0.017)] = np.array([40, 40, 42], np.float32)
        img[(r >= 0.1) & (r < 0.118)] *= 0.55
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(out, name))


def roll_mark(name, lines, size, font_px):
    """Engraved lettering: dark, slightly soft, on a transparent background."""
    from PIL import ImageDraw, ImageFilter, ImageFont
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", font_px)
    img = Image.new("L", size, 0)
    d = ImageDraw.Draw(img)
    y = 0
    for text, px, x in lines:
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", px) if px else font
        d.text((x, y), text, fill=255, font=f)
        y += int((px or font_px) * 1.35)
    img = img.filter(ImageFilter.GaussianBlur(0.4))
    rgba = Image.new("RGBA", size, (38, 38, 40, 0))
    rgba.putalpha(img.point(lambda a: int(a * 0.85)))
    rgba.save(os.path.join(out, name))


stainless_brushed("stainless_brushed.png")
stainless_matte("stainless_matte.png")
rosewood_grip("grip_rosewood.png")
roll_mark("rollmark_slide.png", [("GOVERNMENT MODEL", 0, 4)], (512, 40), 30)
roll_mark("rollmark_frame.png", [("M1911 A1  U.S. ARMY", 0, 2), ("No. 1911045", 0, 120)], (512, 72), 26)
print("stainless textures written to", out)
