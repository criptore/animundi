# Animundi — Roadmap to 1.0

**Order of work: the simulation first, the player's powers last.** Before any god power, the world must live on its own: start a world with at least two peoples, speed up time, and watch them live their lives among animals, plants, seasons and disasters. Then the AI minds make every game different: peoples that build ever more advanced cities, invent new things, take different directions, think differently and use different powers. Only once all that works well do the player's powers come (0.9), to influence the world at will.

Milestones from [GAME_DESIGN.md § 23](GAME_DESIGN.md#23-milestones). Tick items as they land. Design lessons from WorldBox's wiki that shaped several items: [WORLDBOX_WIKI_LESSONS.md](WORLDBOX_WIKI_LESSONS.md).

Direction: **built like WorldBox** (flat 2D map, batched sprites, data-driven content, batched simulation in C#; see [WORLDBOX_ANALYSIS.md](WORLDBOX_ANALYSIS.md)), **different where it matters**: local AI minds that invent objects, buildings and ways of life, and make them evolve. The AI arrives at 0.5, as soon as there are settlements to invent for.

## 0.1 World ✅
- [x] Seeded generation: continents, climate, rivers, 21 biomes
- [x] Five terrain levels (deep sea, shallow water, plain, hill, mountain)
- [x] Sprites cut from the reference sheets (104 sprites, Ratfolk removed: 12 races)
- [x] Asset sheets rendered with the game's look
- [x] 3D pixel-art prototype (terraces, volcano cones, reflections, outline and cel shaders); retired for performance, kept in history
- [x] Merge the design-doc and 0.1 pull requests

## 0.15 2D core
- [x] Map drawn as one texture (one pixel per tile, scaled up), biome and level colours, step edges, zoom-in patterns; 2D map camera (zoom toward the mouse, pan, stays on the map)
- [x] Sprites drawn in batches (MultiMesh2D, one atlas, strips of 16 rows), sorted by screen height, drawn shadows; plants placed by biome
- [x] Zoom-dependent detail: sprites become dots of their average colour when zoomed out (no shadows), full sprites when zoomed in; flowers hidden from far
- [x] Animated water (slow swell, twinkling glints, shore foam) and wind sway of tall sprites, all in shaders
- [x] Natural map generator: tectonic plates, mountain chains on colliding borders, warped coasts, large biome regions; no special biomes at random (see [MAP_GENERATION.md](MAP_GENERATION.md))
- [x] Plants never overhang water; mushrooms smaller than the peoples
- [x] C# simulation core (`sim/`): world object, one manager per kind of entity (units so far), zones of 8×8 tiles for spatial queries, batched ticks at different rates, world processes on timers over map slices; units drawn from one MultiMesh buffer, sorted by height
- [x] Data-driven assets: species and plants as data records (`data/`); buildings, items and powers join as they are made
- [x] Performance check (`tools/perf_check.gd`): 5,000 wandering animals cost ~0.25 ms per step and ~2 ms per frame of drawing on the CPU (20,000: ~0.8 ms and ~5 ms); GPU frame rate still to confirm on a real mid-range PC

## 0.2 Life
- [x] Living flora (C#): saplings grow, adult plants seed their neighbourhood up to their biome's density, bare ground is recolonised
- [x] Fire on tiles, as in WorldBox: each biome has a burn chance and burn time (`data/biomes.json`), a burning tile lights its neighbours while they have fuel (grass or plants), sets its plants alight and kills what stands in it, then turns to ash that fades over most of a year; forests burn through, grassland in patches, swamps never; rocks don't burn
- [x] Natural spawning as data: each species lists the biomes it is born in, with weights; monsters only in special biomes; a fresh world has animals, never monsters
- [x] Animals born over time by biome (world law "animal spawn"), only while their species is scarce; creatures with no natural biome only come from the player (events and deaths that bring zombies, skeletons… come with 0.7)
- [x] Animals with needs: hunger (grazing a grass layer that regrows), thirst (walking to the nearest water), rest, breeding with a mate nearby; death by old age, hunger, thirst, predators or fire
- [x] Food chains: herbivores graze, carnivores and omnivores hunt prey of their size or smaller; each species' habitat feeds a limited number (births slow down as it fills); fires and winters thin populations
- [x] Seasons (a year is 60 s): growth fast in spring and stopped in midwinter, frost spreading from the poles on the map; migrating species head for the equator in winter; extinctions logged in the events panel
- [x] World laws as switches in the simulation (animal spawn, hunger, old age, natural disasters, tree growth); a menu for them comes with 0.9
- [x] Events panel (extinctions, lightning fires), time of year and population per species in the HUD; F sets fire under the mouse (test tool, not a power)
- [x] Time controls: pause, ×1, ×2, ×5, ×10 (buttons, Space, comma and period)
- [x] Sprite animations: two walking steps, a strike when a hunter reaches its prey, remains lying where a creature died (5 s); young creatures drawn smaller
- [ ] Colour masks for kingdom colours and biome skins (WorldBox-style phenotypes); dedicated child sprites; swimming once creatures can swim
- [x] **Redrawn sprites of every living being** (`art/creatures.py`, sheet in [images/creatures.png](images/creatures.png)): 12 animals, 9 monsters and the 12 peoples in their 4 roles, original pixel art in the spirit of WorldBox (see [WORLDBOX_WIKI_LESSONS.md](WORLDBOX_WIKI_LESSONS.md) § 3):
  - drawn at display size, one sprite pixel per world pixel: about a tile tall (animals 6–13 px wide, people 7×9), a dragon three tiles long
  - a text template and palette per creature, automatic shading (lit top edge, soft darker outline)
  - six poses each, made from the template: idle, two walking steps (the legs swing), attack (lunge), swim, death (lying down)
  - peoples assembled from parts: a body per race (ears, horns, beard, tusks, crest, tail, fins, foliage, wings, sockets) and an outfit per role (villager's sack, warrior's helmet and sword, chief's crown and cape, shaman's hood and staff)

## 0.3 Peoples
- [x] World setup before starting: the world waits while the player picks the peoples (at least two) and how many found each village, then starts it and watches at any speed
- [x] Peoples as data (`data/races.json`): liked biomes, size, speed, lifespan, temperament, stats, language sounds; each founds its first village in a biome it likes, near fresh water, far from the others
- [x] Per-world race variation: stats, temperament, speed and lifespan shifted by the seed (colour variation comes with the colour masks)
- [x] Language generator (`sim/Language.cs`): each people's sounds narrowed by the seed into a dialect, syllable patterns, endings and a small lexicon; names for people and villages (rivers, gods and kingdoms later)
- [x] Individuals: name, sex, age, two traits (brave, lazy, kind, greedy, wise, strong), partner, mother and father; children grow up (adults at 16 at most, so elves and dwarves grow up in time), work, pair, have children, grow old and die; hovering a creature tells who it is
- [x] Jobs handed out by the village by what it lacks: gatherers (wild food from the grass), woodcutters (trees are felled), hunters (animals of their size or a little bigger), builders (houses from wood); warriors prefer the hunt and defend; chiefs and shamans lead (a new chief when the old one dies)
- [ ] More jobs: farmer, herder, miner, fisher (0.4, with fields and mines)
- [x] First villages: a bonfire, then houses in each people's style built when room runs out (`art/buildings.py`), food and wood stores; villages are abandoned when everyone is gone
- [x] Utility AI for people, as WorldBox's neurons: each action (drink, eat, rest, pair, breed, work, play, wander) has a weight, a cooldown, a priority and a switch; urgent thirst and hunger interrupt any task (the unit inspector that shows and switches them comes with 0.9)
- [ ] Home biome gives species and peoples their starting traits

## 0.4 Civilisation
- [ ] Settlements grow: camp → village → town → city
- [ ] Buildings generated from function × culture × age, with generated sprites
- [ ] Roads, boats, trade
- [ ] Kingdoms: borders, capitals, rulers, dynasties, generated banners
- [ ] Diplomacy (peace, alliance, rivalry) and war (armies, sieges, conquest)
- [ ] Rebellions, civil wars, secessions
- [ ] Plans shown before they happen: leaders plot wars, alliances and rebellions, with a progress icon the player can watch, cancel or force
- [ ] Event log with filters (kings, wars, cities, disasters, favourites)

## 0.5 AI minds (the edge)
- [ ] Small local model (llama.cpp through a GDExtension) with grammar-forced JSON output
- [ ] The invention language: objects, tools, buildings, abilities as validated data records
- [ ] Cultures invent **objects and buildings**; their sprites are assembled from parts and the culture's palette
- [ ] Inventions spread, get copied by neighbours, are forgotten when useless: evolution by descent, traced in the chronicle
- [ ] Procedural fallback when no model is available

## 0.6 Culture
- [ ] AI-shaped cultures: values, laws, rituals, taboos, architecture style
- [ ] Religions: gods and myths drawn from real world events
- [ ] The player recognised as a god: worshipped, feared or hated
- [ ] Chronicle written by the AI (wars, heroes, disasters, named ages)

## 0.7 Monsters and nature
- [ ] Monster species with AI minds: mutations, new abilities, lairs
- [ ] Nature spirits (forests, volcanoes, seas) with moods
- [ ] Disasters: earthquakes, eruptions, floods, tornadoes, droughts, wildfires
- [ ] Generated diseases and plagues

## 0.8 Ages
- [ ] Stone to Space and beyond, with no final age
- [ ] AI-driven evolution of objects, buildings and vehicles through the ages
- [ ] Consequences: pollution, climate change, nuclear war
- [ ] Moods of the world: eras of a few decades (bright, dark, rainy, cold, magical…) that change weather, growth and monsters, steerable by the player

## 0.9 God powers and interface
Nothing here before the world lives on its own (see the order of work above). Special biomes and volcanoes are never generated at random: the player places them with these tools.
- [ ] Biome brush: paint mushroom land, cursed land, volcanic rock, lava (and the natural biomes), with a brush size
- [ ] Stamps: ready-made presets (volcanoes of several sizes, later islands, craters, oases) pasted on the map where the player clicks; levels around them are fixed so the terrain stays valid
- [ ] The player's own presets: select an area of the map and save it as a stamp, reuse it in any world
- [ ] Plants and the map texture update only where the terrain changed
- [ ] Fire power drops sparks (particles) that set alight the tiles they land on, as in WorldBox; the F key is only a test tool until then
- [ ] Every power: terrain, spawning, weather, disasters, miracles, curses, destruction, faith mode, avatar, gestures, world laws, storyteller
- [ ] Inspector cards: unit, city, kingdom, species, spirit, invention (with its script and lineage)
- [ ] Map layers (kingdoms, cultures, languages, religions, clans, families, species, alliances, armies), war lines, plot and task icons, unit arrows, and statistics
- [ ] World laws: one switch per simulation rule, grouped (diplomacy, civilisations, units, nature, biomes, weather, disasters), each with a one-line description
- [ ] Powers that act on minds: rain traits, make people forget their language, culture, faith or kingdom, whisper war or friendship
- [ ] Save, load, share a seed

## 1.0 Polish
- [ ] Balancing and performance
- [ ] Sound and music
- [ ] Achievements, scenarios, mod support
- [ ] A playable build to distribute
