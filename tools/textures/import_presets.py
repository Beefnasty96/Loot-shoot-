"""Import settings for uploaded level textures (assets/textures/**).

Writes or fixes each image's .import file so Godot imports it as a 3D
texture: mipmaps on, VRAM compression (ETC2/ASTC on the Thor), capped at
2048 px, normal-map mode for *_normal / *_n files. Run before
`godot --headless --import` (the APK build does). Safe to run again.

Usage: python3 tools/textures/import_presets.py [root ...]
"""
import os
import re
import sys

EXTS = (".png", ".jpg", ".jpeg", ".webp")
PARAMS = {
    "compress/mode": "2",
    "compress/high_quality": "false",
    "compress/lossy_quality": "0.7",
    "compress/hdr_compression": "1",
    "compress/channel_pack": "0",
    "mipmaps/generate": "true",
    "mipmaps/limit": "-1",
    "roughness/mode": "0",
    "process/fix_alpha_border": "true",
    "process/premult_alpha": "false",
    "process/normal_map_invert_y": "false",
    "process/size_limit": "2048",
    "detect_3d/compress_to": "0",
}


def is_normal(name):
    stem = os.path.splitext(name)[0]
    stem = re.sub(r"@[0-9.]+(ft|in|cm|m)$", "", stem)
    return stem.endswith("_normal") or stem.endswith("_n") or re.search(r"_(normal|n)@", name) is not None


def want(name):
    p = dict(PARAMS)
    p["compress/normal_map"] = "1" if is_normal(name) else "0"
    return p


def fix(path):
    imp = path + ".import"
    params = want(os.path.basename(path))
    if not os.path.exists(imp):
        with open(imp, "w") as f:
            f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n')
            for k, v in params.items():
                f.write(f"{k}={v}\n")
        return "new"
    text = open(imp).read()
    changed = False
    for k, v in params.items():
        pat = re.compile(r"^" + re.escape(k) + r"=.*$", re.M)
        if pat.search(text):
            new = pat.sub(f"{k}={v}", text)
        else:
            new = text.replace("[params]\n", f"[params]\n{k}={v}\n", 1) if "[params]" in text else text + f"\n[params]\n{k}={v}\n"
        if new != text:
            text, changed = new, True
    if changed:
        open(imp, "w").write(text)
        return "fixed"
    return "ok"


def main():
    roots = sys.argv[1:] or ["assets/textures"]
    counts = {"new": 0, "fixed": 0, "ok": 0}
    for root in roots:
        for d, _, files in os.walk(root):
            for n in sorted(files):
                if n.lower().endswith(EXTS):
                    counts[fix(os.path.join(d, n))] += 1
    print("textures: %(new)d new, %(fixed)d fixed, %(ok)d already set" % counts)


if __name__ == "__main__":
    main()
