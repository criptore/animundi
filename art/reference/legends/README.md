# Sources of the legendary monsters' sprites

These six 32×32 sprites come from the tiles of **Dungeon Crawl Stone Soup**, released under **CC0 1.0** (public domain, see `LICENSE-CC0.txt`), as published on OpenGameArt:
- [Dungeon Crawl 32x32 tiles](https://opengameart.org/content/dungeon-crawl-32x32-tiles), maintained by Chris Hamons;
- [Dungeon Crawl 32x32 tiles supplemental](https://opengameart.org/content/dungeon-crawl-32x32-tiles-supplemental).

CC0 asks for no attribution. Thanks go anyway to the Dungeon Crawl Stone Soup artists and to rltiles, which they grew from. The full list of artists is in the tile package (`utility/FilteredList.txt`).

| File | Tile in the package | Changes made by `art/legends.py` |
|---|---|---|
| `ash_wyrm.png` | `monster/dragons/dragon.png` | mirrored to face right; green scales recoloured to embers, wings darkened |
| `frost_titan.png` | `monster/frost_giant_new.png` | none |
| `elder_treant.png` | `monster/fungi_plants/treant.png` | none |
| `hollow_king.png` | `monster/undead/ancient_lich_new.png` | none |
| `sand_colossus.png` | `monster/stone_giant_new.png` | warmed to sandstone |
| `storm_roc.png` | `monster/griffon.png` | mirrored to face right; brown feathers recoloured to storm blue |

For every legend, `art/legends.py` makes the game's poses from the single tile: two walking frames, an attack, a swim and a death pose. `python3 art/legends.py --drawn` draws the legends from shapes instead, as before.
