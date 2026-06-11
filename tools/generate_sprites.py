#!/usr/bin/env python3
"""Generate player body-part sprites and reconstruct the micro uzi weapon sprite."""
import struct, zlib, os

# ── PNG helpers ────────────────────────────────────────────────────────────────

def _chunk(name: bytes, data: bytes) -> bytes:
    body = name + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

def save_png(path: str, w: int, h: int, rows: list) -> None:
    """Save RGBA PNG."""
    raw = b""
    for row in rows:
        raw += b"\x00"
        for r, g, b, a in row:
            raw += bytes([r & 0xFF, g & 0xFF, b & 0xFF, a & 0xFF])
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # colour type 6 = RGBA
    data = (b"\x89PNG\r\n\x1a\n"
            + _chunk(b"IHDR", ihdr)
            + _chunk(b"IDAT", zlib.compress(raw, 9))
            + _chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    print(f"  {w}×{h} → {path}")

# ── Colour palette ─────────────────────────────────────────────────────────────

T    = (0,   0,   0,   0)    # transparent

# body / gear
B_MN = (56,  56,  68,  255)  # body main (dark blue-gray)
B_ED = (72,  72,  84,  255)  # body edge highlight
B_DK = (38,  38,  48,  255)  # body dark / shadow
B_GR = (48,  48,  60,  255)  # chest gear stripe

# head
H_MN = (66,  66,  78,  255)  # head main
H_HL = (82,  82,  94,  255)  # head top highlight
H_DK = (44,  44,  54,  255)  # head rim shadow

# sleeve + glove
SL_M = (52,  52,  64,  255)  # sleeve main
SL_D = (36,  36,  46,  255)  # sleeve edge/shadow
GL_M = (30,  28,  26,  255)  # glove main (dark brown-black)
GL_D = (20,  19,  18,  255)  # glove deep shadow

# boot
BT_M = (26,  26,  32,  255)  # boot main
BT_E = (40,  40,  48,  255)  # boot edge

# micro uzi colour palette (extracted from uploaded sprite)
UZ_M = (96,  96, 112,  255)  # main body colour
UZ_D = (64,  64,  80,  255)  # magazine / dark accent
UZ_L = (130,130, 144,  255)  # highlight / lighter part

# ── Player body parts ──────────────────────────────────────────────────────────

def make_body() -> tuple:
    """18 × 10 px  —  h:w ≈ 1:1.8 brick, top-down tactical silhouette."""
    W, H = 18, 10
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            if y == H - 1:                col = B_DK           # bottom shadow row
            elif y == 0:                   col = B_ED           # top edge highlight
            elif x == 0 or x == W - 1:    col = B_DK           # side shadows
            elif x in (8, 9):             col = B_GR           # centre chest-rig stripe
            else:                          col = B_MN
            row.append(col)
        rows.append(row)
    return W, H, rows


def make_head() -> tuple:
    """10 × 10 px  —  aliased hard-edged circle (no anti-aliasing)."""
    W, H = 10, 10
    cx, cy, r = 4.5, 4.5, 4.49
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            dx, dy = x - cx, y - cy
            dist = (dx * dx + dy * dy) ** 0.5
            if dist > r:
                row.append(T)
            elif dist > r - 1.0:
                row.append(H_DK)          # rim pixel
            elif dy < -1.5:
                row.append(H_HL)          # top-of-head highlight
            else:
                row.append(H_MN)
        rows.append(row)
    return W, H, rows


def make_upper_arm() -> tuple:
    """5 × 4 px  —  shoulder to elbow (sleeve only); pivot at top edge."""
    W, H = 5, 4
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            if x == 0 or x == W - 1 or y == 0:
                col = SL_D
            else:
                col = SL_M
            row.append(col)
        rows.append(row)
    return W, H, rows


def make_lower_arm() -> tuple:
    """5 × 4 px  —  elbow to hand (sleeve row + 3 glove rows); pivot at top edge."""
    W, H = 5, 4
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            if y == 0:
                col = SL_D if (x == 0 or x == W - 1) else SL_M
            else:
                gy = y - 1
                col = GL_D if (x == 0 or x == W - 1 or gy == 2) else GL_M
            row.append(col)
        rows.append(row)
    return W, H, rows


def make_foot() -> tuple:
    """5 × 4 px  —  single boot; used for both feet."""
    W, H = 5, 4
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            if y == 0 or x == 0 or x == W - 1:
                row.append(BT_E)
            else:
                row.append(BT_M)
        rows.append(row)
    return W, H, rows


# ── M1911 pistol sprite ────────────────────────────────────────────────────────
# 5 × 11 px, muzzle at top (row 0), grip base at bottom (row 10).
# Narrower barrel than the uzi; open trigger guard at row 6.

_M1911 = [
    #  0 1 2 3 4
    "..SS.",  # row  0 – barrel tip
    "..SS.",  # row  1 – barrel
    ".SSSS",  # row  2 – slide widens
    "LSSSS",  # row  3 – slide (L = left highlight)
    "LSSSS",  # row  4 – slide
    ".SSSS",  # row  5 – frame / trigger guard top
    ".SS..",  # row  6 – trigger guard (open on right)
    ".SSS.",  # row  7 – grip top
    ".SSS.",  # row  8 – grip
    ".SSS.",  # row  9 – grip
    "..SS.",  # row 10 – mag / grip base
]

def make_m1911() -> tuple:
    W, H = 5, len(_M1911)
    rows = []
    for row_str in _M1911:
        row = []
        for ch in row_str:
            if   ch == 'S': row.append(UZ_M)
            elif ch == 'L': row.append(UZ_L)
            elif ch == '*': row.append(UZ_D)
            else:           row.append(T)
        rows.append(row)
    return W, H, rows


# ── Micro Uzi weapon sprite ────────────────────────────────────────────────────
# Reconstructed from the uploaded pixel art (5 × 11 px).
# Orientation: muzzle at top (row 0), stock at bottom (row 10).

_UZI = [
    #  0 1 2 3 4
    "..SS.",  # row  0 – barrel tip / rear sights
    ".SSSS",  # row  1 – upper receiver
    ".SSSS",  # row  2 – upper receiver
    "SSSSS",  # row  3 – widest (grip area)
    "SSSSS",  # row  4 – widest (grip area)
    ".SSSS",  # row  5 – lower receiver
    ".SSS*",  # row  6 – magazine (* = dark accent)
    ".SSS*",  # row  7 – magazine
    ".SSSS",  # row  8 – body
    ".SSLL",  # row  9 – body lower (L = lighter finish)
    ".S..S",  # row 10 – stock / split end
]

def make_uzi() -> tuple:
    W, H = 5, len(_UZI)
    rows = []
    for row_str in _UZI:
        row = []
        for ch in row_str:
            if   ch == 'S': row.append(UZ_M)
            elif ch == '*': row.append(UZ_D)
            elif ch == 'L': row.append(UZ_L)
            else:           row.append(T)
        rows.append(row)
    return W, H, rows


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parts = [
        ("body",      make_body,      "assets/player/body.png"),
        ("head",      make_head,      "assets/player/head.png"),
        ("upper_arm", make_upper_arm, "assets/player/upper_arm.png"),
        ("lower_arm", make_lower_arm, "assets/player/lower_arm.png"),
        ("foot",      make_foot,      "assets/player/foot.png"),
        ("micro_uzi", make_uzi,       "assets/weapons/micro_uzi.png"),
        ("m1911",     make_m1911,     "assets/weapons/m1911.png"),
    ]
    for label, fn, rel in parts:
        W, H, rows = fn()
        save_png(os.path.join(base, rel), W, H, rows)
    print("Done — 6 sprite PNGs generated.")
    print("Player part sizes: body=18×10, head=10×10, arm=5×8, feet=11×4")
    print("Weapon: micro_uzi=5×11 (muzzle at top, stock at bottom)")
