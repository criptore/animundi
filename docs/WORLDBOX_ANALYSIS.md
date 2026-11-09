# How WorldBox is built, and what Animundi takes from it

WorldBox runs huge worlds with thousands of units smoothly on phones. This note collects how it does it, to guide Animundi's rendering and simulation. Points are marked **confirmed** (seen in the code of open-source WorldBox mods, which call the game's own classes), **observed** (visible in the game) or **inferred**.

## Engine

- **Unity, 2D, C#** (confirmed: mods compile against the game's `Assembly-CSharp.dll`).
- Mostly one developer (Maxim Karpenko), with artists brought in for buildings, units and icons.

## Architecture (confirmed by mods)

| Piece | Role |
|---|---|
| `MapBox` | The single world object: the tile grid (`tiles_map`, `tiles_list`) and every manager (`units`, `kingdoms`, `cities`…) |
| `WorldTile` | One grid cell, with a ground type (`TileType`) and a cover type (`TopTileType`: grass, forest, corruption…), two separate layers |
| `ActorManager`, `KingdomManager`, `CityManager`… | One manager per kind of entity, all derived from `CoreSystemManager` (storage: a hash set). `SimSystemManager` for things simulated every tick (units), `MetaSystemManager` for abstract entities (kingdoms, cities, cultures, clans) |
| `BatchActors`, `JobManager`, `JobSlots` | Units are updated **in batches**, not one by one every frame |
| `ZoneCalculator` | The map is cut into **zones** for spatial queries (who is near whom, city territory) instead of scanning the whole map |
| `AssetManager` + `ActorAsset`, `BuildingAsset`, `GodPower`, `WorldBehaviourAsset`… | **Everything is data**: content is described by assets in libraries; adding a creature is adding an asset, not code |
| `WorldBehaviourAsset` | World processes (grass growth, fire, corruption) run on timers, a slice of the map at a time |
| `SpriteTextureLoader` | Every image is loaded by path from folders and cached |

## Rendering (observed and inferred)

- **The map is one image where one tile is one pixel**, scaled up on screen. Changing terrain changes a few pixels of that image. The whole map costs **one draw**, whatever its size.
- **Units are tiny sprites** (a few pixels), seen from the side, with 2-3 walking frames, a small drawn shadow, and sorted by height on screen.
- **Zoom-dependent detail**: zoomed out, units become coloured dots or are not drawn; zoomed in, details appear. Thousands of detailed sprites are never drawn at once.
- Buildings are small sprites on tiles; effects (fire, explosions, rain) are pixel sprites and particles.
- **No dynamic lighting or real-time shadows**; shadows are drawn into the sprites.

## Look

- **Flat top-down view**, no 3D relief: height (mountains, hills) is told by **tile colour** only.
- **Flat colours per ground type**, slight per-tile variation, hard staircase edges.
- Pixel art **at the scale of the tile**: reads like a map from far away.
- **Tiny, expressive units**: simple silhouettes, kingdom colours, very short animations.

## What Animundi takes

1. **Rendering**: a 2D map drawn as one texture (one pixel per tile, scaled up, light pattern when zoomed in); sprites drawn in batches (MultiMesh2D: thousands per draw call), reduced to coloured dots when zoomed out; no real-time lighting.
2. **Simulation**: a world object with one manager per kind of entity, zones for spatial queries, batched updates at different rates, world processes on timers over slices of the map. The simulation core in **C#**.
3. **Data-driven content**: every species, building, item and power is a data record. This is also what lets the AI create new content: it writes records, the engine runs them.

What Animundi does **not** copy: its content. WorldBox's species, buildings and items are hand-made. Animundi's are generated, and evolve through local AI minds: that is the game's edge (see GAME_DESIGN.md § 1).

## Sources

- [WorldBoxOpenMods/ModLoader](https://github.com/WorldBoxOpenMods/ModLoader), [ModernMod](https://github.com/WorldBoxOpenMods/ModernMod), [PowerBox](https://github.com/WorldBoxOpenMods/PowerBox) (MIT)
- [fullya99/worldbox-mcp](https://github.com/fullya99/worldbox-mcp) (reflection notes on `MapBox`, managers, `CoreSystemManager`)
- [inmny/Cultivation-Way-Core](https://github.com/inmny/Cultivation-Way-Core) (sprite animation, assets)
- [DipCrai WorldBoxModLoader wiki](https://github.com/DipCrai/WorldBoxModLoader/wiki/Creating-your-first-mod)
- [Forum Tom's Hardware: Unity 2D, zoom detail](https://forum.tomshw.it/threads/worldbox.840809/)
- [WorldBox changelog](https://superworldbox.com/changelog), [WorldBox on Wikipedia](https://en.wikipedia.org/wiki/WorldBox)
