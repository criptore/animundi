# Villages: what WorldBox has, and what Animundi implements

**Status: implemented in 0.35** (`sim/Villages.cs`, `sim/Jobs.cs`, `data/buildings.json`, `art/buildings.py`), except what section 6 leaves for later. Differences from the list below: woodcutters are 1 when wood is plentiful (more than 30 + one per person), else 2 plus one per 10 people, so that great buildings get built; warriors are 15–35% of adults depending on the people's aggression.

The minimum is everything a WorldBox village does (from its wiki: Villages, City Building, Houses, Jobs, buildings pages). Animundi takes the mechanisms, never the art or names: all sprites are drawn by `art/buildings.py`, all names come from the peoples' generated languages.

## 1. Territory
| WorldBox | Animundi |
|---|---|
| A village owns zones of 8×8 tiles; it starts with 3×3 zones and its leader claims more over time | Same: zones of 8×8 tiles, 3×3 at founding, a new zone claimed next to the territory as the village grows |
| Borders shown on the map in the kingdom's colour | Borders drawn by the map shader in the village's colour (each people a hue, each village a shade) |
| Buildings only inside the territory | Same |

## 2. Buildings (data/buildings.json)
| WorldBox building | Effect | Animundi |
|---|---|---|
| Bonfire | First building, heart of the village, +3 homes, makes biome food | Same; people gather and talk around it |
| Houses, tiers 0–6 (tent → hut → stone → mansion), wood then stone, 3–6 people | Homes | Tiers 1–4 per people: hut (wood), house (wood), stone house (stone), big house (stone); upgraded in place |
| Town hall (tiers) | +homes, stores goods | Town hall, needs 15 people and stone; stores goods |
| Stockpile | Stores resources, units throw goods in from 7 tiles | Same (goods delivered from 7 tiles, not walked to the door) |
| Windmill + farms | Field tiles around the windmill, farmers sow and harvest wheat | Same: fields drawn on the map, wheat grows with the seasons |
| Well | +3 homes, restores energy | Same; people drink there too |
| Mine | Miners spend months inside, ores appear around | Miners work the mine for stone, common metal and gold (gold only in mountains and hills) |
| Docks + boats | Fishing boats, trade and transport | Dock on the shore; fishers bring fish (boats come with 0.4 trade) |
| Barracks + training dummies | Faster warrior hiring, training | Same: warriors train on dummies and grow stronger |
| Watch tower | Shoots arrows at enemies, at the border | Same: shoots at beasts and enemies in range |
| Temple, library, statue, market | Mostly decoration, homes, books | Built when the village is rich; homes; the library and temple matter later (religions, books in 0.6) |
| Roads | Built by road builders between buildings, +50% walking speed | Same: roads drawn on the map between buildings, faster walking |
| Ruins | What is left when a building is destroyed or the village abandoned | Same |

**Building plan** (WorldBox's rules): one plan per month; one building or upgrade at a time; a building needs its population, prerequisites, resources and a free spot. Houses and halls cluster near other buildings; mines, windmills and towers stand apart; towers stand at the border; docks on the shore.

## 3. Resources
| WorldBox | Animundi |
|---|---|
| Food items (berries, herbs, meat, wheat, bread, fish, biome food…) | Food (one stock, filled by gatherers, hunters, farmers, fishers, the bonfire) |
| Wood, stone, common metal, silver, gold, gems… | Wood, stone, metal, gold |
| Gold, loot, coins, taxes | Gold stock now; loot and taxes with kingdoms (0.4) |

## 4. Jobs (with WorldBox's limits)
| Job | Rule |
|---|---|
| Builder | Up to 3 while something is being built or upgraded |
| Woodcutter | 1 when wood > 15, else up to 3 |
| Gatherer | By food: 1 above 100, 4 above 60, 5 above 40, 7 above 20, else 10 |
| Hunter | 1 (more when food is short) |
| Farmer | While the village has fields |
| Miner | Up to 5 when there is a mine |
| Fisher | While the village has a dock |
| Blacksmith | 1 when the village has 15 people and metal: makes tools (faster work) and weapons (stronger warriors) |
| Fireman | When fire burns in the territory: puts it out |
| Road builder | 1 when roads are planned |
| Warrior | Up to 35% of adults once the village has 15 people; train at the barracks |

## 5. People in villages
- Everyone has a **home** (a house, or the bonfire when homeless); they rest at home.
- The village grows by births while it has free homes and food.
- **New villages**: a village with enough adults (and enough years or crowding) sends 6–12 settlers with their families to found a new village of the same people nearby, in a land it likes.
- Buildings burn (wooden ones), firemen put fires out; a village left empty turns to ruins.

## 6. Later, with kingdoms and AI (0.4–0.6)
Kingdoms and capitals, loyalty, taxes and tribute, trade and transport boats, diplomacy and war, rebellions, culture traits that change buildings (roads, towers, statues), religions in temples, books in libraries, the AI minds inventing new buildings.
