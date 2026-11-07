# Animundi — Roadmap to 1.0

Milestones from [GAME_DESIGN.md § 23](GAME_DESIGN.md#23-milestones), updated with what is done. Tick items as they land.

## 0.1 World
- [x] Seeded generation: continents, climate, rivers, 21 biomes
- [x] Five terrain levels (deep sea, shallow water, plain, hill, mountain), terraced 3D terrain
- [x] 3D pixel-art view, fixed camera, the reference sprites standing in the world
- [x] Asset sheets rendered with the game's look
- [x] Volcano as a real cone with a lava crater
- [x] Patterns on tile tops (grass, sand, snow, rock, lava)
- [x] Water with reflections
- [ ] Merge the design-doc and 0.1 pull requests

## 0.2 Wildlife
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
- [ ] Buildings generated from function × culture × age
- [ ] Roads, boats, trade
- [ ] Kingdoms: borders, capitals, rulers, dynasties, generated banners
- [ ] Diplomacy (peace, alliance, rivalry) and war (armies, sieges, conquest)
- [ ] Rebellions, civil wars, secessions

## 0.5 Culture
- [ ] Generated cultures: values, laws, rituals, taboos, architecture style
- [ ] Religions: gods and myths drawn from real world events
- [ ] The player recognised as a god: worshipped, feared or hated
- [ ] Chronicle: world history written as it happens (wars, heroes, disasters, named ages)

## 0.6 Monsters and nature
- [ ] Generated monsters, growing lairs, named legendary creatures
- [ ] Nature spirits (forests, volcanoes, seas) with moods
- [ ] Disasters: earthquakes, eruptions, floods, tornadoes, droughts, wildfires
- [ ] Generated diseases and plagues

## 0.7 Inventions and ages
- [ ] The invention language: effects, costs, conditions, validated by the engine
- [ ] Procedural inventions that spread or are forgotten
- [ ] Stone to Medieval ages, magic

## 0.75 Industry and beyond
- [ ] Renaissance → Space: steam, trains, planes, nuclear, rockets
- [ ] Pollution, climate change, nuclear war
- [ ] Endless generated ages after the Future
- [ ] Sprites and buildings that change with the age

## 0.8 God powers and interface
- [ ] Every power: terrain, spawning, weather, disasters, miracles, curses, destruction, faith mode, avatar, gestures, world laws, storyteller
- [ ] Inspector cards: unit, city, kingdom, species, spirit
- [ ] Map layers (kingdoms, cultures, religions…) and statistics
- [ ] Save, load, share a seed

## 0.9 Local AI
- [ ] Small local model (Ollama or llama.cpp) wired into Godot
- [ ] Peoples invent their culture and the code of their inventions
- [ ] Monsters evolve abilities; nature spirits react
- [ ] Procedural fallback when no model is available

## 1.0 Polish
- [ ] Balancing and performance (5,000+ units at 60 fps)
- [ ] Sound and music
- [ ] Achievements, scenarios, mod support
- [ ] A playable build to distribute
