#!/usr/bin/env python3
"""Generate safehouse_atlas.png — 9 tiles × 16×16 px, horizontal strip."""
import struct, zlib, os, sys

TILE  = 16
COUNT = 9
OUT   = os.path.join(os.path.dirname(__file__), "../assets/tiles/safehouse_atlas.png")

# ── PNG helpers ───────────────────────────────────────────────────────────────

def _chunk(name, data):
    body = name + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

def save_png(path, w, h, rows_rgb):
    raw = b""
    for row in rows_rgb:
        raw += b"\x00"
        for r, g, b in row:
            raw += bytes([r & 0xFF, g & 0xFF, b & 0xFF])
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    data = (b"\x89PNG\r\n\x1a\n"
            + _chunk(b"IHDR", ihdr)
            + _chunk(b"IDAT", zlib.compress(raw, 9))
            + _chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)

def rgb(h):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))

def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# ── Tile designs ──────────────────────────────────────────────────────────────
# Each function(x,y) → (r,g,b) for a 16×16 tile.

def tile_wall(x, y):
    mortar  = rgb("0f0e0d")
    stone_a = rgb("221f1c")
    stone_b = rgb("2c2824")
    stone_c = rgb("181614")

    band = y // 5           # which 5-row brick band
    in_mortar_h = (y % 5 == 4)
    v_offset = (band % 2) * 8
    in_mortar_v = ((x + v_offset) % 8 == 0)

    if in_mortar_h or in_mortar_v:
        return mortar
    bx = (x + v_offset) % 8
    by = y % 5
    if bx == 1 and by == 0:   return stone_c          # top-left shadow
    if by == 3:                return stone_c          # bottom shadow row
    if (bx * 3 + by * 7) % 11 == 0: return stone_b   # highlight fleck
    return stone_a

def tile_floor_entry(x, y):
    base  = rgb("16161a")
    dark  = rgb("111115")
    light = rgb("1d1d22")
    if x % 8 == 0 or y % 8 == 0:    return dark       # subtle grid seam
    if (x * 5 + y * 3) % 19 == 0:   return light      # wear spot
    return base

def tile_floor_living(x, y):
    base   = rgb("1f1309")
    grain1 = rgb("180f07")
    grain2 = rgb("261807")
    knot   = rgb("2e1c09")
    if y % 3 == 0:                   return grain1     # wood grain line
    if (x + y // 3) % 7 == 0:       return grain2     # darker grain
    if (x * 3 + y * 2) % 23 == 0:   return knot       # wood knot highlight
    return base

def tile_floor_workshop(x, y):
    base  = rgb("111520")
    line  = rgb("0d1019")
    rivet = rgb("1e2436")
    if x % 4 == 0 or y % 4 == 0: return line          # metal plate grid
    if x % 4 == 1 and y % 4 == 1: return rivet        # rivet highlight
    return base

def tile_floor_stash(x, y):
    base  = rgb("101b11")
    dark  = rgb("0c1509")
    light = rgb("15221a")
    if y % 6 == 5:                   return dark       # horizontal crack
    if (x * 7 + y * 5) % 13 == 0:   return light      # worn patch
    return base

def tile_floor_armory(x, y):
    base   = rgb("1e1108")
    stripe = rgb("16100a")
    rust   = rgb("2a1609")
    if x % 3 == 0:                   return stripe     # vertical metal stripe
    if (x + y * 4) % 17 == 0:       return rust       # rust spot
    return base

def tile_floor_planning(x, y):
    base  = rgb("0e1119")
    grid  = rgb("0a0d13")
    fiber = rgb("141822")
    if x % 3 == 0 and y % 3 == 0:   return grid       # carpet weave
    if (x * 2 + y) % 7 == 0:        return fiber      # fiber highlight
    return base

def tile_floor_range(x, y):
    base  = rgb("161718")
    crack = rgb("111213")
    worn  = rgb("1c1e20")
    if y % 8 == 7:                   return crack      # horizontal crack
    if (x * 11 + y * 7) % 31 == 0:  return worn       # worn patch
    return base

def tile_door_frame(x, y):
    base   = rgb("2a2624")
    metal  = rgb("3c3530")
    shadow = rgb("1f1d1a")
    if x == 0 or x == 15 or y == 0 or y == 15: return metal   # border trim
    if x == 1 or y == 1:            return shadow
    return base

TILE_FNS = [
    tile_wall, tile_floor_entry, tile_floor_living, tile_floor_workshop,
    tile_floor_stash, tile_floor_armory, tile_floor_planning,
    tile_floor_range, tile_door_frame,
]

# ── Build atlas ───────────────────────────────────────────────────────────────

def build_atlas():
    W = TILE * COUNT
    H = TILE
    rows = []
    for y in range(H):
        row = []
        for ti in range(COUNT):
            for x in range(TILE):
                row.append(TILE_FNS[ti](x, y))
        rows.append(row)
    return W, H, rows

if __name__ == "__main__":
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    W, H, rows = build_atlas()
    save_png(OUT, W, H, rows)
    print(f"Saved {W}×{H} atlas → {os.path.abspath(OUT)}")
    print(f"Tiles: 0=wall  1=entry  2=living  3=workshop  4=stash  "
          f"5=armory  6=planning  7=range  8=door_frame")
