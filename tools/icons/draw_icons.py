"""Draws simple inventory icons for loot and ammo (transparent PNG, 64 px per square).

Usage: python3 draw_icons.py <out_dir>
Drawn at 4x and scaled down for smooth edges.
"""
import os
import sys

from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
CELL = 64
SS = 4
os.makedirs(OUT, exist_ok=True)


def canvas(w, h):
    img = Image.new("RGBA", (w * CELL * SS, h * CELL * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img, name):
    w, h = img.size
    img.resize((w // SS, h // SS), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
    print("icon", name)


def S(*v):
    return [x * SS for x in v]


def shaded_rect(d, box, fill, outline=(20, 20, 20, 255), r=6):
    d.rounded_rectangle(S(*box), radius=r * SS, fill=fill, outline=outline, width=2 * SS)
    x0, y0, x1, y1 = box
    hi = tuple(min(255, c + 35) for c in fill[:3]) + (255,)
    d.rounded_rectangle(S(x0 + 3, y0 + 3, x1 - 3, y0 + 3 + (y1 - y0) * 0.25), radius=r * SS, fill=hi)


# ---------------------------------------------------------------- ammo (3 cartridges)
BULLETS = {
    "fmj": ((184, 115, 51), "round"),
    "jhp": ((150, 150, 150), "hollow"),
    "jhpp": ((150, 150, 150), "hollow_p"),
    "cu_hp": ((196, 110, 60), "hollow"),
    "lswc": ((120, 122, 128), "swc"),
    "frang": ((90, 100, 130), "round"),
}
for key, (bc, shape) in BULLETS.items():
    img, d = canvas(1, 1)
    for i, x in enumerate((14, 30, 46)):
        top = 14 + (i % 2) * 4
        d.rectangle(S(x - 6, top + 14, x + 6, 56), fill=(205, 165, 70), outline=(90, 70, 20), width=SS)   # brass case
        d.rectangle(S(x - 6, 52, x + 6, 56), fill=(170, 130, 50))
        if shape == "round":
            d.chord(S(x - 6, top, x + 6, top + 22), 180, 360, fill=bc, outline=(60, 40, 20), width=SS)
            d.rectangle(S(x - 6, top + 11, x + 6, top + 15), fill=bc)
        elif shape.startswith("hollow"):
            d.polygon(S(x - 6, top + 15, x - 5, top + 6, x + 5, top + 6, x + 6, top + 15), fill=bc, outline=(50, 50, 50))
            d.ellipse(S(x - 3, top + 4, x + 3, top + 9), fill=(30, 30, 30))
        elif shape == "swc":
            d.rectangle(S(x - 6, top + 9, x + 6, top + 15), fill=bc)
            d.rectangle(S(x - 4, top + 3, x + 4, top + 9), fill=bc, outline=(60, 60, 60))
        if shape == "hollow_p":
            d.rectangle(S(x - 6, top + 22, x + 6, top + 24), fill=(170, 30, 30))
    save(img, "ammo_" + key)

# ---------------------------------------------------------------- loot
img, d = canvas(1, 1)   # IFAK pouch
shaded_rect(d, (8, 12, 56, 54), (110, 115, 70, 255))
d.rectangle(S(28, 20, 36, 46), fill=(200, 30, 30)); d.rectangle(S(19, 29, 45, 37), fill=(200, 30, 30))
save(img, "ifak")

img, d = canvas(2, 1)   # car first aid kit
shaded_rect(d, (8, 10, 120, 56), (190, 40, 35, 255))
d.rectangle(S(58, 18, 70, 48), fill=(245, 245, 245)); d.rectangle(S(49, 27, 79, 39), fill=(245, 245, 245))
d.rectangle(S(54, 6, 74, 12), fill=(40, 40, 40))
save(img, "medkit")

img, d = canvas(1, 1)   # painkiller blister
shaded_rect(d, (10, 14, 54, 50), (210, 210, 215, 255), r=3)
for row in range(2):
    for col in range(4):
        cx, cy = 17 + col * 10, 24 + row * 16
        d.ellipse(S(cx - 4, cy - 4, cx + 4, cy + 4), fill=(240, 240, 240), outline=(150, 150, 160), width=SS)
save(img, "painkillers")

img, d = canvas(1, 2)   # water bottle
d.rounded_rectangle(S(18, 30, 46, 120), radius=8 * SS, fill=(120, 170, 220, 210), outline=(40, 70, 110), width=2 * SS)
d.rectangle(S(25, 16, 39, 30), fill=(120, 170, 220, 210), outline=(40, 70, 110), width=SS)
d.rectangle(S(24, 8, 40, 16), fill=(30, 90, 170))
d.rectangle(S(18, 60, 46, 84), fill=(240, 240, 240)); d.rectangle(S(18, 68, 46, 76), fill=(40, 120, 200))
save(img, "water")

img, d = canvas(1, 1)   # canned beans
d.rectangle(S(14, 12, 50, 54), fill=(170, 170, 175), outline=(70, 70, 75), width=2 * SS)
d.rectangle(S(14, 20, 50, 46), fill=(170, 60, 30)); d.ellipse(S(24, 26, 40, 40), fill=(230, 200, 140))
save(img, "beans")

img, d = canvas(1, 1)   # cash roll
d.rounded_rectangle(S(10, 20, 54, 46), radius=12 * SS, fill=(95, 140, 85), outline=(40, 70, 40), width=2 * SS)
d.rectangle(S(28, 18, 36, 48), fill=(210, 180, 60))
save(img, "cash")

img, d = canvas(1, 1)   # gold bar
d.polygon(S(8, 46, 16, 22, 48, 22, 56, 46), fill=(225, 180, 50), outline=(130, 90, 10))
d.polygon(S(16, 22, 48, 22, 44, 28, 20, 28), fill=(250, 215, 100))
save(img, "gold")

img, d = canvas(1, 1)   # classified folder
shaded_rect(d, (8, 14, 56, 52), (205, 175, 110, 255), r=2)
d.rectangle(S(8, 30, 56, 37), fill=(180, 30, 30))
save(img, "docs")

img, d = canvas(2, 1)   # graphics card
shaded_rect(d, (6, 14, 122, 50), (45, 48, 52, 255), r=3)
for cx in (40, 88):
    d.ellipse(S(cx - 15, 17, cx + 15, 47), fill=(25, 25, 28), outline=(90, 90, 95), width=SS)
    d.ellipse(S(cx - 4, 28, cx + 4, 36), fill=(90, 90, 95))
d.rectangle(S(12, 50, 100, 55), fill=(200, 160, 50))
save(img, "gpu")

img, d = canvas(3, 2)   # laptop
d.polygon(S(40, 18, 152, 18, 156, 82, 36, 82), fill=(70, 72, 78), outline=(20, 20, 20))
d.rectangle(S(46, 24, 146, 76), fill=(40, 70, 110))
d.polygon(S(20, 86, 172, 86, 182, 110, 10, 110), fill=(95, 97, 103), outline=(20, 20, 20))
for r in range(3):
    d.rectangle(S(36 + r * 4, 90 + r * 6, 156 - r * 4, 93 + r * 6), fill=(60, 62, 66))
save(img, "laptop")

# ---------------------------------------------------------------- 5.56 NATO (3 slim bottlenecked cartridges)
TIPS = {"m193": None, "m855": (60, 140, 60), "m856": (220, 110, 30)}
for key, tip in TIPS.items():
    img, d = canvas(1, 1)
    for i, x in enumerate((16, 32, 48)):
        top = 6 + (i % 2) * 4
        # case body, shoulder, neck
        d.rectangle(S(x - 5, top + 24, x + 5, 58), fill=(205, 165, 70), outline=(90, 70, 20), width=SS)
        d.polygon(S(x - 5, top + 24, x + 5, top + 24, x + 3, top + 19, x - 3, top + 19), fill=(205, 165, 70), outline=(90, 70, 20))
        d.rectangle(S(x - 3, top + 14, x + 3, top + 19), fill=(205, 165, 70))
        d.rectangle(S(x - 5, 54, x + 5, 58), fill=(170, 130, 50))
        # copper bullet: long ogive
        d.polygon(S(x - 3, top + 14, x + 3, top + 14, x + 2, top + 6, x, top, x - 2, top + 6), fill=(184, 115, 51), outline=(60, 40, 20))
        if tip:
            d.polygon(S(x - 2, top + 6, x + 2, top + 6, x, top), fill=tip)
    save(img, "ammo_" + key)
