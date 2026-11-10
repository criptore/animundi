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
- [x] Individuals: name, sex, age, two traits (brave, lazy, kind, greedy, wise, strong), partner, mother and father; children grow up (adults at 4 at most, so children work within a few minutes), work, pair, have children, grow old and die; hovering a creature tells who it is
- [x] Jobs handed out by the village by what it lacks: gatherers (wild food from the grass), woodcutters (trees are felled), hunters (animals of their size or a little bigger), builders (houses from wood); warriors prefer the hunt and defend; chiefs and shamans lead (a new chief when the old one dies)
- [x] More jobs: farmer, miner, fisher (0.35); herder later
- [x] First villages: a bonfire, then houses in each people's style built when room runs out (`art/buildings.py`), food and wood stores; villages are abandoned when everyone is gone
- [x] Utility AI for people, as WorldBox's neurons: each action (drink, eat, rest, pair, breed, work, play, wander) has a weight, a cooldown, a priority and a switch; urgent thirst and hunger interrupt any task (the unit inspector that shows and switches them comes with 0.9)
- [ ] Home biome gives species and peoples their starting traits

## 0.35 Villages (WorldBox parity, see [VILLAGES.md](VILLAGES.md))
- [x] Territory: zones of 8×8 tiles, 3×3 at founding, one more each month while the village grows; borders drawn on the map in the people's colour (a shade per village); buildings only on the village's land
- [x] Buildings as data (`data/buildings.json`): bonfire, hut → house → stone house → big house (upgraded in place), stockpile, well, windmill, mine, dock, town hall, barracks, training dummies, watch tower, market, temple, library, statue, ruins
- [x] Building plan, WorldBox's rules: once a month one building or one upgrade; homes first when people run short; needs people, prerequisites, goods and a place (cluster, apart, border, shore, near rock, next to the barracks)
- [x] Stores: food, wood, stone, metal, gold; tools (faster work) and weapons (stronger warriors) made by the blacksmith; goods thrown into a stockpile or town hall from 7 tiles
- [x] Jobs with WorldBox's limits: builders (3), gatherers by food in store, woodcutters, hunters, farmers, miners (gold only near hills and mountains), fishers, blacksmith, firemen, road builders; warriors up to 15–35% of adults (by temperament) guard the village and train on dummies
- [x] Homes: everyone lives in a building (or by the bonfire); people sleep at home, eat at the stores, drink at wells
- [x] Fields around windmills: sown and harvested by farmers, wheat grows with the seasons (drawn on the map, green then gold)
- [x] Roads from every new building to the bonfire, laid by road builders, half again as fast to walk on
- [x] Fire: wooden buildings catch fire from burning land, burn down to ruins unless firemen put them out; ruins crumble after two years; abandoned villages fall to ruins and free their land
- [x] Watch towers shoot beasts in range
- [x] Settlers: big crowded villages send 6–12 adults and their children to found a new village of their people 18–45 tiles away
- [x] Building sprites (`art/buildings.py`, [images/buildings.png](images/buildings.png)): homes redrawn in WorldBox's 3/4 style by `art/homes.py` (12 peoples × 4 tiers × 4 variants, each people its materials: timber, stumps, stone, tents, domes, mushrooms), roofs and banners in a colour mask painted in the village's colour; 5 great buildings per people, plus the shared buildings

### Known issues (set aside for now)
- [ ] Rocks and some sprites still flicker at Ultra speed. Already ruled out: the wind phase (now from the position) and animations on simulation time (now real time). Leads: strips rebuilt every frame while plants grow fast (instance counts changing), the far-view/near-view switch, sort ties between plants and creatures at the same height

## 0.4 Civilisation
- [x] Settlements grow: camp → village → town → city (by people; a city needs a town hall)
- [ ] **Buildings by age**: every home and building redrawn for each era of a people (wood → stone → metal → industrial → modern → future), the way homes now change by tier; a village's look follows the age its culture has reached (0.8 Ages drives the eras)
- [ ] **Notable buildings unlocked by culture and age** (later, with cultures and ages): colosseum, museum, triumphal arch, aqueduct, lighthouse, pyramid, great library, observatory, cathedral, bathhouse, amphitheatre, harbour fortress, university, monuments of each people; each with its unlock (age, culture traits, wealth, population) and an effect on the village (happiness, faith, knowledge, trade, defence)
- [ ] Buildings generated from function × culture × age, with generated sprites (moved to 0.5 AI minds and 0.8 Ages)
- [x] Trade (`sim/Trade.cs`): routes between friendly villages with a market or stockpile; every month the surplus (food, wood, stone) goes where it is lacking, markets earn gold; carts follow land paths, boats sail between docks along water paths (paths found once per route)
- [x] Kingdoms (`sim/Kingdoms.cs`): every people starts as a kingdom, settlers' villages join it; capital, king or queen of a dynasty (the eldest grown child inherits, else a new dynasty), the kingdom's colour on its land and roofs (a shade per village), a generated banner (colours, division, symbol)
- [x] Diplomacy: opinions (kin peoples, temperament, borders, old wars, allies), alliances (allies join wars), war when a ruler dislikes a reachable, not stronger neighbour, peace after long or costly wars, with lasting bitterness
- [x] War (`sim/War.cs`): armies of two thirds of the warriors march along a land road on the nearest enemy village, on rations; people of kingdoms at war fight (health, strength, training, weapons); defenders guard their land; a village without defenders is besieged (wooden buildings set alight) and taken; a kingdom with no village left falls
- [x] Rebellions, civil wars, secessions: loyalty of each village (distance to the capital, size, people, war weariness, a dead king, conquest); big disloyal villages plot to break away and found a kingdom, disloyal neighbours join, and the old kingdom goes to war
- [x] Plans shown before they happen: wars, peace, alliances and rebellions are plots that grow over months, shown in the panel with their progress; the simulation can cancel or force them (the god powers of 0.9 will)
- [x] Event log with filters (kings, wars, cities, disasters); favourites come with the inspector (0.9)
- [x] Boats of war: when no land road leads to the enemy, soldiers walk to their dock, board a war boat (five aboard, or twenty seconds after the first), sail a water path to the shore nearest the target and go ashore to fight

## 0.5 AI minds (the edge)
See [INVENTIONS.md](INVENTIONS.md).
- [x] Small local model built into the game: llama.cpp compiled in through LLamaSharp (native libraries for every platform in every build, the right CPU variant loaded at run time), the model found next to the game or downloaded once in the background on first launch, answers forced by a GBNF grammar and validated; a llama.cpp server or Ollama the player runs can replace it (HTTP, JSON schema)
- [x] The invention language: tools, weapons, armour, techniques and buildings as validated data records (kinds, effect blocks with caps, a power budget by rank, costs that pay for the power)
- [x] Cultures invent **objects and buildings**: each kingdom's mind once a year, from its situation (war, hunger, crowding, restlessness, its busiest job); invented buildings get sprites assembled from parts with the kingdom's colour (`art/homes.py`, 32 shapes)
- [x] Inventions spread (kingdom, trade partners, neighbours, by usefulness), are forgotten when useless or replaced, and evolve by descent (parent, generation), traced in the chronicle (event filter "inventions")
- [x] Procedural fallback when no model is available (and when it is slow or wrong)
- [ ] Inventions with new effect blocks unlocked by ages (0.8), monster and nature minds (0.7), the culture mind writing laws, rituals and myths (0.6)

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
- [x] Biome brush: paint mushroom land, cursed land, volcanic rock, lava (and the natural biomes), with a brush size (land only; the old plants go and the new biome's grow; lava kills what stands on it)
- [ ] Stamps: ready-made presets (volcanoes of several sizes, later islands, craters, oases) pasted on the map where the player clicks; levels around them are fixed so the terrain stays valid
- [ ] The player's own presets: select an area of the map and save it as a stamp, reuse it in any world
- [x] Plants and the map texture update only where the terrain changed
- [ ] Fire power drops sparks (particles) that set alight the tiles they land on, as in WorldBox (the fire power lights the tiles under the brush for now; the F test key is gone)
- [x] The powers bar (`scripts/ui/power_bar.gd`, `sim/Powers.cs`): a power and a brush size, then click or drag on the map; first powers: bring creatures, settle a people (a new village and kingdom), fire, lightning, rain, meteor, smite, bless
- [ ] More powers: terrain (raise, lower, water), weather, disasters, miracles, curses, faith mode, avatar, gestures, storyteller
- [x] Inspector cards for a creature and a village: click to pin, refreshed while it lives
- [ ] Inspector cards: kingdom, species, spirit, invention (with its script and lineage)
- [ ] Map layers (kingdoms, cultures, languages, religions, clans, families, species, alliances, armies), war lines, plot and task icons, unit arrows, and statistics
- [x] World laws menu: a switch for each of the five laws the simulation has
- [ ] World laws: one switch per simulation rule, grouped (diplomacy, civilisations, units, nature, biomes, weather, disasters), each with a one-line description
- [x] Whispers: war, peace or alliance between two kingdoms, by clicking their lands
- [ ] Powers that act on minds: rain traits, make people forget their language, culture, faith or kingdom
- [x] The whole interface in one look (`scripts/ui/ui.gd`, icons by `art/ui_icons.py`): title screen, world setup, top bar, dock of books (kingdoms, villages, life, inventions, chronicle), tabbed powers bar, inspector, map layers, laws, settings and pause windows; every feature to come already has its locked button
- [ ] Save, load, share a seed

## 1.0 Polish
- [ ] Balancing and performance
- [ ] Sound and music
- [ ] Achievements, scenarios, mod support
- [ ] A playable build to distribute
