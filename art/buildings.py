"""Draws every village building of Animundi (docs/VILLAGES.md), in the same pixel art as the
creatures (art/creatures.py): one sprite pixel = one world pixel, a tile is 8 pixels, a hut a
little more than a tile wide, a town hall more than two.

Homes and great buildings are drawn in each people's style: three families of shapes (timber
houses, round huts, tents and longhouses), each in the people's own colours, with four tiers of
homes (hut, house, stone house, big house) and the town hall, temple, library, barracks and watch
tower. The other buildings are the same for everyone: bonfire (3 frames), stockpile, windmill
(2 frames), well, mine, dock, market, statue, training dummy, ruin and building site.

Inspired by WorldBox's buildings (what they are and how big), drawn from scratch.

Writes assets/sprites/buildings/*.png and docs/images/buildings.png.
    python3 art/buildings.py
"""

from pathlib import Path

from PIL import Image

from creatures import parse, render

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites" / "buildings"
SHEET = ROOT / "docs" / "images" / "buildings.png"

# Letters: R roof, W wall, D door, N window, S stone, K dark (chimney, iron), B banner, T timber,
# Y gold, G leaves, A water, C cloth, F flame, H hay, P paper (books).
COMMON = {
    "S": "#9a958c", "K": "#4a4440", "T": "#8a5a32", "Y": "#f0c94a", "G": "#4f9a45", "A": "#3b8fe0",
    "F": "#ee5a1c", "H": "#d8b860", "P": "#efe6cf", "C": "#d8d0c0",
}

# ---------------------------------------------------------------------------------- homes

TIMBER = {
    "hut": """
....RR....
...RRRR...
..RRRRRR..
.RRRRRRRR.
RRRRRRRRRR
.WWWWWWWW.
.WNWWWDDW.
.WWWWWDDW.
""",
    "house": """
.........KK.
.....RR..KK.
....RRRRRRR.
...RRRRRRRR.
..RRRRRRRRR.
.RRRRRRRRRRR
RRRRRRRRRRRR
.WWWWWWWWWW.
.WNNWWWWDDW.
.WNNWWWWDDW.
.WWWWWWWDDW.
""",
    "stone_house": """
..........KK..
......RR..KK..
.....RRRRRRR..
....RRRRRRRRR.
...RRRRRRRRRR.
..RRRRRRRRRRRR
.RRRRRRRRRRRRR
RRRRRRRRRRRRRR
.SSSSSSSSSSSS.
.SNNSSNNSSDDS.
.SNNSSNNSSDDS.
.SSSSSSSSSDDS.
""",
    "big_house": """
.......RR.......
......RRRR...KK.
.....RRRRRR..KK.
....RRRRRRRRRRR.
...RRRRRRRRRRRR.
..RRRRRRRRRRRRRR
.RRRRRRRRRRRRRRR
RRRRRRRRRRRRRRRR
.WWWWWWWWWWWWWW.
.WNNWWNNWWNNWWW.
.WNNWWNNWWNNWWW.
.SSSSSSSSSSSSSS.
.SNNSSNNSSSDDSS.
.SNNSSNNSSSDDSS.
.SSSSSSSSSSDDSS.
""",
}

ROUND = {
    "hut": """
...RRRR...
.RRRRRRRR.
RRRRRRRRRR
RRRRRRRRRR
.WWWWWWWW.
.WWWDDWWW.
.WWWDDWWW.
""",
    "house": """
.....RR.....
...RRRRRR...
..RRRRRRRR..
.RRRRRRRRRR.
RRRRRRRRRRRR
.WWWWWWWWWW.
.WWNWWWDDWW.
.WWWWWWDDWW.
.WWWWWWDDWW.
""",
    "stone_house": """
.....RRR......
...RRRRRRR....
..RRRRRRRRR...
.RRRRRRRRRRR..
RRRRRRRRRRRRR.
.SSSSSSSSSSS..
.SSNSSSSDDSS..
.SSSSSSSDDSS..
.SSSSSSSDDSS..
""",
    "big_house": """
.....RRR..........
...RRRRRRR...RR...
..RRRRRRRRR.RRRR..
.RRRRRRRRRRRRRRRR.
RRRRRRRRRRRRRRRRRR
.SSSSSSSSSSSSSSSS.
.SSNSSSNSSSSNSSSS.
.SSSSSSSSSDDSSSSS.
.SSNSSSNSSDDSSNSS.
.SSSSSSSSSDDSSSSS.
""",
}

TENT = {
    "hut": """
....RR....
...RRRR...
..RRWRRR..
.RRRWRRRR.
RRRRDDRRRR
RRRRDDRRRR
""",
    "house": """
.....BB.....
.....RR.....
....RRRR....
...RRWRRR...
..RRRWRRRR..
.RRRRWRRRRR.
RRRRRDDRRRRR
RRRRRDDRRRRR
""",
    "stone_house": """
.B..........B.
.T..........T.
.RRRRRRRRRRRR.
RRRRRRRRRRRRRR
RRRRRRRRRRRRRR
.WWWWWWWWWWWW.
.WWWWWDDWWWWW.
.SSSSSDDSSSSS.
""",
    "big_house": """
.B.....BB.....B.
.T.....RR.....T.
.RRRRRRRRRRRRRR.
RRRRRRRRRRRRRRRR
RRRRRRRRRRRRRRRR
RRRRRRRRRRRRRRRR
.WWWWWWWWWWWWWW.
.WWKWWWDDWWWKWW.
.WWWWWWDDWWWWWW.
.SSSSSSDDSSSSSS.
""",
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

# Per people: its family of homes and its colours (R roof, W wall, D door, N window, B banner).
STYLES = {
    "humans": (TIMBER, {"R": "#b8483a", "W": "#e2cfa4", "D": "#6b4423", "N": "#8fd8ff", "B": "#4a86d0"}),
    "elves": (TIMBER, {"R": "#5aae55", "W": "#f0e6c8", "D": "#8a6a3a", "N": "#f0d264", "B": "#9ad65a"}),
    "dwarves": (ROUND, {"R": "#7a7470", "W": "#a8a29a", "D": "#5a3a1e", "N": "#e8a923", "B": "#e8a923"}),
    "orcs": (TENT, {"R": "#8b5a2b", "W": "#c49a6a", "D": "#2a1a10", "N": "#d83a3a", "B": "#8c2323"}),
    "goblins": (TENT, {"R": "#9aa04a", "W": "#c4a65a", "D": "#2a2010", "N": "#f0d264", "B": "#f0d264"}),
    "lizardfolk": (ROUND, {"R": "#c9b458", "W": "#7aa070", "D": "#2a4a3a", "N": "#4dbfb0", "B": "#f08a2a"}),
    "felines": (TENT, {"R": "#9b59c6", "W": "#f0d264", "D": "#3a2050", "N": "#f49ac1", "B": "#f0d264"}),
    "merfolk": (ROUND, {"R": "#4dbfb0", "W": "#e8e0d0", "D": "#3b8fe0", "N": "#8fd8ff", "B": "#3b8fe0"}),
    "treefolk": (ROUND, {"R": "#3f7a3f", "W": "#9a6a3a", "D": "#4a2d19", "N": "#9ad65a", "B": "#9ad65a"}),
    "fairies": (ROUND, {"R": "#e05a8a", "W": "#f8f0f0", "D": "#b07ad0", "N": "#fff0a0", "B": "#f49ac1"}),
    "bullfolk": (TIMBER, {"R": "#a03a32", "W": "#b08a60", "D": "#4a2a18", "N": "#f08a2a", "B": "#f08a2a"}),
    "undead": (TIMBER, {"R": "#3d3d4a", "W": "#8a8478", "D": "#1b1b22", "N": "#b07ad0", "B": "#4f2470"}),
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
    shape, pal = STYLES[race]
    full = dict(COMMON)
    full.update(pal)
    if race in STONE:
        full["S"] = STONE[race]
    return full


def all_buildings():
    """Every building sprite, by name (without the folder)."""
    images = {}
    for k in range(3):
        images[f"bonfire_{k}"] = bonfire(k)
    for race, (family, _) in STYLES.items():
        pal = people_palette(race)
        for tier, shape in family.items():
            images[f"{tier}_{race}"] = render(parse(shape), pal)
        for name, shape in GREAT.items():
            images[f"{name}_{race}"] = render(parse(shape), pal)
    images["stockpile"] = render(parse(STOCKPILE), COMMON)
    for k, shape in enumerate(WINDMILL):
        images[f"windmill_{k}"] = render(parse(shape), {**COMMON, **WINDMILL_PAL})
    images["well"] = render(parse(WELL), {**COMMON, "R": "#8a4a32"})
    images["mine"] = render(parse(MINE), COMMON)
    images["dock"] = render(parse(DOCK), COMMON)
    images["market"] = render(parse(MARKET), {**COMMON, **MARKET_PAL})
    images["statue"] = render(parse(STATUE), COMMON)
    images["dummy"] = render(parse(DUMMY), COMMON)
    images["ruin"] = render(parse(RUIN), COMMON)
    images["site"] = render(parse(SITE), {"T": "#a87a4a"})
    return images


def sheet(images, names, cols, cell=22, scale=4):
    """A contact sheet of some sprites on grass, `cols` per row."""
    rows = (len(names) + cols - 1) // cols
    img = Image.new("RGBA", (cols * cell * scale, rows * cell * scale), (70, 120, 60, 255))
    for k, name in enumerate(names):
        sprite = images[name]
        x = (k % cols) * cell + (cell - sprite.width) // 2
        y = (k // cols) * cell + cell - sprite.height - 2
        img.alpha_composite(sprite.resize((sprite.width * scale, sprite.height * scale), Image.NEAREST), (x * scale, y * scale))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for f in OUT.glob("*.png"):
        f.unlink()
    images = all_buildings()
    for name, img in images.items():
        img.save(OUT / f"{name}.png")
    # One row per people (homes and great buildings), then the shared buildings.
    tiers = ["hut", "house", "stone_house", "big_house", *GREAT]
    names = [f"{t}_{race}" for race in STYLES for t in tiers]
    shared = ["bonfire_0", "stockpile", "windmill_0", "windmill_1", "well", "mine", "dock", "market", "statue",
              "dummy", "ruin"]
    names += shared + ["site"]
    sheet(images, names, len(tiers)).save(SHEET)
    print(f"{len(images)} building sprites -> {OUT}")


if __name__ == "__main__":
    main()
