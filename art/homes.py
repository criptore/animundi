"""Homes of the 12 peoples, drawn by code in the spirit of WorldBox's houses (studied on the
official wiki, see docs/WORLDBOX_WIKI_LESSONS.md), never copied:

- a 3/4 view: a big roof over short walls on a stone footing, a dark outline, light from the left;
- roofs (and some cloth) drawn in a colour MASK, magenta shades: the game paints them in the
  village's colour (shaders/sprite_batch.gdshader), so every village has its own roofs;
- each people its own materials and shapes (timber houses, tree stumps, stone halls, hide tents,
  mud domes, shell domes, mushrooms...), four tiers (hut, house, stone house, big house) that grow
  from one small home into a compound with annexes and towers;
- many variations: every home is drawn from a seed (sizes, roof, windows, chimney, annex side,
  props such as barrels, crates, flowers, fences, woodpiles), VARIANTS per people and tier.

Used by art/buildings.py, which writes the sprites.
"""

import random

VARIANTS = 4

# Mask shades: (v, 0, v). The shader keeps the shade and swaps the hue for the village's colour.
MASK = {"hi": (250, 0, 250), "base": (208, 0, 208), "mid": (176, 0, 176), "lo": (140, 0, 140), "dk": (104, 0, 104)}


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[k:k + 2], 16) for k in (0, 2, 4))


def sh(c, f):
    """Shade a colour: f > 1 lightens, f < 1 darkens. Mask colours stay mask colours."""
    if c[1] == 0 and c[0] == c[2] and c[0] > 60:
        v = max(70, min(250, int(c[0] * f)))
        return (v, 0, v)
    if f >= 1:
        return tuple(min(255, int(v + (255 - v) * (f - 1))) for v in c)
    return tuple(int(v * f) for v in c)


class Canvas:
    """Pixels on a grid, y down. Drawn bottom-up: the ground line is at y = h - 1."""

    def __init__(self, w=34, h=30):
        self.w, self.h = w, h
        self.px = {}

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.px[(x, y)] = c

    def get(self, x, y):
        return self.px.get((x, y))

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, c)

    def image(self):
        """Cropped to what was drawn, with a dark outline (the darker shade of the neighbour)."""
        from PIL import Image
        if not self.px:
            return Image.new("RGBA", (1, 1))
        out = dict(self.px)
        for (x, y), c in self.px.items():
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                p = (x + dx, y + dy)
                if p not in self.px and p not in out:
                    out[p] = sh(c, 0.42)
        xs = [p[0] for p in out]
        ys = [p[1] for p in out]
        x0, y0 = min(xs), min(ys)
        img = Image.new("RGBA", (max(xs) - x0 + 1, max(ys) - y0 + 1), (0, 0, 0, 0))
        for (x, y), c in out.items():
            img.putpixel((x - x0, y - y0), c + (255,))
        return img


# ---------------------------------------------------------------------------------- parts

def light(x, x0, x1):
    """Light from the left: 1.1 on the left edge, 0.85 on the right."""
    t = (x - x0) / max(1, x1 - x0)
    return 1.1 - 0.25 * t


def wall(cv, x0, x1, y0, y1, kind, col, rng):
    """A front wall from (x0, y0) top-left to (x1, y1) bottom-right. kind: planks, logs, stone,
    plaster, mud, bark, shell."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            c = col
            if kind == "planks":
                c = sh(col, 0.82) if (x - x0) % 3 == 2 else col
            elif kind == "logs":
                c = sh(col, 0.8) if (y - y0) % 2 == 1 else col
                if x in (x0, x1) and (y - y0) % 2 == 0:
                    c = sh(col, 1.25)  # log ends
            elif kind == "stone":
                row = (y - y1) % 2
                off = 0 if ((y - y1) // 2) % 2 == 0 else 2
                if row == 1 or (x - x0 + off) % 4 == 3:
                    c = sh(col, 0.75)
                else:
                    c = sh(col, 0.95 + 0.12 * rng.random())
            elif kind == "plaster":
                c = sh(col, 0.97 + 0.06 * rng.random())
            elif kind == "mud":
                c = sh(col, 0.9 + 0.2 * rng.random()) if rng.random() < 0.3 else col
            elif kind == "bark":
                c = sh(col, 0.75) if (x * 7 + y * 3) % 5 == 0 or (x - x0) % 3 == 1 and rng.random() < 0.4 else col
            elif kind == "shell":
                c = sh(col, 0.88) if (x - x0 + y) % 4 == 0 else col
            cv.set(x, y, sh(c, light(x, x0, x1)))


def timber_frame(cv, x0, x1, y0, y1, col):
    """Dark timber posts and a beam on a plaster wall."""
    for y in range(y0, y1 + 1):
        cv.set(x0, y, col)
        cv.set(x1, y, sh(col, 0.85))
    for x in range(x0, x1 + 1):
        cv.set(x, y0, col)
    mid = (x0 + x1) // 2
    if x1 - x0 > 8:
        for y in range(y0, y1 + 1):
            cv.set(mid, y, col)


def footing(cv, x0, x1, y, col, rng):
    """A row of stones under the wall."""
    for x in range(x0 - 1, x1 + 2):
        cv.set(x, y, sh(col, 0.85 + 0.25 * rng.random()) if x % 3 else sh(col, 0.7))


def door(cv, x, ybot, h, col, frame, arch=False, w=2):
    for yy in range(ybot - h + 1, ybot + 1):
        for xx in range(x, x + w):
            cv.set(xx, yy, sh(col, 0.75 if xx == x + w - 1 else 1.0))
    for yy in range(ybot - h + 1, ybot + 1):
        cv.set(x - 1, yy, frame)
        cv.set(x + w, yy, sh(frame, 0.8))
    if arch:
        for xx in range(x, x + w):
            cv.set(xx, ybot - h, frame)
    else:
        for xx in range(x - 1, x + w + 1):
            cv.set(xx, ybot - h, frame)


def window(cv, x, y, glass, frame, shutters=None, w=2, h=2):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            cv.set(xx, yy, sh(glass, 1.15) if (xx == x and yy == y) else glass)
    for xx in range(x - 1, x + w + 1):
        cv.set(xx, y + h, frame)
    if shutters:
        for yy in range(y, y + h):
            cv.set(x - 1, yy, shutters)
            cv.set(x + w, yy, sh(shutters, 0.8))


def gable_roof(cv, cx, ybase, half, height, tex, rng, gable=None, overhang=1):
    """A pointed roof seen at 3/4: the left plane lit, the right in shade, shingle rows, a lit
    ridge; `gable` = (colour of the gable wall, opening colour) shows the gable end in front."""
    top = ybase - height + 1
    for y in range(top, ybase + 1):
        r = (y - top + 1) / height
        hw = max(1, round((half + overhang) * r))
        for x in range(cx - hw, cx + hw + 1):
            left = x <= cx
            base = MASK["base"] if left else MASK["lo"]
            if tex == "shingles":
                row = (ybase - y) % 2
                c = sh(base, 0.86) if row == 1 and (x + (ybase - y) // 2) % 3 == 0 else base
                if row == 1:
                    c = sh(c, 0.93)
            elif tex == "thatch":
                c = sh(base, 0.85 + 0.25 * rng.random())
            elif tex == "planks":
                c = sh(base, 0.82) if (x - cx) % 3 == 0 else base
            else:
                c = base
            if x == cx:
                c = MASK["hi"]
            if y == ybase:
                c = sh(c, 0.8)
            cv.set(x, y, c)
    if gable:
        gw, gop = gable
        # The gable end: a small triangle of wall under the roof's front edge with an opening.
        gh = max(2, height // 2)
        for y in range(ybase - gh + 1, ybase + 1):
            r = (y - (ybase - gh)) / gh
            hw = max(0, round((half - 2) * r) - 1)
            for x in range(cx - hw, cx + hw + 1):
                cv.set(x, y, sh(gw, light(x, cx - hw, cx + hw)))
        cv.set(cx, ybase - 1, gop)
        cv.set(cx, ybase, gop)
        cv.set(cx + 1, ybase, sh(gop, 0.8))


def round_roof(cv, cx, ybase, half, height, col=None, spots=None, rng=None, scallop=False):
    """A dome or cap (huts, mushrooms, shells): lit on the upper left."""
    top = ybase - height + 1
    for y in range(top, ybase + 1):
        t = (ybase - y + 0.5) / height
        hw = max(1, round(half * (1 - t * t) ** 0.5 + 0.3))
        for x in range(cx - hw, cx + hw + 1):
            base = col or MASK["base"]
            f = 1.12 if (x < cx and y < top + height // 2) else (0.82 if x > cx + hw // 3 else 1.0)
            c = sh(base, f)
            if spots and rng.random() < 0.12 and y < ybase:
                c = spots
            cv.set(x, y, c)
        if scallop and y == ybase:
            for x in range(cx - hw, cx + hw + 1, 2):
                cv.set(x, y + 1, sh(col or MASK["base"], 0.7))


def cone(cv, cx, ybase, half, height, stripes=False, patches=None, rng=None):
    """A tent cone in mask cloth, with stripes or hide patches."""
    top = ybase - height + 1
    for y in range(top, ybase + 1):
        r = (y - top + 1) / height
        hw = max(0, round(half * r))
        for x in range(cx - hw, cx + hw + 1):
            c = MASK["base"] if x <= cx else MASK["lo"]
            if stripes and (x - cx) % 4 in (2, 3):
                c = patches or (238, 226, 200)
                c = sh(c, 1.0 if x <= cx else 0.85)
            elif patches and rng and rng.random() < 0.12:
                c = sh(patches, 1.0 if x <= cx else 0.82)
            cv.set(x, y, c)


def chimney(cv, x, ytop, h, col):
    for y in range(ytop, ytop + h):
        cv.set(x, y, sh(col, 1.05))
        cv.set(x + 1, y, sh(col, 0.8))
    cv.set(x, ytop, sh(col, 0.6))
    cv.set(x + 1, ytop, sh(col, 0.5))


def flag(cv, x, ytop, accent, pole=(90, 64, 40)):
    for y in range(ytop, ytop + 5):
        cv.set(x, y, pole)
    for y in range(ytop, ytop + 2):
        for xx in range(x + 1, x + 4):
            cv.set(xx, y, MASK["base"] if accent is None else accent)


# ---------------------------------------------------------------------------------- props

def barrel(cv, x, ybot):
    for y in range(ybot - 2, ybot + 1):
        cv.set(x, y, (150, 98, 52))
        cv.set(x + 1, y, (116, 74, 40))
    cv.set(x, ybot - 1, (70, 60, 56))
    cv.set(x + 1, ybot - 1, (56, 48, 44))


def crate(cv, x, ybot):
    for y in range(ybot - 2, ybot + 1):
        for xx in range(x, x + 3):
            cv.set(xx, y, (176, 128, 70) if (xx + y) % 2 else (150, 106, 56))
    cv.set(x, ybot - 2, (196, 150, 90))


def flowers(cv, x, ybot, rng):
    for k in range(3):
        cv.set(x + k, ybot, (60, 130, 50))
        cv.set(x + k, ybot - 1, rng.choice([(226, 64, 70), (250, 214, 76), (246, 246, 236), (120, 150, 240)]))


def fence(cv, x, ybot, n):
    for k in range(n):
        cv.set(x + k, ybot - 1, (160, 116, 66))
        if k % 2 == 0:
            cv.set(x + k, ybot, (130, 92, 50))
            cv.set(x + k, ybot - 2, (176, 128, 74))


def woodpile(cv, x, ybot):
    for k in range(4):
        cv.set(x + k, ybot, (130, 86, 46))
        cv.set(x + k, ybot - 1, (176, 120, 66) if k % 2 else (150, 100, 54))
    cv.set(x + 1, ybot - 2, (176, 120, 66))
    cv.set(x + 2, ybot - 2, (150, 100, 54))


def bush(cv, x, ybot, rng, col=(70, 140, 60)):
    for dy in range(3):
        for dx in range(-1, 2 + (dy == 0)):
            if rng.random() < 0.85:
                cv.set(x + dx, ybot - dy, sh(col, 1.15 if dx < 0 else 0.9))


def tree_crown(cv, cx, ybot, r, rng, col=(76, 150, 64)):
    """A leafy canopy (elves' and treefolk's homes grow with trees)."""
    for y in range(ybot - 2 * r, ybot + 1):
        for x in range(cx - r - 1, cx + r + 2):
            dx, dy = (x - cx) / (r + 0.8), (y - (ybot - r)) / (r + 0.5)
            if dx * dx + dy * dy <= 1.0 and rng.random() < 0.96:
                f = 1.18 if dx < -0.1 and dy < 0 else (0.82 if dx > 0.3 or dy > 0.5 else 1.0)
                cv.set(x, y, sh(col, f * (0.95 + 0.1 * rng.random())))


def horns(cv, x, y, left=True):
    """A bone horn or tusk sticking out (orcs)."""
    d = -1 if left else 1
    pts = [(0, 0), (d, -1), (2 * d, -2), (2 * d, -3)]
    for k, (dx, dy) in enumerate(pts):
        cv.set(x + dx, y + dy, (236, 226, 196) if k < 3 else (250, 246, 230))


def cauldron(cv, x, ybot):
    for xx in range(x, x + 3):
        cv.set(xx, ybot, (54, 50, 54))
        cv.set(xx, ybot - 1, (70, 66, 70))
    cv.set(x + 1, ybot - 2, (110, 200, 80))


def props(cv, rng, x0, x1, ybot, kinds, count):
    """A few props in front of or beside the home."""
    spots = [x0 - 4, x0 - 3, x1 + 2, x1 + 3]
    rng.shuffle(spots)
    for k in range(count):
        kind = rng.choice(kinds)
        x = spots[k % len(spots)]
        {"barrel": lambda: barrel(cv, x, ybot), "crate": lambda: crate(cv, x - 1, ybot),
         "flowers": lambda: flowers(cv, x - 1, ybot, rng), "fence": lambda: fence(cv, x - 1, ybot, 4),
         "woodpile": lambda: woodpile(cv, x - 1, ybot), "bush": lambda: bush(cv, x, ybot, rng),
         "cauldron": lambda: cauldron(cv, x - 1, ybot)}[kind]()


# ---------------------------------------------------------------------------------- houses

def timber_house(cv, rng, cx, ybot, w, wall_h, roof_h, mat, pal, chim=True):
    """One gabled house: footing, wall, door, windows, roof; returns (x0, x1, roof top)."""
    x0, x1 = cx - w // 2, cx - w // 2 + w - 1
    footing(cv, x0, x1, ybot, pal["stone"], rng)
    wt = ybot - wall_h
    kind = mat
    wall(cv, x0, x1, wt, ybot - 1, kind, pal["wall"] if kind != "stone" else pal["stone"], rng)
    if kind == "plaster":
        timber_frame(cv, x0, x1, wt, ybot - 1, pal["timber"])
    dx = rng.choice([x0 + 1, cx - 1, x1 - 2]) if w > 7 else cx - 1
    door(cv, dx, ybot - 1, min(3, wall_h), pal["door"], pal["timber"], arch=kind == "stone")
    for wx in (x0 + 1, x1 - 2):
        if abs(wx - dx) > 2 and wall_h >= 3 and rng.random() < 0.85:
            window(cv, wx, wt + 1, pal["glass"], pal["timber"], shutters=pal.get("shutters") if rng.random() < 0.4 else None)
    gable_roof(cv, (x0 + x1) // 2, wt - 1, w // 2, roof_h, pal["roof_tex"], rng,
               gable=(pal["gable"], (40, 30, 26)) if rng.random() < 0.7 else None)
    top = wt - roof_h
    if chim and rng.random() < 0.6:
        side = rng.choice([-1, 1])
        chimney(cv, (x0 + x1) // 2 + side * max(2, w // 4), top + roof_h // 3, 3, pal["stone"])
    return x0, x1, top


def lean_to(cv, rng, x0, x1, ybot, h, pal, left):
    """A small annex with a one-sided roof against the main house."""
    wall(cv, x0, x1, ybot - h, ybot - 1, "planks", pal["wall"], rng)
    footing(cv, x0, x1, ybot, pal["stone"], rng)
    for k, x in enumerate(range(x0 - 1, x1 + 2)):
        t = (x1 + 1 - x) if left else (x - x0 + 1)
        top = ybot - h - 1 - t // 2
        for y in range(top, ybot - h):
            cv.set(x, y, MASK["mid"] if (y - top) % 2 else MASK["lo"])
    if x1 - x0 >= 3:
        window(cv, (x0 + x1) // 2, ybot - h + 1, pal["glass"], pal["timber"], w=1)


def style_timber(rng, tier, pal):
    """Humans, bullfolk, undead: gabled houses, growing into compounds."""
    cv = Canvas()
    cx, yb = 17, 28
    w = [9, 11, 12, 13][tier] + rng.randint(-1, 2)
    wall_h = [3, 4, 4, 5][tier] + rng.choice([0, 0, 1])
    roof_h = [6, 7, 8, 8][tier] + rng.randint(-1, 2)
    mat = rng.choice(pal["mats"][max(0, tier - 1):tier + 1])
    pal = dict(pal, roof_tex=rng.choice(pal.get("roof_texs", [pal["roof_tex"]])))
    side = rng.choice([-1, 1])
    if tier >= 3:
        # A second, smaller house behind, to one side.
        timber_house(cv, rng, cx + side * 6, yb - 3, 9, 4, 6, pal["mats"][1], pal, chim=False)
    if tier >= 1 and rng.random() < 0.8:
        ax0 = cx + w // 2 + 1 if side > 0 else cx - w // 2 - 4
        lean_to(cv, rng, ax0, ax0 + 2 + (tier > 1), yb, wall_h - 1, pal, side < 0)
    if tier >= 2 and mat != "stone":
        # A stone ground floor under the timber upper floor.
        x0 = cx - w // 2
        wall(cv, x0, x0 + w - 1, yb - 2, yb - 1, "stone", pal["stone"], rng)
    x0, x1, top = timber_house(cv, rng, cx, yb if tier < 3 else yb, w, wall_h + (tier >= 2), roof_h, mat, pal)
    if tier >= 3 and rng.random() < 0.6:
        tx = cx - side * (w // 2 + 1)
        wall(cv, tx - 1, tx + 1, yb - 9, yb - 1, "stone", pal["stone"], rng)
        cone(cv, tx, yb - 10, 2, 4)
        window(cv, tx, yb - 7, pal["glass"], pal["stone"], w=1)
    if tier >= 2 and rng.random() < 0.5:
        flag(cv, cx, top - 4, None)
    props(cv, rng, x0, x1, yb, pal["props"], tier // 2 + 1 + rng.randint(0, 1))
    return cv.image()


def style_stump(rng, tier, pal):
    """Elves and treefolk: homes in tree stumps, later white stone with trees growing around."""
    cv = Canvas()
    cx, yb = 17, 28
    if tier >= 2 and rng.random() < 0.9:
        tree_crown(cv, cx + rng.choice([-6, 6]), yb - 9, 4 + tier // 3, rng, pal["leaves"])
    w = [8, 10, 11, 13][tier] + rng.randint(-1, 2)
    h = [5, 6, 6, 7][tier] + rng.randint(-1, 1)
    x0, x1 = cx - w // 2, cx - w // 2 + w - 1
    if tier < 2:
        # A stump: bark wall with roots, a round cap of a roof.
        wall(cv, x0, x1, yb - h, yb - 1, "bark", pal["bark"], rng)
        for x in (x0 - 1, x1 + 1):
            cv.set(x, yb, sh(pal["bark"], 0.8))
            cv.set(x, yb - 1, sh(pal["bark"], 0.9))
        door(cv, cx - 1, yb - 1, 3, (40, 30, 24), sh(pal["bark"], 1.3), arch=True)
        if tier == 1:
            window(cv, x1 - 2, yb - h + 1, pal["glass"], sh(pal["bark"], 1.3), w=1)
        round_roof(cv, cx, yb - h - 1, w // 2 + 2, 4 + tier, scallop=True)
        if rng.random() < 0.6:
            for k in range(2):
                cv.set(cx + rng.randint(-2, 2), yb - h - 5 - tier - k, (90, 160, 70))
    else:
        # White stone walls with arched windows, pointed caps, a tower for the biggest.
        wall(cv, x0, x1, yb - h, yb - 1, "stone", pal["stone"], rng)
        door(cv, cx - 1, yb - 1, 4, (40, 34, 30), sh(pal["stone"], 0.7), arch=True)
        for wx in (x0 + 1, x1 - 2):
            window(cv, wx, yb - h + 1, pal["glass"], sh(pal["stone"], 0.75), h=3)
        round_roof(cv, cx, yb - h - 1, w // 2 + 1, 5, scallop=True)
        if tier == 3:
            tx = cx + rng.choice([-1, 1]) * (w // 2)
            wall(cv, tx - 1, tx + 1, yb - h - 6, yb - h - 1, "stone", pal["stone"], rng)
            cone(cv, tx, yb - h - 7, 2, 5)
    for k in range(rng.randint(0, 2) + tier // 2):
        bush(cv, rng.choice([x0 - 2, x1 + 2]), yb, rng, pal["leaves"])
    if rng.random() < 0.5:
        flowers(cv, rng.choice([x0 - 4, x1 + 2]), yb, rng)
    return cv.image()


def style_stone(rng, tier, pal):
    """Dwarves: squat stone homes with low roofs, chimneys, forges; then halls."""
    cv = Canvas()
    cx, yb = 17, 28
    w = [10, 11, 13, 15][tier] + rng.randint(-1, 2)
    wall_h = [3, 4, 4, 5][tier] + rng.choice([0, 0, 1])
    x0, x1 = cx - w // 2, cx - w // 2 + w - 1
    wall(cv, x0, x1, yb - wall_h, yb - 1, "stone", pal["stone"], rng)
    footing(cv, x0, x1, yb, sh(pal["stone"], 0.8), rng)
    door(cv, cx - 1, yb - 1, 3, (60, 40, 26), (90, 64, 40), arch=True, w=2 + (tier >= 2))
    if wall_h >= 4:
        for wx in (x0 + 1, x1 - 2):
            window(cv, wx, yb - wall_h + 1, (240, 170, 70), (70, 60, 56))
    # Low hip roof, planks, a big chimney (forge glow on top).
    roof_h = [4, 5, 5, 6][tier] + rng.randint(-1, 1)
    top = yb - wall_h - roof_h
    for k in range(roof_h):
        y = yb - wall_h - 1 - k
        inset = k
        for x in range(x0 - 1 + inset, x1 + 2 - inset):
            c = MASK["base"] if x < cx else MASK["lo"]
            if (x - x0) % 3 == 0:
                c = sh(c, 0.85)
            if k == roof_h - 1:
                c = MASK["hi"]
            cv.set(x, y, c)
    cx2 = cx + rng.choice([-1, 1]) * (w // 3)
    chimney(cv, cx2, top - 2, roof_h + 1, sh(pal["stone"], 0.9))
    cv.set(cx2, top - 3, (250, 150, 60))
    if tier >= 2:
        # A wooden deck or a second hall to one side.
        side = rng.choice([-1, 1])
        dx0 = x1 + 1 if side > 0 else x0 - 5
        for x in range(dx0, dx0 + 5):
            cv.set(x, yb - 1, (150, 106, 56))
            cv.set(x, yb, (110, 76, 40))
        for x in (dx0, dx0 + 4):
            for y in range(yb - 3, yb - 1):
                cv.set(x, y, (120, 84, 46))
        if tier == 3:
            flag(cv, cx, top - 6, None)
    props(cv, rng, x0, x1, yb, ["barrel", "crate", "woodpile"], 1 + tier // 2)
    return cv.image()


def style_tent(rng, tier, pal):
    """Orcs, goblins, felines: hide or cloth tents on poles; then big halls with spikes."""
    cv = Canvas()
    cx, yb = 17, 28
    if tier < 2:
        half = [5, 6][tier] + rng.randint(-1, 1)
        h = [8, 9][tier] + rng.randint(-1, 2)
        cone(cv, cx, yb, half, h, stripes=pal.get("stripes", False), patches=pal.get("patch"), rng=rng)
        # Poles sticking out of the top.
        for d in (-1, 1):
            cv.set(cx + d, yb - h, (120, 84, 46))
            cv.set(cx + 2 * d, yb - h - 1, (140, 100, 56))
        # Door flap.
        for y in range(yb - 3, yb + 1):
            for x in range(cx - 1, cx + 1 + (y > yb - 2)):
                cv.set(x, y, (40, 28, 22))
        x0, x1 = cx - half, cx + half
    else:
        # A long hall: low walls of logs or stone, a big hide roof, spikes or pennants.
        w = [13, 16][tier - 2] + rng.randint(-1, 2)
        x0, x1 = cx - w // 2, cx - w // 2 + w - 1
        wall(cv, x0, x1, yb - 3, yb - 1, pal.get("hall", "logs"), pal["wall"], rng)
        footing(cv, x0, x1, yb, pal["stone"], rng)
        door(cv, cx - 1, yb - 1, 3, (40, 28, 22), (120, 84, 46))
        gable_roof(cv, cx, yb - 4, w // 2, 6 + tier - 2, "thatch" if not pal.get("stripes") else "flat", rng)
        if pal.get("stripes"):
            for y in range(yb - 10, yb - 3):
                for x in range(x0 - 1, x1 + 2):
                    if cv.get(x, y) and cv.get(x, y)[1] == 0 and (x - cx) % 4 in (2, 3):
                        cv.set(x, y, sh(pal["patch"], 1.0 if x <= cx else 0.85))
    if pal.get("horns"):
        horns(cv, x0 - 1, yb - 3, True)
        horns(cv, x1 + 1, yb - 3, False)
        if tier >= 2:
            horns(cv, cx - 2, yb - 11 - (tier - 2), True)
            horns(cv, cx + 2, yb - 11 - (tier - 2), False)
    if pal.get("pennant") and tier >= 1:
        flag(cv, cx, yb - 14 - tier, None)
    for x in range(x0 - 2, x1 + 3):
        if rng.random() < 0.35:
            cv.set(x, yb, sh(pal["stone"], 0.8 + 0.3 * rng.random()))
    props(cv, rng, x0, x1, yb, pal["props"], 1 + tier // 2)
    return cv.image()


def style_dome(rng, tier, pal):
    """Lizardfolk (mud), merfolk (shells), fairies (mushrooms): domes and caps, stacked when big."""
    cv = Canvas()
    cx, yb = 17, 28
    domes = [(0, 0, 1.0)] if tier < 2 else [(rng.choice([-5, 5]), -2, 0.75), (0, 0, 1.0)]
    if tier == 3:
        domes.insert(0, (-domes[0][0], -3, 0.7))
    x0, x1 = cx, cx
    for (dx, dy, s) in domes:
        w = int(([8, 10, 11, 12][tier]) * s) + rng.randint(-1, 2)
        h = int(([4, 5, 5, 6][tier]) * s) + rng.randint(-1, 1)
        bx0, bx1 = cx + dx - w // 2, cx + dx - w // 2 + w - 1
        x0, x1 = min(x0, bx0), max(x1, bx1)
        b = yb + dy
        wall(cv, bx0, bx1, b - h, b - 1, pal["mat"], pal["wall"], rng)
        if pal["roof"] != "cap" and rng.random() < 0.6:
            for x in range(bx0, bx1 + 1):
                cv.set(x, b - h, MASK["mid"] if x <= cx + dx else MASK["lo"])
        if s < 1.0 and h >= 3 and rng.random() < 0.7:
            window(cv, cx + dx - 1, b - h + 1, pal["glass"], sh(pal["wall"], 0.7), w=1)
        if s == 1.0:
            door(cv, cx + dx - 1, b - 1, min(3, h), (50, 36, 30), sh(pal["wall"], 0.75), arch=True)
            if h >= 4:
                window(cv, bx1 - 2, b - h + 1, pal["glass"], sh(pal["wall"], 0.7), w=1)
        if pal["roof"] == "cap":
            round_roof(cv, cx + dx, b - h - 1, w // 2 + 2, 4 + tier // 2, spots=(250, 246, 240), rng=rng)
        else:
            round_roof(cv, cx + dx, b - h - 1, w // 2 + 1, 3 + tier // 2)
            if pal["roof"] == "shell":
                for k in range(3):
                    cv.set(cx + dx - 1 + k, b - h - 3 - tier // 2, (250, 236, 230))
    if pal.get("reeds"):
        for x in (x0 - 2, x1 + 2):
            for y in range(yb - 3, yb + 1):
                cv.set(x, y, (120, 150, 70) if y > yb - 3 else (170, 130, 70))
    props(cv, rng, x0, x1, yb, pal["props"], 1 + tier // 2)
    return cv.image()


# Per people: its style, materials, colours and props. The roofs are always in the mask.
PEOPLES = {
    "humans": (style_timber, {"mats": ["planks", "plaster", "plaster", "stone"], "wall": hexc("#a0703e"),
                              "stone": hexc("#9a958c"), "timber": hexc("#5e3e24"), "door": hexc("#4a3020"),
                              "glass": hexc("#7ec8f0"), "gable": hexc("#b88a52"), "roof_tex": "shingles", "roof_texs": ["shingles", "shingles", "thatch", "planks"],
                              "shutters": hexc("#4a86d0"), "props": ["barrel", "crate", "flowers", "fence", "woodpile"]}),
    "bullfolk": (style_timber, {"mats": ["logs", "logs", "planks", "stone"], "wall": hexc("#8a5a32"),
                                "stone": hexc("#8a8076"), "timber": hexc("#4a2e1a"), "door": hexc("#3a2414"),
                                "glass": hexc("#f0a050"), "gable": hexc("#a07040"), "roof_tex": "thatch", "roof_texs": ["thatch", "planks"],
                                "props": ["woodpile", "barrel", "fence"]}),
    "undead": (style_timber, {"mats": ["planks", "stone", "stone", "stone"], "wall": hexc("#6a6058"),
                              "stone": hexc("#6e6a72"), "timber": hexc("#2e2a2e"), "door": hexc("#1e1a20"),
                              "glass": hexc("#a070d0"), "gable": hexc("#5a5250"), "roof_tex": "planks",
                              "props": ["crate", "fence", "barrel"]}),
    "elves": (style_stump, {"bark": hexc("#8a5a34"), "stone": hexc("#d8d4c4"), "glass": hexc("#7ec8f0"),
                            "leaves": hexc("#5aae55")}),
    "treefolk": (style_stump, {"bark": hexc("#6e4a2a"), "stone": hexc("#a89a7a"), "glass": hexc("#b0e070"),
                               "leaves": hexc("#3f8a3f")}),
    "dwarves": (style_stone, {"stone": hexc("#8e8a84")}),
    "orcs": (style_tent, {"stone": hexc("#7a7470"), "wall": hexc("#7a5434"), "patch": hexc("#a88a60"),
                          "horns": True, "props": ["cauldron", "woodpile", "crate"]}),
    "goblins": (style_tent, {"stone": hexc("#7a7a60"), "wall": hexc("#8a7040"), "patch": hexc("#9aa04a"),
                             "hall": "planks", "props": ["crate", "barrel", "woodpile"]}),
    "felines": (style_tent, {"stone": hexc("#b8a888"), "wall": hexc("#c8a060"), "patch": hexc("#f0e2c0"),
                             "stripes": True, "pennant": True, "props": ["flowers", "crate", "barrel"]}),
    "lizardfolk": (style_dome, {"mat": "mud", "wall": hexc("#b89a64"), "roof": "dome", "glass": hexc("#4dbfb0"),
                                "reeds": True, "props": ["crate", "bush"]}),
    "merfolk": (style_dome, {"mat": "shell", "wall": hexc("#e8e0d4"), "roof": "shell", "glass": hexc("#8fd8ff"),
                             "props": ["bush", "barrel"]}),
    "fairies": (style_dome, {"mat": "plaster", "wall": hexc("#f4ecdc"), "roof": "cap", "glass": hexc("#fff0a0"),
                             "props": ["flowers", "bush"]}),
}

TIERS = ["hut", "house", "stone_house", "big_house"]


def all_homes():
    """name -> image: <tier>_<people>_<variant>."""
    out = {}
    for people, (style, pal) in PEOPLES.items():
        for t, tier in enumerate(TIERS):
            for v in range(VARIANTS):
                rng = random.Random(f"{people}-{tier}-{v}")
                out[f"{tier}_{people}_{v}"] = style(rng, t, pal)
    return out


# ---------------------------------------------------------------------------------- great buildings

def family(people):
    return {style_timber: "timber", style_stump: "stump", style_stone: "stone", style_tent: "tent",
            style_dome: "dome"}[PEOPLES[people][0]]


def great_material(people):
    """Wall material and colour of a people's great buildings."""
    fam = family(people)
    pal = PEOPLES[people][1]
    if fam == "tent":
        return pal.get("hall", "logs"), pal["wall"]
    if fam == "dome":
        return pal["mat"], pal["wall"]
    return "stone", pal["stone"]


def great_roof(cv, people, rng, cx, ybase, half, height):
    """The roof of a great building in the people's way: gables, caps, cones or domes."""
    fam = family(people)
    if fam in ("timber", "stone"):
        gable_roof(cv, cx, ybase, half, height, PEOPLES[people][1].get("roof_tex", "shingles"), rng)
    elif fam == "stump":
        round_roof(cv, cx, ybase, half + 1, height, scallop=True)
    elif fam == "tent":
        pal = PEOPLES[people][1]
        cone(cv, cx, ybase, half + 1, height + 1, stripes=pal.get("stripes", False), patches=pal.get("patch"), rng=rng)
    else:
        round_roof(cv, cx, ybase, half + 1, height - 1, spots=(250, 246, 240) if PEOPLES[people][1]["roof"] == "cap" else None, rng=rng)


def glass_of(people):
    return PEOPLES[people][1].get("glass", (240, 200, 90))


def town_hall(people, rng):
    """A long hall with a bell tower, banners on both sides."""
    cv = Canvas()
    cx, yb = 17, 28
    mat, col = great_material(people)
    w = 19
    x0, x1 = cx - w // 2, cx + w // 2
    wall(cv, x0, x1, yb - 6, yb - 1, mat, col, rng)
    footing(cv, x0, x1, yb, (130, 126, 120), rng)
    door(cv, cx - 1, yb - 1, 4, (60, 40, 26), sh(col, 0.6), arch=True, w=3)
    for wx in (x0 + 2, x0 + 5, x1 - 6, x1 - 3):
        window(cv, wx, yb - 5, glass_of(people), sh(col, 0.65), h=2)
    great_roof(cv, people, rng, cx, yb - 7, w // 2, 7)
    # Bell tower over the middle.
    wall(cv, cx - 2, cx + 2, yb - 16, yb - 11, mat, sh(col, 1.05), rng)
    window(cv, cx - 1, yb - 15, (60, 50, 40), sh(col, 0.65), h=2)
    cv.set(cx, yb - 14, (230, 190, 70))
    cone(cv, cx, yb - 17, 3, 5)
    flag(cv, cx, yb - 26, None)
    for x in (x0 - 1, x1 + 1):
        flag(cv, x, yb - 12, None)
    props(cv, rng, x0, x1, yb, ["barrel", "crate", "flowers"], 2)
    return cv.image()


def temple(people, rng):
    """Columns in front, a steep roof and a spire with a golden tip."""
    cv = Canvas()
    cx, yb = 17, 28
    mat, col = great_material(people)
    w = 15
    x0, x1 = cx - w // 2, cx + w // 2
    wall(cv, x0, x1, yb - 6, yb - 1, mat, col, rng)
    for x in range(x0 + 1, x1, 3):
        for y in range(yb - 6, yb):
            cv.set(x, y, sh(col, 1.25 if y < yb - 1 else 1.0))
    for x in range(x0 - 1, x1 + 2):
        cv.set(x, yb, sh((150, 146, 140), 1.0 if x % 2 else 0.85))
    door(cv, cx - 1, yb - 1, 4, (50, 34, 40), (230, 190, 70), arch=True, w=3)
    great_roof(cv, people, rng, cx, yb - 7, w // 2, 6)
    # Spire.
    for y in range(yb - 20, yb - 12):
        cv.set(cx, y, sh(col, 1.1))
        cv.set(cx + 1, y, sh(col, 0.8))
    cone(cv, cx, yb - 21, 2, 4)
    for y in range(yb - 26, yb - 22):
        cv.set(cx, y, (240, 200, 80))
    cv.set(cx - 1, yb - 25, (240, 200, 80))
    cv.set(cx + 1, yb - 25, (240, 200, 80))
    window(cv, cx, yb - 17, (150, 100, 210), sh(col, 0.7), w=1, h=2)
    props(cv, rng, x0, x1, yb, ["flowers", "bush"], 2)
    return cv.image()


def library(people, rng):
    """Two storeys of lit windows, books in the windows, a chimney."""
    cv = Canvas()
    cx, yb = 17, 28
    mat, col = great_material(people)
    w = 15
    x0, x1 = cx - w // 2, cx + w // 2
    wall(cv, x0, x1, yb - 9, yb - 1, mat, col, rng)
    for x in range(x0, x1 + 1):
        cv.set(x, yb - 5, sh(col, 0.7))
    door(cv, cx - 1, yb - 1, 3, (70, 46, 30), sh(col, 0.6), w=2)
    for wx in (x0 + 1, x0 + 4, x1 - 5, x1 - 2):
        window(cv, wx, yb - 8, (250, 220, 130), sh(col, 0.65))
        if abs(wx - cx) > 2:
            window(cv, wx, yb - 4, (250, 220, 130), sh(col, 0.65))
    for x in range(x0 + 1, x1, 2):
        cv.set(x, yb - 7, rng.choice([(180, 60, 50), (60, 100, 170), (90, 140, 70), (200, 160, 60)]))
    great_roof(cv, people, rng, cx, yb - 10, w // 2, 6)
    chimney(cv, x1 - 3, yb - 16, 4, (130, 126, 120))
    props(cv, rng, x0, x1, yb, ["crate", "flowers"], 1)
    return cv.image()


def barracks(people, rng):
    """A long fort of a house: crenellated walls, banners, a weapons rack."""
    cv = Canvas()
    cx, yb = 17, 28
    mat, col = great_material(people)
    w = 19
    x0, x1 = cx - w // 2, cx + w // 2
    wall(cv, x0, x1, yb - 6, yb - 1, mat, col, rng)
    footing(cv, x0, x1, yb, (130, 126, 120), rng)
    for x in range(x0, x1 + 1):
        if (x - x0) % 3 != 2:
            cv.set(x, yb - 7, sh(col, 1.1))
    door(cv, cx - 1, yb - 1, 4, (50, 36, 26), (90, 64, 40), w=3)
    for wx in (x0 + 2, x1 - 3):
        cv.set(wx, yb - 4, (40, 34, 30))
        cv.set(wx, yb - 5, (40, 34, 30))
    # A low roof in the middle, the kingdom's banners, a rack of spears.
    great_roof(cv, people, rng, cx, yb - 8, 5, 4)
    for x in (x0 + 1, x1 - 1):
        flag(cv, x, yb - 13, None)
    for k in range(3):
        for y in range(yb - 4, yb + 1):
            cv.set(x1 + 3 + k * 2, y, (120, 84, 46))
        cv.set(x1 + 3 + k * 2, yb - 5, (200, 200, 210))
    return cv.image()


def watch_tower(people, rng):
    """A tall tower with arrow slits and a crenellated top under a small roof."""
    cv = Canvas()
    cx, yb = 17, 28
    mat, col = great_material(people)
    if mat in ("logs", "planks"):
        # Wooden peoples build theirs as a stilted lookout.
        for y in range(yb - 12, yb + 1):
            for x in (cx - 3, cx + 3):
                cv.set(x, y, (120, 84, 46))
        for k in range(0, 12, 3):
            cv.set(cx - 2 + k % 5, yb - k, (100, 70, 40))
        wall(cv, cx - 4, cx + 4, yb - 16, yb - 13, "planks", col, rng)
    else:
        wall(cv, cx - 3, cx + 3, yb - 14, yb - 1, mat, col, rng)
        for y in (yb - 10, yb - 5):
            cv.set(cx, y, (30, 26, 24))
            cv.set(cx, y + 1, (30, 26, 24))
        wall(cv, cx - 4, cx + 4, yb - 17, yb - 15, mat, sh(col, 1.05), rng)
        door(cv, cx - 1, yb - 1, 3, (50, 36, 26), sh(col, 0.6), arch=True)
    for x in range(cx - 4, cx + 5, 2):
        cv.set(x, yb - 18, sh(col, 1.1))
    cone(cv, cx, yb - 19, 3, 4)
    flag(cv, cx, yb - 27, None)
    return cv.image()


GREAT = {"town_hall": town_hall, "temple": temple, "library": library, "barracks": barracks,
         "watch_tower": watch_tower}


def all_great():
    """name -> image: <building>_<people>."""
    out = {}
    for people in PEOPLES:
        for name, draw in GREAT.items():
            out[f"{name}_{people}"] = draw(people, random.Random(f"{people}-{name}"))
    return out


# ---------------------------------------------------------------------------------- shared buildings

STONE = (150, 146, 138)
WOOD = (150, 104, 58)


def stockpile(rng):
    cv = Canvas()
    yb = 28
    for k, x in enumerate((10, 14)):
        crate(cv, x, yb)
        crate(cv, x + 1, yb - 3)
    for k in range(3):
        barrel(cv, 18 + k * 2, yb)
    woodpile(cv, 22, yb)
    for x in range(9, 27):
        cv.set(x, yb + 1, (110, 80, 50))
    return cv.image()


def windmill(frame):
    cv = Canvas()
    cx, yb = 17, 28
    rng = random.Random("windmill")
    # Tapered body.
    for y in range(yb - 11, yb):
        hw = 2 + (y - (yb - 11)) // 4
        for x in range(cx - hw, cx + hw + 1):
            cv.set(x, y, sh((226, 210, 172), light(x, cx - hw, cx + hw)))
    door(cv, cx - 1, yb - 1, 3, (70, 46, 30), WOOD)
    window(cv, cx, yb - 8, (60, 50, 40), WOOD, w=1)
    footing(cv, cx - 4, cx + 4, yb, STONE, rng)
    for x in range(cx - 3, cx + 4):
        for y in range(yb - 14, yb - 11):
            if abs(x - cx) <= 3 - (yb - 12 - y):
                cv.set(x, y, MASK["base"] if x <= cx else MASK["lo"])
    # Sails turning: an X or a +.
    hub = (cx, yb - 11)
    for r in range(1, 8):
        for dx, dy in (((1, 1), (-1, 1), (1, -1), (-1, -1)) if frame == 0 else ((1, 0), (-1, 0), (0, 1), (0, -1))):
            x, y = hub[0] + dx * r, hub[1] + dy * r
            cv.set(x, y, (120, 84, 46))
            if r > 2:
                cv.set(x + (dy if frame else 0), y + (dx if frame else 0), (236, 228, 210))
    cv.set(*hub, (60, 44, 30))
    return cv.image()


def well(rng):
    cv = Canvas()
    cx, yb = 17, 28
    wall(cv, cx - 4, cx + 4, yb - 2, yb, "stone", STONE, rng)
    for x in range(cx - 3, cx + 4):
        cv.set(x, yb - 3, (60, 120, 200) if abs(x - cx) < 3 else sh(STONE, 1.1))
    for y in range(yb - 8, yb - 2):
        cv.set(cx - 4, y, WOOD)
        cv.set(cx + 4, y, sh(WOOD, 0.8))
    for x in range(cx - 5, cx + 6):
        cv.set(x, yb - 9, MASK["base"] if x <= cx else MASK["lo"])
        if abs(x - cx) <= 3:
            cv.set(x, yb - 10, MASK["hi"])
    cv.set(cx, yb - 6, (90, 80, 70))
    cv.set(cx, yb - 5, (90, 80, 70))
    return cv.image()


def mine(rng):
    cv = Canvas()
    cx, yb = 17, 28
    for y in range(yb - 8, yb + 1):
        hw = 3 + (y - (yb - 8))
        for x in range(cx - hw, cx + hw + 1):
            cv.set(x, y, sh(STONE, (0.9 + 0.2 * rng.random()) * light(x, cx - hw, cx + hw)))
    for y in range(yb - 4, yb + 1):
        for x in range(cx - 2, cx + 3):
            cv.set(x, y, (34, 28, 26))
    for y in range(yb - 5, yb + 1):
        cv.set(cx - 3, y, WOOD)
        cv.set(cx + 3, y, sh(WOOD, 0.8))
    for x in range(cx - 3, cx + 4):
        cv.set(x, yb - 5, WOOD)
    # A cart of ore on its rails.
    for x in range(cx + 5, cx + 12):
        cv.set(x, yb, (90, 80, 70))
    for x in range(cx + 6, cx + 10):
        cv.set(x, yb - 1, (110, 80, 50))
        cv.set(x, yb - 2, rng.choice([(140, 140, 150), (230, 190, 70), (120, 116, 110)]))
    return cv.image()


def dock(rng):
    cv = Canvas()
    yb = 28
    for x in range(9, 26):
        cv.set(x, yb - 2, sh(WOOD, 1.1 if x % 3 else 0.85))
        cv.set(x, yb - 1, sh(WOOD, 0.8))
    for x in (10, 16, 22, 25):
        cv.set(x, yb, (90, 64, 40))
        cv.set(x, yb + 1, (90, 64, 40))
    barrel(cv, 12, yb - 3)
    crate(cv, 18, yb - 3)
    for y in range(yb - 8, yb - 2):
        cv.set(24, y, (90, 64, 40))
    cv.set(25, yb - 8, MASK["base"])
    cv.set(26, yb - 8, MASK["base"])
    cv.set(25, yb - 7, MASK["lo"])
    return cv.image()


def market(rng):
    cv = Canvas()
    yb = 28
    for x0 in (9, 18):
        for y in range(yb - 6, yb):
            cv.set(x0, y, WOOD)
            cv.set(x0 + 7, y, sh(WOOD, 0.8))
        for x in range(x0 - 1, x0 + 9):
            for y in (yb - 8, yb - 7):
                cv.set(x, y, MASK["base"] if (x // 2) % 2 == 0 else (240, 232, 214))
        for x in range(x0, x0 + 8):
            cv.set(x, yb - 2, sh(WOOD, 1.1))
            cv.set(x, yb - 3, rng.choice([(220, 70, 60), (240, 200, 70), (90, 160, 70), (200, 120, 60), (240, 240, 230)]))
    return cv.image()


def statue(rng):
    cv = Canvas()
    cx, yb = 17, 28
    wall(cv, cx - 3, cx + 3, yb - 2, yb, "stone", STONE, rng)
    gold = (232, 192, 74)
    figure = ["..#..", ".###.", "#.#.#", "..#..", ".#.#.", ".#.#."]
    for r, row in enumerate(figure):
        for c, ch in enumerate(row):
            if ch == "#":
                cv.set(cx - 2 + c, yb - 9 + r, sh(gold, 1.1 if c < 2 else 0.85))
    cv.set(cx, yb - 10, sh(gold, 1.15))
    return cv.image()


def dummy(rng):
    cv = Canvas()
    cx, yb = 17, 28
    for y in range(yb - 6, yb + 1):
        cv.set(cx, y, WOOD)
    for x in range(cx - 2, cx + 3):
        cv.set(x, yb - 5, WOOD)
    for y in range(yb - 8, yb - 5):
        for x in range(cx - 1, cx + 2):
            cv.set(x, y, (216, 184, 100))
    cv.set(cx, yb - 7, (180, 60, 50))
    return cv.image()


def ruin(rng):
    cv = Canvas()
    yb = 28
    for x in range(9, 24):
        h = rng.choice([0, 1, 1, 2, 3, 4]) if x not in (9, 23) else 5
        for y in range(yb - h, yb + 1):
            cv.set(x, y, sh(STONE, 0.75 + 0.25 * rng.random()))
    for k in range(5):
        cv.set(rng.randint(10, 22), yb, (60, 50, 44))
    return cv.image()


def all_shared():
    rng = lambda n: random.Random(n)
    return {
        "stockpile": stockpile(rng("stockpile")), "windmill_0": windmill(0), "windmill_1": windmill(1),
        "well": well(rng("well")), "mine": mine(rng("mine")), "dock": dock(rng("dock")),
        "market": market(rng("market")), "statue": statue(rng("statue")), "dummy": dummy(rng("dummy")),
        "ruin": ruin(rng("ruin")),
    }
