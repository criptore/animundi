# Mods (1.0)

A mod is a folder in the game's data folder, under `mods/` (`user://mods/` for Godot: on Linux `~/.local/share/godot/app_userdata/Animundi/mods/`, on Windows `%APPDATA%\Godot\app_userdata\Animundi\mods\`). Every folder there is read when a world is made; the settings list the mods found and what each brought, or why one was refused. A file that does not read is skipped: the game goes on without it.

```
mods/
  my_mod/
    species.json      new creatures, or creatures changed (same id)
    buildings.json    new village buildings, or buildings changed
    eras.json         new moods of the world, or moods changed
    ages.json         more words for the ages beyond the future
    scenarios.json    more scenarios on the title screen
    stamps/*.json     more stamps (saved with "Copy the land")
    sprites/*.png     pictures: sprites/foo.png is the sprite "effects/Mod_foo"
```

Each file has the shape of the game's own (`data/species.json`, `data/buildings.json`, `data/eras.json`, `data/ages.json` "beyond", `data/scenarios.json`); a record with an id the game has replaces it, a new one is added.

- **A creature**: `{"species": [{"id": "glowbeast", "name": "Glowbeast", "sprite": "effects/Mod_glowbeast", "natural": {"Grassland": 0.2}, "diet": "herbivore", "size": 3, "lifespan": 8}]}`. `natural` gives the biomes it is born in and how often. Its sprite needs a picture per pose: `sprites/glowbeast_idle.png`, `_walk1`, `_walk2`, `_attack`, `_swim`, `_death` (128 pixels at most a side; a pixel is a world pixel, a tile is 8).
- **A building**: as in `data/buildings.json`, with `age` for the age it waits for. It is placed before the ruin, last in the plan.
- **A mood of the world**: as in `data/eras.json` (growth, cold, fire, monsters, spirits, knowledge, harvest, disasters, tint, weight).
- **A scenario**: as in `data/scenarios.json`.

Mods are trusted data, never code: nothing in a mod runs.
