"""Draws the legendary monsters of Animundi (data/legends.json): unique beings, several tiles
tall, drawn with more detail than the common creatures of art/creatures.py.

Where a common creature is a small text template with one colour per part, a legend is drawn
from shapes (ellipses, polygons, thick lines), each in a material: a ramp of four to five
shades. Every pixel keeps how much light it gets from the top left, so bodies are rounded;
mid-tones are dithered; the outline takes the darkest shade of what it surrounds (no flat black);
glowing parts (eyes, runes, lava, lightning, magic) are never shaded.

Poses: idle, two walking frames, attack (each legend's own: fire breath, a stomp, thorns, a bolt
of magic, a quake, lightning), swim (cut at the waterline) and death (lying down, darkened).

Writes assets/sprites/creatures/<id>_<pose>.png (and their Godot .import files, so a checkout
without the editor still loads them) and a preview sheet docs/images/legends.png.
    python3 art/legends.py
"""

import hashlib
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites" / "creatures"
SHEET = ROOT / "docs" / "images" / "legends.png"
POSES = ["idle", "walk1", "walk2", "attack", "swim", "death"]


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[k:k + 2], 16) for k in (0, 2, 4))


# Materials: shades from dark to light. Glowing materials are drawn as they are.
MATS = {
    # Ash Wyrm
    "scale": ["#2a1214", "#4e1c1c", "#7a2a22", "#a8402c", "#cf6a3c"],
    "belly": ["#5a3a22", "#8a5a2e", "#b8823c", "#dcae5a"],
    "membrane": ["#2c1416", "#4a2020", "#6e3026", "#934a32"],
    "bone": ["#5c5040", "#9a8a6c", "#cfc2a0", "#f0e8d0"],
    "lava": ["#ffb43a"],
    "fire": ["#fff2a0"],
    "fire2": ["#ff8a2a"],
    "fire3": ["#e0401a"],
    # Frost Titan
    "frost": ["#1e3048", "#34557a", "#5682aa", "#86b4d6", "#c4e2f2"],
    "ice": ["#6ab4d8", "#a6e0f4", "#e4f8ff"],
    "fur": ["#4a5260", "#7a8494", "#aab4c2", "#dce4ec"],
    "frostglow": ["#9ef6ff"],
    # Elder Treant
    "bark": ["#24160e", "#3e2816", "#5e3e22", "#7e5830", "#a07a48"],
    "leaf": ["#14301a", "#22502a", "#38743a", "#5a9c48", "#8cc460"],
    "moss": ["#2e4a1e", "#4e7230", "#7a9e44"],
    "blossom": ["#f0a8c8"],
    "amber": ["#ffcc4a"],
    # Hollow King
    "robe": ["#160e1e", "#2a1838", "#40265a", "#5c3a7c", "#7e58a0"],
    "skull": ["#6a6458", "#a8a08a", "#d8d0b8", "#f4eedc"],
    "gold": ["#6a4410", "#a8701c", "#e0a82c", "#ffe07a"],
    "wood": ["#2a1a10", "#4a3018", "#6e4a26"],
    "soul": ["#8affb0"],
    "soul2": ["#d8ffe4"],
    # Sand Colossus
    "sand": ["#4a3420", "#7a5a34", "#a8824c", "#d0aa6a", "#ecd29a"],
    "rock": ["#2e2a2a", "#4e4844", "#76706a", "#9e9890"],
    "rune": ["#4af0e0"],
    "dust": ["#e8d4a4"],
    # Storm Roc
    "feather": ["#141a2a", "#222c46", "#34446a", "#4e6290", "#7488b4"],
    "plume": ["#3c3a5e", "#5e5a8a", "#8a86b6", "#bcb8e0"],
    "beak": ["#5a3a10", "#a0701c", "#e0b030", "#ffe27a"],
    "talon": ["#2a2420", "#5a504a", "#8a8078"],
    "spark": ["#fff8a0"],
    "spark2": ["#8ad8ff"],
    "eye": ["#ffe84a"],
    "eyered": ["#ff3a2a"],
    "ink": ["#140c12"],
}
GLOW = {"lava", "fire", "fire2", "fire3", "frostglow", "blossom", "amber", "soul", "soul2", "rune", "dust",
        "spark", "spark2", "eye", "eyered", "ink"}
DITHER = {"scale", "membrane", "frost", "fur", "bark", "leaf", "robe", "sand", "rock", "feather", "plume"}


class Canvas:
    """Shapes in materials, each pixel with the light it gets (-1 dark .. 1 lit)."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.mat = [[None] * w for _ in range(h)]
        self.light = [[0.0] * w for _ in range(h)]

    def put(self, x, y, m, light=0.0):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.mat[y][x] = m
            self.light[y][x] = light

    def _fill(self, mask_draw, m, bbox, lift=0.0):
        """Fills the pixels of a PIL mask; light falls from the top left of the shape's box."""
        mask = Image.new("L", (self.w, self.h), 0)
        mask_draw(ImageDraw.Draw(mask))
        x0, y0, x1, y1 = bbox
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        rx, ry = max(1.0, (x1 - x0) / 2), max(1.0, (y1 - y0) / 2)
        px = mask.load()
        for y in range(self.h):
            for x in range(self.w):
                if px[x, y]:
                    dx, dy = (x - cx) / rx, (y - cy) / ry
                    # Rounded: lit towards the top left, dark at the rim and below.
                    rim = min(1.0, dx * dx + dy * dy)
                    light = -0.35 * dx - 0.75 * dy + 0.25 - 0.45 * rim + lift
                    self.mat[y][x] = m
                    self.light[y][x] = max(-1.0, min(1.0, light))

    def ellipse(self, cx, cy, rx, ry, m, lift=0.0):
        box = (cx - rx, cy - ry, cx + rx, cy + ry)
        self._fill(lambda d: d.ellipse(box, fill=255), m, box, lift)

    def poly(self, pts, m, lift=0.0):
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        self._fill(lambda d: d.polygon(pts, fill=255), m, (min(xs), min(ys), max(xs), max(ys)), lift)

    def line(self, x0, y0, x1, y1, m, width=1, lift=0.0):
        box = (min(x0, x1) - width, min(y0, y1) - width, max(x0, x1) + width, max(y0, y1) + width)
        self._fill(lambda d: d.line([x0, y0, x1, y1], fill=255, width=width), m, box, lift)

    def rect(self, x0, y0, x1, y1, m, lift=0.0):
        self._fill(lambda d: d.rectangle([x0, y0, x1, y1], fill=255), m, (x0, y0, x1, y1), lift)

    def render(self):
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        px = img.load()
        filled = lambda x, y: 0 <= x < self.w and 0 <= y < self.h and self.mat[y][x] is not None
        for y in range(self.h):
            for x in range(self.w):
                m = self.mat[y][x]
                if m is None:
                    continue
                ramp = MATS[m]
                if m in GLOW:
                    px[x, y] = rgb(ramp[0]) + (255,)
                    continue
                v = (self.light[y][x] + 1) / 2 * (len(ramp) - 1)
                # The underside of a shape sits in shadow.
                if not filled(x, y + 1):
                    v -= 0.8
                base = int(math.floor(v))
                frac = v - base
                if m in DITHER and 0.3 < frac < 0.7 and (x + y) % 2 == 0:
                    base += 1
                elif frac >= 0.7:
                    base += 1
                base = max(0, min(len(ramp) - 1, base))
                px[x, y] = rgb(ramp[base]) + (255,)
        # Outline: the darkest shade of what it surrounds, darker still.
        out = img.copy()
        opx = out.load()
        for y in range(self.h):
            for x in range(self.w):
                if self.mat[y][x] is not None:
                    continue
                near = [self.mat[ny][nx] for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                        if 0 <= nx < self.w and 0 <= ny < self.h and self.mat[ny][nx] is not None]
                if not near:
                    continue
                glow = [m for m in near if m in GLOW and m != "ink"]
                if glow and len(glow) == len(near):
                    # Light spills around glowing things instead of an outline.
                    c = rgb(MATS[glow[0]][0])
                    opx[x, y] = c + (110,)
                    continue
                dark = rgb(MATS[[m for m in near if m not in GLOW or m == "ink"][0] if any(m not in GLOW or m == "ink" for m in near) else near[0]][0])
                opx[x, y] = tuple(int(v * 0.55) for v in dark) + (255,)
        return out


def pad(img, w, h):
    """Centres the drawing on a canvas of w x h with its feet on the bottom row."""
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(img, ((w - img.width) // 2, h - img.height))
    return out


# ---------------------------------------------------------------------------------- the legends

def ash_wyrm(pose):
    """A great dragon of the burning mountains: ember scales, lava cracks, bone horns, ragged wings."""
    W, H = 54, 30
    c = Canvas(W, H)
    step = {"walk1": 1, "walk2": -1}.get(pose, 0)
    wing = {"walk1": -2, "walk2": 1, "attack": -3}.get(pose, 0)
    lunge = 2 if pose == "attack" else 0
    # Far wing, behind the body.
    c.poly([(18, 12), (10 , 1 + wing), (16, 4 + wing), (24, 2 + wing), (27, 11)], "membrane", lift=-0.4)
    # Tail, tapering to the left, with spikes.
    c.poly([(14, 15), (2, 21), (0, 24), (5, 22), (15, 20)], "scale")
    for x in (4, 8, 12):
        c.poly([(x, 20 - (x - 2) // 4), (x + 1, 17 - (x - 2) // 4), (x + 2, 20 - (x - 2) // 4)], "bone")
    # Back legs.
    c.poly([(12 - step, 19), (16 - step, 19), (15 - step, 27), (11 - step, 27)], "scale", lift=-0.2)
    c.rect(10 - step, 27, 15 - step, 28, "bone")
    # Body and belly.
    c.ellipse(21, 18, 11, 6, "scale")
    c.ellipse(22, 21, 9, 3, "belly")
    for x in range(14, 30, 3):
        c.put(x, 21, "belly", -0.4)
    # Lava glowing between the scales.
    for (x, y) in ((17, 15), (18, 16), (23, 14), (24, 15), (28, 17), (13, 17), (20, 19)):
        c.put(x, y, "lava")
    # Spines along the back.
    for x in range(12, 30, 3):
        c.poly([(x, 13), (x + 1, 9), (x + 2, 13)], "bone")
    # Front legs.
    c.poly([(26 + step, 19), (30 + step, 19), (30 + step + lunge, 27), (26 + step + lunge, 27)], "scale", lift=0.1)
    c.rect(26 + step + lunge, 27, 31 + step + lunge, 28, "bone")
    # Neck and head.
    hx = 37 + lunge
    c.poly([(26, 16), (30, 10), (hx - 3, 5), (hx, 8), (32, 14), (30, 18)], "scale", lift=0.15)
    c.ellipse(hx, 7, 5, 3, "scale", lift=0.2)
    c.poly([(hx + 1, 6), (hx + 8, 7), (hx + 7, 9), (hx + 1, 9)], "scale", lift=0.1)  # snout
    if pose == "attack":
        c.poly([(hx + 1, 10), (hx + 7, 12), (hx + 1, 12)], "scale", lift=-0.3)  # open jaw
    c.poly([(hx - 3, 4), (hx - 8, 0), (hx - 1, 4)], "bone")  # horns
    c.poly([(hx - 1, 4), (hx - 3, 1), (hx + 1, 4)], "bone")
    c.put(hx + 2, 6, "eye")
    c.put(hx + 3, 6, "eye")
    c.put(hx + 7, 7, "ink")
    # Near wing, over the body, with its bone spars.
    c.poly([(19, 13), (12, 3 + wing), (18, 6 + wing), (23, 4 + wing), (29, 6 + wing), (26, 13)], "membrane")
    c.line(19, 13, 12, 3 + wing, "bone")
    c.line(20, 13, 23, 4 + wing, "bone")
    c.line(24, 13, 29, 6 + wing, "bone")
    if pose == "attack":
        # Fire breath.
        c.poly([(hx + 7, 10), (W - 1, 4), (W - 2, 13), (W - 1, 18)], "fire3")
        c.poly([(hx + 7, 10), (W - 2, 7), (W - 3, 11), (W - 2, 15)], "fire2")
        c.poly([(hx + 7, 10), (W - 4, 9), (W - 4, 12)], "fire")
    return c.render()


def frost_titan(pose):
    """A giant of the frozen north: ice-blue skin, a mane of white fur, crystal shoulders, glowing eyes."""
    W, H = 28, 34
    c = Canvas(W, H)
    step = {"walk1": 1, "walk2": -1}.get(pose, 0)
    # Legs and feet.
    c.rect(9, 23 + max(0, -step), 12, 31, "frost", lift=-0.2)
    c.rect(15, 23 + max(0, step), 18, 31, "frost", lift=-0.2)
    c.rect(8, 31, 12, 33, "ice")
    c.rect(15, 31, 19, 33, "ice")
    # Loincloth of fur.
    c.poly([(8, 21), (19, 21), (18, 26), (14, 24), (9, 26)], "fur")
    # Torso.
    c.ellipse(13.5, 16, 7, 7, "frost")
    c.ellipse(13.5, 15, 4, 3, "frost", lift=0.35)
    # Mane of fur around the neck.
    c.ellipse(13.5, 9, 6, 3, "fur", lift=0.2)
    # Head and icy beard.
    c.ellipse(13.5, 5, 4, 4, "frost", lift=0.1)
    c.rect(11, 4, 16, 6, "frost", lift=-0.9)  # a shadowed brow and face
    c.poly([(10, 7), (17, 7), (13.5, 13)], "fur", lift=0.4)  # white beard
    c.put(12, 5, "frostglow")
    c.put(15, 5, "frostglow")
    c.poly([(10, 3), (6, -1), (11, 1)], "ice")
    c.poly([(17, 3), (21, -1), (16, 1)], "ice")
    # Crystal shoulders.
    for sx, d in ((6, -1), (21, 1)):
        c.poly([(sx, 11), (sx + 2 * d, 6), (sx + 3 * d, 10), (sx + 1 * d, 13)], "ice")
        c.put(sx + 2 * d, 8, "frostglow")
    # Arms.
    if pose == "attack":
        c.line(20, 12, 24, 4, "frost", 3)
        c.ellipse(24, 3, 2.5, 2.5, "ice")  # a fist of ice raised to strike
        c.line(7, 12, 5, 21, "frost", 3)
        c.ellipse(5, 22, 2, 2, "frost")
        for (x, y) in ((22, 1), (26, 2), (25, 6)):
            c.put(x, y, "frostglow")
    else:
        sw = step
        c.line(7, 12, 5 - sw, 21, "frost", 3)
        c.line(20, 12, 22 + sw, 21, "frost", 3)
        c.ellipse(5 - sw, 22, 2, 2, "frost")
        c.ellipse(22 + sw, 22, 2, 2, "frost")
    return c.render()


def elder_treant(pose):
    """An ancient walking tree: bark body, root legs, a crown of leaves with blossoms, amber eyes."""
    W, H = 30, 36
    c = Canvas(W, H)
    step = {"walk1": 1, "walk2": -1}.get(pose, 0)
    # Roots as legs.
    c.poly([(10, 26), (13, 26), (11 - step, 34), (6 - step, 35), (8 - step, 32)], "bark", lift=-0.2)
    c.poly([(16, 26), (19, 26), (22 + step, 32), (24 + step, 35), (18 + step, 34)], "bark", lift=-0.2)
    # Trunk.
    c.poly([(10, 27), (9, 14), (11, 10), (18, 10), (20, 14), (19, 27)], "bark")
    for y in range(13, 27, 3):
        c.put(12 + (y % 2), y, "bark", -0.8)
        c.put(16 + (y % 3), y + 1, "bark", -0.8)
    c.ellipse(11, 22, 2, 1.5, "moss")
    c.ellipse(18, 17, 1.5, 1, "moss")
    # A face in the bark.
    c.put(12, 16, "amber")
    c.put(16, 16, "amber")
    c.line(12, 19, 16, 19, "bark", 1, lift=-0.9)
    # Branch arms.
    if pose == "attack":
        c.line(19, 14, 27, 10, "bark", 2)
        for x, y in ((28, 9), (27, 12), (25, 8), (29, 11)):
            c.put(x, y, "bark", 0.5)  # thorns
        c.line(10, 14, 4, 21, "bark", 2)
    else:
        c.line(19, 14, 25, 19 + step, "bark", 2)
        c.line(10, 14, 4, 19 - step, "bark", 2)
        c.line(25, 19 + step, 27, 17 + step, "bark", 1)
        c.line(4, 19 - step, 2, 17 - step, "bark", 1)
    # Crown of leaves.
    c.ellipse(14.5, 6, 11, 6, "leaf")
    c.ellipse(8, 8, 5, 3.5, "leaf", lift=-0.2)
    c.ellipse(21, 8, 5, 3.5, "leaf", lift=-0.2)
    c.ellipse(14.5, 3, 6, 3, "leaf", lift=0.3)
    rnd = random.Random(7)
    for _ in range(9):
        c.put(rnd.randint(5, 24), rnd.randint(1, 10), "blossom")
    return c.render()


def hollow_king(pose):
    """A crowned lich floating in a ragged robe, a staff with a soul-fire orb, green eyes."""
    W, H = 26, 32
    c = Canvas(W, H)
    bob = {"walk1": -1, "walk2": 0}.get(pose, 0)
    y0 = bob
    # Ghostly wisps under the robe.
    for x, y in ((7, 30), (10, 31), (14, 30), (17, 31), (12, 29)):
        c.put(x, y + y0, "soul2" if x % 2 else "soul")
    # Ragged robe.
    c.poly([(8, 10 + y0), (18, 10 + y0), (21, 28 + y0), (18, 26 + y0), (16, 29 + y0), (13, 26 + y0),
            (10, 29 + y0), (8, 26 + y0), (5, 28 + y0)], "robe")
    c.line(13, 12 + y0, 13, 26 + y0, "robe", 1, lift=-0.7)
    c.poly([(9, 10 + y0), (17, 10 + y0), (13, 15 + y0)], "gold")  # collar
    # Skull and crown.
    c.ellipse(13, 7 + y0, 3.5, 3.5, "skull", lift=0.2)
    c.rect(11, 9 + y0, 15, 10 + y0, "skull", lift=-0.2)
    c.put(12, 7 + y0, "soul")
    c.put(14, 7 + y0, "soul")
    c.put(13, 9 + y0, "ink")
    c.poly([(9, 4 + y0), (10, 0 + y0), (11, 3 + y0), (13, 0 + y0), (15, 3 + y0), (16, 0 + y0), (17, 4 + y0)], "gold")
    c.put(13, 2 + y0, "eyered")
    # Bony hands and the staff.
    sx = 20 if pose != "attack" else 22
    top = 2 if pose != "attack" else -1
    c.line(sx, top + 4 + y0, sx, 29 + y0, "wood", 1)
    c.ellipse(sx, top + 2 + y0, 2, 2, "soul")
    c.put(sx, top + 2 + y0, "soul2")
    c.line(17, 13 + y0, sx - 1, 16 + y0, "robe", 2)
    c.put(sx - 1, 16 + y0, "skull", 0.5)
    c.line(9, 13 + y0, 6, 19 + y0, "robe", 2)
    c.put(6, 20 + y0, "skull", 0.5)
    if pose == "attack":
        for k in range(4):
            c.put(sx + 1 + k, top + 2 + y0 + (k % 2), "soul2" if k % 2 else "soul")
    return c.render()


def sand_colossus(pose):
    """A giant of sandstone and boulders, with turquoise runes that glow on its chest and face."""
    W, H = 32, 34
    c = Canvas(W, H)
    step = {"walk1": 1, "walk2": -1}.get(pose, 0)
    # Legs of stacked stone.
    c.rect(9, 24 + max(0, -step), 13, 31, "sand", lift=-0.2)
    c.rect(18, 24 + max(0, step), 22, 31, "sand", lift=-0.2)
    c.rect(8, 31, 14, 33, "rock")
    c.rect(17, 31, 23, 33, "rock")
    # Body: a great boulder.
    c.ellipse(15.5, 17, 9, 8, "sand")
    c.ellipse(15.5, 14, 6, 4, "sand", lift=0.3)
    for (x0, y0, x1, y1) in ((11, 12, 13, 18), (18, 20, 21, 22), (20, 11, 22, 14)):
        c.line(x0, y0, x1, y1, "sand", 1, lift=-0.9)  # cracks
    # Runes.
    for (x, y) in ((15, 15), (16, 15), (15, 16), (16, 17), (14, 18), (17, 18), (12, 21), (19, 13)):
        c.put(x, y, "rune")
    # Head, small and square.
    c.rect(12, 4, 19, 9, "rock", lift=0.2)
    c.put(14, 6, "rune")
    c.put(17, 6, "rune")
    c.rect(11, 3, 20, 4, "sand", lift=0.4)
    # Arms of boulders.
    if pose == "attack":
        c.ellipse(26, 5, 3.5, 3, "rock")
        c.line(23, 11, 26, 6, "sand", 4)
        c.ellipse(5, 24, 3.5, 3, "rock")
        c.line(8, 13, 5, 22, "sand", 4)
        for (x, y) in ((24, 1), (28, 1), (30, 3), (2, 30), (6, 31), (10, 30)):
            c.put(x, y, "dust")
    else:
        c.line(8, 13, 5 - step, 22, "sand", 4)
        c.line(23, 13, 26 + step, 22, "sand", 4)
        c.ellipse(5 - step, 24, 3.5, 3, "rock")
        c.ellipse(26 + step, 24, 3.5, 3, "rock")
    # Sand trickling down.
    for (x, y) in ((7, 28), (25, 29), (15, 26)):
        c.put(x, y, "dust")
    return c.render()


def storm_roc(pose):
    """A giant bird of the high peaks: slate feathers, wings spread wide, a golden beak and
    lightning crackling on its wing tips."""
    W, H = 40, 30
    c = Canvas(W, H)
    flap = {"idle": 0, "walk1": -3, "walk2": 2, "attack": -4}.get(pose, 0)
    # Far wing.
    c.poly([(17, 14), (6, 4 + flap), (12, 6 + flap), (22, 10)], "feather", lift=-0.5)
    # Tail.
    c.poly([(12, 17), (1, 14), (0, 18), (2, 22), (12, 20)], "plume")
    c.line(1, 16, 11, 18, "plume", 1, lift=-0.6)
    c.line(1, 20, 11, 19, "plume", 1, lift=-0.6)
    # Legs and talons.
    c.line(18, 21, 17, 27, "talon", 2)
    c.line(23, 21, 24, 27, "talon", 2)
    c.rect(15, 27, 19, 28, "talon")
    c.rect(22, 27, 26, 28, "talon")
    # Body.
    c.ellipse(20, 17, 9, 5.5, "feather")
    c.ellipse(22, 19, 6, 3, "plume", lift=0.2)
    # Neck and head.
    hx = 30 + (2 if pose == "attack" else 0)
    c.poly([(26, 15), (hx - 2, 8), (hx + 2, 9), (29, 17)], "feather", lift=0.2)
    c.ellipse(hx, 8, 3.5, 3, "feather", lift=0.3)
    c.poly([(hx - 3, 6), (hx - 7, 3), (hx - 2, 5)], "plume")  # crest
    c.poly([(hx + 3, 7), (hx + 7, 9), (hx + 5, 11), (hx + 3, 10)], "beak")
    c.put(hx + 1, 7, "eye")
    # Near wing, spread, with layered feathers.
    c.poly([(17, 15), (3, 1 + flap), (10, 2 + flap), (16, 4 + flap), (24, 8), (27, 14)], "feather")
    for k in range(4):
        x = 5 + k * 4
        c.line(x, 2 + flap + k, x + 6, 9 + k, "plume", 1)
    # Lightning on the wing tips.
    for (x, y) in ((3, 0), (2, 2), (5, 0), (1, 1)):
        c.put(x, y + flap, "spark")
    c.put(4, 1 + flap, "spark2")
    if pose == "attack":
        # A bolt thrown down to the right.
        pts = [(hx + 6, 12), (hx + 4, 16), (hx + 7, 17), (hx + 5, 22), (hx + 8, 26)]
        for (a, b) in zip(pts, pts[1:]):
            c.line(a[0], a[1], b[0], b[1], "spark", 1)
        c.put(hx + 7, 17, "spark2")
    return c.render()


LEGENDS = {
    "ash_wyrm": ash_wyrm, "frost_titan": frost_titan, "elder_treant": elder_treant,
    "hollow_king": hollow_king, "sand_colossus": sand_colossus, "storm_roc": storm_roc,
}


# ---------------------------------------------------------------------------------- poses

def swim(img):
    """Only the upper body shows above the water, with a waterline."""
    cut = int(img.height * 0.68)
    out = Image.new("RGBA", (img.width, cut + 1), (0, 0, 0, 0))
    out.alpha_composite(img.crop((0, 0, img.width, cut)))
    px = out.load()
    for x in range(img.width):
        if any(px[x, y][3] for y in range(cut)):
            px[x, cut] = (120, 200, 240, 210)
    return out


def death(img):
    """A tall legend falls on its side, a long one rolls over; darkened."""
    out = img.rotate(-90, expand=True) if img.height > img.width else img.transpose(Image.FLIP_TOP_BOTTOM)
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (int(r * 0.75), int(g * 0.75), int(b * 0.75), a)
    return out


def poses(draw):
    idle = draw("idle")
    return {
        "idle": idle, "walk1": draw("walk1"), "walk2": draw("walk2"), "attack": draw("attack"),
        "swim": swim(idle), "death": death(idle),
    }


IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
path="res://.godot/imported/{name}-{md5}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://assets/sprites/creatures/{name}"
dest_files=["res://.godot/imported/{name}-{md5}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def write_import(name):
    """The .import file Godot would write (Godot rewrites it if anything differs)."""
    path = OUT / (name + ".import")
    if path.exists():
        return
    md5 = hashlib.md5(f"res://assets/sprites/creatures/{name}".encode()).hexdigest()
    alphabet = "abcdefghijklmnopqrstuvwxy0123456789"
    seed = int(md5[:12], 16)
    uid = ""
    while seed:
        seed, r = divmod(seed, len(alphabet))
        uid += alphabet[r]
    path.write_text(IMPORT.format(uid=uid or "a", name=name, md5=md5))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    frames = {name: poses(draw) for name, draw in LEGENDS.items()}
    for name, fs in frames.items():
        for pose, img in fs.items():
            img.save(OUT / f"{name}_{pose}.png")
            write_import(f"{name}_{pose}.png")
    # Preview: one row per legend, its poses side by side, scaled up 4x, over grass.
    scale, cw, ch = 4, 58, 40
    sheet = Image.new("RGBA", (len(POSES) * cw * scale, len(frames) * ch * scale), (74, 120, 62, 255))
    for row, (name, fs) in enumerate(frames.items()):
        for col, pose in enumerate(POSES):
            img = fs[pose]
            x0 = col * cw + (cw - img.width) // 2
            y0 = row * ch + ch - img.height - 3
            sheet.alpha_composite(img.resize((img.width * scale, img.height * scale), Image.NEAREST), (x0 * scale, y0 * scale))
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(SHEET)
    print(f"{len(frames)} legends x {len(POSES)} poses -> {OUT}")


if __name__ == "__main__":
    main()
