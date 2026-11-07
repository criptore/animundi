"""Animundi sprites, "micro roguelike" style: 8x8 tiles, one small shared palette.

Each sprite is a grid of 8 rows of 8 characters; each character is a colour from PAL
('.' = transparent). Peoples are generated: base body + race traits + role.

    python3 art/sprites.py   ->  art/sheet_*.png, art/native/*.png,
                                 assets/tiles/terrain.png, scripts/generated/terrain_atlas.gd
"""
from PIL import Image, ImageDraw, ImageFont
import os

PAL = {
    'k': '#1e1e24', 'K': '#3d3d4a', 'N': '#5e5e6a', 'n': '#8a8a96', 'g': '#b8b8c2', 'w': '#f4f4f0',
    's': '#f0c39b', 'S': '#c48a5c', 'h': '#6b4423', 't': '#8b5a2b', 'T': '#5a3a1e',
    'y': '#f0d264', 'm': '#e8a923', 'f': '#fff0a0', 'o': '#f08a2a',
    'r': '#d83a3a', 'R': '#8c2323', 'p': '#f49ac1', 'j': '#c95f8c',
    'l': '#9ad65a', 'G': '#4caf50', 'D': '#2c6e35', 'e': '#4dbfb0', 'E': '#2a7d72',
    'c': '#8fd8ff', 'b': '#3b8fe0', 'B': '#233f8c', 'A': '#1d4a94',
    'u': '#9b59c6', 'U': '#4f2470', 'q': '#e9d48a', 'Q': '#c4a65a', 'V': '#c9b458',
    'M': '#55663a', 'O': '#8aa38c', 'z': '#eaf3ff', 'Z': '#b9d3ee',
    'v': '#ff5a1a', 'i': '#a52a0a', 'x': '#e8e0c8',
}

# ---------------------------------------------------------------- peoples
# H hair/headwear, F skin, C clothes, L legs
BASE = ["..HHHH..",
        "..FkFk..",
        "..FFFF..",
        ".CCCCCC.",
        "F.CCCC.F",
        "..CCCC..",
        "..L..L..",
        "..L..L.."]

# skin, hair, clothes, legs, banner (shield/cape), magic (staff orb), traits
RACES = {
    'Humans':         dict(F='s', H='h', C='b', L='T', ban='r', mag='c', traits=[]),
    'Elves':           dict(F='s', H='y', C='G', L='D', ban='l', mag='l', traits=['ears']),
    'Dwarves':           dict(F='S', H='o', C='r', L='T', ban='m', mag='o', traits=['short', 'beard']),
    'Orcs':            dict(F='G', H='k', C='t', L='T', ban='R', mag='r', traits=['tusks']),
    'Goblins':        dict(F='l', H='M', C='Q', L='T', ban='y', mag='l', traits=['short', 'big_ears']),
    'Lizardfolk':  dict(F='e', H='E', C='V', L='e', ban='o', mag='y', traits=['crest', 'tail:E']),
    'Felines':          dict(F='o', H='o', C='u', L='o', ban='y', mag='p', traits=['cat_ears', 'tail:o']),
    'Merfolk':         dict(F='c', H='b', C='e', L='c', ban='b', mag='c', traits=['fins']),
    'Treefolk':        dict(F='t', H='G', C='D', L='T', ban='l', mag='l', traits=['foliage']),
    'Fairies':            dict(F='p', H='u', C='c', L='p', ban='p', mag='f', traits=['short', 'wings']),
    'Bullfolk':         dict(F='S', H='T', C='R', L='T', ban='o', mag='r', traits=['horns']),
    'Undead':   dict(F='x', H='K', C='U', L='K', ban='U', mag='u', traits=['sockets']),
}
ROLES = ['Villager', 'Warrior', 'Chief', 'Shaman']


def humanoid(race, role):
    r = RACES[race]
    g = [list(row) for row in BASE]
    tr = r['traits']
    if 'short' in tr:                       # one row shorter: drop the chin
        g = [list('........')] + g[:2] + g[3:]
    hr = 1 if 'short' in tr else 0          # head row
    face, body = hr + 1, hr + 2 if 'short' in tr else 3
    put = lambda x, y, c: (0 <= y < 8 and 0 <= x < 8) and g[y].__setitem__(x, c)

    if 'ears' in tr: put(1, face, 'F'); put(6, face, 'F')
    if 'big_ears' in tr:
        for x in (0, 1, 6, 7): put(x, face, 'F')
    if 'cat_ears' in tr:
        g[hr] = list('..H..H..')
    if 'round_ears' in tr: put(1, hr, 'p'); put(6, hr, 'p')
    if 'tusks' in tr: put(2, 2, 'w'); put(5, 2, 'w')
    if 'beard' in tr:
        g[body] = list('.CHHHHC.')
        g[body + 1][3] = g[body + 1][4] = 'H'
    if 'crest' in tr: g[hr] = list('...HH...')
    if 'fins' in tr: put(1, face, 'H'); put(6, face, 'H')
    if 'foliage' in tr: put(1, hr, 'H'); put(6, hr, 'H'); put(1, face, 'H')
    if 'wings' in tr:
        for y in (face, body): put(0, y, 'c'); put(7, y, 'c')
    if 'horns' in tr: put(1, hr, 'x'); put(6, hr, 'x')
    if 'sockets' in tr: g[face] = list('..kFkF..')
    for t in tr:
        if t.startswith('tail:'):
            put(6, 6, t[5:]); put(7, 5, t[5:])

    arm_y = body + 1
    if role == 'Warrior':
        if not ({'horns', 'cat_ears', 'crest'} & set(tr)):
            g[hr] = list('..nnnn..') if 'sockets' not in tr else g[hr]
        for y in range(max(0, arm_y - 3), arm_y): put(7, y, 'g')          # blade
        put(6, arm_y - 1, 'm')                                             # crossguard
        for y in (arm_y - 1, arm_y, arm_y + 1): put(0, y, 'ban')           # shield
    elif role == 'Chief':
        if 'cat_ears' in tr: g[hr] = list('..mmmm..')
        else:
            for x in range(2, 6): put(x, hr, 'm')
        for y in (5, 6): put(1, y, 'ban'); put(6, y, 'ban')                # cape
    elif role == 'Shaman':
        for x in range(2, 6):
            if g[hr][x] == 'H' or g[hr][x] == '.': put(x, hr, 'mag2')     # hood
        g[6] = list('..CCCC..'); g[7] = list('.CCCCCC.')                   # long robe
        for y in range(hr, 8):
            if y != arm_y: put(7, y, 't')
        put(7, max(0, hr - 1) if hr else 0, 'mag')                        # orb

    cmap = {'H': r['H'], 'F': r['F'], 'C': r['C'], 'L': r['L'], 'ban': r['ban'],
            'mag': r['mag'], 'mag2': 'U' if r['C'] != 'U' else 'K'}
    if role == 'Shaman':
        cmap['mag2'] = r['ban']
    return ["".join(cmap.get(c, c) for c in row) for row in g]


# ---------------------------------------------------------------- world
W = {}
W['Animals'] = {
    'Sheep':  ["........", "........", ".wwwww..", "wwwwwwkk", "wwwwwwkk", ".wwwww..", ".k.k.k..", ".k.k.k.."],
    'Cow':   ["........", "......xx", "wwkkwwkk", "wwkkwwkp", "wwwwwwk.", ".wwkww..", ".k.k.k..", ".k.k.k.."],
    'Pig':  ["........", "........", "j.......", ".pppppp.", "ppppppkp", "pppppppj", ".pppppp.", ".j.j.j.."],
    'Chicken':  ["........", "....r...", "...wwk..", "w..wwwo.", "wwwwww..", ".wwww...", "..o.o...", "........"],
    'Horse':  ["......tt", ".....Ttk", ".....tt.", "Ttttttt.", "Ttttttt.", ".t.t.t..", ".t.t.t..", ".T.T.T.."],
    'Wolf':    ["........", "......n.", "n.....nn", "nnnnnnnk", ".nnnnnn.", ".ngggn..", ".n.n.n..", ".n.n.n.."],
    'Bear':    ["........", "........", "......T.", ".tttttTt", "tttttttk", "tttttttt", ".tttttt.", ".TT..TT."],
    'Deer':    [".....T.T", "......T.", "......tt", "tttttttk", ".ttqqtt.", ".t.t.t..", ".t.t.t..", ".k.k.k.."],
    'Rabbit':   ["........", "........", ".....g.g", ".....g.g", "..gggggk", ".gggggg.", "w.gggg..", "..g..g.."],
    'Fox':  ["........", "........", "......o.", "w.....ok", "ooooooow", ".oooooo.", ".k.k.k..", "........"],
    'Fish': ["........", "........", "...bb...", "b.bbbbb.", "bbbbbbkb", "b.bbbbb.", "...bb...", "........"],
    'Crab':   ["........", "........", ".r....r.", "rr....rr", ".rkrrkr.", ".rrrrrr.", "r.r..r.r", "........"],
}
W['Monsters'] = {
    'Skeleton': ["..xxxx..", "..xkxk..", "..xxxx..", "...xx...", ".xxxxxx.", "x..xx..x", "..x..x..", "..x..x.."],
    'Zombie':    ["..TT.T..", "..lklk..", "..llll..", ".uuuulll", ".uuuu...", "..uuuu..", "..p..p..", "..k..k.."],
    'Slime':     ["........", "........", "...ll...", "..llll..", ".lkllkl.", ".llllll.", "llllllll", ".GGGGGG."],
    'Fire slime': ["........", "........", "...oo...", "..oooo..", ".okoook.", ".oooooo.", "oooooooo", ".rrrrrr."],
    'Demon':     [".x....x.", ".xrrrrx.", "..rfrf..", "..rrrr..", "RrrrrrrR", "R.rrrr.R", "..r..r..", ".kk..kk."],
    'Ghost':   ["..wwww..", ".wwwwww.", ".wkwwkw.", ".wwwwww.", ".wwkkww.", ".wwwwww.", ".wwwwww.", ".w.ww.w."],
    'Spider':  ["........", "k..kk..k", ".k.kk.k.", "..kkkk..", "kkkrrkkk", "..kkkk..", ".k.kk.k.", "k......k"],
    'Bat': ["........", "........", "..u..u..", "..uuuu..", "U.urru.U", "UUuuuuUU", "U.U..U.U", "........"],
    'Golem':     ["..nnnn..", "..cnnc..", ".nnnnnn.", "nNnnnnNn", "nN.nn.Nn", "...nn...", "..nn.nn.", "..NN.NN."],
    'Sandworm': ["........", "..qqq...", ".qkqQq..", ".qqqqQ..", "..QqqQ..", "...qqQ..", ".qqqqQq.", "QQQQQQQQ"],
    'Yeti':      ["..wwww..", "..wkwk..", "..wBBw..", ".wwwwww.", "w.wwww.w", "..wwww..", "..w..w..", "..w..w.."],
    'Kraken':    ["...uu...", "..uuuu..", ".ukuuku.", ".uuuuuu.", "u.u..u.u", "u.u..u.u", ".u.uu.u.", "..u..u.."],
}
W['Nature'] = {
    'Oak':        ["..GGGG..", ".GGlGGG.", "GGGGGlGG", "GlGGGGGG", ".GGDDGG.", "...tt...", "...tt...", "..tttt.."],
    'Pine':        ["...DD...", "..DGGD..", "..DDDD..", ".DGGGGD.", ".DDDDDD.", "DGGGGGGD", "DDDDDDDD", "...tt..."],
    'Snowy pine':["...zz...", "..zDDz..", "..DDDD..", ".zzDDzz.", ".DDDDDD.", "zzDDDDzz", "DDDDDDDD", "...tt..."],
    'Birch':      ["..llll..", ".llGlll.", "lllllGll", ".llGlll.", "..llll..", "...wk...", "...ww...", "...kw..."],
    'Palm':      [".GG..GG.", "GGGGGGGG", "G..tt..G", "...t....", "...t....", "....t...", "....t...", "...ttt.."],
    'Cactus':       ["...G....", "..GlG...", "G.GlG...", "GGGlG.G.", "..GlGGG.", "..GlG...", "..GlG...", "..GlG..."],
    'Dead tree':   [".T...T..", "..T.T..T", "...T..T.", "...TTT..", "....T...", "....T...", "....T...", "...TTT.."],
    'Cursed tree': ["..UUUU..", ".UuUUuU.", "UUUuUUUU", ".UUUUuU.", "..UUUU..", "...kk...", "...kk...", "..kkkk.."],
    'Giant mushroom': ["........", "..rrrr..", ".rwrrwr.", "rrrrrrrr", "...xx...", "...xx...", "...xx...", "..xxxx.."],
    'Berry bush': ["........", "........", "........", "..GGGG..", ".GrGGrG.", "GGGGrGGG", "GrGGGGGG", ".DDDDDD."],
    'Flowers':       ["........", "........", "........", "......y.", ".r...ymy", "rmr...y.", ".G..p.G.", ".G.pmpG."],
    'Reeds':      ["........", ".t...t..", ".t.t.t..", ".G.t.G.t", ".G.G.G.t", ".G.G.G.G", ".G.G.G.G", "GG.G.GGG"],
    'Rock':       ["........", "........", "........", "..ngg...", ".nnngn..", "nnnnnnN.", "nnnnnNNN", ".NNNNNN."],
    "Gold ore": ["........", "........", "........", "..nmg...", ".nnnnm..", "nmnnnnN.", "nnnmnNNN", ".NNNNNN."],
    'Iron ore':["........", "........", "........", "..nog...", ".nnnno..", "nonnnnN.", "nnnonNNN", ".NNNNNN."],
    'Crystals':     ["........", "...c....", "..cbc.c.", "..cbccb.", ".cbcbcb.", ".cbcbcb.", "..nnnnn.", "........"],
    'Bones':    ["........", "........", "........", "..xxxx..", ".xkxxkx.", ".xxxxxx.", "..x.x.x.", "x......x"],
}
W['Buildings'] = {
    'Hut':        ["...yy...", "..yyyy..", ".yyQyyy.", "yyyyyyQy", ".tttttt.", ".ttkktt.", ".ttkktt.", ".TTkkTT."],
    'Tent':        ["........", "........", "...r....", "..rwr...", ".rwkwr..", "rwrkrwr.", "rwrkrwr.", "........"],
    'House':       ["...RR...", "..RrrR..", ".RrrrrR.", "RRRRRRRR", ".tttttt.", ".tcttkt.", ".tcttkt.", ".TTTTkT."],
    'Stone house': ["...BB...", "..BbbB..", ".BbbbbB.", "BBBBBBBB", ".nnnnnn.", ".ncnnkn.", ".ncnnkn.", ".NNNNkN."],
    'Tower':         [".n.nn.n.", ".nnnnnn.", ".NnnnnN.", "..nkkn..", "..nnnn..", "..nnnn..", "..ntTn..", ".NNTTNN."],
    'Temple':       ["...mm...", "..xxxx..", ".xxxxxx.", "xxxxxxxx", ".x.xx.x.", ".x.xx.x.", ".x.xx.x.", "xxxxxxxx"],
    'Windmill':       [".g...g..", "..g.g...", "...T....", "..gtg...", ".gtttg..", "..ttt...", "..tkt...", "..TkT..."],
    'Forge':        [".....g..", "......g.", ".....NN.", "RRRRRRRR", ".nnnnnn.", ".noonkn.", ".nffnkn.", ".NNNNkN."],
    'Well':        ["........", ".RRRRRR.", "RRRRRRRR", ".T..t.T.", ".T..b.T.", "nnnnnnnn", "nNnNnNnN", "NNNNNNNN"],
    'Wheat field': ["yyyyyyyy", "lylylyly", "TTTTTTTT", "yyyyyyyy", "lylylyly", "TTTTTTTT", "yyyyyyyy", "lylylyly"],
    'Boat':       ["...k....", "...kww..", "...kwww.", "...kwwww", "...k....", "tttttttt", ".tTTTTt.", "..TTTT.."],
    'Wall':     ["........", "........", "n.n.n.n.", "nnnnnnnn", "nNnnNnnN", "nnnnnnnn", "NnnNnnNn", "NNNNNNNN"],
    'Grave':        ["........", "........", "..nnnn..", ".nnknnn.", ".nkkknn.", ".nnknnn.", ".nnnnnn.", "DDDDDDDD"],
    'Totem':        ["..rrrr..", "..tkkt..", "..tttt..", ".rtrrtr.", "..tkkt..", "..tttt..", "..tTTt..", ".TTTTTT."],
}
W['Items'] = {
    'Wood':       ["........", "........", "........", "qtttttt.", "Qtttttt.", ".qtttttt", ".Qtttttt", "........"],
    'Stone':     ["........", "........", "........", "........", "..nng...", ".nnnnn..", "nnNnnnNn", ".NNNNNN."],
    "Gold bar":["........", "........", "........", "........", "..yyyy..", ".ymmmmm.", "mmmmmm..", "........"],
    'Iron bar':["........", "........", "........", "........", "..gggg..", ".gnnnnn.", "nnnnnn..", "........"],
    'Bread':       ["........", "........", "........", "........", "..SSSS..", ".SoSoSS.", ".SSSSSS.", "........"],
    'Meat':     ["........", "........", "...rr...", "..rrrr..", ".rrrrr..", "x.rrr...", "xx......", "........"],
    'Sword':       [".......g", "......g.", ".....g..", "....g...", ".m.g....", "..m.....", ".t.m....", "t......."],
    'Shield':   ["........", ".nnnnnn.", ".nrrrrn.", ".nrmmrn.", ".nrmmrn.", ".nrrrrn.", "..nrrn..", "...nn..."],
    'Potion':     ["........", "...tt...", "...cc...", "..cccc..", ".cuuuuc.", ".cuuuuc.", ".cuuuuc.", "..cccc.."],
    'Scroll':  ["........", "........", ".Txxxx..", "..xkkx..", "..xxxx..", "..xkkx..", "..xxxxT.", "........"],
    'Crown':   ["........", "........", "........", ".m.mm.m.", ".mmmmmm.", ".mrmmbm.", ".mmmmmm.", "........"],
}
W['Phenomena'] = {
    'Fire':        ["....f...", "...ff...", "..fof..f", ".fooff.f", ".foroff.", "forrrof.", "forrrof.", ".ooooo.."],
    'Meteor':  ["f.......", ".f......", "..fo....", "...oo...", "....onN.", "...nnnnN", "...nNnnN", "....NNN."],
    'Lightning':     ["...yyy..", "..yyy...", ".yyy....", "yyyyyy..", "...yy...", "..yy....", ".yy.....", "y......."],
    'Tornado':    ["gggggggg", ".nnnnnn.", "..gggg..", "..nnnn..", "...gg...", "...nn...", "....g...", "...n...."],
    'Rain':      ["..ggg...", ".gggggg.", "gggggggg", ".nnnnnn.", "b..b..b.", ".b..b..b", "b..b..b.", ".b..b..."],
    'Blizzard':   ["..ggg...", ".gggggg.", "gggggggg", ".nnnnnn.", "Z..Z..Z.", ".Z..Z..Z", "Z..Z..Z.", ".Z..Z..."],
    'Acid rain':["..lll...", ".llllll.", "llllllll", ".GGGGGG.", "l..l..l.", ".l..l..l", "l..l..l.", ".l..l..."],
    'Explosion':  ["o..f..o.", ".ofyyfo.", "ofyffyfo", ".fyffyf.", "ofyffyfo", ".ofyyfo.", "o..ff..o", "........"],
    'Blessing':["..c.....", ".ccc..y.", "..c..yyy", "......y.", "...y....", "..yyy.c.", "...y.ccc", "......c."],
    'Curse':["..u.....", ".uuu..U.", "..u..UUU", "......U.", "...U....", "..UUU.u.", "...U.uuu", "......u."],
    'Earthquake':     ["QqQqQkQq", "qQqQkQqQ", "QqQkkQqQ", "qQqkQqQq", "QqkQqQqQ", "qkkqQqQq", "QkqQqQqQ", "kqQqQqQq"],
}


def tile(base, a1, a2=None):
    g = [[base] * 8 for _ in range(8)]
    for i, (x, y) in enumerate([(1, 1), (5, 1), (3, 3), (6, 4), (1, 5), (4, 6), (7, 7)]):
        g[y][x] = a1 if (i < 4 or a2 is None) else a2
    return ["".join(r) for r in g]


W['Terrain'] = {
    'Deep water': tile('A', 'B', 'b'), 'Water': tile('b', 'c'), 'Sand': tile('q', 'Q'),
    'Grass': tile('G', 'l'), 'Flower meadow': tile('G', 'l', 'p'), 'Forest': tile('D', 'G'),
    'Jungle': tile('D', 'l', 'E'), 'Savanna': tile('V', 'Q', 'G'), 'Swamp': tile('M', 'e', 'D'),
    'Tundra': tile('O', 'z', 'G'), 'Snow': tile('z', 'Z'), 'Ice': tile('Z', 'c', 'w'),
    'Mountain': tile('n', 'N', 'g'), 'Peak': tile('g', 'w', 'n'), 'Volcanic rock': tile('K', 'k', 'i'),
    'Lava': tile('v', 'i', 'f'), 'Cursed soil': tile('U', 'u'), 'Mushroom land': tile('j', 'p', 'u'),
    'Desert': ["qqqqqqqq", "qqQQqqqq", "qqqqqqqq", "qqqqqQQq", "qqqqqqqq", "QQqqqqqq", "qqqqqqqq", "qqqqQQqq"],
    'Hills': ["GGGGGGGG", "GGlllGGG", "GlGGGDGG", "GGGGGGGG", "GGGGlllG", "GGGlGGGD", "GDGGGGGG", "GGGGGGGG"],
    'Taiga': tile('D', 'z', 'O'),
}

# Order of the tiles in the game's terrain atlas (assets/tiles/terrain.png). Append only: the game
# looks tiles up by name through scripts/generated/terrain_atlas.gd, never by position.
TERRAIN_ATLAS = list(W['Terrain'].keys())


def export_terrain_atlas(repo_root):
    tiles = [to_image(W['Terrain'][n]) for n in TERRAIN_ATLAS]
    atlas = Image.new('RGBA', (8 * len(tiles), 8), (0, 0, 0, 0))
    for i, im in enumerate(tiles):
        atlas.paste(im, (8 * i, 0))
    tiles_dir = os.path.join(repo_root, 'assets', 'tiles')
    gen_dir = os.path.join(repo_root, 'scripts', 'generated')
    os.makedirs(tiles_dir, exist_ok=True)
    os.makedirs(gen_dir, exist_ok=True)
    atlas.save(os.path.join(tiles_dir, 'terrain.png'))
    with open(os.path.join(gen_dir, 'terrain_atlas.gd'), 'w') as f:
        f.write('# Generated by art/sprites.py. Do not edit by hand.\n')
        f.write('extends RefCounted\n\n')
        f.write('const TILE_SIZE := 8\n')
        f.write('const TEXTURE := "res://assets/tiles/terrain.png"\n')
        f.write('const TILES := [\n' + ''.join(f'\t"{n}",\n' for n in TERRAIN_ATLAS) + ']\n')


# ---------------------------------------------------------------- rendering
def to_image(rows):
    im = Image.new('RGBA', (len(rows[0]), len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != '.':
                c = PAL[ch]
                im.putpixel((x, y), (int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16), 255))
    return im


def outlined(rows):
    """Sheets only: grey outline around very light pixels (otherwise invisible on white)."""
    if not any(c in 'wxz' for r in rows for c in r):
        return rows
    w = len(rows[0]) + 2
    g = [['.'] * w] + [['.'] + list(r) + ['.'] for r in rows] + [['.'] * w]
    out = [row[:] for row in g]
    for y in range(len(g)):
        for x in range(w):
            if g[y][x] == '.' and any(0 <= y + dy < len(g) and 0 <= x + dx < w and g[y + dy][x + dx] in 'wxz'
                                      for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = 'g'
    return ["".join(r) for r in out]


def check(name, rows):
    assert len(rows) == 8 and all(len(r) == 8 for r in rows), (name, [len(r) for r in rows])
    bad = {c for r in rows for c in r if c != '.' and c not in PAL}
    assert not bad, (name, bad)


def slug(s):
    return s.replace("'", '').replace(' ', '_')


if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, 'native')
    os.makedirs(out, exist_ok=True)
    bold = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 24)
    small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 14)
    SC = 7
    n = 0

    def paste(sheet, rows, cx, bottom, terrain=False):
        im = to_image(rows if terrain else outlined(rows))
        im = im.resize((im.width * SC, im.height * SC), Image.NEAREST)
        sheet.paste(im, (cx - im.width // 2, bottom - im.height), im)

    # --- peoples sheet: one row per race, one column per role
    CW, RH, LW, PAD = 120, 95, 190, 30
    sheet = Image.new('RGB', (PAD * 2 + LW + CW * len(ROLES), PAD + 60 + RH * len(RACES) + PAD), 'white')
    d = ImageDraw.Draw(sheet)
    d.text((PAD, PAD), 'Peoples', fill='#222', font=bold)
    for j, role in enumerate(ROLES):
        tw = d.textlength(role, font=small)
        d.text((PAD + LW + j * CW + CW / 2 - tw / 2, PAD + 40), role, fill='#555', font=small)
    for i, race in enumerate(RACES):
        y = PAD + 60 + i * RH
        d.text((PAD, y + RH / 2 - 8), race, fill='#333', font=small)
        for j, role in enumerate(ROLES):
            rows = humanoid(race, role); check(race, rows)
            paste(sheet, rows, PAD + LW + j * CW + CW // 2, y + RH - 10)
            to_image(rows).save(os.path.join(out, f'{slug(race)}_{role}.png')); n += 1
    sheet.save(os.path.join(here, 'sheet_peoples.png'))

    # --- world sheet
    CELL, ROWH, PAD = 140, 120, 30
    cols = 9
    lines = sum((len(v) + cols - 1) // cols for v in W.values())
    sheet = Image.new('RGB', (PAD * 2 + cols * CELL, PAD + len(W) * 54 + lines * ROWH + PAD), 'white')
    d = ImageDraw.Draw(sheet)
    y = PAD
    for group, items in W.items():
        y += 12; d.text((PAD, y), group, fill='#222', font=bold); y += 42
        for k, (name, rows) in enumerate(items.items()):
            check(name, rows)
            if k and k % cols == 0: y += ROWH
            cx = PAD + (k % cols) * CELL + CELL // 2
            paste(sheet, rows, cx, y + ROWH - 30, terrain=(group == 'Terrain'))
            tw = d.textlength(name, font=small)
            d.text((cx - tw / 2, y + ROWH - 24), name, fill='#555', font=small)
            to_image(rows).save(os.path.join(out, slug(name) + '.png')); n += 1
        y += ROWH
    sheet.save(os.path.join(here, 'sheet_world.png'))
    export_terrain_atlas(os.path.dirname(here))
    print(n, 'sprites')
