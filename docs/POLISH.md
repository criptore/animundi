# Version 1.0

1.0 finishes the game: worlds can be saved and loaded, the world sounds and has its music, there are achievements to win and scenarios to begin with, mods can add to the game, every power and button that waited is in, it runs faster over long histories, and it builds into a game to share ([BUILD.md](BUILD.md)). Mods have their own page: [MODS.md](MODS.md).

| | Code | Data |
|---|---|---|
| Saved worlds | `sim/SaveState.cs`, `scripts/world/world_store.gd`, `scripts/ui/saves_window.gd` | `user://saves/` |
| Sound and music | `scripts/audio/soundscape.gd` | made as the game plays |
| Achievements | `scripts/world/achievements.gd`, `scripts/ui/achievements_window.gd`, `sim/Cards.cs` (Facts) | `data/achievements.json`, `user://achievements.json` |
| Scenarios | `scripts/main.gd` (start_scenario), `scripts/ui/scenarios_window.gd` | `data/scenarios.json` |
| Mods | `sim/AssetLibrary.cs` (LoadMods), `scripts/render2d/sprite_atlas.gd` | `user://mods/` |
| The last powers, favourites | `sim/Storyteller.cs`, `scripts/ui/favourites_window.gd` | |
| Weather on screen | `scripts/render2d/weather.gd` | |

## Saved worlds

- **Save** from the top bar or the pause menu, in one of six slots; **load** from there, from the pause menu or the title screen (**Load a world**). **Continue** on the title screen goes back to the world saved last.
- A **autosave** keeps the world every ten years (settings, on by default).
- A save holds **everything**: the land as the terrain tools left it, its settings, and the whole simulation (every creature, plant, village, building, kingdom, culture, myth, invention, spirit, legend, sickness, the ages, the mood of the world, the chronicle, even the dice). A world of 300 years and 3,500 people is about 1.7 MB and saves in a third of a second.
- How: the simulation's fields are written by reflection, shared objects kept shared; lists, dictionaries and sets are written as their items and built again on loading (hash codes change from one run to the next). Drawing, the scheduler's systems and questions still waiting for the model are left out: drawing is made again, and a mind whose question was lost asks again.
- A save from a newer version is refused; a broken one is refused without changing the world shown.

## Sound and music

Nothing is recorded: every sound is synthesised by the game the first time it is needed.

- **Effects** (Effects bus): fire, lightning, rain, meteors, the bomb, quakes and the terrain tools, blessings and miracles, sickness, curses, war drums, the fanfare of a new age, rockets, an achievement won. Powers and the great events of the chronicle play them.
- **Music** (Music bus): a slow generative piece; a drone holds the root while notes of a scale fall one by one. Its scale and pace follow the **mood of the world**: major in bright eras, minor in dark ones, whole tones in magical ones, slow and low under a nuclear winter.
- **Ambience** (Ambience bus): wind over the land and a far sea.
- The settings set the volume of each, and of everything.

## Achievements

23 achievements (`data/achievements.json`), won once and for good in any world: a city, five kingdoms, a thousand people, a hundred and a thousand years, the Iron, Industrial and Atomic Ages, the moon, an age beyond, the bomb, the long night, a warmer world, three wars at once, a legend slain, a plague, five heroes, a people that worships you and one that curses you, a wrathful spirit, five moods of the world, a thousand tiles reshaped, a hundred inventions. Each reads a fact of the world (the simulation's `Facts`); the game says when one is won, and the star in the top bar shows them all.

## Scenarios

**Scenarios** on the title screen (`data/scenarios.json`, and those of mods): The Twin Isles, Age of Steam (everyone in the Industrial Age), The Brink (two atomic powers at war), The Long Night (a dark era), Ice Age, Golden Age (every people, a bright era), The Quiet Earth (no disasters, plagues or spirits). A scenario gives the land, the peoples, the age they start in, the mood of the world, a war, and the laws.

## Everything that waited

- **Favourites**: the heart on the inspector's card follows a creature or a village; the heart in the top bar lists them (a click shows one) and the game tells when one dies or falls.
- The inspector's **family** (partner, parents, children), **story** (what the chronicle tells of them) and **mind** (what they do and need).
- **Hail** and **wind** (the wind blows for a year where the player points: fire runs with it, sparks fly its way), **forget a language**, the **storyteller** (a war, a hero, a plague, a legend wakes, a golden age, a rebellion, a discovery, the fall of the great).
- **Faith mode** (a law): every power costs faith, given each year by the peoples who worship (or fear, a little) the player, shown in the top bar.
- Settings: pause when a great event happens, screen shake on disasters, weather on screen (rain, snow, ash, motes of magic, by the mood of the world).
- The avatar is not in the game: the player stays a hand from the sky.

## Speed

Over long histories the spread of inventions grew costly (every village asked how useful every invention was, counting its people each time): it counts jobs once a year and remembers what it worked out, from 400 ms to 10 ms a year with 2,600 inventions. A world of 4 peoples at size 256 runs its simulation steps in 0.5 to 0.9 ms after 300 years.
