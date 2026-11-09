"""Draws every village building of Animundi (docs/VILLAGES.md), in the same pixel art as the
creatures (art/creatures.py): one sprite pixel = one world pixel, a tile is 8 pixels, a hut a
little more than a tile wide, a town hall more than two.

Homes come from art/homes.py: 4 tiers x 4 variants per people, in WorldBox's 3/4 style. Great
buildings (town hall, temple, library, barracks, watch tower) are templates in each people's
colours. Roofs and banners are drawn in the colour mask (magenta shades) that the game paints in
the village's colour. The other buildings are the same for everyone: bonfire (3 frames),
stockpile, windmill (2 frames), well, mine, dock, market, statue, training dummy, ruin and site.

Inspired by WorldBox's buildings (what they are, how big, the colour mask), drawn from scratch.

Writes assets/sprites/buildings/*.png and docs/images/buildings.png.
    python3 art/buildings.py
"""

from pathlib import Path

from PIL import Image

from creatures import hex_rgb, parse, render
import homes

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites" / "buildings"
SHEET = ROOT / "docs" / "images" / "buildings.png"

# Letters: R roof, W wall, D door, N window, S stone, K dark (chimney, iron), B banner, T timber,
# Y gold, G leaves, A water, C cloth, F flame, H hay, P paper (books).
COMMON = {
    "S": "#9a958c", "K": "#4a4440", "T": "#8a5a32", "Y": "#f0c94a", "G": "#4f9a45", "A": "#3b8fe0",
    "F": "#ee5a1c", "H": "#d8b860", "P": "#efe6cf", "C": "#d8d0c0",
}

# ---------------------------------------------------------------------------------- great buildings
# One shape each, in every people's colours (roof, wall, door, windows, banner).

GREAT = {
    "town_hall": """
........B.........
........BB........
........T.........
.......RRR........
......RRRRR.......
.....RRRRRRR......
....RRRRRRRRR.....
...RRRRRRRRRRRRRR.
..RRRRRRRRRRRRRRRR
.RRRRRRRRRRRRRRRRR
RRRRRRRRRRRRRRRRRR
.SSSSSSSSSSSSSSSS.
.SNNSSNNSSNNSSNNS.
.SNNSSNNSSNNSSNNS.
.SSSSSSSDDDSSSSSS.
.SSSSSSSDDDSSSSSS.
""",
    "temple": """
.......Y........
.......Y........
......YYY.......
......RRR.......
.....RRRRR......
.....SSSSS......
.....SNSNS......
....RRRRRRR.....
...RRRRRRRRR....
..RRRRRRRRRRR...
.SSSSSSSSSSSSS..
.SWSWSWSWSWSWS..
.SWSWSWDDWSWSS..
.SWSWSWDDWSWSS..
SSSSSSSSSSSSSSS.
""",
    "library": """
......RRRR......
....RRRRRRRR....
..RRRRRRRRRRRR..
RRRRRRRRRRRRRRRR
.WWWWWWWWWWWWWW.
.WNNWNNWWNNWNNW.
.WPPWPPWWPPWPPW.
.WWWWWWWWWWWWWW.
.WNNWNNDDWNNWNW.
.WWWWWWWDDWWWWW.
.SSSSSSSDDSSSSS.
""",
    "barracks": """
.B............B.
.T.RRRRRRRRRR.T.
.TRRRRRRRRRRRRT.
RRRRRRRRRRRRRRRR
RRRRRRRRRRRRRRRR
.SSSSSSSSSSSSSS.
.SKSSKSSDDSSKSS.
.SSSSSSSDDSSSSS.
.SSSSSSSDDSSSSS.
""",
    "watch_tower": """
..B.....
..BB....
..T.....
.RRRR...
RRRRRR..
RRRRRRR.
.SSSSS..
.SKKKS..
.SSSSS..
.SSSSS..
.SSNSS..
.SSSSS..
.SSSSS..
.SSSSS..
.SSNSS..
.SSSSS..
SSSSSSS.
SSDDSSS.
""",
}

# Per people: the colours of its great buildings (W wall, D door, N window; R roof and B banner
# are replaced by the colour mask). Homes are drawn by art/homes.py.
STYLES = {
    "humans": {"R": "#b8483a", "W": "#e2cfa4", "D": "#6b4423", "N": "#8fd8ff", "B": "#4a86d0"},
    "elves": {"R": "#5aae55", "W": "#f0e6c8", "D": "#8a6a3a", "N": "#f0d264", "B": "#9ad65a"},
    "dwarves": {"R": "#7a7470", "W": "#a8a29a", "D": "#5a3a1e", "N": "#e8a923", "B": "#e8a923"},
    "orcs": {"R": "#8b5a2b", "W": "#c49a6a", "D": "#2a1a10", "N": "#d83a3a", "B": "#8c2323"},
    "goblins": {"R": "#9aa04a", "W": "#c4a65a", "D": "#2a2010", "N": "#f0d264", "B": "#f0d264"},
    "lizardfolk": {"R": "#c9b458", "W": "#7aa070", "D": "#2a4a3a", "N": "#4dbfb0", "B": "#f08a2a"},
    "felines": {"R": "#9b59c6", "W": "#f0d264", "D": "#3a2050", "N": "#f49ac1", "B": "#f0d264"},
    "merfolk": {"R": "#4dbfb0", "W": "#e8e0d0", "D": "#3b8fe0", "N": "#8fd8ff", "B": "#3b8fe0"},
    "treefolk": {"R": "#3f7a3f", "W": "#9a6a3a", "D": "#4a2d19", "N": "#9ad65a", "B": "#9ad65a"},
    "fairies": {"R": "#e05a8a", "W": "#f8f0f0", "D": "#b07ad0", "N": "#fff0a0", "B": "#f49ac1"},
    "bullfolk": {"R": "#a03a32", "W": "#b08a60", "D": "#4a2a18", "N": "#f08a2a", "B": "#f08a2a"},
    "undead": {"R": "#3d3d4a", "W": "#8a8478", "D": "#1b1b22", "N": "#b07ad0", "B": "#4f2470"},
}

# Stone tints per people: dwarves' grey granite, elves' pale stone, undead's dark rock...
STONE = {"elves": "#c8c4b4", "dwarves": "#8a8580", "undead": "#6a6670", "lizardfolk": "#a89a70",
         "fairies": "#d8d0e0", "treefolk": "#8a8a70", "merfolk": "#b8c8c8"}

# ---------------------------------------------------------------------------------- shared buildings

BONFIRE = """
...FF..
..FYF..
..FYYF.
.SFYFS.
SSTTTSS
.SSSSS.
"""

STOCKPILE = """
........TTT.
.KKKK..TTTTT
.KTTK..TTTTT
.KTTK.TTTTTT
KKKKKKTTTTTT
KTTKTTKHHH..
KTTKTTKHHHH.
KKKKKKKHHHH.
"""

WINDMILL = [
    """
..T...........T.
...T.........T..
....T.......T...
.....T.RRR.T....
......RRRRR.....
.....RRRRRRR....
......TWWWT.....
.....TWWWWWT....
....T.WWWWW.T...
...T..WWNWW..T..
..T...WWWWW...T.
......WWWWW.....
.....WWWWWWW....
.....WWWDDWW....
.....WWWDDWW....
""",
    """
.......T........
.......T........
.......T........
.......RRR......
......RRRRR.....
.....RRRRRRR....
TTTTTTWWWWWTTTTT
......WWWWW.....
......WWWWW.....
......WWNWW.....
.......T........
......WWWWW.....
.....WWWWWWW....
.....WWWDDWW....
.....WWWDDWW....
""",
]
WINDMILL_PAL = {"R": "#8a4a32", "W": "#e2cfa4", "N": "#4a4440", "D": "#6b4423"}

WELL = """
.TTTTTTT.
TRRRRRRRT
.T.....T.
.T..K..T.
.T..K..T.
SSSSSSSSS
SAAAAAAAS
SSSSSSSSS
"""

MINE = """
.....SSSS.....
...SSSSSSSS...
..SSSSSSSSSSS.
.SSSTTTTTSSSSS
SSSTKKKKKTSSSS
SSSTKKKKKTSSSS
SSSTKKKKKTSSSS
SSSTKKKKKTSSKS
"""

DOCK = """
.T........T.
.T........T.
TTTTTTTTTTTT
TKTTKTTKTTKT
.T........T.
.T........T.
"""

MARKET = """
CRCRCRCRCRCRCR
CRCRCRCRCRCRCR
.T..........T.
.T..........T.
.T..........T.
TTTTTTTTTTTTTT
TYHHGGYYHHGGYT
TTTTTTTTTTTTTT
.T..........T.
"""
MARKET_PAL = {"R": "#c8503e", "C": "#f0e6c8"}

STATUE = """
...YY...
...YY...
..YYYY..
.Y.YY.Y.
...YY...
...YY...
..Y..Y..
..Y..Y..
.SSSSSS.
.SSSSSS.
SSSSSSSS
SSSSSSSS
"""

DUMMY = """
.HHH.
TTHTT
.HHH.
..H..
..T..
..T..
..T..
.TTT.
"""

RUIN = """
.S..........
.SS......S..
.SSS....SS..
.SKS.S..SSS.
SSSSSS.SSKS.
SKSSSSSSSSSS
"""

# Trade (0.4): a cart of goods and a boat with a sail in the kingdom's colour (R = mask).
CART = """
..HHCH..
.TTTTTTT
.TKTTTKT
..K...K.
"""

BOAT = """
....R....
....RR...
....RRR..
....RRRR.
....T....
TTTTTTTTT
.TTTTTTT.
..TTTTT..
"""

SITE = """
.....T......
....T.T.....
...T...T....
..TTTTTTT...
.T.......T..
TTTTTTTTTTT.
.T...T...T..
.T...T...T..
.T...T...T..
"""


def bonfire(k):
    """Frame k of the bonfire: stones, logs and a flame that changes shape."""
    rows = [list(r) for r in parse(BONFIRE)]
    if k == 1:
        rows[0] = list("..FF...")
        rows[1] = list("..FYF..")
    elif k == 2:
        rows[0] = list("...F...")
        rows[1] = list("..FYFF.")
    return render(["".join(r) for r in rows], COMMON)


def people_palette(race):
    pal = STYLES[race]
    full = dict(COMMON)
    full.update(pal)
    if race in STONE:
        full["S"] = STONE[race]
    return full


def snap_mask(img):
    """Roofs and banners are drawn in the colour mask (magenta shades, see art/homes.py); the
    automatic shading of render() tints them a little: put them back on the mask exactly."""
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a and r > 60 and b > 60 and abs(r - b) < 12 and g < min(r, b) * 0.45:
                v = (r + b) // 2
                px[x, y] = (v, 0, v, a)
    return img


def all_buildings():
    """Every building sprite, by name (without the folder)."""
    images = {}
    for k in range(3):
        images[f"bonfire_{k}"] = bonfire(k)
    # Homes: 4 tiers x VARIANTS per people, drawn by art/homes.py.
    images.update(homes.all_homes())
    # Great buildings and the shared ones, in the same 3/4 style (art/homes.py).
    images.update(homes.all_great())
    images.update(homes.all_shared())
    images["site"] = render(parse(SITE), {"T": "#a87a4a"})
    images["cart"] = render(parse(CART), COMMON)
    images["boat"] = snap_mask(render(parse(BOAT), {**COMMON, "R": "#d000d0"}))
    return images


def recolor(img, rgb):
    """The mask painted in a colour, as the game does (for the contact sheet)."""
    img = img.copy()
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a and g == 0 and r == b and r > 60:
                k = r / 208
                c = [int(v * k) if k <= 1 else min(255, int(v + (255 - v) * (k - 1) * 1.5)) for v in rgb]
                px[x, y] = (*c, 255)
    return img


SHEET_COLOURS = ["#4a86d0", "#c8503e", "#5aae55", "#9b59c6", "#e8a923", "#4dbfb0"]


def sheet(images, names, cols, cell=26, scale=4):
    """A contact sheet of some sprites on grass, `cols` per row, each row in a village colour."""
    rows = (len(names) + cols - 1) // cols
    img = Image.new("RGBA", (cols * cell * scale, rows * cell * scale), (70, 120, 60, 255))
    for k, name in enumerate(names):
        sprite = recolor(images[name], hex_rgb(SHEET_COLOURS[(k // cols) % len(SHEET_COLOURS)]))
        x = (k % cols) * cell + (cell - sprite.width) // 2
        y = (k // cols) * cell + cell - sprite.height - 2
        img.alpha_composite(sprite.resize((sprite.width * scale, sprite.height * scale), Image.NEAREST), (x * scale, y * scale))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for f in list(OUT.glob("*.png")) + list(OUT.glob("*.png.import")):
        f.unlink()
    images = all_buildings()
    for name, img in images.items():
        img.save(OUT / f"{name}.png")
    # One row per people (homes and great buildings), then the shared buildings.
    tiers = [f"{t}_{{}}_{v}" for t in homes.TIERS for v in (0, 1)] + [f"{g}_{{}}" for g in homes.GREAT]
    names = [t.format(race) for race in STYLES for t in tiers]
    shared = ["bonfire_0", "stockpile", "windmill_0", "windmill_1", "well", "mine", "dock", "market", "statue",
              "dummy", "ruin", "cart", "boat"]
    names += shared + ["site"]
    sheet(images, names, len(tiers)).save(SHEET)
    print(f"{len(images)} building sprites -> {OUT}")


if __name__ == "__main__":
    main()
