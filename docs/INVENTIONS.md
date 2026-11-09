# Inventions and minds (0.5 AI minds)

Every kingdom has a **mind**. Once a year it invents what its people need, in the **invention language**: a small JSON record the engine validates before it exists. Inventions change the world, spread, are forgotten, and evolve by descent. Code: `sim/Inventions.cs` (language, validation, effects, spread) and `sim/Minds.cs` (the minds).

## The invention language

```json
{
  "name": "Wheel Plough",
  "kind": "tool",
  "improves": "Iron Plough",
  "description": "A better Iron Plough.",
  "cost": { "wood": 12, "metal": 6 },
  "effects": [ { "do": "yield", "job": "farmer", "amount": 30 } ],
  "sprite": 0
}
```

| Kind | Effects it may have |
|---|---|
| tool | `work_speed`, `yield` (with a job) |
| technique | `work_speed`, `yield` (with a job), `food`, `loyalty` |
| weapon | `attack` |
| armour | `defense` |
| building | `homes`, `food`, `loyalty`, `defense`; its look is `sprite` (0–31) |

| Effect | What it does | Cap per invention |
|---|---|---|
| `work_speed` | the job works faster (%) | 30 |
| `yield` | the job brings more home (%) | 40 |
| `attack` | soldiers strike harder (%) | 35 |
| `defense` | blows that get through armour are smaller (%) | 35 |
| `homes` | homes in the building | 12 |
| `food` | food a month | 10 |
| `loyalty` | loyalty to the kingdom | 15 |

Jobs: gatherer, woodcutter, hunter, builder, farmer, miner, fisher, blacksmith.

**Rules** (`Simulation.ValidateDraft`):
- 1 to 3 effects, each allowed for the kind, with a positive amount up to its cap.
- **Power** is the sum of amount ÷ cap. It must stay within the kingdom's **budget**: 1 + 0.5 × the rank of its biggest settlement (camp 0 … city 3).
- **Cost** must pay for the power. Wood counts 1, stone 1, metal 2 and gold 4, and the total must be at least 12 × power.
- **Name**: 2–28 letters, spaces, hyphens or apostrophes.
- Anything else is rejected and never enters the world.

**In the world:**
- The bonuses of what a village knows add up, with ceilings: work speed, yield, attack, armour, food and loyalty.
- An invented building becomes a building type that only the villages knowing it can build. Its sprite is assembled from parts by `art/homes.py` (`inv_0` … `inv_31`): body, material, roof, tower, wing, columns and banners. Its roof is in the inventor's kingdom colour.

**Evolution:**
- Most inventions improve one the people already know (`improves`), so each invention has a parent and a generation.
- **Spread**: once a year, villages copy what their kingdom, their trade partners and their neighbours know. The more useful an invention is to them, the likelier they are to copy it.
- **Forgetting**: villages forget what is useless to them, and drop a parent once they know its child.
- An invention no one knows any more is lost. Each step is written in the chronicle (event filter "inventions").

## The minds

- **Procedural inventor** (always available). It looks at the kingdom's situation:
  - at war → weapons and armour
  - short of food → techniques
  - crowded or restless → buildings
  - otherwise → tools for its busiest job

  Half the time it improves something known. It names the invention in the people's language.
- **Local language model** (optional).
  - It gets a summary of the kingdom (people, temperament, stores, war, busiest job, what it knows) and the rules.
  - Its output is forced to the language's **JSON schema** (`Simulation.InventionSchema()`), then validated like any other record.
  - The request runs in the background; the world never waits.
  - If the model is slow (90 s), absent or wrong, the procedural inventor answers instead.

### Running a local model

Animundi talks to a model server on your computer over HTTP. No GDExtension is needed: the game stays playable and portable without one.

With **llama.cpp**, start a server with a small instruct model (1–3B parameters, quantised):

```bash
llama-server -m qwen2.5-1.5b-instruct-q4_k_m.gguf --port 8080
```

```bash
ANIMUNDI_LLM_URL=http://127.0.0.1:8080 godot --path .
```

With **Ollama**:

```bash
ANIMUNDI_LLM_URL=http://127.0.0.1:11434 ANIMUNDI_LLM_MODE=ollama ANIMUNDI_LLM_MODEL=qwen2.5:1.5b godot --path .
```

From code: `SetMindEndpoint(url)` and `SetMindModel(mode, model)`. The HUD lists the latest inventions, and its tooltip tells which mind made each one ("model" or "procedural").

The test suite starts a fake llama.cpp server. It checks that the request carries the prompt and the schema, and that the answer becomes an invention.
