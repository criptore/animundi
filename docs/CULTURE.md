# Cultures, religions and the chronicle (0.6 Culture)

Every kingdom has a **culture**: what its people value, how they rule and build, their customs, their gods and their myths. The kingdom's mind (the one that invents, see [INVENTIONS.md](INVENTIONS.md)) also writes its customs and myths, and a chronicler writes the world's history. Code: `sim/Culture.cs` (cultures and customs), `sim/Religion.cs` (gods, myths, faith, the player as a god), `sim/Chronicle.cs` (annals, chapters, ages, heroes).

Everything a mind writes is a small JSON record. The local model's answers are forced into that record by a grammar, then validated by the engine. With no model (or a slow or wrong one), a procedural writer answers. The world never waits.

## Cultures

**Values.** Eight weights from 0 to 1: war, honour, nature, wealth, knowledge, faith, freedom, tradition. They start from the people's temperament and the world's seed. A custom strengthens the value it is about, a myth strengthens faith.

Values act on the world:
- Kingdoms that value the same things like each other more (`Opinion`), and those that value war are quicker to start one (`Aggression`).
- The dearest value names how the kingdom rules itself, once it is more than a camp: monarchy, theocracy, warrior chiefdom, council of equals, merchant league, council of elders, tribal league.
- They decide whether a people that dreads the player fears or hates them (see below).

**Architecture.** Each culture has its walls (stone, plank, plaster, mud, log, shell), its roofs (gabled, domed, conical, flat, stepped) and an ornament. The buildings a kingdom invents take the sprite that matches its walls, and usually its roof.

**Inheritance.** A kingdom born of a rebellion keeps its mother's values (a little shifted, with more love of freedom), her way of building, her customs, her gods and her myths.

## The custom language

Once a year a kingdom's mind writes a law, a ritual or a taboo:

```json
{
  "name": "Blood Oath",
  "kind": "law",
  "about": "war",
  "text": "Every grown hand owes a season to the army.",
  "effects": [ { "do": "attack", "amount": 12 }, { "do": "loyalty", "amount": -4 } ]
}
```

| Effect | What it changes in the kingdom's villages | Most it gives or takes |
|---|---|---|
| `attack` | how hard soldiers strike (%) | 15 |
| `defense` | armour (%) | 15 |
| `food` | food a month | 5 |
| `loyalty` | loyalty to the kingdom | 10 |
| `faith` | the kingdom's faith | 10 |
| `work_speed` | a job's speed (%), with a job | 15 |
| `yield` | what a job brings home (%), with a job | 20 |
| `aggression` | eagerness for war | 20 |

**Rules** (`Simulation.ValidateCustom`):
- `kind` is law, ritual or taboo; `about` is one of the eight values.
- 1 or 2 effects. Amounts are whole numbers, positive (given) or negative (taken), within the cap.
- **Power** is the sum of amount ÷ cap (aggression is a leaning and is not counted). It must not exceed 0.6: a strong gain needs a price.
- A taboo forbids something: it has at least one negative effect.
- Name: 2–28 letters, spaces, hyphens or apostrophes. Text: one plain sentence, 160 characters at most.
- Anything else is rejected and never enters the world.

A kingdom keeps **three customs of each kind**. A fourth makes the oldest give way, so cultures drift over the years. Each step is written in the chronicle (event filter "Gods and customs").

The procedural writer picks a value the kingdom holds dear, a gain that fits it (war → attack, tradition → loyalty, knowledge → faster builders or smiths…) and, when the gain is large or the custom is a taboo, a price.

## Religions

Each culture starts with one god (a name in its language, a domain, a temperament) and a creed named after it.

**Myths come from the world.** A kingdom remembers what it lived through: a war, a peace, a village taken or lost, a ruler's death, a town becoming a city, lightning setting the land ablaze, a hero, a rebellion, and what the player did to it. When its mind thinks of its culture and something heavy enough is untold, it tells it as a myth:

```json
{ "title": "How Urun Threw the Bolt", "text": "In year 14, lightning set the land ablaze near Karum. ..." }
```

The mind writes the title and the text. The engine ties the myth to what really happened (its source, shown under the myth) and to a god: the culture's god of that domain, or a **new god born of the event** when it has none (five gods at most).

**Faith** (0–100) moves every season toward what the culture values, its temples, its myths, its customs and what it makes of the player. Faith adds or takes loyalty in every village. Kingdoms of the same religion like each other more; devout kingdoms of rival religions like each other less.

## The player is a god

Peoples notice what the powers do within sight of their villages (the brush and 14 tiles):

| Power | Leaves |
|---|---|
| Bless (people healed), rain that puts fires out | gratitude |
| Fire, lightning, meteor, smite (people killed) | dread |

Both fade over the seasons. While both are faint the player is unnoticed. Then:
- gratitude at least equal to dread: the player is **worshipped** (more faith, more loyalty);
- else, in cultures where faith and tradition outweigh freedom and war: **feared** (a little more faith);
- else: **hated** (less faith, less loyalty, more eagerness for war).

The first time they notice, they give the unseen hand a name in their language, and it joins their gods. Miracles and wrath become myths about that god. Powers are dragged over the map and act every frame: a kingdom feels one kind of act at most every 0.4 seconds, and remembers and speaks of it once a season.

## The chronicle

Every event of the log is kept in the **annals**. Every five years the chronicler writes a **chapter** from the annals of those years:

```json
{ "title": "Blades and Banners", "text": "In year 12, Karum declares war on Belit! ...", "age": "The Age of Iron" }
```

- With a model, the chapter is its telling of the listed events.
- Without one, the procedural chronicler tells the four events that mattered most, in order, and counts the rest.

**Heroes.** A warrior who slays four foes in war is hailed a hero: it is told in the chronicle (event filter "Heroes"), remembered by the kingdom, and may become a myth. A hero's death is told too.

**Ages.** The world begins in the Age of Dawn. When a chapter is written, the kind of events that filled the last ten years (wars, disasters, heroes, gods and customs, crowns, cities, inventions) is compared with what the age was named after. If it changed and the age is at least ten years old, a new age begins: "The Age of Ash", "The Age of Blades", "The Age of Makers"… The model may name it; no name is used twice. The age shows beside the date.

## In the game

- The **Cultures** book of the dock lists each kingdom's values, rule, architecture, faith, gods, customs, latest myths and what it makes of you.
- The **Chronicle** book shows the age and the latest chapters above the events.

## Tests

`test_culture` in `tests/test_world.gd` checks the custom language's rules, the effects of customs on villages, the procedural writer, the player's standing after blessings and meteors, myths drawn from real events, chapters and ages, inheritance by rebels, a fake model server, and the grammars with the tiny random model. One test alone:

```bash
godot --headless --path . --script res://tools/run_test.gd -- test_culture
```
