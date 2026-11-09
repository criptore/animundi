# Animundi — Roadmap to 1.0

Milestones from [GAME_DESIGN.md § 23](GAME_DESIGN.md#23-milestones). Tick items as they land.

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
- [ ] Sprites drawn in batches (MultiMesh2D), sorted by screen height, drawn shadows
- [ ] Zoom-dependent detail: dots when zoomed out, full sprites when zoomed in
- [ ] Animated water and wind sway, cheaply
- [ ] C# simulation core: world object, one manager per kind of entity, zones for spatial queries, batched ticks at different rates, world processes on timers over map slices
- [ ] Data-driven assets: species, plants, buildings, items, powers as data records
- [ ] Performance check: 5,000+ moving units at 60 fps on a mid-range PC

## 0.2 Life
- [ ] Living flora: forests grow, spread, burn and regrow
- [ ] Animals that move, with needs (hunger, thirst, rest, reproduction)
- [ ] Food chains: herbivores and predators, populations that rise and crash
- [ ] Seasonal migrations, extinctions
- [ ] Simple sprite animations (2-frame walk, attack)

## 0.3 Peoples
- [ ] The 12 races placed in their preferred biomes at world start
- [ ] Per-world race variation (colours, stats, temperament)
- [ ] Language generator for names (people, cities, rivers, gods)
- [ ] Individuals: age, traits, skills, family, life cycle
- [ ] Jobs: gatherer, farmer, woodcutter, miner, builder, hunter…
- [ ] First villages, with utility AI for inhabitants (no language model)

## 0.4 Civilisation
- [ ] Settlements grow: camp → village → town → city
- [ ] Buildings generated from function × culture × age, with generated sprites
- [ ] Roads, boats, trade
- [ ] Kingdoms: borders, capitals, rulers, dynasties, generated banners
- [ ] Diplomacy (peace, alliance, rivalry) and war (armies, sieges, conquest)
- [ ] Rebellions, civil wars, secessions

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

## 0.9 God powers and interface
- [ ] Every power: terrain, spawning, weather, disasters, miracles, curses, destruction, faith mode, avatar, gestures, world laws, storyteller
- [ ] Inspector cards: unit, city, kingdom, species, spirit, invention (with its script and lineage)
- [ ] Map layers (kingdoms, cultures, religions…) and statistics
- [ ] Save, load, share a seed

## 1.0 Polish
- [ ] Balancing and performance
- [ ] Sound and music
- [ ] Achievements, scenarios, mod support
- [ ] A playable build to distribute
