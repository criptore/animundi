# Animundi

*Anima mundi*: the soul of the world.

A top-down pixel-art god sandbox. You shape a world, drop in peoples, animals and monsters, then watch history write itself.

The twist: every people, monster species and force of nature (forest, volcano, ocean…) is driven by a small AI running locally on your machine. It invents its own culture: items, rituals, laws, architecture, and even the code of its own inventions, written in a small in-game language.

## Status

First sprite set, "micro roguelike" style: 8×8 tiles, one small shared palette.

- `assets/sheet_peoples.png`: 13 peoples × 4 roles (villager, warrior, chief, shaman)
- `assets/sheet_world.png`: animals, monsters, nature, buildings, items, phenomena, terrain
- `assets/native/`: every sprite as a transparent 8×8 PNG
- `assets/sprites.py`: the source of every sprite

To regenerate the sheets (Python 3 and Pillow):

```bash
pip install pillow
python3 assets/sprites.py
```

Each sprite is a grid of 8 rows of 8 characters; each character is a palette colour. Peoples are generated from a base body, race traits (ears, tusks, tail, wings…) and a role. A race fits on one line, which is what will let the AIs invent peoples of their own.

## Next steps

1. Playable 2D map with these tiles and a few living villages.
2. The invention language (effects, costs, conditions).
3. One local AI per people, thinking rarely and evolving its culture.
