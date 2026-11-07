# Animundi

*Anima mundi*: the soul of the world.

A top-down pixel-art god sandbox. You shape a world, drop in peoples, animals and monsters, then watch history write itself.

The twist: every people, monster species and force of nature (forest, volcano, ocean…) is driven by a small AI running locally on your machine. It invents its own culture: items, rituals, laws, architecture, and even the code of its own inventions, written in a small in-game language.

## Status: 0.1 World

![A generated world](docs/images/world_0.1.png)

A map shader adds relief lighting, depth-coloured animated water, shore foam and drifting cloud shadows (toggle with E).

Every world is generated from a seed: continents, mountains, climate (latitude, altitude, winds and rain shadows), rivers and lakes, and 21 biomes, including volcanoes, mushroom lands and cursed lands.

## Running the game

Requires [Godot 4.3](https://godotengine.org/download) (standard version, not .NET).

1. Open Godot, click **Import**, and pick `project.godot` in this folder.
2. Press **F5** to run.

Controls:

| Action | Input |
|---|---|
| Zoom | mouse wheel |
| Pan | right or middle drag, WASD, arrow keys |
| New random world | R or the **Random** button |
| Map layers | 1 Biomes · 2 Height · 3 Temperature · 4 Humidity · 5 Rivers |
| Effects on / off | E |
| Tile info | hover the map (bottom bar) |

Type any word or number as the seed: the same seed and settings always give the same world.

## Project layout

| Path | Content |
|---|---|
| `scripts/world/` | world settings, data and the generator (shape → climate → hydrology → biomes) |
| `scripts/render/` | map renderer (tiles and data layers) |
| `scripts/ui/` | camera and HUD |
| `shaders/` | map shader (relief, water, clouds) |
| `scripts/core/` | seeded random streams, priority queue |
| `scripts/generated/` | files written by `art/sprites.py`, do not edit |
| `assets/tiles/` | terrain atlas used by the game |
| `art/` | sprite source (`sprites.py`), sprite sheets and loose 8×8 PNGs (not imported by Godot) |
| `tests/` | headless tests |
| `tools/` | headless preview renderer and screenshot tool |
| `docs/` | game design and research |

## Tests and tools

```bash
godot --headless --path . --import
```

```bash
godot --headless --path . --script res://tests/test_world.gd
```

```bash
godot --headless --path . --script res://tools/render_preview.gd -- <seed> <size> <out_dir>
```

After editing sprites, regenerate the sheets, the terrain atlas and its index (Python 3 and Pillow):

```bash
python3 art/sprites.py
```

## Design

- [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md): everything the game must contain and how it is generated.
- [docs/GOD_GAMES_RESEARCH.md](docs/GOD_GAMES_RESEARCH.md): what other god games let you do, and what Animundi takes.

Engine: Godot 4.3.

## Next steps

See the milestones in [docs/GAME_DESIGN.md § 23](docs/GAME_DESIGN.md#23-milestones). Next: **0.2 Life** (flora spreading, generated animal species, food chains).
