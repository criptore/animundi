# Map generation

How Animundi builds a world, the other approaches looked at, and why it uses the one it does.

## What a good map needs

- **Continents shaped like real ones**: long, irregular, with bays, peninsulas, island chains, and no round blobs or straight coasts along the map edge.
- **Mountains in chains**, not scattered bumps. On Earth they follow the borders of tectonic plates (Andes, Himalayas, Alps).
- **Biomes in large, natural regions** that follow climate: wet coasts, dry interiors and rain shadows, a desert belt, cold poles. No speckle of tiny patches.
- **Nothing magical at random.** Mushroom land, cursed land, volcanoes and lava are put on the map by the player with the god tools.
- **Fast**: a 512 × 512 world in a few seconds, in GDScript for now.

## Approaches looked at

| Approach | How it works | Good | Bad |
|---|---|---|---|
| **Noise + falloff** (Red Blob Games, "Making maps with noise") | Fractal noise, pushed down towards the edges or around continent centres | Simple and fast | Blobby continents, mountains anywhere. This was 0.1's generator |
| **Heightmap templates** (Azgaar's Fantasy Map Generator) | Scripted steps: add hills, ranges, troughs, pits, straits, then mask | Lots of control, many map styles | Hand-written templates, the maps feel designed |
| **Polygon maps** (Red Blob Games "Polygonal map generation", mapgen4) | Voronoi cells, elevation from distance to the coast, rivers down the slope, moisture from rivers and wind | Very readable maps, good rivers | Built on a polygon mesh, not on a tile grid |
| **Tectonic plates** (PlaTec by Lauri Viitanen; "Undiscovered Worlds") | Plates drift, collide and pull apart; mountains rise at collisions | Natural continents and mountain chains | A full simulation is slow |
| **Erosion** (hydraulic droplets by Hans Theobald Beyer and Sebastian Lague; stream power by Braun & Willett, Cordonnier et al. 2016) | Water carves valleys and lays sediment | Very realistic valleys and ridges | Thousands of iterations, too slow in GDScript for now |
| **Whittaker biomes** | Biome from temperature and rainfall | Natural biome placement | Needs believable climate fields to work on |

## What Animundi does (0.15)

A light version of the plate approach, without a time simulation, plus the climate model from 0.1:

1. **Plates** (`world_generator.gd::_plates`, on a coarse grid of about 128 cells across):
   - About 10 to 26 plate centres, spread out, with borders made irregular by domain warping.
   - A few clusters of plates become continents (as many as the *Continents* setting), started far apart, grown towards the middle of the map and kept away from its edges.
   - Every plate drifts in a random direction. Along each border, the relative speed tells whether the plates collide or pull apart.
2. **Uplift** from the border type:

   | Border | Result |
   |---|---|
   | Continent meets continent | The highest, widest ranges |
   | Ocean plate dives under a continent | A coastal range a little inland, with a trench offshore |
   | Two ocean plates meet | An arc of islands |
   | Plates pull apart | A rift valley on land, a ridge under the sea |

3. **Shape**:
   - The continent mask is blurred, then roughened with warped fractal noise, so coasts don't follow the plate borders.
   - Ridged noise carves crests and valleys into the uplift.
   - The ocean edge band is warped too, so no coast runs straight along the map edge.
   - The sea level is set so that the *Water %* setting is met exactly.
4. **Climate**:
   - Temperature comes from latitude, falling slowly at first so only the poles are frozen, and from altitude.
   - Humidity comes from the global rain belts, winds carrying moisture from the sea, and rain shadows behind mountains.
5. **Rivers and lakes**: water is flooded down from every tile to the sea (priority flood), and flow accumulates into rivers.
6. **Levels**:
   - Heights are cut into the five terrain levels and smoothed with a majority filter.
   - The rule that neighbouring tiles differ by at most one level is applied as a distance transform: two sweeps instead of repeated passes.
7. **Biomes**:
   - Each tile gets a Whittaker-style biome from its climate and height.
   - Three passes of a majority filter, then patches smaller than about 1/4000 of the map merge into what surrounds them.
   - No special biomes are placed: they come from the god tools.

## Later

- Erosion (stream power, a few iterations), once the simulation core is in C#: it gives dendritic valleys and sharper ranges.
- Volcano hotspots and volcanic islands proposed by the generator, but only as suggestions that the player can accept.
- Map styles as settings: archipelago, pangaea, inland sea.
