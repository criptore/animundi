# Animundi — Game Design Document

Status: draft v0.1. This document lists everything the game must contain. Decisions still open are collected in [§ 24 Open questions](#24-open-questions).

---

## 1. Vision

Animundi is a top-down, pixel-art god sandbox. The player shapes a world and watches peoples, beasts and forces of nature live, build, fight, believe and die on their own.

**Everything is procedural.** A world is born from a single seed: its land, its climate, its species, its peoples, their languages, gods, buildings, banners and history. Two seeds never give the same world. Nothing in the content is hand-authored except the *rules* and the *building blocks* the generators combine.

**Progress never stops.** Peoples go from stone tools to bronze, iron, gunpowder, steam, planes, rockets and space travel, and keep going: there is no final age.

**The twist:** on top of the procedural generators, small local AI models give each people, monster species and nature force a mind of its own. They invent culture and write the code of their own inventions in a small in-game language. The game must stay fully playable **without** AI: generators produce everything by default, and the AI only replaces some of their choices.

### Design pillars

1. **One seed, one world.** Same seed + same player actions = same world (deterministic simulation).
2. **Generators, not content.** Every kind of thing (species, people, building, item, god, word) has a generator with parameters, never a fixed list.
3. **Readable at 8×8.** Every entity fits in one 8×8 tile (large creatures up to 16×16), from one shared palette.
4. **Emergent stories.** History is not scripted; the chronicle only records what the simulation did.
5. **The AI adds, never blocks.** If the model is slow, missing or wrong, the world keeps living.

---

## 2. Generation pipeline

Generation runs in a fixed order. Each stage only reads the output of earlier stages and its own seeded RNG stream, so any stage can be re-rolled alone.

```
seed
 └─ 1. World shape      heightmap, continents, oceans
     └─ 2. Climate      temperature, humidity, winds, seasons
         └─ 3. Hydrology   rivers, lakes, coasts
             └─ 4. Biomes     from height × temperature × humidity
                 └─ 5. Resources & sites   ores, crystals, ruins, lairs
                     └─ 6. Life      flora, then fauna species
                         └─ 7. Monsters    species, lairs, legendary beasts
                             └─ 8. Peoples     races, languages, cultures, gods
                                 └─ 9. Settlements   first villages and territories
                                     └─ 10. Prehistory   simulate N years quickly, write the first chronicle
```

- **RNG:** one seeded PRNG (e.g. xoshiro128) with a named sub-stream per generator (`rng("biomes")`, `rng("people:3")`), so adding a generator never changes the others.
- **Noise:** simplex / value noise with octaves for every continuous field.
- **World settings** (chosen before generation): size, sea level, number of continents, climate (ice age ↔ hot), magic level, monster density, number of starting peoples, length of prehistory.

---

## 3. World

### 3.1 Map

- Tile grid, 8×8 px per tile. Sizes: Tiny 128², Small 256², Medium 384², Large 512².
- Each tile stores: height, temperature, humidity, biome, fertility, corruption, owner (kingdom), resource, building, fire/flood state.

### 3.2 Terrain shape

- Heightmap = continent mask (number of continents, falloff to the edges) + multi-octave noise + ridge noise for mountain chains.
- Sea level cuts the heightmap into **deep water / shallow water / land**.
- **Five terrain levels**: deep sea, shallow water (coasts, rivers, lakes), plain (and beach), hill, mountain. The heightmap is quantised into these levels, smoothed with a cellular automaton (each land tile takes the majority level of its 3×3 neighbourhood) and constrained so that two neighbouring tiles never differ by more than one level: mountains are ringed by hills, coasts and river banks are plains, deep sea is ringed by shallow water. In 3D every tile is a flat terrace with small cliffs, about one tile high per level, so the relief stays at the scale of the people on it.
- Volcanoes: placed on high ridges or hotspots; they create volcanic rock and lava around them.

### 3.3 Climate

- **Temperature** = latitude gradient + altitude cooling + noise.
- **Humidity** = distance to water, carried by prevailing winds, blocked by mountains (rain shadow).
- **Seasons:** temperature and rain oscillate during the year; snow and ice spread in winter, rivers can dry in summer.
- **Weather:** rain, storm, snow, blizzard, heat wave, drought, fog. Generated as moving cells over the map.

### 3.4 Hydrology

- Rivers start on high, wet tiles and flow downhill to the sea or a lake (flow accumulation).
- Lakes fill local basins. Swamps form on flat, wet lowlands.
- Water tiles matter for: thirst, farming, fishing, boats, trade routes, borders.

### 3.5 Biomes

Biome = f(height, temperature, humidity), from a lookup table (Whittaker-style), plus special overrides.

| Biome | Conditions | Typical life |
|---|---|---|
| Deep water / Water | below sea level | fish, crabs, kraken |
| Beach / Sand | coast | crabs, palms |
| Grassland, Flower meadow | temperate, medium humidity | sheep, horses, rabbits |
| Forest | temperate, wet | deer, wolves, bears, oaks, birches |
| Jungle | hot, very wet | big cats, snakes, giant plants |
| Savanna | hot, dry-ish | herds, big predators |
| Desert | hot, dry | cacti, sandworms, scorpions |
| Swamp | flat, wet | reeds, lizards, slimes |
| Tundra | cold, dry | yetis, foxes |
| Snow / Ice | very cold | snowy pines, ice creatures |
| Mountain / Peak | high | golems, dwarves' favourite |
| Volcanic / Lava | near volcanoes | fire slimes, demons |
| Special: Cursed land, Mushroom land, Crystal fields, Enchanted forest | magic sources, events, player | corrupted or magical life |

Biomes are **not fixed**: they change with climate, fire, flooding, farming, deforestation, corruption and god powers.

### 3.6 Resources and sites

- **Resources:** wood, stone, clay, iron, copper, gold, gems, crystals, salt, fertile soil, fish, game, herbs, mana springs.
- **Sites:** ancient ruins, monster lairs, sacred groves, caves, meteor craters, mana wells, burial grounds.
- Placement follows rules (iron in hills, gold in mountains, herbs in forests…) with noise-driven clustering.

---

## 4. Time and simulation

- Engine: **Godot 4** (GDScript for gameplay; C# or a GDExtension in C++ for the hot loops if needed).
- Fixed-step simulation (`_physics_process` or a custom fixed tick), independent from rendering. Speeds: pause, ×1, ×2, ×5, ×20, and "skip years".
- Time units: tick → day → season → year → age. Default: 1 year ≈ 1 minute at ×1.
- Scheduling: things update at different rates (movement every tick, needs every few ticks, settlements daily, kingdoms seasonally, AI minds yearly).
- **Determinism:** seed + recorded player actions replay the exact same world.
- Performance target: 5,000+ living units on a Medium map at 60 fps on a mid-range PC.

---

## 5. Life: flora

- Plants are tile features: grass, flowers, bushes, trees (by biome), crops, giant mushrooms, cursed trees.
- Plants **spread** to neighbouring suitable tiles, burn, get eaten, are cut for wood, and regrow.
- Forests advance and retreat with climate and civilisation.

---

## 6. Life: fauna (procedural species)

Animal species are **generated per world**, not fixed. Each world has its own sheep-like grazers, wolf-like hunters, etc.

### 6.1 Species generator

| Parameter | Values |
|---|---|
| Body plan | quadruped, biped, bird, fish, insect, serpent, blob |
| Size | tiny (rabbit) → huge (16×16, mammoth) |
| Diet | herbivore, carnivore, omnivore, scavenger, filter, magical |
| Habitat | one or more biomes, land / water / air |
| Social | solitary, pair, herd, pack, swarm |
| Temperament | timid, neutral, territorial, aggressive |
| Traits | horns, tusks, shell, fur, scales, venom, wings, glow, camouflage… |
| Domesticable | yes / no (can become livestock or mounts) |
| Colours | 2–3 palette colours picked to match the biome |
| Name | generated by each people's language |

### 6.2 Ecology

- Needs: hunger, thirst, rest, reproduction.
- Food chain: plants → herbivores → carnivores; populations rise and crash (predator–prey balance).
- Migration with seasons; extinction is possible and recorded in the chronicle.
- Peoples can hunt, herd, domesticate and ride species.

### 6.3 Sprites

Sprites are assembled from body-plan templates + trait overlays + palette, like the peoples' generator in `assets/sprites.py`.

---

## 7. Monsters

Monsters are species with a **threat** role. They are generated the same way as fauna, with extra components.

- **Origins:** natural (giant spiders, sandworms, krakens), magical (slimes, golems, elementals), corrupted (zombies, cursed beasts, demons), undead (from graveyards, necromancy, plagues).
- **Components:** body plan, element (fire, ice, poison, shadow, stone, lightning), size class, special abilities (built from the invention language, see § 13), weaknesses, loot.
- **Lairs:** caves, ruins, nests, portals. Lairs grow and spawn new monsters when left alone.
- **Legendary creatures:** a few unique named monsters per world (a dragon, a world serpent, a lich…) with their own history, goals and chronicle entries.
- **Monster minds (AI):** a monster species can evolve strategies, new attacks and mutations over generations.

---

## 8. Peoples (procedural races)

**Decision: a fixed pool of 12 races**, the ones in `assets/`: Humans, Elves, Dwarves, Orcs, Goblins, Lizardfolk, Felines, Merfolk, Treefolk, Fairies, Bullfolk, Undead. Each world picks some of them and **varies** them (palette shifts, stat spread, traits, temperament), so the Elves of one world are not the Elves of the next. Everything built on top of a race (language, culture, religion, buildings, history) stays fully generated.

### 8.1 Race definition and per-world variation

Each race is a data record with the parameters below. The base values are fixed per race; world generation applies a seeded variation on top.

| Parameter | Examples |
|---|---|
| Body | size (short / normal / tall), skin palette, hair/headwear palette |
| Visual traits | pointed ears, big ears, cat ears, tusks, beard, horns, crest, tail, fins, wings, foliage, eye sockets |
| Lifespan | 30 → 1,000 years |
| Fertility | births per year, maturity age |
| Preferred biomes | 1–3, with comfort and tolerance ranges (temperature, water) |
| Diet | plants, meat, fish, minerals, mana, blood… |
| Base stats | strength, agility, intelligence, endurance, magic affinity |
| Temperament | peaceful ↔ warlike, curious ↔ traditional, nomadic ↔ settled |
| Special abilities | swim, fly, night vision, regrow, photosynthesis, undeath |
| Language | generated phonology (§ 9) |

A race is a small data record; the sprite, stats and behaviour all derive from it. The AI can tune a race's variation (within limits) but does not create new races.

### 8.2 Origins of peoples

- Spawned at world creation (number set in world settings), placed in their preferred biomes.
- Spawned by the player.
- **Transformations inside the pool:** a curse or a plague can turn a people Undead, an enchanted forest can give birth to Treefolk. Animals are never awakened into peoples. A group isolated for a long time drifts into a distinct **culture** (and slight visual variation), not a new race.

---

## 9. Languages and names

Every people has a generated language used for all names in the world.

- **Phonology:** consonant and vowel inventories, syllable patterns (CV, CVC, CCV…), forbidden clusters, typical endings. Harsh for Orcs, flowing for Elves… as generator tendencies, not fixed lists.
- **Lexicon:** a small generated dictionary of roots (water, fire, mountain, king, god, war, home…) combined into names.
- Names generated for: people, families/dynasties, settlements, kingdoms, gods, rivers, mountains, species, items, wars, ages.
- Names change over time (sound drift) and borrow from neighbours through contact.

---

## 10. Individuals

### 10.1 Data

- Identity: name, race, sex (if the race has one), age, family, home settlement, kingdom.
- Stats from race ± personal variation.
- **Personal traits** (2–4): brave, coward, greedy, wise, cruel, kind, ambitious, pious, lazy, genius, mad…
- **Skills:** farming, building, mining, crafting, fighting, hunting, fishing, trading, magic, leading, preaching.
- Needs: food, water, rest, safety, social, faith.
- Inventory: tools, weapon, armour, items, gold.
- Relations: family, friends, rivals, lovers, enemies.
- Memory (light): important events lived (battle, disaster, miracle), used by the chronicle.

### 10.2 Life cycle

Birth → childhood → adulthood (job) → old age → death (age, hunger, disease, war, monster, disaster). Some become **heroes**, **kings**, **prophets**, **traitors**, **legends**.

### 10.3 Behaviour

Utility AI and behaviour trees (no language model at this level): each unit picks the most useful action from its needs, job, orders from its settlement and its personality. Cheap enough for thousands of units.

### 10.4 Jobs

Gatherer, farmer, herder, woodcutter, miner, builder, smith, crafter, fisher, hunter, trader, warrior, guard, priest/shaman, mage, scholar, leader. Unlocked by culture and technology.

---

## 11. Cultures

A culture belongs to a people (one people can split into several cultures). It is the main thing the AI shapes later; by default it comes from generators.

| Aspect | Generated content |
|---|---|
| Values | weights for war, honour, nature, wealth, knowledge, faith, freedom, tradition |
| Aesthetics | 3–4 palette colours, banner (shape, pattern, symbol), favourite materials |
| Architecture | building style rules: roof shape, wall material, colours, decorations → feeds the building sprite generator |
| Clothing | palette and items per role (villager, warrior, chief, shaman) |
| Social structure | tribe, chiefdom, monarchy, theocracy, council, hive, anarchy |
| Laws | generated rules: inheritance, crime and punishment, slavery yes/no, who can fight, who can rule… |
| Customs & rituals | birth, coming-of-age, marriage, funerals, seasonal festivals, sacrifices |
| Taboos | foods, places, animals, acts |
| Art & legends | named songs, stories and heroes taken from real chronicle events |
| Relationship to nature | exploit, coexist, worship |

Cultures **drift** over time (events, contact with neighbours, leaders) and can **split** (schism, rebellion, colony) into new cultures.

---

## 12. Religion and gods

- Each culture generates a pantheon or a single god: name, domain (sun, sea, war, death, harvest…), symbol, temperament, demands.
- Myths are generated from the world itself (the first volcano eruption becomes the birth of the fire god).
- Faith gives bonuses, priests, temples, holy wars, heresies, conversions.
- **The player is a god too:** peoples notice the player's miracles and disasters and can worship, fear or hate the player.
- Spirits of nature (§ 15) can be worshipped as gods.

---

## 13. Technology, magic and the invention language

### 13.1 Progress: it never stops

Peoples keep advancing as long as they survive. There is **no last age**.

| Age | Examples of what appears |
|---|---|
| Stone | tools, fire, huts, spears, first farms |
| Bronze | metalwork, wheels, writing, temples, boats |
| Iron | iron weapons, roads, fortresses, coins |
| Medieval | castles, mills, crossbows, guilds, universities |
| Renaissance | gunpowder, cannons, printing, ocean ships, banks |
| Industrial | steam engines, trains, factories, rifles, cities of brick |
| Modern | electricity, cars, **planes**, radio, tanks, skyscrapers |
| Atomic | nuclear power and **nuclear weapons**, computers, jets |
| Space | **rockets**, satellites, moon landings, space stations |
| Future | robots, AI, lasers, fusion, orbital cities, starships |
| Beyond | generated without end: each new age is named and filled by the generators (and the AI), e.g. colonising other worlds, terraforming, post-physical civilisations |

- Progress comes from knowledge points (scholars, libraries, universities, contact, discoveries, war).
- There is **no fixed tech tree**. Inventions are generated items, buildings, vehicles, techniques and spells, written in the invention language. Each age only unlocks new **building blocks** (materials, energy sources, effect types) that inventions can combine.
- Magic grows on its own track depending on magic level and culture, and can merge with technology (magitech) instead of disappearing.
- Peoples can also **regress**: wars, plagues, disasters or a nuclear winter can throw a civilisation back several ages, and knowledge can be lost and rediscovered.
- **Consequences of progress:** pollution, deforestation, climate change, extinctions, nuclear wars. Nature spirits react to them (§ 15).
- **Space:** rockets launch from the map; later ages unlock satellites, the moon and other worlds (a separate small map per celestial body, generated from the same seed).

### 13.2 Invention language (Animundi Script)

A small, safe, data-only language. Generators (and later the AI) combine **building blocks**; the engine validates and runs them.

```json
{
  "name": "Ash Spear",
  "kind": "weapon",
  "cost": { "iron": 2, "obsidian": 1 },
  "requires": { "age": "bronze", "building": "forge" },
  "effects": [
    { "on": "hit", "do": "damage", "amount": 8, "type": "fire" },
    { "on": "hit", "if": "target.biome == 'forest'", "do": "ignite", "radius": 1 }
  ],
  "sprite": { "template": "spear", "colors": ["obsidian", "fire"] }
}
```

- **Kinds:** weapon, armour, tool, vehicle (cart, ship, train, car, plane, rocket…), building, energy source, technique (farming, mining…), spell, ritual, law, unit ability, monster ability.
- **Blocks:** triggers (`on`), conditions (`if`), actions (`do`: damage, heal, spawn, transform tile, buff, debuff, move, fly, launch, build, produce, pollute…), costs and requirements. New blocks unlock with each age.
- **Rules:** every effect has a cost; power is capped by age and resources; invalid scripts are rejected; nothing outside the sandbox can be touched.
- **Selection:** inventions are tested in the world. Useful ones spread to other settlements and get copied by neighbours; useless ones are forgotten.

---

## 14. Settlements, kingdoms, economy, war

### 14.1 Settlements

- Founded by a group on a good spot (water, food, resources, culture's favourite biome).
- Grow from **camp → village → town → city → capital**, with a zone layout (houses around a centre, fields outside, workshops near resources, walls when threatened).
- **Buildings** are generated: function (house, farm, storage, forge, temple, barracks, tower, wall, port, market, library, mine, well…) × culture's architecture style × age.
- Roads link settlements; boats connect coasts and islands.

### 14.2 Kingdoms and politics

- Settlements group into kingdoms with borders (territory tiles), a capital, a ruler and a dynasty.
- Generated **banner** and name per kingdom.
- **Diplomacy:** opinions between kingdoms from culture, religion, borders, history and leaders' traits → peace, trade pact, alliance, vassal, rivalry, war.
- **Internal events:** succession, civil war, rebellion, secession, coups, plagues, golden ages.

### 14.3 Economy

- Production chains: raw resources → materials (planks, bricks, ingots) → goods (tools, weapons, food, luxury).
- Storage per settlement; trade caravans and ships between settlements and kingdoms.
- Scarcity drives migration, trade and war.

### 14.4 War

- Causes: territory, resources, religion, revenge, a leader's ambition, monsters.
- Armies gather, march, siege, fight in the open (simple unit-vs-unit combat with stats, equipment and terrain).
- Warfare follows the age: spears and bows, then cannons and muskets, then tanks, planes, missiles and nuclear weapons, then robots and orbital weapons.
- Results: conquest, razing, refugees, tribute, peace treaties. All recorded in the chronicle.

---

## 15. Forces of nature

Nature has its own **spirits**: one per large biome region or special site (Forest of X, Volcano Y, the Northern Sea). They are agents like peoples (with an optional AI mind).

- A spirit has a mood (calm ↔ angry) driven by what happens in its domain: deforestation, mining, pollution, industry, nuclear tests, worship, offerings. The more industrial the world, the angrier nature can get.
- When angry or rewarded, it acts through **natural events:** storms, floods, droughts, earthquakes, eruptions, wildfires, plagues of beasts, blooming, bountiful harvests.
- Spirits can be worshipped, bargained with or fought.

### 15.1 Disasters and phenomena (also available to the player)

Fire and wildfire, meteor, lightning, tornado, flood, tsunami, earthquake, volcano eruption, drought, blizzard, acid rain, plague, corruption spread, blessing, curse.

### 15.2 Diseases

Generated diseases: name, carrier (people, animals, water, rats), symptoms (stat penalties), lethality, cure (herbs, magic, quarantine). Can become plagues that change history.

---

## 16. History and chronicle

- Every meaningful event becomes a chronicle entry: births and deaths of notable people, foundations, wars, battles, disasters, inventions, extinctions, conversions, miracles.
- Entries are written from **templates + generated names** by default, rewritten by the AI later for flavour.
- Ages are named automatically ("The Age of Ash", after the dominant events).
- **Legends:** big events turn into myths and songs of the cultures that lived them.
- Views: global timeline, per kingdom, per person, per place.
- Export the chronicle as text.

---

## 17. Player: god powers

| Category | Powers |
|---|---|
| Terrain | raise / lower land, water, sand, mountains, biome brushes, rivers, volcano |
| Life | spawn any species, people or monster (including legendary ones), give or remove traits, spread infections (zombie, spores) |
| Nature | rain, drought, snow, storms, lightning, tornado, earthquake, meteor, fire, flood |
| Destruction | bombs, napalm, nukes, UFO attack, Armageddon (every kingdom at war), destroy buildings |
| Magic | bless, curse, corrupt, purify, heal, resurrect, madness, plague, cure, epic miracles, powers from sacred sites |
| Gestures | miracles cast by drawing a gesture with the mouse |
| Civilisation | inspire (invention or research direction), rebellion, peace, war, alliance, friendship / spite, world laws, gift of resources |
| Faith | belief of followers gives mana (optional Faith mode), good ↔ evil alignment that changes how the world looks, rival gods (nature spirits) |
| Avatar | a creature the player trains by rewards and punishments, which then acts on its own |
| Tools | inspect anything, follow a unit, favourite units, name things, time controls, divine hand (pick up, drop, throw), poke |
| World | world settings, regenerate with a seed, save/load, share a seed, rename anything, scenarios with goals, achievements, storyteller that paces events (optional) |
| Mods | races, species, inventions and powers as data files |

Peoples **react** to the player's acts (§ 12).

The full survey of what other god games offer, and what Animundi takes from it, is in [GOD_GAMES_RESEARCH.md](GOD_GAMES_RESEARCH.md).

---

## 18. User interface

- Main map view with zoom and pan; pixel-perfect scaling.
- **Map layers:** biomes, height, temperature, humidity, kingdoms, cultures, religions, resources, corruption.
- **Inspector:** click any tile, unit, building, settlement, kingdom, species or spirit for its card (stats, traits, history, inventions with their script).
- **Chronicle panel** with filters.
- **Powers bar** with brushes and categories.
- Speed and time controls; world clock (year, season, age).
- Notifications for major events (war declared, legendary monster awakened…).

---

## 19. Graphics

**Art direction:** 3D pixel art in the style of David Holland's *3D pixel art rendering* (https://davidholland.netlify.app/articles/3d-pixel-art-rendering), the main visual reference. Details and rules in [ART_DIRECTION.md](ART_DIRECTION.md).

- The world is a 3D scene rendered at low resolution and upscaled with sharp pixels (see ART_DIRECTION.md). The 8×8 sprites in `art/` remain the reference for palettes and for flat UI icons.
- **All sprites are generated** from templates + traits + palette, and **change with the age**: a village of huts becomes a brick city, then a city of skyscrapers; clothes, weapons and vehicles follow:
  - peoples (body + race traits + role + culture colours),
  - animals and monsters (body plan + traits + element colours),
  - buildings (function template + culture style + age),
  - items and vehicles (template + materials + age),
  - banners (shape + pattern + symbol + colours).
- Terrain tiles with procedural variations and transitions between biomes.
- Simple animations: walk (2 frames), attack, work, idle; fire, water and lava animated.
- Effects: particles for magic, smoke, rain, snow, blood, explosions.

---

## 20. Audio (later)

- Procedural sound effects (jsfxr-style) for actions and disasters.
- Ambient loops per biome; music generated or picked by mood of the world.

---

## 21. AI layer (after the procedural base)

| Agent | Thinks | Produces |
|---|---|---|
| People / culture | yearly or on major events | values drift, laws, rituals, inventions (scripts), building style, myths, chronicle text |
| Kingdom leader | seasonally | diplomacy and war decisions, inside what the culture allows |
| Monster species | every few years | mutations, new abilities (scripts), lair strategy |
| Nature spirit | on events | mood, natural events, demands to peoples |

- **Models:** small local models (1–3B parameters, quantised), one base model with per-domain LoRA adapters (culture, monsters, nature).
- **Runtime:** llama.cpp linked through a Godot GDExtension, or a local Ollama server called over HTTP from Godot.
- **Input:** a compact summary of the agent's situation and memory (its chronicle).
- **Output:** JSON forced by grammar (JSON schema / GBNF), validated by the engine like any other script.
- **Fallback:** if no model is available, the procedural generators make the same decisions.
- Asynchronous queue: the simulation never waits for the AI.

---

## 22. Saving and sharing

- Save = seed + world settings + current state snapshot (+ action log for replays).
- Share a world by its seed; export a world to a file; export the chronicle.
- Screenshot and GIF capture of a region.

---

## 23. Milestones

| Version | Content |
|---|---|
| **0.1 World** | seed, heightmap, climate, rivers, biomes, rendering with the current tiles, map layers, zoom/pan |
| **0.2 Life** | flora spreading, generated animal species, needs, food chain |
| **0.3 Peoples** | race generator, languages and names, individuals, first villages, jobs |
| **0.4 Civilisation** | settlements growth, generated buildings, kingdoms, borders, diplomacy, war |
| **0.5 Culture** | cultures, religions, gods, laws, rituals, chronicle |
| **0.6 Monsters & nature** | monster generator, lairs, legendary creatures, spirits, disasters, diseases |
| **0.7 Inventions** | the invention language, procedural inventions, ages from Stone to Medieval, magic |
| **0.75 Industry & beyond** | Renaissance → Space ages, vehicles, planes, rockets, pollution, nuclear war, endless generated ages |
| **0.8 God powers & UI** | full power set, inspector, chronicle views, save/load |
| **0.9 AI minds** | local model integration for cultures, monsters and spirits |
| **1.0** | balancing, performance, audio, polish |

---

## 24. Open questions

Decided: **Godot 4** desktop game; **fixed pool of 12 races**, varied per world.

1. **Map size target** and number of units we want to support.
2. **Violence level:** blood, slavery, sacrifices, genocide in the chronicle — what is in and what is out?
3. **Is the player visible** in the world as a god the peoples know, or an invisible force?
4. **Multiplayer / shared worlds** — ever, or never?
5. **Steam release** target, or a free open-source project?
