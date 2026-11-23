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
