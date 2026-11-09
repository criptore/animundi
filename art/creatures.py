"""Draws the sprites of every living being of Animundi: animals, monsters and the 12 peoples in
their 4 roles, as original pixel art in the spirit of WorldBox (docs/WORLDBOX_WIKI_LESSONS.md § 3).

- Drawn at the size they are shown: one sprite pixel = one world pixel (a tile is 8), so a
  creature is about one tile tall and nothing is scaled down from large art.
- Each creature is a small text template (one character per pixel, facing right) and a palette.
  Shading is automatic: the lit top edge is lighter, the other edges darker (a soft outline).
- Poses are made from the template: idle; two walking frames (the leg pixels, `L`, swing); attack
  (the upper body lunges forward); swim (legs under water); death (lying on its side).
- Peoples are assembled from parts: a body per race (skin, hair, ears, horns, tail, wings...) and
  an outfit per role (villager, warrior, chief, shaman). Clothes use the race's colours for now;
  kingdom colours (colour masks) come with 0.3.

Writes assets/sprites/creatures/<id>_<pose>.png and a preview sheet docs/images/creatures.png.
    python3 art/creatures.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites" / "creatures"
SHEET = ROOT / "docs" / "images" / "creatures.png"
POSES = ["idle", "walk1", "walk2", "attack", "swim", "death"]


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[k:k + 2], 16) for k in (0, 2, 4))


def shade(c, f):
    """f > 1 lightens, f < 1 darkens."""
    if f >= 1:
        return tuple(min(255, int(v + (255 - v) * (f - 1))) for v in c)
    return tuple(int(v * f) for v in c)


# ---------------------------------------------------------------------------------- templates

# Characters: '.' empty. Every other character is looked up in the creature's palette. `L` marks
# leg pixels (they swing when walking), `E` an eye and `*` details that are never shaded.
NO_SHADE = set("E*")

ANIMALS = {
    "cow": ("""
..........HH
.........WWW.
WWBBWWWWWWWEW
WBBBWWWBWWWPP
.WWWWWBBBWW..
.WWWWWWWWWW..
.L.L.....L.L.
.L.L.....L.L.
""", {"W": "#f2efe6", "B": "#3a3433", "P": "#e9a0a0", "H": "#d8cfa8", "E": "#1b1b1b", "L": "#4a3b33"}),
    "sheep": ("""
..WWWWW...
.WWWWWWWFF
WWWWWWWWFE
.WWWWWWWFF
..WWWWWW..
..L.L.L.L.
..L.L.L.L.
""", {"W": "#f4f1ea", "F": "#4b4140", "E": "#111111", "L": "#4b4140"}),
    "pig": ("""
.......D..
.PPPPPPPPD
PPPPPPPPEP
PPPPPPPPPS
.PPPPPPPP.
.L.L..L.L.
.L.L..L.L.
""", {"P": "#f0a8b0", "D": "#d9808e", "S": "#c66a7a", "E": "#1b1b1b", "L": "#c87888"}),
    "chicken": ("""
...R..
..WWW.
..WEWY
WWWWW.
.WWWW.
..L.L.
..L.L.
""", {"W": "#fbfaf4", "R": "#e2392f", "Y": "#f1b52b", "E": "#111111", "L": "#e8922a"}),
    "horse": ("""
.........MBB.
........MBBEB
........MBBBB
.......MBBB..
.BBBBBBBBBB..
MBBBBBBBBBB..
M.BBBBBBBBB..
..BBBBBBBB...
..L.L...L.L..
..L.L...L.L..
""", {"B": "#9a6234", "M": "#3b2618", "E": "#111111", "L": "#5b3a22"}),
    "deer": ("""
.........A.A
.........AA.
.........TT.
........TTET
........TTT.
.TTTTTTTTT..
WTTTTTTTTT..
.TWWWWWWT...
.L.L...L.L..
.L.L...L.L..
""", {"T": "#b9824c", "W": "#efe2c8", "A": "#e6dcc0", "E": "#111111", "L": "#7a5532"}),
    "rabbit": ("""
....G.
....GG
...GGE
WGGGGG
.GGGG.
.L..L.
""", {"G": "#b9b2a6", "W": "#ffffff", "E": "#111111", "L": "#8c867c"}),
    "fox": ("""
.........O.O
........OOOO
W.......OOEO
OO.....OOOOW
.OOOOOOOOOW.
..OOOOOOOW..
..L.L..L.L..
..L.L..L.L..
""", {"O": "#e47a2c", "W": "#fbf2e6", "E": "#111111", "L": "#3a2a22"}),
    "wolf": ("""
.........G.G.
........GGGG.
GG......GGEGG
.GGGGGGGGGGW.
..GGGGGGGGW..
..GWWWWWGG...
..L.L..L.L...
..L.L..L.L...
""", {"G": "#8b8f98", "W": "#d9dbe0", "E": "#ffd34a", "L": "#5a5d66"}),
    "bear": ("""
.........B.B.
........BBBBB
.BBBBBBBBBEBD
BBBBBBBBBBBDD
BBBBBBBBBBB..
BBBBBBBBBBB..
.BBBBBBBBB...
.LL.LL..LL.LL
.LL.LL..LL.LL
""", {"B": "#6e4426", "D": "#3d2516", "E": "#111111", "L": "#4a2d19"}),
    "crab": ("""
.E....E.
RR.RR.RR
.RRRRRR.
RRRRRRRR
L.L..L.L
""", {"R": "#e0523a", "E": "#111111", "L": "#b03a28"}),
    "fish": ("""
..BB...
.BBBBB.
BBBBEBB
.BBBBB.
""", {"B": "#5aa0d8", "E": "#111111"}),
}

MONSTERS = {
    "skeleton": ("""
..WW..
.WWEW.
..WW..
.WWWW.
W.WW.W
..WW..
.W..W.
.L..L.
.L..L.
""", {"W": "#ece6d2", "E": "#1b1b1b", "L": "#d8d0b8"}),
    "zombie": ("""
.HHH..
.SSSE.
.SSSS.
..SS..
.CCCCSS
S.CC...
..PP...
..L.L..
..L.L..
""", {"H": "#3a4a2a", "S": "#86b06a", "E": "#d02a2a", "C": "#5a6a8a", "P": "#3a3a4a", "L": "#3a3a4a"}),
    "ghost": ("""
..WWW..
.WWWWW.
.WEWEW.
.WWWWW.
WWWWWWW
.WWWWW.
.W.W.W.
""", {"W": "#dfeefa", "E": "#2a3a5a"}),
    "spider": ("""
....DDD..
...DDDDE.
.L.DDDDD.
L.L.D.D.L
L.L.L.L.L
""", {"D": "#2b2433", "E": "#e2392f", "L": "#3d3348"}),
    "slime": ("""
..GGGG..
.GGGGGG.
GGG*EG*G
GGGGGGGG
.GGGGGG.
""", {"G": "#6cd06a", "E": "#103010", "*": "#c8f8b8"}),
    "demon": ("""
.H...H.
.HRRRH.
..RERE.
..RRR..
.RRRRR.
RR.R.RR
...RR..
..L..L.
..L..L.
""", {"R": "#c8322a", "H": "#2a1a1a", "E": "#ffd34a", "L": "#7a1a14"}),
    "golem": ("""
...SSSS..
...SESE..
...SSSS..
.SSSSSSSS
SSSSSSSSS
SS.SSSS.SS
...SSSS..
...LL.LL.
...LL.LL.
""", {"S": "#8a8478", "E": "#7ad0f0", "L": "#6a655c"}),
    "yeti": ("""
...WWW..
..WWWW..
..WFEF..
..WWWW..
.WWWWWW.
WWWWWWWW
W.WWWW.W
..WWWW..
..LL.LL.
..LL.LL.
""", {"W": "#eef2f6", "F": "#7aa0c0", "E": "#1b1b1b", "L": "#c8d0d8"}),
    "dragon": ("""
................HH.
...............RRRR
.......WW......RRER
......WWWW....RRRRR
.....WWWWWW..RRR...
.RR...WWRRRRRRRR...
RR..RRRRRRRRRRRR...
R..RRRRRRRRRRRR....
....RRRRRRRRRR.....
.....L.L....L.L....
.....L.L....L.L....
""", {"R": "#c0392b", "W": "#e8833a", "H": "#f0d264", "E": "#ffd34a", "L": "#7a1f17"}),
}

# ---------------------------------------------------------------------------------- peoples

RACES = {
    # skin, hair, clothes, trim, legs, traits
    "Humans": ("#f0c39b", "#6b4423", "#4a86d0", "#d85a4a", "#5a3a1e", []),
    "Elves": ("#f3cfa8", "#f0d264", "#5aae55", "#9ad65a", "#2c6e35", ["ears"]),
    "Dwarves": ("#d49a6a", "#e8823a", "#c8503e", "#e8a923", "#5a3a1e", ["short", "beard"]),
    "Orcs": ("#6fae55", "#2a2a30", "#8b5a2b", "#8c2323", "#5a3a1e", ["tusks"]),
    "Goblins": ("#a6d46a", "#55663a", "#c4a65a", "#f0d264", "#5a3a1e", ["short", "big_ears"]),
    "Lizardfolk": ("#4dbfb0", "#2a7d72", "#c9b458", "#f08a2a", "#4dbfb0", ["crest", "tail"]),
    "Felines": ("#f0a050", "#c0702a", "#9b59c6", "#f0d264", "#f0a050", ["cat_ears", "tail"]),
    "Merfolk": ("#8fd8ff", "#3b8fe0", "#4dbfb0", "#3b8fe0", "#4dbfb0", ["fins"]),
    "Treefolk": ("#9a6a3a", "#5aae55", "#3f7a3f", "#9ad65a", "#5a3a1e", ["foliage"]),
    "Fairies": ("#f8c8d8", "#b07ad0", "#a8e0f8", "#f49ac1", "#f8c8d8", ["short", "wings"]),
    "Bullfolk": ("#b07a50", "#5a3a1e", "#a03a32", "#f08a2a", "#5a3a1e", ["horns", "big"]),
    "Undead": ("#e8e0c8", "#3d3d4a", "#5e3a7a", "#4f2470", "#3d3d4a", ["sockets"]),
}
ROLES = ["Villager", "Warrior", "Chief", "Shaman"]


def person(race, role):
    """A person, facing right, as (template, palette). 7 wide; 10 tall (8 for short races)."""
    skin, hair, clothes, trim, legs, traits = RACES[race]
    short = "short" in traits
    # Body rows, before role overlays: hair, head with eye, body with arms, belt, legs.
    rows = [
        "..HHH..",
        "..SSE..",
        "..SSS..",
        ".SCCCS.",
        ".SCCCS.",
        "..CCC..",
        "..PPP..",
        "..L.L..",
        "..L.L..",
    ]
    if short:
        rows = [rows[0], rows[1], rows[2], ".SCCCS.", "..CCC..", "..L.L..", "..L.L.."]
    rows = [list(r) for r in rows]
    pal = {"H": hair, "S": skin, "C": clothes, "P": legs, "L": legs, "E": "#1b1b1b",
           "T": trim, "G": "#9aa3ad", "M": "#c8cdd2", "Y": "#f0c838", "W": "#8a5a2a", "O": "#8fd8ff"}

    def put(x, y, ch):
        if 0 <= y < len(rows) and 0 <= x < len(rows[0]):
            rows[y][x] = ch

    if "ears" in traits:
        put(1, 1, "S")
    if "big_ears" in traits:
        put(1, 1, "S"); put(0, 0, "S")
    if "cat_ears" in traits:
        put(2, 0, "S"); put(4, 0, "S"); put(3, 0, "H")
    if "horns" in traits:
        put(1, 0, "M"); put(5, 0, "M")
    if "beard" in traits:
        put(3, 2, "H"); put(4, 2, "H"); put(4, 3, "H")
    if "tusks" in traits:
        put(4, 2, "M")
    if "crest" in traits:
        put(2, 0, "H"); put(3, 0, "T"); put(4, 0, "H")
    if "tail" in traits:
        put(0, len(rows) - 3, "S"); put(1, len(rows) - 4, "S")
    if "fins" in traits:
        put(1, 1, "O")
    if "foliage" in traits:
        put(1, 0, "H"); put(5, 0, "H"); put(3, 0, "H")
    if "wings" in traits:
        put(0, 3, "O"); put(0, 4, "O"); put(1, 2, "O")
    if "sockets" in traits:
        put(4, 1, "*")
        pal["*"] = "#5a2a6a"

    body_top = 3
    if role == "Warrior":
        # Helmet over the hair, a sword raised in the front hand.
        for x in range(2, 5):
            put(x, 0, "G")
        put(6, body_top - 1, "M"); put(6, body_top, "M"); put(6, body_top + 1, "W")
        put(5, body_top + 1, "S")
    elif role == "Chief":
        # A gold crown and a cape in the trim colour.
        put(2, 0, "Y"); put(3, 0, "Y"); put(4, 0, "Y")
        put(1, body_top, "T"); put(1, body_top + 1, "T"); put(1, body_top + 2, "T")
    elif role == "Shaman":
        # A hood and a staff with a glowing orb.
        for x in range(1, 5):
            put(x, 0, "T")
        put(1, 1, "T")
        put(6, 0, "O"); put(6, 1, "W"); put(6, 2, "W"); put(6, 3, "W"); put(6, 4, "W")
    else:
        # Villager: a tool on the back (a small sack).
        put(1, body_top, "W"); put(1, body_top + 1, "W")
    if "big" in traits:
        # Bullfolk stand a head taller: an extra body row.
        rows.insert(body_top + 1, list(".SCCCS."))
    return "\n".join("".join(r) for r in rows), pal


# ---------------------------------------------------------------------------------- drawing

def parse(template):
    lines = [l for l in template.strip("\n").split("\n")]
    w = max(len(l) for l in lines)
    return [l.ljust(w, ".") for l in lines]


def render(grid, pal, swim=False):
    """Pixels of a grid (list of strings) with automatic shading, as an RGBA image."""
    h, w = len(grid), len(grid[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    filled = lambda x, y: 0 <= x < w and 0 <= y < h and grid[y][x] != "."
    for y in range(h):
        for x in range(w):
            ch = grid[y][x]
            if ch == ".":
                continue
            c = hex_rgb(pal[ch])
            if ch not in NO_SHADE:
                if not filled(x, y + 1) or not filled(x - 1, y) or not filled(x + 1, y):
                    c = shade(c, 0.72)  # soft outline on the bottom and sides
                elif not filled(x, y - 1):
                    c = shade(c, 1.12)  # lit top edge
            img.putpixel((x, y), c + (255,))
    if swim:
        # A line of water across the bottom.
        for x in range(w):
            if any(filled(x, yy) for yy in range(h)):
                img.putpixel((x, h - 1), (120, 200, 240, 200))
    return img


def leg_groups(grid):
    """Columns of leg pixels in the bottom row, grouped into legs (left to right)."""
    bottom = grid[-1]
    groups, cur = [], []
    for x, ch in enumerate(bottom):
        if ch == "L":
            cur.append(x)
        elif cur:
            groups.append(cur); cur = []
    if cur:
        groups.append(cur)
    return groups


def walk(grid, phase):
    """A walking frame: the bottom row of every other leg steps forward, the others back."""
    g = [list(r) for r in grid]
    w = len(g[0])
    bottom = ["."] * w
    for k, cols in enumerate(leg_groups(grid)):
        step = (1 if (k % 2 == 0) == (phase == 1) else -1)
        for x in cols:
            nx = min(max(x + step, 0), w - 1)
            bottom[nx] = "L"
    for x, ch in enumerate(grid[-1]):
        if ch != "L" and ch != ".":
            bottom[x] = ch
    g[-1] = bottom
    return ["".join(r) for r in g]


def attack(grid):
    """The upper body lunges one pixel forward (to the right)."""
    h = len(grid)
    legs_from = h - 2 if any("L" in r for r in grid[-2:]) else h
    out = []
    for y, r in enumerate(grid):
        out.append(("." + r[:-1]) if y < legs_from - 1 else r)
    return [r + "." for r in out]


def swim(grid):
    """Only the body shows above the water: the leg rows are cut, a water line drawn."""
    rows = [r for r in grid if "L" not in r or r.replace("L", ".").strip(".")]
    rows = [r.replace("L", ".") for r in rows]
    return rows + ["".join("~" if c != "." else "." for c in rows[-1])]


def death(grid):
    """Dead: a tall creature (a person) lies on its side, feet to the left; a long one (an
    animal) lies on its back, legs up."""
    h, w = len(grid), len(grid[0])
    if h >= w:
        # A quarter turn clockwise: the old top goes to the right.
        return ["".join(grid[h - 1 - j][i] for j in range(h)) for i in range(w)]
    return grid[::-1]


def poses(template, pal):
    grid = parse(template)
    pal = dict(pal)
    pal["~"] = "#78c8f0"
    out = {
        "idle": render(grid, pal),
        "walk1": render(walk(grid, 1), pal),
        "walk2": render(walk(grid, 2), pal),
        "attack": render(attack(grid), pal),
        "swim": render(swim(grid), pal),
        "death": render(death(grid), pal),
    }
    # The dead lie down: their sprite is wider than tall, darkened a little.
    d = out["death"]
    px = d.load()
    for y in range(d.height):
        for x in range(d.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (int(r * 0.8), int(g * 0.8), int(b * 0.8), a)
    return out


def all_creatures():
    creatures = {}
    for name, (t, p) in ANIMALS.items():
        creatures[name] = poses(t, p)
    for name, (t, p) in MONSTERS.items():
        creatures[name] = poses(t, p)
    for race in RACES:
        for role in ROLES:
            t, p = person(race, role)
            creatures[f"{race.lower()}_{role.lower()}"] = poses(t, p)
    return creatures


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for f in OUT.glob("*.png"):
        f.unlink()
    creatures = all_creatures()
    for name, frames in creatures.items():
        for pose, img in frames.items():
            img.save(OUT / f"{name}_{pose}.png")
    # Preview sheet: one row per creature, its poses side by side, scaled up 4x.
    scale, cell = 4, 26
    names = list(creatures)
    cols = 3
    per_col = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * len(POSES) * cell * scale + (cols - 1) * 4 * scale,
                               per_col * cell * scale), (70, 120, 60, 255))
    for k, name in enumerate(names):
        col, row = divmod(k, per_col)
        for p, pose in enumerate(POSES):
            img = creatures[name][pose]
            x0 = (col * len(POSES) + p) * cell + col * 4 + (cell - img.width) // 2
            y0 = row * cell + cell - img.height - 3
            sheet.alpha_composite(img.resize((img.width * scale, img.height * scale), Image.NEAREST),
                                  (x0 * scale, y0 * scale))
    sheet.save(SHEET)
    print(f"{len(creatures)} creatures x {len(POSES)} poses -> {OUT}")


if __name__ == "__main__":
    main()
