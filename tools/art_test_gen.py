#!/usr/bin/env python3
"""Art test generator: draws every PNG used by scenes/art_test into art/test/.

Run:  python3 tools/art_test_gen.py

Everything is drawn from flat polygons at 4x supersampling (8 px per design unit),
downsampled to 2 texels per design unit (design unit = 1 px of the 1280x720 layout,
1.5 px at 1080p).  Rig parts / props are exported as TWO files:

  <name>.png    albedo, flat base colours + outline (actors / pickups only)
  <name>_h.png  data map for the shading shader (R = wide height, G = narrow height,
                B = 0 outside/outline, 128 inside, 255 emissive)

The shader derives the 3 tones (base / cold shadow / crisp highlight) from the height maps
and the *world* light direction (top-left), so shading stays consistent while parts rotate.
Decals / fx are plain flat PNGs.  layout.json carries pivots, sizes and glow points.
"""
import json
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "test")
SS = 4          # supersampling
PX = 2          # texels per design unit
S = SS * PX     # drawing px per unit
LAYOUT = {"parts": {}, "glows": {}, "meta": {}}

# ---------------------------------------------------------------- palette
INK = (14, 13, 12)
CH = (182, 138, 40)        # sickly orange-yellow chitin
CH_L = (202, 158, 52)
CH_D = (140, 100, 34)
JOINT = (52, 36, 22)
FLESH = (96, 54, 30)
LEG = (120, 90, 40)
PUST = (255, 150, 36)
EYE = (255, 84, 36)
GOO = (222, 112, 26)
YEL = (246, 204, 38)
YEL_D = (214, 164, 28)
ARM = (96, 100, 110)
ARM_D = (70, 74, 84)
ARM_L = (122, 126, 136)
BLUE = (70, 160, 255)
ROCK = (110, 106, 100)
ROCK_L = (122, 118, 111)
CONC = (100, 98, 94)


def rgb_i(c):
    return tuple(int(v) for v in c)


class Part:
    """Layered flat-shape drawing with height + emissive maps and optional outline."""

    def __init__(self, name, x0, y0, x1, y1, outline=True, ow=1.0, pad=1.6, sigw=3.2, sign=1.0):
        self.name, self.outline, self.ow = name, outline, ow
        pad = pad if outline else 0.5
        self.x0, self.y0 = x0 - pad, y0 - pad
        self.x1, self.y1 = x1 + pad, y1 + pad
        self.W = int(math.ceil((self.x1 - self.x0) * S))
        self.H = int(math.ceil((self.y1 - self.y0) * S))
        # round to multiple of SS
        self.W += (-self.W) % SS
        self.H += (-self.H) % SS
        self.alb = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        self.hgt = Image.new("L", (self.W, self.H), 0)
        self.emi = Image.new("L", (self.W, self.H), 0)
        self.sigw, self.sign = sigw, sign
        self.glows = []

    def P(self, pts):
        return [((x - self.x0) * S, (y - self.y0) * S) for x, y in pts]

    def _mask(self, fn):
        m = Image.new("L", (self.W, self.H), 0)
        fn(ImageDraw.Draw(m))
        return m

    def _apply(self, m, col, lift, emissive):
        self.alb.paste(Image.new("RGBA", (self.W, self.H), tuple(col) + (255,)), (0, 0), m)
        if emissive:
            self.emi.paste(255, (0, 0), m)
        else:
            self.emi.paste(0, (0, 0), m)
            self.hgt.paste(int(255 * lift), (0, 0), m)

    def poly(self, pts, col, lift=0.4, emissive=False):
        pts = self.P(pts)
        self._apply(self._mask(lambda d: d.polygon(pts, fill=255)), col, lift, emissive)

    def ellipse(self, cx, cy, rx, ry, col, lift=0.4, emissive=False):
        x0, y0 = self.P([(cx - rx, cy - ry)])[0]
        x1, y1 = self.P([(cx + rx, cy + ry)])[0]
        self._apply(self._mask(lambda d: d.ellipse([x0, y0, x1, y1], fill=255)), col, lift, emissive)

    def line(self, a, b, w, col, lift=0.4, emissive=False):
        a, b = self.P([a, b])
        self._apply(self._mask(lambda d: d.line([a, b], fill=255, width=max(1, int(w * S)))),
                    col, lift, emissive)

    def poly_line(self, pts, w, col, lift=0.2):
        pp = self.P(pts)

        def fn(d):
            d.line(pp, fill=255, width=max(1, int(w * S)), joint="curve")
        self._apply(self._mask(fn), col, lift, False)

    def bump(self, cx, cy, rx, ry, total=0.3, n=5, rot=0.0):
        """Adds a domed height (concentric ellipses, additive) so big bodies shade as volumes (3 tones)."""
        for i in range(n):
            f = 1.0 - i / n
            pts = []
            for a in range(28):
                th = a / 28 * 2 * math.pi
                x, y = rx * f * math.cos(th), ry * f * math.sin(th)
                pts.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
            m = self._mask(lambda d, q=self.P(pts): d.polygon(q, fill=255))
            add = Image.new("L", (self.W, self.H), 0)
            add.paste(int(255 * total / n), (0, 0), m)
            self.hgt = ImageChops.add(self.hgt, add)

    def glow(self, x, y, r, col):
        self.glows.append([round(x, 2), round(y, 2), round(r, 2), list(col)])

    def save(self):
        fw, fh = self.W // SS, self.H // SS
        alb = self.alb.resize((fw, fh), Image.BOX)
        hgt = self.hgt.resize((fw, fh), Image.BOX)
        emi = self.emi.resize((fw, fh), Image.BOX)
        a = alb.getchannel("A")
        inside = a.point(lambda v: 255 if v > 110 else 0)
        if self.outline:
            r = max(1, int(round(self.ow * PX)))
            dil = a.filter(ImageFilter.MaxFilter(2 * r + 1))
            dil = dil.filter(ImageFilter.GaussianBlur(0.5)).point(lambda v: min(255, int(v * 1.6)))
            # tint: near-black from average visible colour
            px = [p for p in alb.convert("RGBA").get_flattened_data() if p[3] > 200]
            n = max(1, len(px))
            avg = [sum(p[i] for p in px) / n for i in range(3)]
            oc = tuple(int(INK[i] * 0.55 + avg[i] * 0.16) for i in range(3))
            base = Image.new("RGBA", alb.size, oc + (255,))
            base.putalpha(dil)
            base.alpha_composite(alb)
            alb = base
            inside_full = a.point(lambda v: 255 if v > 110 else 0)
            inside = inside_full
        # data map
        wide = hgt.filter(ImageFilter.GaussianBlur(self.sigw))
        nar = hgt.filter(ImageFilter.GaussianBlur(self.sigw * 0.38))
        b = inside.point(lambda v: 128 if v else 0)
        b = ImageChops.lighter(b, emi.point(lambda v: 255 if v > 100 else 0))
        data = Image.merge("RGB", (wide, nar, b))
        alb.save(os.path.join(OUT, self.name + ".png"))
        data.save(os.path.join(OUT, self.name + "_h.png"))
        LAYOUT["parts"][self.name] = {
            "w": fw, "h": fh, "ox": round(self.x0, 3), "oy": round(self.y0, 3)}
        if self.glows:
            LAYOUT["glows"][self.name] = self.glows


def save_rgba(img, name):
    img.save(os.path.join(OUT, name + ".png"))
    LAYOUT["parts"][name] = {"w": img.width, "h": img.height, "ox": -img.width / PX / 2,
                              "oy": -img.height / PX / 2}


def mul(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def sc(pts, kx, ky=None):
    ky = kx if ky is None else ky
    return [(x * kx, y * ky) for x, y in pts]


def mir(pts):
    return [(x, -y) for x, y in pts]


# ================================================================== BUGS
def bug_parts(prefix, k, heavy, dmg=0, only=None):
    """Draw all parts of a Terminid.  k = scale, heavy = armoured Charger variant."""
    wk = 1.18 if heavy else 1.0                  # width multiplier
    thick = (k ** 0.6)
    chit = CH if not heavy else (164, 122, 36)
    chit_l = CH_L if not heavy else (184, 140, 46)
    plate = (186, 142, 42) if not heavy else (146, 102, 34)
    plate_l = (206, 162, 54) if not heavy else (172, 126, 44)
    ow = 1.0
    want = lambda n: only is None or n in only

    # ------------------------------------------------ thorax
    if want("thorax"):
        T = [(9, 0), (6, -7), (0, -9.5), (-7, -7), (-9, 0), (-7, 7), (0, 9.5), (6, 7)]
        T = [(x * k, y * k * wk) for x, y in T]
        p = Part(f"{prefix}_thorax", -12 * k, -15 * k * wk, 12 * k, 15 * k * wk, ow=ow, sigw=3.2 * min(2.2, k ** 0.5))
        p.poly(T, chit, 0.40)
        # shoulder spikes
        for s in (-1, 1):
            sp = [(3, 8), (-1, 14.5 if heavy else 13), (-4.5, 7)]
            p.poly([(x * k, s * y * k * wk) for x, y in sp], plate, 0.58)
            sp2 = [(7, 6.5), (6, 11), (3, 7)]
            p.poly([(x * k, s * y * k * wk) for x, y in sp2], plate_l, 0.62)
        # dorsal plate
        dp = [(7, 0), (3, -5.2), (-5, -6.2), (-8, 0), (-5, 6.2), (3, 5.2)]
        p.poly([(x * k, y * k * wk) for x, y in dp], plate_l if not heavy else plate, 0.66)
        if heavy:
            # layered armour plates
            for i, (x0, w) in enumerate([(5.5, 6.6), (0.5, 7.4), (-4.5, 6.8)]):
                pl = [(x0 + 3.2, -w), (x0 - 2.6, -w - 0.7), (x0 - 2.6, w + 0.7), (x0 + 3.2, w)]
                p.poly([(x * k, y * k) for x, y in pl], chit_l if i % 2 == 0 else plate_l, 0.74 + 0.04 * i)
                p.line((( x0 - 2.7) * k, -w * k * 0.9), ((x0 - 2.7) * k, w * k * 0.9), 0.55 * thick, JOINT, 0.28)
        else:
            p.line((-2.5 * k, -6.5 * k), (-2.5 * k, 6.5 * k), 0.8, JOINT, 0.28)
        # ridge spikes
        for x in ((4.5, 0.5, -3.5) if not heavy else ()):
            sp = [(x + 2.2, 0), (x - 1.6, -2.2), (x - 1.6, 2.2)]
            p.poly([(a * k, b * k) for a, b in sp], (232, 200, 100), 0.88)
        if heavy:
            # one long dorsal spine pointing back instead of the ridge row
            p.poly([(k * 1.0, -1.6 * k), (k * -6.5, 0), (k * 1.0, 1.6 * k)], (214, 176, 96), 0.9)
        # pustules + glow
        for (x, y) in [(-2, 3.6), (-5, -3.2), (2, -2.6)] if not heavy else [(-1.5, 3.2), (-5.5, -2.8)]:
            p.ellipse(x * k, y * k, 0.8 * thick, 0.8 * thick, PUST, emissive=True)
            p.glow(x * k, y * k, 2.4 * thick, PUST)
        if dmg >= 1:
            # chipped plate: exposed flesh and cracks
            ch = [(5.6, -2.0), (1.6, -5.0), (-1.4, -3.6), (-0.6, -0.6), (3.2, 0.6)]
            p.poly([(x * k, y * k) for x, y in ch], FLESH, 0.26)
            p.poly([(x * k * 0.92, y * k * 0.92) for x, y in [(4.5, -2.2), (1.8, -4.0), (0.2, -3.0), (2.6, -1.0)]], (200, 90, 24), 0.2, emissive=True)
            p.poly_line([(-2 * k, 5.8 * k), (-4 * k, 3.5 * k), (-3.2 * k, 1.5 * k), (-5.5 * k, -0.5 * k)], 0.5 * thick, INK, 0.1)
            p.poly_line([(3.5 * k, 3.0 * k), (2 * k, 5 * k)], 0.45 * thick, INK, 0.1)
        if dmg >= 2:
            ch = [(-3.2, 1.8), (-6.6, 3.0), (-7.2, 6.0), (-4.2, 6.6), (-1.8, 4.4)]
            p.poly([(x * k, y * k) for x, y in ch], FLESH, 0.24)
            p.poly([(x * k, y * k) for x, y in [(-3.6, 2.8), (-5.6, 3.6), (-5.2, 5.2), (-3.8, 4.6)]], (210, 96, 24), 0.2, emissive=True)
            p.poly_line([(5 * k, -6 * k), (3 * k, -3.6 * k), (4 * k, -1.6 * k)], 0.5 * thick, INK, 0.1)
        if heavy:
            p.bump(0, 0, 9.5 * k, 9.5 * k * wk, 0.42, 6)
            p.bump(-1 * k, 0, 6 * k, 7 * k * wk, 0.22, 4)
        p.save()

    # ------------------------------------------------ head (pivot at neck)
    if want("head"):
        hk = k
        Hh = [(0, -5), (5, -6), (10, -3.5), (13, 0), (10, 3.5), (5, 6), (0, 5)]
        if heavy:
            Hh = [(0, -7.5), (6, -8), (12, -5), (15, 0), (12, 5), (6, 8), (0, 7.5)]
        p = Part(f"{prefix}_head", -2 * hk, -15 * hk * (1.15 if heavy else 1), 18 * hk, 15 * hk * (1.15 if heavy else 1),
                 ow=ow, sigw=3.0 * min(2.0, hk ** 0.5))
        p.poly(sc(Hh, hk), chit if not heavy else (150, 108, 36), 0.40)
        for s in (-1, 1):
            if not heavy:
                br = [(4, s * 6), (8.5, s * 10.5), (9.5, s * 4)]
                p.poly(sc(br, hk), plate, 0.6)
            else:
                # swept horns
                hr = [(3, s * 7.5), (-1, s * 15), (9, s * 11), (11, s * 6)]
                p.poly(sc(hr, hk), (214, 184, 110), 0.68)
                hr2 = [(11, s * 4.8), (17.5, s * 8.5), (15, s * 3.2)]
                p.poly(sc(hr2, hk), (206, 172, 100), 0.7)
        if heavy:
            # heavy head plates: shield + two brow slabs
            sh = [(15.5, 0), (10, -7.2), (2, -7.0), (-0.6, 0), (2, 7.0), (10, 7.2)]
            pl = (176, 132, 46)
            p.poly(sc(sh, hk), pl, 0.72)
            if dmg < 2:
                p.poly(sc([(14, 0), (9.6, -4.2), (3, -4.2), (1.6, 0), (3, 4.2), (9.6, 4.2)], hk), (196, 154, 58), 0.88)
            for s in (-1, 1):
                if dmg < 1 or s > 0:
                    p.poly(sc([(11, s * 7.2), (6.4, s * 8.4), (3, s * 6.2), (7, s * 5.2)], hk), (150, 106, 34), 0.8)
            p.line((3 * hk, -6.6 * hk), (3 * hk, 6.6 * hk), 0.7 * thick, JOINT, 0.3)
            p.line((8.2 * hk, -5.6 * hk), (8.2 * hk, 5.6 * hk), 0.6 * thick, JOINT, 0.3)
        else:
            p.poly(sc([(11.2, 0), (6, -3.4), (1, -3), (1, 3), (6, 3.4)], hk), plate_l, 0.7)
        # eyes (small, glowing)
        for s in (-1, 1):
            ex, ey = (9.6, s * 3.0) if not heavy else (12.2, s * 3.4)
            r = 0.62 * (thick if heavy else 1.0) * (1.0 if not heavy else 0.7)
            p.ellipse(ex * hk, ey * hk, r, r, EYE, emissive=True)
            p.glow(ex * hk, ey * hk, 2.6 * r + 0.8, EYE)
        if dmg >= 1:
            ck = [(14.5, -2), (11, -1), (9, -3.6), (6, -2.6), (4, -4.4)]
            p.poly_line(sc(ck, hk), 0.55 * thick, INK, 0.12)
            p.poly_line(sc([(12, 4.8), (9.5, 3.2), (8.2, 4.8), (5.5, 3.6)], hk), 0.5 * thick, INK, 0.12)
            p.poly(sc([(7, -4.8), (4.6, -6), (2.8, -4.6), (4.8, -3.2)], hk), FLESH, 0.24)
        if dmg >= 2:
            p.poly(sc([(15, 2.2), (12, 1.0), (10.2, 3.4), (12.4, 5.4)], hk), FLESH, 0.24)
            p.poly(sc([(14, 2.6), (12.2, 1.8), (11.4, 3.4), (12.6, 4.4)], hk), (220, 100, 24), 0.2, emissive=True)
            p.poly_line(sc([(4, 6.4), (6, 4.4), (5, 2.4), (7.5, 0.8)], hk), 0.6 * thick, INK, 0.1)
        if heavy:
            p.bump(7.5 * hk, 0, 8 * hk, 7.5 * hk, 0.34, 5)
        p.save()

    # ------------------------------------------------ mandible: curved tapering pincer/tusk (drawn for the +y side,
    # curving inward toward the midline; the rig mirrors it for the other side)
    if want("mand"):
        mk = k * (1.25 if heavy else 1.35)
        Lm = 15.5 if heavy else 14.0
        w0 = 3.0 if heavy else 2.2
        C = 0.34 * Lm if heavy else 0.30 * Lm
        def cl(sv):
            return (Lm * sv, -C * sv ** 2.2)
        def wd(sv):
            return w0 * (1.0 - sv) ** 0.85 + 0.12
        ns = 14
        up, lo = [], []
        for i in range(ns + 1):
            sv = i / ns
            x, y = cl(sv)
            up.append((x, y - wd(sv)))
            lo.append((x, y + wd(sv)))
        outline_pts = up + lo[::-1]
        p = Part(f"{prefix}_mand", -2.5 * mk, -(C + w0 + 2) * mk, (Lm + 2) * mk, (w0 + 2.5) * mk, ow=ow)
        body = (206, 168, 70) if not heavy else (206, 178, 108)
        p.poly(sc(outline_pts, mk), body, 0.46)
        # raised ridge along the spine of the tusk
        ridge = [(Lm * sv, cl(sv)[1] - wd(sv) * 0.25) for sv in [i / ns for i in range(0, ns - 2)]]
        ridge += [(Lm * sv, cl(sv)[1] + wd(sv) * 0.2) for sv in [i / ns for i in range(ns - 3, -1, -1)]]
        p.poly(sc(ridge, mk), (232, 206, 130) if heavy else (226, 192, 96), 0.78)
        # two small serrations on the inner edge (insect pincer, not a crab claw)
        for sv in (0.42, 0.62):
            x, y = cl(sv)
            y2 = y - wd(sv)
            p.poly(sc([(x - 1.2, y2 + 0.2), (x + 0.5, y2 - 1.9), (x + 1.5, y2 + 0.2)], mk), (240, 222, 164), 0.85)
        p.line((0.6 * mk, 0), (4.0 * mk, -0.4 * mk), 0.5 * thick, JOINT, 0.3)
        if heavy:
            p.bump(Lm * 0.3 * mk, -C * 0.09 * mk, 4.5 * mk, w0 * 0.6 * mk, 0.25, 4)
        p.save()

    # ------------------------------------------------ antenna (pivot at base, whips toward +x)
    if want("ant"):
        La = (13.5 if not heavy else 20.0) * k
        ta = (0.55 if not heavy else 0.8) * thick
        pts = [(La * f, -0.10 * La * math.sin(f * 2.4) - 0.04 * La * f * f) for f in [i / 8 for i in range(9)]]
        p = Part(f"{prefix}_ant", -ta * 2, -0.2 * La - ta * 2, La + ta * 2, 0.1 * La + ta * 2, ow=0.8, pad=1.2)
        for i in range(8):
            wv = ta * (1.0 - 0.72 * i / 8)
            p.line(pts[i], pts[i + 1], wv * 2, (118, 88, 40), 0.5)
        p.ellipse(0, 0, ta * 1.3, ta * 1.3, JOINT, 0.3)
        p.save()

    # ------------------------------------------------ abdomen (pivot at front; extends -x)
    if want("abd"):
        n = 5 if heavy else 4
        L = 26.0 if heavy else 22.0
        ws = ([7.5, 9.0, 9.2, 7.4, 5.0, 2.0] if heavy else [6.2, 7.4, 6.6, 4.6, 2.0])
        ak = k
        p = Part(f"{prefix}_abd", -(L + 7) * ak, -11.5 * ak, 1 * ak, 11.5 * ak, ow=ow, sigw=3.0 * min(2.2, k ** 0.5))
        step = L / n
        for i in range(n):
            x0, x1 = -i * step, -(i + 1) * step
            w0, w1 = ws[i], ws[i + 1]
            xm, wm = (x0 + x1) / 2, (w0 + w1) / 2 * 1.0 + (1.8 if heavy else 1.3)
            seg = [(x0, -w0), (xm, -wm), (x1, -w1), (x1, w1), (xm, wm), (x0, w0)]
            col = chit if i % 2 == 0 else chit_l
            if heavy:
                col = (172, 128, 38) if i % 2 == 0 else (190, 146, 48)
            p.poly(sc(seg, ak), col, 0.42)
            # dorsal plate on the segment
            dp = [(x0 - 0.5, -w0 * 0.62), (xm, -wm * 0.62), (x1 + 0.9, -w1 * 0.6), (x1 + 0.9, w1 * 0.6), (xm, wm * 0.62), (x0 - 0.5, w0 * 0.62)]
            p.poly(sc(dp, ak), plate_l if i % 2 == 0 else plate, 0.62)
            # side spikes
            for s in (-1, 1):
                sp = [(xm + 1.2, s * (wm - 0.3)), (xm - 1.4, s * (wm + (3.8 if heavy else 3.0))), (xm - 2.2, s * (wm - 0.6))]
                p.poly(sc(sp, ak), (224, 188, 100), 0.7)
            # joint
            p.line((x1 * ak, -w1 * ak * 0.95), (x1 * ak, w1 * ak * 0.95), 0.9 * thick, JOINT, 0.22)
            # pustule on the midline
            if i in (0, 2) or (heavy and i == 3):
                r = (0.95 if i == 0 else 0.75) * thick
                p.ellipse(((x0 + x1) / 2 - 0.2) * ak, (1.8 if i % 2 == 0 else -1.8) * ak * 0.9, r, r, PUST, emissive=True)
                p.glow(((x0 + x1) / 2 - 0.2) * ak, (1.8 if i % 2 == 0 else -1.8) * ak * 0.9, 2.4 * r + 0.6, PUST)
        if heavy:
            for i in range(n):
                xm = -(i + 0.5) * step * ak
                p.bump(xm, 0, step * 0.62 * ak, (ws[i] + ws[i + 1]) / 2 * ak * 1.25, 0.34, 4)
        # stinger
        xe = -L
        st = [(xe + 0.5, -ws[n] * 1.4), (xe - 7.0, 0), (xe + 0.5, ws[n] * 1.4)]
        p.poly(sc(st, ak), (122, 84, 38), 0.5)
        p.poly(sc([(xe - 2.5, -0.9), (xe - 7.0, 0), (xe - 2.5, 0.9)], ak), (236, 214, 150), 0.9)
        p.save()

    # ------------------------------------------------ legs
    if want("femur"):
        L1 = (10.0 if not heavy else 11.0) * k
        t = (1.15 if not heavy else 3.0) * thick
        p = Part(f"{prefix}_femur", -t * 1.2, -t * 1.7, L1 + t * 1.2, t * 1.7, ow=0.9)
        fe = [(0, -t), (L1 * 0.35, -t * 1.35), (L1, -t * 0.7), (L1, t * 0.7), (L1 * 0.35, t * 1.35), (0, t)]
        p.poly(fe, LEG, 0.5)
        p.poly([(L1 * 0.25, -t * 0.4), (L1 * 0.8, -t * 0.3), (L1 * 0.8, t * 0.3), (L1 * 0.25, t * 0.4)], (160, 124, 56), 0.7)
        p.ellipse(L1, 0, t * 0.85, t * 0.85, JOINT, 0.25)
        p.ellipse(0, 0, t * 0.9, t * 0.9, JOINT, 0.25)
        p.save()
    if want("tibia"):
        L2 = (14.0 if not heavy else 15.0) * k
        t = (1.0 if not heavy else 2.4) * thick
        p = Part(f"{prefix}_tibia", -t * 1.2, -t * 2.6, L2 + t * 1.2, t * 2.6, ow=0.9)
        tip = 0.0 if not heavy else 0.32
        ti = [(0, -t * 0.8), (L2 * 0.55, -t * 0.6), (L2, -t * tip), (L2, t * tip), (L2 * 0.55, t * 0.6), (0, t * 0.8)]
        p.poly(ti, LEG, 0.5)
        for (x, s) in [(0.35, 1), (0.62, -1)]:
            p.poly([(L2 * x, s * t * 0.5), (L2 * (x - 0.1), s * t * 2.2), (L2 * (x + 0.07), s * t * 0.5)], (200, 168, 96), 0.7)
        p.poly([(L2 * 0.8, -t * 0.25), (L2 + t * 0.4, 0), (L2 * 0.8, t * 0.25)], (236, 214, 150), 0.9)
        p.ellipse(0, 0, t * 0.9, t * 0.9, JOINT, 0.25)
        p.save()
    LAYOUT["meta"][prefix] = {
        "k": k, "heavy": heavy,
        "L1": (10.0 if not heavy else 11.0) * k, "L2": (14.0 if not heavy else 15.0) * k,
        "hips": [[5 * k, 7.8 * k * wk], [-0.5 * k, 8.6 * k * wk], [-6 * k, 7.4 * k * wk]],
        "neck": [8.6 * k, 0], "abd": [-8.4 * k, 0],
        "ant": [(10.5 if not heavy else 12.5) * k, 2.2 * k],
        "mand": [[ (11.5 if heavy else 9.5) * k, -3.2 * k * (1.1 if heavy else 1)]],
        "mand_len": 17.5 * k * (1.25 if heavy else 1.35),
        "eye_head": [[ (12.2 if heavy else 9.6) * k, 3.0 * k]],
    }


# ================================================================== PLAYER
def player_parts():
    ow = 1.0
    # torso
    p = Part("pl_torso", -18, -20, 11, 20, ow=ow)
    sh = [(8, -7), (5, -13), (-2, -16), (-8, -12), (-10, -6), (-10, 6), (-8, 12), (-2, 16), (5, 13), (8, 7)]
    p.poly(sh, ARM, 0.4)
    # backpack
    p.poly([(-9, -9), (-15.5, -8), (-16.5, 8), (-9, 9)], ARM_D, 0.6)
    p.poly([(-11, -6), (-14.5, -5.5), (-14.5, 5.5), (-11, 6)], (84, 88, 98), 0.78)
    for s in (-1, 1):
        p.ellipse(-13.2, s * 3.4, 0.9, 0.9, BLUE, emissive=True)
        p.glow(-13.2, s * 3.4, 2.4, BLUE)
    # chest plate
    p.poly([(7.5, 0), (4.5, -8.5), (-5, -9.5), (-7, 0), (-5, 9.5), (4.5, 8.5)], ARM_L, 0.66)
    p.poly([(5.5, 0), (2.5, -3.2), (-1, 0), (2.5, 3.2)], YEL, 0.85)  # emblem
    # pauldrons
    for s in (-1, 1):
        p.ellipse(-0.5, s * 14.2, 7.2, 5.6, YEL, 0.74)
        p.poly([(-6, s * 12.8), (-3, s * 12.0), (-3, s * 16.0), (-6, s * 15.4)], (70, 74, 84), 0.84)
    p.save()
    # head / helmet
    p = Part("pl_head", -9, -9, 9, 9, ow=ow)
    p.ellipse(0, 0, 8, 7.4, (88, 92, 102), 0.5)
    p.poly([(-7.4, -1.5), (6, -1.5), (6, 1.5), (-7.4, 1.5)], YEL, 0.74)
    p.poly([(5.2, -4.6), (8.2, -3.0), (8.2, 3.0), (5.2, 4.6)], (24, 28, 36), 0.3)
    p.ellipse(7.0, 2.0, 0.7, 0.7, BLUE, emissive=True)
    p.glow(7.0, 2.0, 2.2, BLUE)
    p.save()
    # gun + arms (pivot at torso centre)
    p = Part("pl_gun", -2, -17, 43, 12, ow=ow)
    # arms
    p.line((0, -13.5), (16, -3.2), 6.2, ARM_D, 0.5)
    p.line((0, 13.5), (11, 4.0), 6.2, ARM_D, 0.5)
    p.line((0, -13.5), (7, -9.5), 6.8, YEL_D, 0.6)
    p.line((0, 13.5), (5.5, 9.6), 6.8, YEL_D, 0.6)
    # rifle
    p.poly([(0, -2.3), (8, -3.0), (8, 3.0), (0, 2.3)], (62, 66, 74), 0.5)
    p.poly([(8, -2.6), (26, -2.6), (26, 2.6), (8, 2.6)], (86, 90, 100), 0.62)
    p.poly([(15, -1.2), (25, -1.2), (25, 1.2), (15, 1.2)], (122, 126, 136), 0.8)
    p.poly([(26, -1.1), (40, -1.1), (40, 1.1), (26, 1.1)], (58, 62, 70), 0.55)
    p.poly([(38.5, -1.9), (42, -1.9), (42, 1.9), (38.5, 1.9)], (46, 50, 58), 0.7)
    p.poly([(14, 2.6), (19, 2.6), (19, 7.0), (14, 7.0)], YEL, 0.7)
    p.ellipse(19, 0, 1.6, 1.1, BLUE, 0.9, emissive=True)
    p.glow(19, 0, 2.0, BLUE)
    p.ellipse(16, -3.2, 3.0, 3.0, ARM_L, 0.7)
    p.ellipse(11, 4.0, 3.0, 3.0, ARM_L, 0.7)
    p.save()
    # cape (pivot at neck)
    p = Part("pl_cape", -34, -16, 1, 16, ow=ow, sigw=2.6)
    cape = [(0, -12), (-12, -15), (-26, -13), (-31, -8.5), (-28, -5), (-33, -1), (-29, 2.2), (-33, 6), (-28, 9.5), (-25, 14), (-12, 15), (0, 12)]
    p.poly(cape, (196, 152, 28), 0.36)
    p.poly([(-2, -9), (-14, -11), (-27, -9), (-29, -5), (-14, -4), (-2, -3)], (232, 186, 40), 0.52)
    p.poly([(-2, 3), (-14, 4), (-28, 4.4), (-27, 9.6), (-14, 11.5), (-2, 9)], (232, 186, 40), 0.52)
    p.poly_line([(-2, 0), (-14, -0.4), (-30, 0.4)], 0.8, (150, 110, 24), 0.2)
    p.save()
    # boot
    p = Part("pl_boot", -7, -5, 7, 5, ow=0.9)
    p.ellipse(0, 0, 6, 4, (74, 78, 88), 0.5)
    p.poly([(2, -3), (6, -2), (6, 2), (2, 3)], YEL_D, 0.65)
    p.save()
    # grenade
    p = Part("grenade", -5, -5, 5, 5, ow=0.8)
    p.ellipse(0, 0, 4.2, 3.6, (80, 84, 92), 0.5)
    p.poly([(-4, -1.2), (4, -1.2), (4, 1.2), (-4, 1.2)], YEL, 0.7)
    p.ellipse(2.8, -3.0, 1.3, 1.0, (130, 134, 144), 0.8)
    p.save()
    LAYOUT["meta"]["player"] = {"muzzle": [42, 0], "shoulder_y": 14, "neck": [-8, 0]}


# ================================================================== PICKUPS
def pickups():
    p = Part("pickup_crate", -11, -8.5, 11, 8.5, ow=1.0)
    p.poly([(-10, -7.5), (10, -7.5), (10, 7.5), (-10, 7.5)], (150, 156, 168), 0.5)
    p.poly([(-8.2, -5.8), (8.2, -5.8), (8.2, 5.8), (-8.2, 5.8)], (176, 182, 194), 0.66)
    p.poly([(-2.5, -7.5), (2.5, -7.5), (2.5, 7.5), (-2.5, 7.5)], YEL, 0.78)
    p.poly([(-10, -1.5), (10, -1.5), (10, 1.5), (-10, 1.5)], YEL_D, 0.7)
    p.ellipse(6.0, -3.6, 1.0, 1.0, BLUE, emissive=True)
    p.glow(6.0, -3.6, 2.4, BLUE)
    p.save()
    p = Part("pickup_stim", -6, -3.5, 6, 3.5, ow=0.9)
    p.poly([(-5, -2.5), (3, -2.5), (5.5, 0), (3, 2.5), (-5, 2.5)], (190, 214, 240), 0.55)
    p.poly([(-4.4, -1.2), (2.6, -1.2), (2.6, 1.2), (-4.4, 1.2)], BLUE, 0.7, emissive=True)
    p.glow(0, 0, 3.4, BLUE)
    p.save()


# ================================================================== PROPS
def rock(name, r, seed, n=9, squash=0.85):
    rnd = random.Random(seed)
    ang0 = rnd.uniform(0, 6.28)
    pts = []
    for i in range(n):
        a = ang0 + i * 2 * math.pi / n + rnd.uniform(-0.18, 0.18)
        rr = r * rnd.uniform(0.78, 1.12)
        pts.append((math.cos(a) * rr, math.sin(a) * rr * squash))
    p = Part(name, -r * 1.2, -r * 1.2, r * 1.2, r * 1.2, outline=False, sigw=3.0 + r * 0.05)
    p.poly(pts, ROCK, 0.36)
    for f, off, lift, col in [(0.78, (-0.10, -0.10), 0.62, ROCK), (0.5, (-0.17, -0.17), 0.8, ROCK_L), (0.26, (-0.2, -0.2), 0.95, ROCK_L)]:
        q = [((x * f) + off[0] * r, (y * f) + off[1] * r) for x, y in pts]
        # break the facet a bit
        q = [(x + rnd.uniform(-0.05, 0.05) * r, y + rnd.uniform(-0.05, 0.05) * r) for x, y in q]
        p.poly(q, col, lift)
    # cracks
    for _ in range(2):
        a = rnd.uniform(0, 6.28)
        p.poly_line([(math.cos(a) * r * 0.1, math.sin(a) * r * 0.1),
                     (math.cos(a + 0.2) * r * 0.5, math.sin(a + 0.2) * r * 0.45),
                     (math.cos(a - 0.1) * r * 0.85, math.sin(a - 0.1) * r * 0.7)], 0.5, (66, 66, 70), 0.3)
    p.save()


def wall(name, w, h, seed, notch=True, ell=False):
    rnd = random.Random(seed)
    p = Part(name, -w / 2, -h / 2 - (w * 0.2 if ell else 0), w / 2, h / 2 + (w * 0.2 if ell else 0), outline=False, sigw=3.4)
    base = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    if notch:
        base = [(-w / 2, -h / 2), (-w * 0.1, -h / 2), (-w * 0.04, -h * 0.3), (w * 0.08, -h / 2), (w / 2, -h / 2),
                (w / 2 - 4, 0), (w / 2, h / 2), (w * 0.2, h / 2), (w * 0.12, h * 0.25), (-w * 0.05, h / 2), (-w / 2, h / 2), (-w / 2 + 3, 0)]
    p.poly(base, CONC, 0.45)
    cap = [(x * 0.9 + 0, y * 0.62) for x, y in base]
    p.poly(cap, (112, 110, 105), 0.7)
    if ell:
        p.poly([(-h / 2, -h / 2), (h / 2, -h / 2), (h / 2, w * 0.2 + h / 2), (-h / 2, w * 0.2 + h / 2)], CONC, 0.45)
        p.poly([(-h * 0.36, -h * 0.3), (h * 0.36, -h * 0.3), (h * 0.36, w * 0.2 + h * 0.3), (-h * 0.36, w * 0.2 + h * 0.3)], (112, 110, 105), 0.7)
    # rubble + cracks
    for _ in range(3):
        x = rnd.uniform(-w * 0.4, w * 0.4)
        p.poly_line([(x, -h * 0.4), (x + rnd.uniform(-2, 2), -h * 0.05), (x + rnd.uniform(-3, 3), h * 0.35)], 0.5, (62, 62, 66), 0.3)
    p.save()


def debris(name, r, seed):
    rnd = random.Random(seed)
    n = rnd.choice([5, 6, 7])
    pts = []
    for i in range(n):
        a = i * 2 * math.pi / n + rnd.uniform(-0.3, 0.3)
        rr = r * rnd.uniform(0.6, 1.1)
        pts.append((math.cos(a) * rr, math.sin(a) * rr * rnd.uniform(0.6, 1.0)))
    p = Part(name, -r * 1.3, -r * 1.3, r * 1.3, r * 1.3, outline=False, sigw=1.6)
    p.poly(pts, (98, 95, 90), 0.5)
    p.poly([(x * 0.55 - r * 0.1, y * 0.55 - r * 0.1) for x, y in pts], (108, 105, 99), 0.85)
    p.save()


# ================================================================== GROUND / DECALS
def ground_tile(size_units=512, seed=3, name="ground_tile"):
    rnd = random.Random(seed)
    W = size_units * PX
    SSG = 2
    Wd = W * SSG
    base = (70, 67, 62)
    img = Image.new("RGB", (Wd, Wd), base)
    d = ImageDraw.Draw(img)

    def wrapdraw(pts, col):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for dx in (-Wd, 0, Wd):
            for dy in (-Wd, 0, Wd):
                if max(xs) + dx < 0 or min(xs) + dx > Wd or max(ys) + dy < 0 or min(ys) + dy > Wd:
                    continue
                d.polygon([(x + dx, y + dy) for x, y in pts], fill=col)

    def blob(cx, cy, r, col, n=10, el=1.0, rot=0.0):
        pts = []
        for i in range(n):
            a = i * 2 * math.pi / n + rnd.uniform(-0.25, 0.25)
            rr = r * rnd.uniform(0.7, 1.15)
            x, y = math.cos(a) * rr, math.sin(a) * rr * el
            pts.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
        wrapdraw(pts, col)

    # big flat tonal patches (low contrast, crisp edges)
    for _ in range(26):
        v = rnd.choice([(66, 64, 60), (68, 66, 61), (72, 69, 63), (72, 69, 64), (65, 64, 63)])
        blob(rnd.uniform(0, Wd), rnd.uniform(0, Wd), rnd.uniform(90, 230) * SSG, v, n=11, el=rnd.uniform(0.45, 0.9), rot=rnd.uniform(0, 3.14))
    # wind-swept ash streaks (pale)
    for _ in range(46):
        blob(rnd.uniform(0, Wd), rnd.uniform(0, Wd), rnd.uniform(26, 80) * SSG, rnd.choice([(73, 70, 65), (74, 71, 66)]), n=8, el=rnd.uniform(0.12, 0.25), rot=rnd.uniform(-0.15, 0.15) + 0.3)
    # cold dark hollows
    for _ in range(18):
        blob(rnd.uniform(0, Wd), rnd.uniform(0, Wd), rnd.uniform(20, 60) * SSG, (63, 62, 62), n=9, el=rnd.uniform(0.5, 0.9), rot=rnd.uniform(0, 3.14))
    # cracks
    for _ in range(14):
        x, y = rnd.uniform(0, Wd), rnd.uniform(0, Wd)
        a = rnd.uniform(0, 6.28)
        pts = [(x, y)]
        for _ in range(rnd.randint(3, 6)):
            a += rnd.uniform(-0.7, 0.7)
            x += math.cos(a) * rnd.uniform(24, 60) * SSG
            y += math.sin(a) * rnd.uniform(24, 60) * SSG
            pts.append((x, y))
        for dx in (-Wd, 0, Wd):
            for dy in (-Wd, 0, Wd):
                d.line([(px + dx, py + dy) for px, py in pts], fill=(58, 57, 57), width=2 * SSG, joint="curve")
    # pebbles with tiny cast shadow
    for _ in range(420):
        x, y = rnd.uniform(0, Wd), rnd.uniform(0, Wd)
        r = rnd.uniform(1.6, 4.6) * SSG
        blob(x + r * 0.55, y + r * 0.55, r, (52, 52, 55), n=6)
        blob(x, y, r, rnd.choice([(88, 85, 79), (92, 89, 83), (82, 80, 76)]), n=6)
        blob(x - r * 0.25, y - r * 0.25, r * 0.4, (108, 105, 98), n=5)
    img = img.resize((W, W), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"))
    LAYOUT["meta"][name] = {"size_units": size_units}


def goo_splat(name, r, seed, lobes=9, droplets=8, big=False):
    rnd = random.Random(seed)
    S2 = 4
    R = int(r * 1.5)
    W = R * 2 * PX
    img = Image.new("RGBA", (W * S2, W * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = W * S2 / 2
    u = PX * S2

    def blobpts(cx, cy, rad, n):
        pts = []
        for i in range(n):
            a = i * 2 * math.pi / n
            rr = rad * rnd.uniform(0.62, 1.2) * (1.0 if i % 2 else 1.18)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        return pts
    main = blobpts(c, c, r * u, lobes * 2)
    # spikes / streaks
    for i in range(lobes if not big else 5):
        a = rnd.uniform(0, 6.28)
        ln = r * u * rnd.uniform(1.1, 1.45)
        w = r * u * rnd.uniform(0.05, 0.12)
        d.polygon([(c + math.cos(a + 1.57) * w, c + math.sin(a + 1.57) * w), (c + math.cos(a) * ln, c + math.sin(a) * ln), (c - math.cos(a + 1.57) * w, c - math.sin(a + 1.57) * w)], fill=(120, 54, 16, 235))
    d.polygon([(x + 1.2 * u, y + 1.4 * u) for x, y in main], fill=(86, 40, 14, 235))     # shadow tone, bottom-right
    d.polygon(main, fill=(206, 104, 24, 240))
    inner = [(c + (x - c) * 0.62 - 0.1 * r * u, c + (y - c) * 0.62 - 0.1 * r * u) for x, y in main]
    d.polygon(inner, fill=(232, 130, 34, 245))
    # droplets
    for i in range(droplets):
        a = rnd.uniform(0, 6.28)
        dist = r * u * rnd.uniform(1.15, 1.5)
        rr = r * u * rnd.uniform(0.06, 0.16)
        x, y = c + math.cos(a) * dist, c + math.sin(a) * dist
        d.ellipse([x + 0.5 * u, y + 0.6 * u, x + rr * 2 + 0.5 * u, y + rr * 2 + 0.6 * u], fill=(86, 40, 14, 235))
        d.ellipse([x, y, x + rr * 2, y + rr * 2], fill=(210, 106, 24, 240))
    # crisp spec highlights (top-left)
    for i in range(3 if not big else 6):
        a = rnd.uniform(0, 6.28)
        dist = r * u * rnd.uniform(0.1, 0.5)
        x, y = c + math.cos(a) * dist - 0.15 * r * u, c + math.sin(a) * dist - 0.15 * r * u
        rr = r * u * rnd.uniform(0.05, 0.1)
        d.ellipse([x, y, x + rr * 1.6, y + rr], fill=(255, 214, 120, 255))
    img = img.resize((W, W), Image.LANCZOS)
    save_rgba(img, name)


def scorch(name, r, seed):
    rnd = random.Random(seed)
    S2 = 2
    W = int(r * 2 * PX)
    img = Image.new("RGBA", (W * S2, W * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = W * S2 / 2
    u = PX * S2
    # soft outer glow-like halo
    halo = Image.new("L", img.size, 0)
    hd = ImageDraw.Draw(halo)
    hd.ellipse([c - r * u * 0.95, c - r * u * 0.95, c + r * u * 0.95, c + r * u * 0.95], fill=150)
    halo = halo.filter(ImageFilter.GaussianBlur(r * u * 0.12))
    dark = Image.new("RGBA", img.size, (14, 14, 16, 255))
    dark.putalpha(halo)
    img.alpha_composite(dark)
    d = ImageDraw.Draw(img)
    # radial blast streaks
    for i in range(26):
        a = rnd.uniform(0, 6.28)
        ln = r * u * rnd.uniform(0.7, 1.02)
        w = r * u * rnd.uniform(0.012, 0.04)
        d.polygon([(c + math.cos(a + 1.57) * w, c + math.sin(a + 1.57) * w), (c + math.cos(a) * ln, c + math.sin(a) * ln), (c - math.cos(a + 1.57) * w, c - math.sin(a + 1.57) * w)], fill=(12, 12, 14, 200))
    # core
    pts = []
    for i in range(18):
        a = i * 2 * math.pi / 18
        rr = r * u * 0.5 * rnd.uniform(0.82, 1.1)
        pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
    d.polygon(pts, fill=(10, 10, 12, 245))
    # lighter ash ring (crisp)
    pts2 = [(c + (x - c) * 1.18, c + (y - c) * 1.18) for x, y in pts]
    d.line(pts2 + [pts2[0]], fill=(104, 100, 94, 120), width=int(0.6 * u))
    img = img.resize((W, W), Image.LANCZOS)
    save_rgba(img, name)


def soft_disc(name, r, col, alpha=255, falloff=2.0, hard=0.0):
    W = int(r * 2 * PX)
    img = Image.new("RGBA", (W, W), col + (0,))
    px = img.load()
    c = (W - 1) / 2
    for y in range(W):
        for x in range(W):
            dd = math.hypot(x - c, y - c) / c
            if dd >= 1:
                continue
            a = (1 - dd) ** falloff
            a = max(a, hard if dd < 0.35 else 0)
            px[x, y] = col + (int(alpha * a),)
    save_rgba(img, name)


def lumpy(name, r, seed, cols, lobes=7, lobe_r=(0.45, 0.7), n=1, outline=False, dist=0.5):
    """Flat 2/3-tone lumpy cluster (smoke puff / fireball)."""
    rnd = random.Random(seed)
    S2 = 4
    W = int(r * 2.4 * PX)
    img = Image.new("RGBA", (W * S2, W * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = W * S2 / 2
    u = PX * S2
    centers = []
    for i in range(lobes):
        a = i * 2 * math.pi / lobes + rnd.uniform(-0.3, 0.3)
        dd = r * dist * rnd.uniform(0.6, 1.0)
        centers.append((c + math.cos(a) * dd * u, c + math.sin(a) * dd * u, r * rnd.uniform(*lobe_r) * u))
    centers.append((c, c, r * 0.72 * u))
    # layers: shadow (offset bottom-right), base, highlight (offset top-left, smaller)
    layers = [(cols[0], 0.07, 0.07, 1.0), (cols[1], 0.0, 0.0, 1.0)]
    if len(cols) > 2:
        layers.append((cols[2], -0.10, -0.10, 0.8))
    if len(cols) > 3:
        layers.append((cols[3], -0.14, -0.14, 0.45))
    for col, ox, oy, sf in layers:
        for (x, y, rr) in centers:
            rr2 = rr * sf
            x2, y2 = x + ox * r * u + (x - c) * (sf - 1) * 0.4, y + oy * r * u + (y - c) * (sf - 1) * 0.4
            d.ellipse([x2 - rr2, y2 - rr2, x2 + rr2, y2 + rr2], fill=col + (255,))
    img = img.resize((W, W), Image.LANCZOS)
    save_rgba(img, name)


def chips():
    rnd = random.Random(12)
    for i in range(3):
        p = Part(f"chip_rock{i}", -4, -4, 4, 4, outline=False, sigw=1.2)
        r = rnd.uniform(2.2, 3.4)
        pts = [(math.cos(a) * r * rnd.uniform(0.6, 1.1), math.sin(a) * r * rnd.uniform(0.5, 1.0)) for a in [j * 2.0944 + rnd.uniform(-0.3, 0.3) for j in range(3)]]
        p.poly(pts, (74, 72, 70), 0.5)
        p.save()
    for i in range(2):
        p = Part(f"chip_plate{i}", -5, -4, 5, 4, outline=True, ow=0.7, sigw=1.2)
        pts = [(-3.5, -2), (2.5, -3), (4.2, 0.5), (-1.5, 3)] if i == 0 else [(-3, -1), (1, -3), (4, 1), (-2, 2.6)]
        p.poly(pts, (178, 134, 40), 0.5)
        p.poly([(x * 0.5 - 0.4, y * 0.5 - 0.4) for x, y in pts], (214, 172, 62), 0.8)
        p.save()


def telegraph():
    W, H = 128, 192  # texels; tiles along x (64 units), 96 units tall
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, H], fill=(222, 30, 24, 112))
    # chevrons
    for x0 in (0, 64):
        d.polygon([(x0 + 6, 54), (x0 + 38, 96), (x0 + 6, 138), (x0 + 22, 138), (x0 + 54, 96), (x0 + 22, 54)], fill=(255, 64, 44, 190))
    # edges
    d.rectangle([0, 0, W, 7], fill=(255, 74, 52, 215))
    d.rectangle([0, H - 8, W, H], fill=(255, 74, 52, 215))
    img.save(os.path.join(OUT, "telegraph.png"))


def fx_misc():
    # tracer
    img = Image.new("RGBA", (128, 16), (0, 0, 0, 0))
    px = img.load()
    for x in range(128):
        for y in range(16):
            dy = abs(y - 7.5) / 7.5
            fx = x / 127.0
            glow = max(0, 1 - dy) ** 2 * 0.55 * fx
            core = 1.0 if dy < 0.18 else 0.0
            a = max(glow, core * (0.35 + 0.65 * fx))
            col = (255, 232, 150) if core == 0 else (255, 252, 230)
            px[x, y] = col + (int(255 * min(1, a)),)
    img.save(os.path.join(OUT, "tracer.png"))
    # muzzle flash star
    S2 = 4
    W = 48
    img = Image.new("RGBA", (W * S2, 32 * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cy = 16 * S2
    d.polygon([(2 * S2, cy), (14 * S2, cy - 6 * S2), (22 * S2, cy - 2 * S2), (46 * S2, cy), (22 * S2, cy + 2 * S2), (14 * S2, cy + 6 * S2)], fill=(255, 190, 60, 255))
    d.polygon([(8 * S2, cy), (16 * S2, cy - 3.4 * S2), (34 * S2, cy), (16 * S2, cy + 3.4 * S2)], fill=(255, 244, 190, 255))
    d.polygon([(2 * S2, cy), (8 * S2, cy - 11 * S2), (12 * S2, cy), (8 * S2, cy + 11 * S2)], fill=(255, 220, 110, 255))
    img = img.resize((W, 32), Image.LANCZOS)
    img.save(os.path.join(OUT, "muzzle.png"))
    # spark
    img = Image.new("RGBA", (24, 6), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(0, 3), (20, 0.8), (24, 3), (20, 5.2)], fill=(255, 226, 130, 255))
    d.polygon([(8, 3), (20, 1.8), (24, 3), (20, 4.2)], fill=(255, 252, 226, 255))
    img.save(os.path.join(OUT, "spark.png"))
    # goo droplet
    S2 = 4
    img = Image.new("RGBA", (12 * S2, 12 * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([1.2 * S2, 1.4 * S2, 10.8 * S2, 11 * S2], fill=(120, 54, 16, 255))
    d.ellipse([1 * S2, 1 * S2, 10 * S2, 10 * S2], fill=(228, 116, 28, 255))
    d.ellipse([2.4 * S2, 2.2 * S2, 5.2 * S2, 4.2 * S2], fill=(255, 214, 120, 255))
    img = img.resize((12, 12), Image.LANCZOS)
    img.save(os.path.join(OUT, "droplet.png"))
    # shockwave ring
    W = 256
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    px = img.load()
    c = (W - 1) / 2
    for y in range(W):
        for x in range(W):
            dd = math.hypot(x - c, y - c) / c
            ring = max(0, 1 - abs(dd - 0.9) / 0.1)
            soft = max(0, 1 - abs(dd - 0.86) / 0.2) * 0.35
            a = max(ring, soft)
            if a > 0:
                px[x, y] = (232, 228, 218, int(255 * min(1, a)))
    img.save(os.path.join(OUT, "ring.png"))
    # vignette (soft)
    W, H = 256, 144
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            dx, dy = (x - W / 2) / (W / 2), (y - H / 2) / (H / 2)
            dd = math.sqrt(dx * dx * 0.8 + dy * dy)
            a = max(0, min(1, (dd - 0.55) / 0.85)) ** 1.5 * 0.62
            px[x, y] = (8, 9, 12, int(255 * a))
    img.save(os.path.join(OUT, "vignette.png"))
    # dust puff (pale, flat two tone)
    soft_disc("dust", 14, (150, 146, 138), alpha=170, falloff=1.5)
    # explosion smoke + fireball
    for i in range(3):
        lumpy(f"smoke{i}", 22, 20 + i, [(36, 36, 41), (50, 51, 57), (68, 69, 75)], lobes=12, lobe_r=(0.26, 0.42), dist=0.62)
    for i in range(2):
        lumpy(f"fireball{i}", 22, 30 + i, [(176, 52, 14), (240, 112, 22), (255, 184, 52), (255, 240, 170)], lobes=9, lobe_r=(0.42, 0.62), dist=0.6)
    soft_disc("glow", 32, (255, 255, 255), alpha=255, falloff=2.2)
    soft_disc("flash", 48, (255, 255, 255), alpha=255, falloff=1.2, hard=0.9)
    soft_disc("ash_drift", 60, (150, 146, 138), alpha=70, falloff=1.2)
    soft_disc("hollow", 50, (22, 24, 28), alpha=90, falloff=1.2)
    # small pock decal
    S2 = 4
    img = Image.new("RGBA", (10 * S2, 10 * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([1 * S2, 1 * S2, 9 * S2, 9 * S2], fill=(30, 30, 32, 210))
    d.ellipse([0.6 * S2, 0.6 * S2, 5 * S2, 5 * S2], fill=(118, 114, 106, 150))
    d.ellipse([1.8 * S2, 1.8 * S2, 8 * S2, 8 * S2], fill=(18, 18, 20, 235))
    img = img.resize((10, 10), Image.LANCZOS)
    img.save(os.path.join(OUT, "pock.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:] or None
    # Terminids
    bug_parts("scav", 0.82, False)
    bug_parts("chg", 3.1, True, dmg=0)
    for dm in (1, 2):
        bug_parts(f"chg_d{dm}", 3.1, True, dmg=dm, only=("thorax", "head"))
    player_parts()
    pickups()
    for i, (r, sd) in enumerate([(26, 1), (18, 2), (34, 3), (13, 4)]):
        rock(f"rock{i}", r, sd)
    wall("wall0", 140, 22, 7, notch=True)
    wall("wall1", 76, 22, 8, notch=True)
    wall("wall2", 96, 22, 9, notch=False, ell=True)
    for i in range(8):
        debris(f"debris{i}", 2.2 + (i % 4) * 0.9, 40 + i)
    chips()
    ground_tile()
    for i, (r, sd) in enumerate([(14, 1), (12, 2), (17, 3), (11, 4)]):
        goo_splat(f"goo{i}", r, sd, lobes=7 + i, droplets=6)
    goo_splat("goo_big", 62, 9, lobes=13, droplets=16, big=True)
    scorch("scorch", 92, 5)
    telegraph()
    fx_misc()
    with open(os.path.join(OUT, "layout.json"), "w") as f:
        json.dump(LAYOUT, f, indent=1)
    print("done", len(os.listdir(OUT)), "files")


if __name__ == "__main__":
    main()
