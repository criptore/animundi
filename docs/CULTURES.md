# Cultures, faiths and the chronicle (0.6 Culture)

Every kingdom lives by a **culture** and keeps a **faith**. Its mind writes the culture's laws, rituals and taboos; its storytellers make myths of what the people really saw; the player becomes one of their gods; and a chronicler writes the history of the world, age by age. Code: `sim/Cultures.cs`, `sim/Faiths.cs`, `sim/Chronicle.cs`, and `sim/Thoughts.cs` (questions to the local model).

## Cultures

A culture is born with its kingdom, from the people's temperament and the seed:

| Aspect | What it is |
|---|---|
| Values | weights 0–1 for war, honour, nature, wealth, knowledge, faith, freedom, tradition |
| Society | tribe, chiefdom, monarchy (by the size of the kingdom), theocracy (faith above war), council (freedom above tradition) |
| Nature | exploit, coexist or worship |
| Architecture | roof, walls and ornaments of its homes (told to the inventing mind) |
| Customs | laws, rituals and taboos, written in the culture language |
| Legends | songs of its heroes and great deeds (the Song of Aldo the Bold, the Taking of Tolm) |

**Drift**, once a year: war makes a culture value war and honour; peace calms it; hunger turns it to faith and nature; gold to wealth; inventions to knowledge; temples to faith. Allies and trade partners rub off on each other. A people that loves the god in the sky grows in faith; one that fears it holds to tradition; one that hates it values freedom. The chronicle tells when a culture's highest value, its society or its way with nature changes.

**Splits**: a village that breaks away founds a kingdom whose culture is a child of the old one (values drifted, freedom up, half the customs kept). It keeps the old faith, until a schism.

### The culture language

```json
{
  "kind": "ritual",
  "name": "Cradle Dance",
  "text": "At each birth, the Elves dance until dawn.",
  "occasion": "birth",
  "effects": [ { "do": "fertility", "amount": 20 } ]
}
```

| Kind | Effects it may have |
|---|---|
| law | loyalty, faith, fertility, food, attack, defense, warlike, peaceful |
| ritual | the same; needs an occasion: birth, coming_of_age, marriage, funeral, harvest, midwinter, battle, victory |
| taboo | loyalty, faith, food, peaceful |

| Effect | What it does | Cap per custom |
|---|---|---|
| `loyalty` | loyalty of the villages | 10 |
| `faith` | faith of the villages grows | 10 |
| `fertility` | children come sooner (%) | 25 |
| `food` | food a month | 4 |
| `attack`, `defense` | soldiers strike harder, take less (%) | 15 |
| `warlike`, `peaceful` | rulers plot wars more, or less (%) | 30 |

**Rules** (`Simulation.ValidateCustom`): 1 or 2 effects allowed for the kind, each within its cap, their power (sum of amount ÷ cap) at most 1.2; never warlike and peaceful at once; a name of 2–32 letters, a text of at most 160 plain characters. A culture keeps 4 laws, 4 rituals and 3 taboos: a new one replaces the oldest.

**The mind** writes a custom about every three years: the local model when one runs (the culture's situation, values, customs and legends in the prompt, its answer forced by a grammar or a JSON schema, then validated), else the procedural mind: laws of loyalty when villages are restless, rituals of battle at war, of harvest when hungry, of fertility when the people are few, otherwise what its values favour, named and told in the people's words.

## Faiths

A faith begins with one god (a fervent culture that holds little to tradition) or a small pantheon, from its values and its land (a sea god by the coast), and a myth of how the world began. Gods have a domain (sun, moon, sea, sky, storm, fire, earth, harvest, forest, beasts, war, death, wisdom, wealth), a temper and a demand.

**Myths come from what the peoples witness**: lightning, wildfires, meteors, fire rising from the ground, wars, conquests, a ruler's death, a kingdom's fall, a species' extinction, a city's rise. A people that sees a new kind of event may find a new god in it ("When a burning star fell near Tolm in year 12, the Elves saw Vael for the first time, who holds up the heavens"); otherwise the event becomes a deed of the god of its domain. Myths are written by the local model when one runs (validated: god, domain, title, story), else procedurally.

**Faith in the villages** (0–100), once a year: it grows with the culture's faith, temples, shamans, rituals and the love of the god in the sky. It makes villages loyal.

- Kingdoms of the same faith like each other; fervent cultures despise unbelievers and call holy wars.
- A kingdom of weak faith may turn to the faith of a fervent neighbour, ally or trade partner it does not hate.
- A faith kept by several kingdoms splits in a schism when one of them has drifted far from the culture it was born in: the new faith keeps the old gods and finds a new one.

## The god in the sky

The peoples see what the player does:
- mercy (bless, rain on their fires, **miracle**) makes them love the player;
- wrath that strikes them (smite, lightning, meteor, lava) makes them fear and hate the player;
- wrath seen from afar, and monsters brought from the sky, make them fear.

Once a people has seen enough, it knows there is a god in the sky: its faith gives the player a name and a myth ("In year 9 a hand came down from the sky over Tolm and healed the sick with a touch. The Humans call it Orra, and they bow in love."). Each kingdom then **worships**, **fears** or **hates** the player, and this fades with the years:

- worship: more faith, more loyalty;
- fear: rulers dare not plot wars as often;
- hate: rulers plot wars more often, and faith in the god in the sky is low.

The **Miracle** power (Wrath & Mercy tab) heals under the brush and lifts the faith of the villages that see it.

## The chronicle

The event log records everything; the chronicler keeps the weightiest events and, **every five years, writes a page** about them: the local model when one runs ("Write the page of the chronicle for the years 10 to 15…", validated: title and text), else procedurally (an opening by the mood of the years, the weightiest events in order, the heroes).

History is cut into **ages**: the first is the Age of Beginnings; a new one begins when the mood of the years changes (war, ruin, disaster, faith, wonder, growth, quiet) and the age has lasted ten years: the Age of Swords, the Age of Ash, the Golden Age, the Second Age of Swords… The model may name the age that begins.

**Heroes**: a warrior with five victories is hailed as a hero, with an epithet (Aldo the Bold); the culture sings of them; the chronicle mourns them when they fall.

## Laws

Two laws of the world switch these off: **cultures** (drift and the customs the minds write) and **faiths** (myths, conversions, schisms).
