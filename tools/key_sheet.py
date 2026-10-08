"""Key-pose contact sheet: for each clip, the key poses seen from the side (3D pose, rendered by
tools/bake_sprites.gd with side=<dir>) above the baked top-down sprite frames (as in game, 2x).
  python3 tools/key_sheet.py <side dir> <out.png> <skin> <clip>...
"""
import json
import sys
from PIL import Image, ImageDraw

side_dir, out, skin = sys.argv[1:4]
clips = sys.argv[4:]
CELL = 112
BG = (34, 56, 42)
rows = []
for c in clips:
    side = Image.open("%s/%s_%s_side.png" % (side_dir, skin, c)).convert("RGBA")
    sheet = Image.open("art/sprites/%s/%s.png" % (skin, c)).convert("RGBA")
    meta = json.load(open("art/sprites/%s/%s.json" % (skin, c)))
    n = side.width // 128
    fw = sheet.width // n
    rows.append((c, side, sheet, meta, n, fw))
W = CELL * max(r[4] for r in rows)
H = sum(CELL * 2 + 14 for _ in rows)
img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)
y = 0
for c, side, sheet, meta, n, fw in rows:
    labels = meta.get("labels") or [str(i) for i in range(n)]
    starts = meta.get("starts", [])
    d.text((3, y + 1), "%s   (%d keys, starts %s)" % (c, n, " ".join("%.2f" % s for s in starts)), fill=(255, 255, 255))
    y += 14
    for i in range(n):
        s = side.crop((i * 128, 0, i * 128 + 128, 128)).resize((CELL, CELL), Image.NEAREST)
        img.paste(s, (i * CELL, y), s)
        f = sheet.crop((i * fw, 0, i * fw + fw, sheet.height))
        scale = min(CELL // f.width, CELL // f.height) if f.width <= CELL and f.height <= CELL else 1
        f = f.resize((f.width * 2, f.height * 2), Image.NEAREST) if f.width * 2 <= CELL and f.height * 2 <= CELL else f.resize((CELL, int(CELL * f.height / f.width)), Image.NEAREST) if f.width >= f.height else f.resize((int(CELL * f.width / f.height), CELL), Image.NEAREST)
        img.paste(f, (i * CELL + (CELL - f.width) // 2, y + CELL + (CELL - f.height) // 2), f)
        d.text((i * CELL + 3, y + 2), labels[i] if i < len(labels) else "", fill=(255, 230, 120))
    y += CELL * 2
img.save(out, optimize=True)
print("wrote", out, img.size)
