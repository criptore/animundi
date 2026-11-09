"""Draws the first buildings of Animundi's villages, in the same pixel art as the creatures
(art/creatures.py): one sprite pixel = one world pixel, a house about one and a half tiles wide.

- bonfire: the heart of a new village, three flickering frames;
- house_<race>: a home in the colours and materials of each of the 12 peoples;
- site: a house under construction (a wooden frame).

Writes assets/sprites/buildings/*.png and docs/images/buildings.png.
    python3 art/buildings.py
"""

from pathlib import Path

from PIL import Image

from creatures import hex_rgb, parse, render

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites" / "buildings"
SHEET = ROOT / "docs" / "images" / "buildings.png"

HOUSE = """
.....RR.....
....RRRR....
...RRRRRR...
..RRRRRRRR..
.RRRRRRRRRR.
RRRRRRRRRRRR
.WWWWWWWWWW.
.WWNWWWWDDW.
.WWWWWWWDDW.
.WWWWWWWDDW.
"""

TENT = """
.....RR.....
....RRRR....
...RRWRRR...
..RRRWRRRR..
.RRRRWRRRRR.
RRRRRDDRRRRR
RRRRRDDRRRRR
"""

HUT = """
....RRRR....
..RRRRRRRR..
.RRRRRRRRRR.
RRRRRRRRRRRR
.WWWWWWWWWW.
.WWNWWWDDWW.
.WWWWWWDDWW.
"""

SITE = """
.....F......
....F.F.....
...F...F....
..FFFFFFF...
.F.......F..
FFFFFFFFFFF.
.F...F...F..
.F...F...F..
.F...F...F..
"""

# Per people: the shape of its homes and their colours (R roof, W wall, D door, N window).
STYLES = {
    "humans": (HOUSE, {"R": "#b8483a", "W": "#e2cfa4", "D": "#6b4423", "N": "#8fd8ff"}),
    "elves": (HOUSE, {"R": "#5aae55", "W": "#f0e6c8", "D": "#8a6a3a", "N": "#f0d264"}),
    "dwarves": (HUT, {"R": "#7a7470", "W": "#a8a29a", "D": "#5a3a1e", "N": "#e8a923"}),
    "orcs": (TENT, {"R": "#8b5a2b", "W": "#c49a6a", "D": "#2a1a10", "N": "#000000"}),
    "goblins": (TENT, {"R": "#9aa04a", "W": "#c4a65a", "D": "#2a2010", "N": "#000000"}),
    "lizardfolk": (HUT, {"R": "#c9b458", "W": "#7aa070", "D": "#2a4a3a", "N": "#4dbfb0"}),
    "felines": (TENT, {"R": "#9b59c6", "W": "#f0d264", "D": "#3a2050", "N": "#000000"}),
    "merfolk": (HUT, {"R": "#4dbfb0", "W": "#e8e0d0", "D": "#3b8fe0", "N": "#8fd8ff"}),
    "treefolk": (HUT, {"R": "#3f7a3f", "W": "#9a6a3a", "D": "#4a2d19", "N": "#9ad65a"}),
    "fairies": (HUT, {"R": "#e05a8a", "W": "#f8f0f0", "D": "#b07ad0", "N": "#fff0a0"}),
    "bullfolk": (HOUSE, {"R": "#a03a32", "W": "#b08a60", "D": "#4a2a18", "N": "#f08a2a"}),
    "undead": (HOUSE, {"R": "#3d3d4a", "W": "#8a8478", "D": "#1b1b22", "N": "#b07ad0"}),
}

BONFIRE = """
...FF..
..FYF..
..FYYF.
.SFYFS.
SSWWWSS
.SSSSS.
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
    pal = {"F": "#ee5a1c", "Y": "#ffd84a", "S": "#8a8478", "W": "#6b4423"}
    return render(["".join(r) for r in rows], pal)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for f in OUT.glob("*.png"):
        f.unlink()
    images = {}
    for k in range(3):
        images[f"bonfire_{k}"] = bonfire(k)
    for race, (shape, pal) in STYLES.items():
        images[f"house_{race}"] = render(parse(shape), pal)
    images["site"] = render(parse(SITE), {"F": "#a87a4a"})
    for name, img in images.items():
        img.save(OUT / f"{name}.png")
    scale, cell = 6, 16
    sheet = Image.new("RGBA", (len(images) * cell * scale, cell * scale), (70, 120, 60, 255))
    for k, (name, img) in enumerate(images.items()):
        x = k * cell + (cell - img.width) // 2
        y = cell - img.height - 2
        sheet.alpha_composite(img.resize((img.width * scale, img.height * scale), Image.NEAREST), (x * scale, y * scale))
    sheet.save(SHEET)
    print(f"{len(images)} building sprites -> {OUT}")


if __name__ == "__main__":
    main()
