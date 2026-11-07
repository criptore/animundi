"""Cuts the reference asset sheets (art/reference/*.png) into game sprites.

For each sheet: the light-blue background and the drop shadows are removed by flood-filling from
the image border (black outlines stop the fill, so blue inside a sprite stays), plus enclosed
pockets of the exact background blue. Each sprite is cut from a hand-placed cell (SHEETS), brought
back to its true pixel-art grid (the sheets use ~5-10 sheet pixels per art pixel), enlarged and
detailed when its sheet is coarser than the characters (UPSCALE), and saved as a transparent PNG.

    pip install pillow numpy scipy
    python3 art/extract_sprites.py            # writes assets/sprites/<group>/<Name>.png
    python3 art/extract_sprites.py --debug    # also writes art/reference/debug_*.png
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, 'reference')
OUT = os.path.join(os.path.dirname(HERE), 'assets', 'sprites')

ROLES = ['Villager', 'Warrior', 'Chief', 'Shaman']


def grid(names, cols, rows):
    """Cells of a regular grid, row by row: cols/rows are lists of (start, end) in sheet pixels."""
    return [(n, (cx[0], cy[0], cx[1], cy[1])) for n, (cy, cx) in zip(names, [(r, c) for r in rows for c in cols])]


ROLE_COLS = [(95, 318), (322, 560), (562, 782), (786, 1005)]
ROLE_ROWS = [(128, 333), (336, 537), (540, 745), (748, 966)]


def roles(races):
    return grid([f'{r}_{role}' for r in races for role in ROLES], ROLE_COLS, ROLE_ROWS)


# sheet -> (output group, [(name, (x0, y0, x1, y1) cell in the 1024x1024 sheet)])
# Cells are drawn around each sprite and stop above its label.
SHEETS = {
    'trees': ('trees', [
        ('Oak', (60, 50, 245, 235)), ('Autumn oak', (305, 50, 490, 235)), ('Red oak', (550, 50, 735, 235)),
        ('Golden oak', (790, 50, 975, 235)), ('Jungle tree', (30, 310, 275, 575)), ('Swamp tree', (305, 330, 545, 575)),
        ('Pine', (560, 350, 750, 575)), ('Snowy pine', (790, 350, 975, 575)), ('Palm', (80, 665, 295, 930)),
        ('Acacia', (335, 685, 720, 930)), ('Dead tree', (755, 680, 955, 930))]),
    'small_plants': ('plants', [
        ('Bush', (45, 85, 255, 232)), ('Jungle bush', (280, 55, 550, 240)), ('Rock', (585, 125, 745, 232)),
        ('Boulder', (785, 55, 990, 232)), ('Red mushroom', (75, 390, 220, 538)), ('Pink mushroom', (340, 390, 490, 538)),
        ('Purple mushroom', (585, 390, 735, 538)), ('Cactus', (790, 340, 990, 570)), ('Grassy rock', (105, 710, 305, 878)),
        ('Grass', (575, 730, 755, 878)), ('Flowers', (780, 700, 990, 878))]),
    'animals': ('animals', [
        ('Sheep', (35, 120, 245, 295)), ('Cow', (275, 100, 525, 295)), ('Pig', (545, 150, 760, 295)),
        ('Chicken', (805, 125, 985, 295)), ('Horse', (10, 375, 270, 650)), ('Wolf', (260, 420, 510, 650)),
        ('Bear', (520, 420, 790, 650)), ('Deer', (800, 350, 1010, 650)), ('Rabbit', (55, 745, 222, 965)),
        ('Fox', (260, 740, 515, 965)), ('Fish', (570, 775, 735, 925)), ('Crab', (800, 800, 990, 965))]),
    'monsters': ('monsters', [
        ('Skeleton', (70, 90, 250, 325)), ('Zombie', (435, 85, 610, 325)), ('Slime', (745, 175, 935, 325)),
        ('Demon', (20, 380, 295, 650)), ('Ghost', (400, 400, 610, 618)), ('Spider', (695, 450, 995, 650)),
        ('Golem', (10, 705, 310, 970)), ('Yeti', (370, 695, 635, 970)), ('Dragon', (690, 705, 1005, 970))]),
    'races': ('races', [
        ('Humans', (50, 85, 210, 325)), ('Elves', (245, 80, 430, 325)), ('Dwarves', (435, 125, 650, 325)),
        ('Orcs', (650, 80, 835, 325)), ('Goblins', (845, 160, 1010, 325)), ('Lizardfolk', (10, 380, 262, 650)),
        ('Felines', (262, 400, 435, 650)), ('Merfolk', (435, 375, 665, 650)), ('Treefolk', (665, 375, 855, 650)),
        ('Fairies', (855, 435, 1010, 620)), ('Bullfolk', (70, 685, 385, 970)),
        ('Undead', (755, 725, 930, 970))]),
    'roles_humans_elves_dwarves_orcs': ('peoples', roles(['Humans', 'Elves', 'Dwarves', 'Orcs'])),
    'roles_goblins_lizardfolk_felines_merfolk': ('peoples', roles(['Goblins', 'Lizardfolk', 'Felines', 'Merfolk'])),
    'roles_treefolk_fairies_bullfolk_undead': ('peoples', roles(['Treefolk', 'Fairies', 'Bullfolk', 'Undead'])),
}


def background_mask(rgb):
    """True where the pixel is background: bluish and connected to the image border."""
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    bluish = (b > r + 35) & (b > g + 5) & (b > 120)
    labels, _ = ndimage.label(bluish)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    bg = np.isin(labels, list(border))
    # Pockets of background closed off by outlines (between legs, under wings): same blue as the
    # sheet's background, in blobs big enough not to be a highlight.
    ref = np.median(rgb[bg], axis=0)
    close = np.abs(rgb.astype(int) - ref).max(axis=2) < 28
    pockets, _ = ndimage.label(close & ~bg)
    sizes = ndimage.sum(np.ones_like(close), pockets, index=np.arange(pockets.max() + 1))
    return bg | (sizes[pockets] >= 60) & (pockets > 0)


def pixel_size(rgb, fg):
    """Art-pixel size in screen pixels, from the spacing of colour edges inside sprites."""
    lum = rgb.astype(float).mean(axis=2)
    edges = (np.abs(np.diff(lum, axis=1)) > 18) & fg[:, 1:]
    sig = edges.sum(axis=0).astype(float)
    sig -= sig.mean()
    ac = np.correlate(sig, sig, mode='full')[len(sig) - 1:]
    lags = range(4, 13)
    return max(lags, key=lambda l: ac[l])


def to_pixel_grid(rgba, p):
    """Downsample by p, choosing the grid phase that keeps blocks most uniform; median colour."""
    h, w = rgba.shape[:2]
    best, best_err = (0, 0), None
    lum = rgba[..., :3].astype(float).mean(axis=2)
    for oy in range(p):
        for ox in range(p):
            hh, ww = (h - oy) // p, (w - ox) // p
            blocks = lum[oy:oy + hh * p, ox:ox + ww * p].reshape(hh, p, ww, p)
            err = blocks.var(axis=(1, 3)).mean()
            if best_err is None or err < best_err:
                best, best_err = (oy, ox), err
    oy, ox = best
    hh, ww = (h - oy) // p, (w - ox) // p
    blocks = rgba[oy:oy + hh * p, ox:ox + ww * p].reshape(hh, p, ww, p, 4).transpose(0, 2, 1, 3, 4).reshape(hh, ww, p * p, 4)
    alpha = (blocks[..., 3] > 0).mean(axis=2) > 0.5
    # Median of the opaque samples, from an inner window to avoid bleeding from neighbours.
    inner = rgba[oy:oy + hh * p, ox:ox + ww * p].reshape(hh, p, ww, p, 4)[:, 1:p - 1, :, 1:p - 1, :3]
    colour = np.median(inner.transpose(0, 2, 1, 3, 4).reshape(hh, ww, -1, 3), axis=2)
    out = np.zeros((hh, ww, 4), dtype=np.uint8)
    out[..., :3] = colour.astype(np.uint8)
    out[..., 3] = np.where(alpha, 255, 0)
    return out


# Groups drawn at a coarser pixel size than the characters: enlarged with Scale2x (as many times
# as needed) and given extra painted detail, so every sprite has the same pixel density in game.
UPSCALE = {'trees': 4, 'plants': 2}


def scale2x(rgba):
    """EPX / Scale2x: doubles a pixel-art image, rounding diagonal edges without blurring."""
    h, w = rgba.shape[:2]
    pad = np.pad(rgba, ((1, 1), (1, 1), (0, 0)), mode='edge')
    P = pad[1:-1, 1:-1]
    A, B, C, D = pad[:-2, 1:-1], pad[1:-1, 2:], pad[1:-1, :-2], pad[2:, 1:-1]  # up, right, left, down
    eq = lambda x, y: np.all(x == y, axis=2)
    out = np.zeros((h * 2, w * 2, 4), dtype=rgba.dtype)
    c1 = np.where((eq(C, A) & ~eq(C, D) & ~eq(A, B))[..., None], A, P)
    c2 = np.where((eq(A, B) & ~eq(A, C) & ~eq(B, D))[..., None], B, P)
    c3 = np.where((eq(D, C) & ~eq(D, B) & ~eq(C, A))[..., None], C, P)
    c4 = np.where((eq(B, D) & ~eq(B, A) & ~eq(D, C))[..., None], D, P)
    out[0::2, 0::2], out[0::2, 1::2], out[1::2, 0::2], out[1::2, 1::2] = c1, c2, c3, c4
    return out


def thin_outline(rgba):
    """After enlarging, outlines are several pixels thick: keep only their outer pixel (the one
    touching transparency) and fill the inner ones with the colour of the body next to them,
    slightly darkened, so outlines match the 1-pixel outlines of the characters."""
    out = rgba.copy()
    for _ in range(4):
        rgb = out[..., :3].astype(int)
        opaque = out[..., 3] > 0
        outline = opaque & (rgb.max(axis=2) < 60)
        body = opaque & ~outline
        tp = np.pad(~opaque, 1, constant_values=True)
        touches_air = tp[:-2, 1:-1] | tp[2:, 1:-1] | tp[1:-1, :-2] | tp[1:-1, 2:]
        inner = outline & ~touches_air
        bp = np.pad(body, 1)
        cp = np.pad(out[..., :3], ((1, 1), (1, 1), (0, 0)))
        filled = False
        for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
            src = bp[dy:dy + body.shape[0], dx:dx + body.shape[1]] & inner
            if src.any():
                colour = cp[dy:dy + body.shape[0], dx:dx + body.shape[1]][src]
                out[..., :3][src] = (colour * 0.88).astype(np.uint8)
                inner &= ~src
                filled = True
        if not filled:
            break
    return out


def add_detail(rgba, seed):
    """Paints detail on an enlarged sprite: soft light on edges facing the upper left, shade on
    edges facing the lower right, and a fine leaf / stone texture in 2x2 clusters. Outlines stay."""
    rgba = thin_outline(rgba)
    rgb = rgba[..., :3].astype(float)
    opaque = rgba[..., 3] > 0
    outline = opaque & (rgb.max(axis=2) < 60)
    body = opaque & ~outline
    edge = ~body
    pad = np.pad(edge, 1, constant_values=True)
    lit = body & (pad[:-2, 1:-1] | pad[1:-1, :-2])        # something empty above or to the left
    shaded = body & (pad[2:, 1:-1] | pad[1:-1, 2:])        # ... below or to the right
    h, w = edge.shape
    rng = np.random.default_rng(seed)
    cells = rng.random(((h + 1) // 2, (w + 1) // 2))
    noise = np.kron(cells, np.ones((2, 2)))[:h, :w]
    factor = np.ones((h, w))
    factor[body] *= 0.94 + 0.12 * noise[body]
    factor[lit & ~shaded] *= 1.14
    factor[shaded & ~lit] *= 0.84
    out = rgba.copy()
    out[..., :3] = np.clip(rgb * factor[..., None], 0, 255).astype(np.uint8)
    return out


def trim(rgba):
    ys, xs = np.nonzero(rgba[..., 3])
    if len(ys) == 0:
        return rgba
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def main():
    debug = '--debug' in sys.argv
    report = []
    for sheet, (group, cells) in SHEETS.items():
        rgb = np.array(Image.open(os.path.join(REF, sheet + '.png')).convert('RGB'))
        fg = ~background_mask(rgb)
        p = pixel_size(rgb, fg)
        report.append(f'{sheet}: {len(cells)} sprites, {p} sheet pixels per art pixel')
        os.makedirs(os.path.join(OUT, group), exist_ok=True)
        if debug:
            from PIL import ImageDraw
            dbg = Image.fromarray(np.where(fg[..., None], rgb, 255).astype(np.uint8))
            d = ImageDraw.Draw(dbg)
        for name, (x0, y0, x1, y1) in cells:
            mask = fg[y0:y1, x0:x1].copy()
            # Keep only blobs of real size (drops label crumbs and neighbours' tips).
            labels, n = ndimage.label(mask)
            sizes = ndimage.sum(mask, labels, index=np.arange(n + 1))
            mask &= sizes[labels] >= max(40, 0.03 * sizes[1:].max(initial=0))
            rgba = np.dstack([rgb[y0:y1, x0:x1], np.where(mask, 255, 0)]).astype(np.uint8)
            sprite = trim(to_pixel_grid(rgba, p))
            for _ in range(UPSCALE.get(group, 1).bit_length() - 1):
                sprite = scale2x(sprite)
            if group in UPSCALE:
                sprite = add_detail(sprite, seed=sum(map(ord, name)))
            Image.fromarray(sprite).save(os.path.join(OUT, group, name.replace(' ', '_') + '.png'))
            if debug:
                d.rectangle((x0, y0, x1, y1), outline=(255, 0, 0))
                d.text((x0 + 2, y0 + 2), name, fill=(255, 0, 0))
        if debug:
            dbg.save(os.path.join(REF, f'debug_{sheet}.png'))
    print('\n'.join(report))


if __name__ == '__main__':
    main()
