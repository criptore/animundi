# What makes a good sandbox god game: lessons from the WorldBox wiki

Study of the player-run WorldBox wiki (the-official-worldbox-wiki.fandom.com, 315 pages, read through its public MediaWiki API, game version 0.50 era). [WORLDBOX_ANALYSIS.md](WORLDBOX_ANALYSIS.md) covers how WorldBox is *built*. This page covers how it *plays*: which systems make the sandbox fun, and what Animundi takes from them.

Animundi takes the **mechanisms**: layers, toggles, feedback, emergent loops. It never takes WorldBox's content (its species, biomes, powers or names). Animundi's content is generated and evolves through AI minds.

## 1. The ten lessons

1. **Everything the simulation does, the player can also do by hand, and the other way round.** Biomes come from seeds the player drops, and so do terrain levels (shovel up/down, soils, hills, mountains), walls, clouds and disasters. The same disasters also happen on their own, if the player allows it. Natural processes and god powers are the same actions with two triggers.
2. **Every rule is a switch** ("World Laws", about 50 toggles in 12 groups: Harmony, Diplomacy, Civilizations, Units, Mobs, Spawn, Nature, Trees, Plants, Fungi, Biomes, Weather, Disasters). The player decides what is possible: no war, no old age, eternal lava, trees that spread fast, biomes that overgrow each other, natural disasters on or off. Toggles turn one simulation into many games (a peaceful garden, a war sandbox, a survival world).
3. **Show the invisible.** The game lets the player *see* the simulation:
   - map layers: kingdoms, villages, cultures, languages, religions, clans, families, subspecies, alliances, armies
   - war lines, army targets, plot icons, task icons, happiness icons, speech bubbles
   - money flowing between units, arrows to a unit's home, lover, parents, kids and attack target
   
   Emergent stories are only fun if the player notices them.
4. **Foreshadow events** ("Plots"). Wars, rebellions, alliances, new religions and new books are *planned* by leaders, and their progress shows as an icon that fills with colour. The player can watch a war coming, cancel it (kill the plotter, divine light) or force it. Tension comes from seeing the future.
5. **Log history automatically.** A world history log records kings crowned and killed, capitals fallen, wars, clans and disasters, with filters. Favourite units get their own log. The world writes its own chronicle; Animundi's AI chronicle is the rich version of this.
6. **Societies are layered meta-objects that spread like ideas.**
   - Kingdom, village, clan, culture, language, religion, family and subspecies are separate objects. Each has a name, banner, traits, stats, population graphs and a founder.
   - They spread through conversation, conquest and books, and split through rebellion and schism. A language dies when no one speaks it and no book holds it.
   - This is the backbone of emergent history, and it is exactly where Animundi's AI minds plug in.
7. **Traits and genes on everything, with editors.**
   - Creatures, subspecies, cultures, languages, clans, religions and kingdoms all carry traits.
   - Biomes give starting traits to what is born in them. Biomes also seed their creatures, so where a people starts shapes who they are.
   - The player can edit traits, genes and equipment, or rain good, bad or weird traits on a crowd. Hundreds of unlockable traits give "collection" depth.
8. **Evolution is a visible event.**
   - Creatures can *metamorphose* on death (infection, curse, spores).
   - A mysterious monument evolves nearby animals into sapient species once a year.
   - Subspecies split with new traits; animals become peoples.
   
   Animundi's "inventions evolve by descent" should be just as visible and dramatic.
9. **Time has moods** ("Ages"). The world cycles through ages of 30+ years: hope, sun, dark, tears, moon and others. Each changes weather, growth and which monsters appear, and the player can steer the age clock. Cheap to build, and it gives long games a rhythm.
10. **Unit AI that the player can inspect and edit** ("Neurons").
    - Each possible action is a neuron with a cooldown, a weight and a priority layer. Firing it starts a task made of behaviours.
    - The player can open a unit's mind and switch neurons off.
    - This is utility AI made transparent, the right model for Animundi's 0.3 non-LLM inhabitants, with the LLM mind above it for leaders and cultures.

## 2. Other mechanisms worth taking

- **Biomes are living and spread.** Biome seeds, grass growth, trees spreading, biomes overgrowing each other, "terramorphing" (a species' buildings spread its home biome), erosion turning shore tiles to sand. Each biome has its own food, flora, fauna and tile effects (walk speed, burn chance, nutrition, step effects such as curses), and some need an adaptation trait to build on.
- **Two altitudes per biome** (high and low tile variants) and **terrain as pixels** that can be dug, burned, melted (lava cools to rock, heat rays melt ground) and filled with water.
- **Terraformer creatures** that reshape land on their own (worms, Langton ants, cellular automata), and "printer" creatures that draw a whole landscape from a template. This is the same idea as Animundi's planned terrain stamps.
- **Only one volcano at world start, in the middle.** Everything else special comes from the player. This confirms Animundi's choice to keep special biomes and volcanoes out of random generation.
- **Map generator with world types** (continent, islands, box world, flat plains…) and sliders (noise, shapes, rings of trees), from 128² to 576² tiles. Players also convert images into maps.
- **Many small, readable rules instead of a few deep ones.** Examples:
  - Loyalty: king's diplomacy, capital bonus, new village bonus, superior enemies.
  - Happiness: -100 to 100, from tasks and events.
  - Settlements: zones of 8×8 tiles, a building plan every month, one building at a time, population and zone requirements.
  
  Each rule is simple and documented, so players can reason about outcomes.
- **Economy kept light**: gold, loot and taxes, trade boats between docks, books stored in libraries.
- **Collectibles and discovery**: 774 unlockables (creatures, items, genes, traits, plots), creatures unlocked by finding them in your world, achievements, a "knowledge" archive across worlds.
- **Silly, expressive powers**: forgetting dusts (forget language, culture, religion, family or kingdom), whispers of war, friendship, spite, curses, blessings, possession of a creature. Each social system gets a power that pokes it directly.
- **Save, share, workshop**: worlds are saved, uploaded and downloaded, and mods are first-class.

## 3. Who appears naturally, and how creatures look

**Natural spawning is a property of biomes.**
- Each biome lists the creatures born in it on their own, with relative rates. Mushroom land, for example, gets sheep at rate 1 and frogs at rate 3. This happens only while the "Animal Spawn" world law is on.
- Most monsters are never born at random. They come from:
  - the player's powers and buildings (a tower that spawns cold creatures, a tower that spawns demons)
  - events and ages (moon horrors)
  - deaths: the cursed rise as skeletons, those who die on corrupted land as ghosts
  - evolution: a monument that uplifts animals
  - special biomes, which the player sows
- A fresh world has animals, never monsters. Monsters arrive with the biomes the player makes, the disasters the player allows, or the player's own hand.

**Reading the wiki from a session**: the cloud environment "animundi" allows the wiki's hosts. The wiki's web pages refuse automated clients, but its public MediaWiki API answers. Always read it this way:
- page text: `https://the-official-worldbox-wiki.fandom.com/api.php?action=parse&page=<Page>&prop=wikitext&format=json`
- images of a page: `...&prop=images`, then their URLs with `action=query&titles=File:<name>&prop=imageinfo&iiprop=url|size`, downloaded from `static.wikia.nocookie.net` for study only (never copied into the game)

**Houses** (studied on the "Houses" page, 4 races × 6 tiers × 2 designs): a 3/4 view where the roof takes most of the height; roofs drawn in a magenta mask that the game paints in the kingdom's colour; short walls on a stone footing, a dark outline, light from the left; small props (barrels, crates, fences, flowers, chimneys, lean-to annexes); higher tiers become compounds (a second house, a tower, stone floors). Each race its materials: elves in tree stumps then white stone among trees, dwarves in stone, orcs in hide tents with horns and bones. Animundi's homes (`art/homes.py`) follow these rules with their own drawings, 12 peoples × 4 tiers × 4 variants.

**Sprites** (measured on the wiki's sprite sheets, 10× scale):

| What | Size and look |
|---|---|
| Animals and people | About 9 pixels tall, a simple side-view silhouette, 3 walking frames, plus a small "swimming" variant |
| Colours | Drawn with placeholder mask colours (magenta, green) that the game swaps for the kingdom's colours or the subspecies' skin. Skin colours ("phenotypes") come in ramps of 5 shades, chosen by biome (polar white, savanna tan, swamp teal…) |
| Trees | 11–14 pixels tall, soft shading and a drawn shadow, packed densely, with several tints per biome |
| Ground | Flat colour per biome, two shades (high and low). Flowers and grass are single pixels of colour on the ground, not sprites |
| Tiles | 185 tile types with 2–5 variants each, every one with a hex colour and an edge colour |

Animundi takes the **rules**, never the art:
- Spawning is data: each species lists the biomes it is born in, with weights. Species with none never appear on their own; monsters live only in special biomes.
- Flowers are single pixels drawn by the map shader.
- Walking units hop on two frames (a cheap stand-in until real walk cycles in 0.2).
- Sizes stay close: a unit is about one tile tall, a tree about two.
- Still to come: walk cycles, colour masks for kingdom colours and biome skins, high and low shades per biome.

## 4. What this means for Animundi

| WorldBox mechanism | Animundi version | Milestone |
|---|---|---|
| Biome seeds, shovels, printers | Biome brush, terrain levels up/down, stamps and the player's own presets | 0.9 |
| Fire on tiles (burn chance and rate per tile type), sparks as particles | Fire on tiles with a burn chance and time per biome (done, 0.2); sparks for the fire power | 0.2 / 0.9 |
| Living biomes that spread | Flora spreads, burns and regrows; biomes overgrow each other by world law | 0.2 |
| Biome gives starting traits and fauna | Generated species and peoples take traits from their home biome | 0.2–0.3 |
| Neurons (inspectable utility AI) | Utility AI for inhabitants, shown and switchable in the unit inspector | 0.3 |
| Layered meta-objects (kingdom, culture, language, religion, clan, family, subspecies) | Same layering, with cultures, languages and religions shaped by AI minds | 0.3–0.6 |
| Plots with progress icons | Leaders' plans (war, alliance, invention, schism) shown before they happen, cancellable or forceable | 0.4 |
| World history log | AI chronicle, plus a plain event log with filters | 0.4–0.6 |
| Metamorphosis, monolith evolution | Mutations and evolutions made visible as events, with lineage | 0.5–0.7 |
| Ages | Ages of the world, steerable, changing weather, growth and monsters | 0.8 |
| World laws | One toggle per simulation rule, grouped, each with a one-line description | 0.9 |
| Map layers, arrows, icons | Layers for every meta-object, war lines, plot icons, unit arrows | 0.9 |
| Trait rains, editors, forgetting dusts | God powers that act on traits, memory and beliefs | 0.9 |
| Knowledge, achievements | Discovery archive of species, inventions and traits met across worlds | 1.0 |

### Design rules to keep

- **One action, two triggers**: build every natural process as a function the player's powers can call.
- **A toggle per rule**, off or on from the start, so players shape the kind of world they want.
- **Make it visible**: any system worth simulating gets a map layer, an icon or a log line.
- **Foreshadow**: big events are planned and shown before they happen.
- **Small documented rules beat deep hidden ones**: players love working out why things happened.
- **Content is generated, never copied**: WorldBox's charm is hand-made species and jokes; Animundi's is that its peoples invent their own.
