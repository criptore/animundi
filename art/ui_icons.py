"""Draws the interface's pixel-art icons (16x16, dark outline, one shade) into one atlas,
assets/ui/icons.png, with their names in scripts/generated/ui_icons.gd, and the game's emblem
(assets/ui/emblem.png, 32x32).

    python3 art/ui_icons.py

Each icon is a few shapes drawn inside the 14x14 middle of its cell; the outline and the darker
underside are added afterwards, so every icon shares the same look.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SIZE = 16
COLUMNS = 12

INK = (26, 15, 22, 255)
C = {
    "cream": (244, 230, 200), "bone": (206, 186, 156), "gold": (242, 184, 75), "dgold": (190, 122, 40),
    "red": (216, 51, 74), "dred": (140, 29, 46), "orange": (240, 138, 42), "yellow": (255, 226, 110),
    "blue": (73, 160, 223), "lblue": (150, 218, 255), "dblue": (42, 92, 160), "green": (108, 190, 84),
    "dgreen": (58, 128, 62), "purple": (165, 99, 208), "dpurple": (94, 58, 122), "grey": (150, 146, 158),
    "dgrey": (92, 88, 102), "lgrey": (208, 206, 216), "brown": (150, 98, 50), "dbrown": (96, 62, 34),
    "white": (255, 255, 255), "pink": (244, 154, 193), "ink": INK[:3],
}


class Pen:
    """Pixel-exact shapes on one icon. Coordinates are inclusive, in icon pixels."""

    def __init__(self, size=SIZE):
        self.img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def _c(self, colour):
        return (0, 0, 0, 0) if colour is None else C[colour] + (255,)

    def p(self, colour, *points):
        for x, y in points:
            self.img.putpixel((x, y), self._c(colour))

    def r(self, colour, x0, y0, x1, y1):
        self.d.rectangle([x0, y0, x1, y1], fill=self._c(colour))

    def e(self, colour, x0, y0, x1, y1):
        self.d.ellipse([x0, y0, x1, y1], fill=self._c(colour))

    def g(self, colour, points):
        self.d.polygon(points, fill=self._c(colour))

    def l(self, colour, x0, y0, x1, y1, width=1):
        self.d.line([x0, y0, x1, y1], fill=self._c(colour), width=width)

    def finish(self):
        """Darkens the underside of the shapes, then outlines them in ink."""
        img = self.img
        w, h = img.size
        src = img.copy()
        for y in range(h):
            for x in range(w):
                r, g, b, a = src.getpixel((x, y))
                if a and (r, g, b) != INK[:3] and (y + 1 >= h or src.getpixel((x, y + 1))[3] == 0):
                    img.putpixel((x, y), (int(r * 0.74), int(g * 0.7), int(b * 0.74), 255))
        src = img.copy()
        for y in range(h):
            for x in range(w):
                if src.getpixel((x, y))[3]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and src.getpixel((nx, ny))[3]:
                        img.putpixel((x, y), INK)
                        break
        return img


# ---------------------------------------------------------------- shapes shared by several icons

def skull(k, bone="cream", eyes="ink"):
    k.e(bone, 3, 1, 12, 10)
    k.r(bone, 5, 10, 10, 13)
    k.r(eyes, 4, 5, 6, 7)
    k.r(eyes, 9, 5, 11, 7)
    k.p("ink", (7, 9), (8, 9), (6, 12), (6, 13), (9, 12), (9, 13))


def four_star(k, colour, core):
    k.g(colour, [(7, 1), (8, 1), (9, 6), (14, 7), (14, 8), (9, 9), (8, 14), (7, 14), (6, 9), (1, 8), (1, 7), (6, 6)])
    k.r(core, 7, 7, 8, 8)


def sun(k):
    k.e("yellow", 4, 4, 11, 11)
    k.r("gold", 7, 1, 8, 2)
    k.r("gold", 7, 13, 8, 14)
    k.r("gold", 1, 7, 2, 8)
    k.r("gold", 13, 7, 14, 8)
    k.p("gold", (3, 3), (12, 3), (3, 12), (12, 12))
    k.p("white", (6, 6), (7, 6), (6, 7))


def snowflake(k):
    k.r("lblue", 7, 1, 8, 14)
    k.r("lblue", 1, 7, 14, 8)
    k.l("lblue", 3, 3, 12, 12)
    k.l("lblue", 12, 3, 3, 12)
    k.r("white", 7, 7, 8, 8)


def leaf(k, colour, vein):
    k.g(colour, [(3, 12), (3, 6), (7, 2), (12, 2), (12, 7), (8, 12)])
    k.l(vein, 2, 13, 10, 5)
    k.p(vein, (6, 7), (9, 8))


def eye(k, white, iris, pupil):
    k.g(white, [(1, 7), (4, 4), (11, 4), (14, 7), (14, 8), (11, 11), (4, 11), (1, 8)])
    k.e(iris, 5, 5, 10, 10)
    k.r(pupil, 7, 7, 8, 8)
    k.p("white", (6, 6))


def mountain(k):
    k.g("grey", [(1, 13), (6, 3), (9, 8), (11, 6), (14, 13)])
    k.g("white", [(6, 3), (7, 5), (6, 6), (5, 5)])
    k.p("white", (11, 6), (11, 7))
    k.l("dgrey", 7, 8, 9, 12)


def drop(k):
    k.g("blue", [(7, 1), (8, 1), (12, 8), (12, 11), (10, 13), (5, 13), (3, 11), (3, 8)])
    k.p("lblue", (5, 8), (5, 9), (5, 10), (6, 11))


def arrow(k, colour, up, y):
    k.r(colour, 7, y, 8, y + 5)
    tip = y if up else y + 5
    step = 1 if up else -1
    k.p(colour, (6, tip + step), (9, tip + step), (5, tip + 2 * step), (10, tip + 2 * step), (6, tip + 2 * step), (9, tip + 2 * step))


# ---------------------------------------------------------------- the icons

def menu(k):
    for y in (3, 7, 11):
        k.r("cream", 2, y, 13, y + 1)


def pause(k):
    k.r("cream", 3, 2, 6, 13)
    k.r("cream", 9, 2, 12, 13)


def play(k):
    k.g("cream", [(4, 2), (12, 7), (12, 8), (4, 13)])


def fast(k):
    k.g("gold", [(1, 3), (6, 7), (6, 8), (1, 12)])
    k.g("gold", [(8, 3), (13, 7), (13, 8), (8, 12)])


def hourglass(k):
    k.r("gold", 3, 1, 12, 2)
    k.r("gold", 3, 13, 12, 14)
    k.g("lblue", [(4, 3), (11, 3), (8, 7), (7, 7)])
    k.g("cream", [(7, 8), (8, 8), (11, 12), (4, 12)])
    k.p("yellow", (7, 9), (8, 10))


def gear(k):
    k.r("grey", 6, 1, 9, 14)
    k.r("grey", 1, 6, 14, 9)
    k.e("grey", 2, 2, 13, 13)
    k.e("lgrey", 4, 4, 11, 11)
    k.e("ink", 6, 6, 9, 9)


def close(k):
    k.l("cream", 3, 3, 12, 12, 2)
    k.l("cream", 12, 3, 3, 12, 2)


def crown(k):
    k.g("gold", [(2, 12), (2, 5), (5, 8), (7, 3), (8, 3), (10, 8), (13, 5), (13, 12)])
    k.r("dgold", 2, 11, 13, 12)
    k.p("red", (7, 9), (8, 9), (4, 10), (11, 10))
    k.p("yellow", (7, 4), (2, 6), (13, 6))


def house(k):
    k.r("cream", 3, 8, 12, 13)
    k.g("red", [(1, 8), (7, 2), (8, 2), (14, 8)])
    k.r("brown", 7, 10, 8, 13)
    k.p("lblue", (4, 10), (5, 10), (10, 10), (11, 10))


def paw(k):
    k.e("brown", 4, 7, 11, 13)
    k.e("brown", 1, 5, 4, 8)
    k.e("brown", 4, 1, 7, 5)
    k.e("brown", 8, 1, 11, 5)
    k.e("brown", 11, 5, 14, 8)


def bulb(k):
    k.e("yellow", 4, 1, 11, 9)
    k.r("yellow", 6, 9, 9, 10)
    k.r("grey", 6, 11, 9, 12)
    k.r("dgrey", 7, 13, 8, 13)
    k.p("white", (6, 3), (6, 4), (7, 3))


def scroll(k):
    k.r("cream", 3, 3, 12, 12)
    k.r("bone", 2, 2, 13, 3)
    k.r("bone", 2, 12, 13, 13)
    k.l("brown", 5, 6, 10, 6)
    k.l("brown", 5, 8, 10, 8)
    k.l("brown", 5, 10, 8, 10)


def scales(k):
    k.r("gold", 7, 2, 8, 12)
    k.r("gold", 2, 3, 13, 3)
    k.r("dgold", 5, 13, 10, 13)
    k.g("gold", [(1, 8), (5, 8), (4, 10), (2, 10)])
    k.g("gold", [(10, 8), (14, 8), (13, 10), (11, 10)])
    k.p("bone", (3, 4), (3, 5), (3, 6), (3, 7), (12, 4), (12, 5), (12, 6), (12, 7))


def layers(k):
    for colour, y in (("dblue", 6), ("green", 3), ("cream", 0)):
        k.g(colour, [(7, y + 2), (8, y + 2), (14, y + 5), (8, y + 8), (7, y + 8), (1, y + 5)])
        k.l("ink", 1, y + 6, 7, y + 9)
        k.l("ink", 14, y + 6, 8, y + 9)


def chart(k):
    k.r("cream", 1, 13, 14, 14)
    k.r("red", 2, 8, 4, 12)
    k.r("gold", 6, 3, 8, 12)
    k.r("green", 10, 6, 12, 12)


def save(k):
    k.r("blue", 2, 2, 13, 13)
    k.r("cream", 4, 2, 10, 6)
    k.r("dgrey", 8, 3, 9, 5)
    k.r("lgrey", 4, 9, 11, 13)


def load(k):
    k.r("dgold", 2, 3, 7, 5)
    k.r("gold", 2, 5, 13, 12)
    k.r("yellow", 2, 7, 13, 7)


def door(k):
    k.r("dbrown", 3, 2, 12, 13)
    k.r("brown", 5, 3, 10, 13)
    k.p("gold", (9, 8), (9, 9))


def people(k):
    k.e("cream", 5, 2, 10, 7)
    k.g("blue", [(2, 14), (3, 10), (5, 8), (10, 8), (12, 10), (13, 14)])


def lock(k):
    k.r("grey", 5, 2, 10, 3)
    k.r("grey", 4, 3, 5, 7)
    k.r("grey", 10, 3, 11, 7)
    k.r("gold", 3, 7, 12, 13)
    k.p("ink", (7, 9), (8, 9), (7, 10), (8, 10), (7, 11), (8, 11))


def plus(k):
    k.r("cream", 6, 3, 9, 12)
    k.r("cream", 3, 6, 12, 9)


def minus(k):
    k.r("cream", 3, 6, 12, 9)


def target(k):
    k.e("cream", 2, 2, 13, 13)
    k.e(None, 4, 4, 11, 11)
    k.e("red", 6, 6, 9, 9)
    k.r("cream", 7, 1, 8, 3)
    k.r("cream", 7, 12, 8, 14)
    k.r("cream", 1, 7, 3, 8)
    k.r("cream", 12, 7, 14, 8)


def globe(k):
    k.e("blue", 2, 2, 13, 13)
    k.r("green", 4, 4, 7, 6)
    k.r("green", 5, 6, 6, 8)
    k.r("green", 9, 7, 12, 10)
    k.r("green", 8, 10, 10, 11)
    k.p("lblue", (10, 3), (11, 4))


def dice(k):
    k.r("cream", 2, 2, 13, 13)
    for x, y in ((4, 4), (10, 4), (7, 7), (4, 10), (10, 10)):
        k.r("ink", x, y, x + 1, y + 1)


def search(k):
    k.l("brown", 9, 9, 13, 13, 3)
    k.e("cream", 1, 1, 10, 10)
    k.e("lblue", 3, 3, 8, 8)
    k.p("white", (4, 4), (5, 4))


def swords(k):
    k.l("lgrey", 3, 2, 11, 10, 2)
    k.l("lgrey", 12, 2, 4, 10, 2)
    k.r("gold", 2, 11, 4, 13)
    k.r("gold", 11, 11, 13, 13)
    k.p("dgold", (5, 10), (10, 10), (4, 9), (11, 9))


def dove(k):
    k.e("white", 3, 6, 11, 12)
    k.e("white", 9, 3, 13, 7)
    k.g("lgrey", [(3, 7), (6, 1), (9, 8)])
    k.g("white", [(1, 9), (4, 8), (4, 11)])
    k.p("orange", (14, 5))
    k.p("ink", (11, 5))
    k.p("green", (14, 7), (13, 8), (14, 9))


def rings(k):
    k.e("gold", 1, 4, 9, 12)
    k.e(None, 3, 6, 7, 10)
    k.e("yellow", 6, 4, 14, 12)
    k.e(None, 8, 6, 12, 10)
    k.p("gold", (8, 5), (9, 6), (9, 7))


def flag(k):
    k.r("brown", 3, 1, 4, 14)
    k.g("red", [(5, 2), (13, 4), (13, 6), (5, 9)])
    k.p("gold", (3, 1), (4, 1))


def book(k):
    k.r("dpurple", 2, 3, 13, 13)
    k.r("purple", 3, 2, 13, 11)
    k.r("cream", 4, 12, 12, 12)
    k.r("gold", 6, 5, 10, 8)
    k.p("purple", (8, 6), (8, 7))


def ankh(k):
    k.e("gold", 5, 1, 10, 7)
    k.e(None, 7, 3, 8, 5)
    k.r("gold", 7, 7, 8, 14)
    k.r("gold", 4, 8, 11, 9)


def note(k):
    k.r("cream", 6, 2, 12, 3)
    k.r("cream", 6, 2, 6, 11)
    k.r("cream", 12, 2, 12, 9)
    k.e("cream", 2, 10, 6, 13)
    k.e("cream", 8, 8, 12, 11)


def monitor(k):
    k.r("grey", 1, 2, 14, 10)
    k.r("lblue", 2, 3, 13, 9)
    k.r("grey", 7, 11, 8, 12)
    k.r("grey", 4, 13, 11, 13)
    k.p("white", (3, 4), (4, 4), (3, 5))


def keys(k):
    k.r("grey", 1, 4, 14, 12)
    for x in (3, 6, 9, 12):
        k.p("cream", (x, 6), (x, 8))
    k.r("cream", 4, 10, 11, 10)


def info(k):
    k.e("blue", 2, 2, 13, 13)
    k.r("white", 7, 7, 8, 11)
    k.r("white", 7, 4, 8, 5)


def star(k):
    k.g("gold", [(7, 1), (8, 1), (10, 6), (14, 6), (11, 9), (12, 14), (8, 11), (7, 11), (3, 14), (4, 9), (1, 6), (5, 6)])
    k.p("yellow", (7, 4), (7, 5), (6, 7))


def heart(k):
    k.g("red", [(2, 5), (4, 3), (6, 3), (7, 5), (8, 5), (9, 3), (11, 3), (13, 5), (13, 8), (8, 13), (7, 13), (2, 8)])
    k.p("pink", (4, 5), (4, 6), (5, 5))


def fire(k):
    k.g("red", [(7, 1), (11, 6), (12, 10), (10, 13), (5, 13), (3, 10), (4, 6), (6, 5)])
    k.g("orange", [(7, 5), (10, 9), (9, 13), (6, 13), (5, 10)])
    k.g("yellow", [(7, 9), (9, 11), (8, 13), (7, 13), (6, 11)])


def lightning(k):
    k.g("yellow", [(9, 1), (4, 8), (7, 8), (5, 14), (12, 6), (8, 6), (11, 1)])
    k.p("white", (9, 2), (8, 3))


def rain(k):
    k.e("lgrey", 1, 3, 8, 8)
    k.e("lgrey", 5, 1, 13, 8)
    k.r("lgrey", 3, 6, 13, 8)
    k.p("white", (7, 3), (8, 3), (6, 4))
    for x in (3, 7, 11):
        k.p("blue", (x + 1, 10), (x, 11), (x, 12))


def meteor(k):
    k.g("red", [(5, 6), (14, 1), (11, 10)])
    k.g("yellow", [(7, 7), (13, 3), (10, 9)])
    k.e("brown", 2, 7, 9, 14)
    k.p("dbrown", (4, 10), (6, 12), (7, 9))


def smite(k):
    skull(k, "cream", "red")


def bless(k):
    four_star(k, "gold", "white")
    k.p("yellow", (12, 2), (3, 12), (12, 12), (3, 3))


def curse(k):
    eye(k, "dpurple", "purple", "yellow")
    k.p("purple", (3, 1), (7, 1), (11, 1), (5, 13), (9, 13))


def heal(k):
    k.r("green", 6, 2, 9, 13)
    k.r("green", 2, 6, 13, 9)
    k.p("white", (7, 3), (7, 4), (3, 7), (4, 7))


def sprout(k):
    k.r("dgreen", 7, 7, 8, 12)
    k.g("green", [(8, 7), (12, 2), (13, 6), (10, 8)])
    k.g("green", [(7, 8), (3, 4), (2, 8), (5, 10)])
    k.r("brown", 4, 12, 11, 14)


def tornado(k):
    for colour, x0, x1, y in (("lgrey", 2, 13, 2), ("grey", 3, 12, 4), ("lgrey", 5, 12, 6), ("grey", 6, 10, 8),
            ("lgrey", 6, 9, 10), ("grey", 7, 8, 12)):
        k.r(colour, x0, y, x1, y + 1)


def quake(k):
    k.r("brown", 1, 8, 14, 13)
    k.r("green", 1, 7, 14, 8)
    k.l("ink", 7, 7, 6, 9)
    k.l("ink", 6, 9, 9, 11)
    k.l("ink", 9, 11, 8, 13)
    k.p("cream", (3, 2), (4, 3), (3, 4), (12, 2), (11, 3), (12, 4), (7, 1), (8, 2), (7, 3), (8, 4))


def flood(k):
    for colour, y in (("lblue", 3), ("blue", 7), ("dblue", 11)):
        for x in range(1, 15):
            dy = (0, -1, -1, 0, 1, 1)[x % 6]
            k.p(colour, (x, y + dy), (x, y + dy + 1))


def volcano(k):
    k.g("dgrey", [(1, 14), (5, 6), (10, 6), (14, 14)])
    k.g("red", [(5, 6), (10, 6), (9, 9), (8, 7), (7, 10), (6, 7)])
    k.p("orange", (7, 4), (8, 3), (7, 2), (9, 4), (6, 4), (8, 1))
    k.p("yellow", (7, 5), (8, 5))


def plague(k):
    skull(k, "green", "ink")
    k.p("dgreen", (2, 12), (2, 13), (13, 11), (13, 12))


def raise_(k):
    k.g("grey", [(1, 14), (5, 9), (10, 9), (14, 14)])
    arrow(k, "green", True, 2)


def lower(k):
    k.r("grey", 1, 11, 14, 14)
    k.r(None, 5, 11, 10, 12)
    arrow(k, "red", False, 2)


def stamp(k):
    k.r("brown", 6, 1, 9, 6)
    k.r("dbrown", 4, 7, 11, 9)
    k.r("red", 2, 10, 13, 12)
    k.r("dred", 2, 13, 13, 13)


def spiral(k):
    k.e("purple", 1, 1, 14, 14)
    k.e(None, 3, 3, 12, 12)
    k.e("purple", 5, 5, 10, 10)
    k.e(None, 7, 7, 8, 8)
    k.r(None, 8, 1, 14, 4)
    k.r("purple", 8, 3, 9, 6)


def grave(k):
    k.e("grey", 4, 2, 11, 8)
    k.r("grey", 4, 5, 11, 13)
    k.r("dgrey", 7, 4, 8, 10)
    k.r("dgrey", 6, 6, 9, 7)
    k.r("dgreen", 2, 13, 13, 14)
    k.p("yellow", (13, 2), (13, 4), (12, 3), (14, 3), (2, 5))


def halo(k):
    k.e("gold", 3, 1, 12, 6)
    k.e(None, 5, 3, 10, 4)
    k.r("yellow", 7, 8, 8, 14)
    k.l("yellow", 5, 8, 2, 13)
    k.l("yellow", 10, 8, 13, 13)


def forget(k):
    k.e("lgrey", 1, 1, 14, 10)
    k.p("lgrey", (4, 12), (5, 12), (4, 11), (2, 14))
    k.l("red", 5, 3, 10, 8, 2)
    k.l("red", 10, 3, 5, 8, 2)


def biome(k):
    leaf(k, "green", "dgreen")


def height(k):
    mountain(k)


def thermo(k):
    k.r("lgrey", 6, 1, 9, 10)
    k.e("red", 4, 8, 11, 14)
    k.r("red", 7, 4, 8, 10)
    k.p("white", (6, 11))


def river(k):
    for x in range(1, 15):
        y = 7 + (0, 1, 2, 2, 1, 0, -1, -2, -2, -1)[x % 10]
        k.r("blue", x, y, x, y + 2)
        k.p("lblue", (x, y))


def bread(k):
    k.e("gold", 1, 4, 14, 12)
    k.p("dgold", (4, 6), (5, 7), (7, 6), (8, 7), (10, 6), (11, 7))
    k.p("yellow", (3, 8), (6, 5))


def log(k):
    k.r("brown", 2, 5, 12, 11)
    k.e("bone", 10, 5, 14, 11)
    k.p("dbrown", (12, 8), (4, 7), (5, 7), (6, 9), (7, 9))


def stone(k):
    k.g("grey", [(2, 12), (3, 6), (7, 3), (12, 5), (13, 12)])
    k.p("lgrey", (6, 5), (7, 5), (5, 6), (8, 4))
    k.l("dgrey", 8, 8, 10, 11)


def ingot(k):
    k.g("lgrey", [(4, 5), (13, 5), (11, 11), (2, 11)])
    k.r("white", 5, 6, 11, 6)
    k.l("grey", 3, 10, 10, 10)


def coin(k):
    k.e("gold", 2, 2, 13, 13)
    k.e("dgold", 4, 4, 11, 11)
    k.e("gold", 5, 5, 10, 10)
    k.p("yellow", (5, 4), (4, 5), (6, 4))


def hammer(k):
    k.r("grey", 2, 2, 12, 6)
    k.r("lgrey", 2, 2, 12, 2)
    k.r("brown", 7, 7, 8, 14)


def sword(k):
    k.l("lgrey", 12, 2, 6, 8, 2)
    k.p("white", (13, 1), (12, 2), (11, 3))
    k.l("gold", 3, 6, 8, 11, 2)
    k.l("brown", 4, 10, 2, 12, 2)


def wheat(k):
    k.r("dgold", 7, 5, 8, 14)
    for y in (1, 4, 7):
        k.e("gold", 3, y, 6, y + 3)
        k.e("gold", 9, y, 12, y + 3)
    k.r("gold", 7, 1, 8, 3)


def spring(k):
    k.r("dgreen", 7, 8, 8, 14)
    k.p("green", (9, 11), (10, 10), (5, 12), (6, 12))
    for x, y in ((5, 0), (2, 3), (8, 3), (5, 6)):
        k.e("pink", x, y, x + 4, y + 3)
    k.r("yellow", 7, 4, 8, 5)


def summer(k):
    sun(k)


def autumn(k):
    leaf(k, "orange", "dred")


def winter(k):
    snowflake(k)


def drought(k):
    sun(k)
    k.r("brown", 1, 13, 14, 14)
    k.p("ink", (5, 13), (6, 14), (10, 13), (9, 14))


def blizzard(k):
    snowflake(k)


def water(k):
    drop(k)


def humidity(k):
    drop(k)
    k.p("lblue", (13, 3), (13, 4), (1, 11), (1, 12))


def legend(k):
    """A horned dragon's head in profile, a glowing eye: the legendary monsters."""
    k.g("red", [(1, 9), (5, 5), (10, 5), (14, 8), (14, 10), (9, 11), (6, 13), (1, 12)])
    k.g("dred", [(8, 10), (14, 10), (13, 12), (8, 12)])
    k.g("bone", [(4, 6), (1, 1), (7, 5)])
    k.g("bone", [(8, 5), (8, 1), (10, 5)])
    k.p("yellow", (10, 7))
    k.p("ink", (13, 8))


def inspect(k):
    eye(k, "cream", "blue", "ink")


def brush(k):
    k.e("cream", 2, 2, 13, 13)
    k.e(None, 4, 4, 11, 11)


ICONS = [
    menu, pause, play, fast, hourglass, gear, close, crown, house, paw, bulb, scroll,
    scales, layers, chart, save, load, door, people, lock, plus, minus, target, globe,
    dice, search, swords, dove, rings, flag, book, ankh, note, monitor, keys, info,
    star, heart, fire, lightning, rain, meteor, smite, bless, curse, heal, sprout, tornado,
    quake, flood, volcano, plague, raise_, lower, stamp, spiral, grave, halo, forget, biome,
    height, thermo, river, bread, log, stone, ingot, coin, hammer, sword, wheat, spring,
    summer, autumn, winter, drought, blizzard, water, humidity, inspect, brush, legend,
]


def emblem():
    """The soul of the world: an eye in a red sun, crowned with rays."""
    k = Pen(32)
    for a, b, c in (((15, 0), (12, 6), (19, 6)), ((15, 31), (12, 25), (19, 25)), ((0, 15), (6, 12), (6, 19)),
            ((31, 15), (25, 12), (25, 19)), ((4, 4), (10, 6), (6, 10)), ((27, 4), (21, 6), (25, 10)),
            ((4, 27), (6, 21), (10, 25)), ((27, 27), (25, 21), (21, 25))):
        k.g("gold", [a, b, c])
    k.e("dred", 4, 4, 27, 27)
    k.e("red", 5, 5, 26, 25)
    k.g("cream", [(7, 15), (12, 10), (19, 10), (24, 15), (24, 16), (19, 21), (12, 21), (7, 16)])
    k.e("ink", 11, 11, 20, 20)
    k.e("gold", 13, 13, 18, 18)
    k.r("ink", 15, 14, 16, 17)
    k.p("white", (12, 12), (13, 12), (12, 13))
    return k.finish()


def main():
    rows = (len(ICONS) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * SIZE, rows * SIZE), (0, 0, 0, 0))
    names = []
    for i, draw in enumerate(ICONS):
        pen = Pen()
        draw(pen)
        sheet.paste(pen.finish(), ((i % COLUMNS) * SIZE, (i // COLUMNS) * SIZE))
        names.append(draw.__name__.rstrip("_"))
    out = ROOT / "assets" / "ui"
    out.mkdir(parents=True, exist_ok=True)
    sheet.save(out / "icons.png")
    emblem().save(out / "emblem.png")
    lines = ["# Generated by art/ui_icons.py. Do not edit by hand.", "extends RefCounted", "",
            "const SIZE := %d" % SIZE, "const COLUMNS := %d" % COLUMNS,
            'const TEXTURE := "res://assets/ui/icons.png"', "const NAMES := ["]
    lines += ['\t"%s",' % n for n in names]
    lines += ["]", ""]
    (ROOT / "scripts" / "generated" / "ui_icons.gd").write_text("\n".join(lines))
    print("%d icons -> %s" % (len(names), out / "icons.png"))


if __name__ == "__main__":
    main()
