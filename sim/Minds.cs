using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;


namespace Animundi.Sim;

/// <summary>
/// The minds that invent (0.5, docs/INVENTIONS.md). Each kingdom thinks once a year:
/// - with a local language model when one is configured (a llama.cpp server or Ollama on this
///   computer: SetMindEndpoint, or the ANIMUNDI_LLM_URL environment variable): the request is
///   sent in the background with the invention language's JSON schema, so the model can only
///   answer with a record; the answer is validated like any other;
/// - else, or when the model is slow, absent or wrong, with the procedural inventor, which makes
///   the same kind of decision from the kingdom's situation.
/// The simulation never waits for a model: answers are picked up when they arrive.
/// </summary>
public partial class Simulation
{
	private sealed class MindState
	{
		public double Next;
		public System.Threading.Tasks.Task<string> Pending;
		public double Asked;
	}

	private readonly Dictionary<int, MindState> _minds = new();
	private static string _llmUrl = Environment.GetEnvironmentVariable("ANIMUNDI_LLM_URL") ?? "";
	private static string _llmMode = Environment.GetEnvironmentVariable("ANIMUNDI_LLM_MODE") ?? "llama";
	private static string _llmModel = Environment.GetEnvironmentVariable("ANIMUNDI_LLM_MODEL") ?? "";
	private static HttpClient _http;
	public int ModelAnswers { get; private set; }
	/// <summary>The model's last raw answer and why it was refused ("" if accepted): settings, tests.</summary>
	public string LastModelAnswer { get; private set; } = "";
	public string LastModelError { get; private set; } = "";
	public int ModelFailures { get; private set; }
	public const double ModelTimeout = 90.0;

	/// <summary>Uses a local model to invent: the `url` of a llama.cpp server (e.g.
	/// http://127.0.0.1:8080) or of Ollama (then SetMindModel("ollama", name)). An empty url goes
	/// back to the procedural inventor.</summary>
	public void SetMindEndpoint(string url) => _llmUrl = url ?? "";

	/// <summary>The kind of local server ("llama" for llama.cpp, "ollama") and, for Ollama, the
	/// model's name.</summary>
	public void SetMindModel(string mode, string model)
	{
		_llmMode = string.IsNullOrEmpty(mode) ? "llama" : mode;
		_llmModel = model ?? "";
	}

	public string MindEndpoint() => _llmUrl;

	/// <summary>Starts the model built into the game (LocalModel): found next to the game or in
	/// the player's data, else downloaded once in the background when `download` is true.
	/// `file` and `url` empty: the default model.</summary>
	public void StartMind(string file, string url, bool download) => LocalModel.Start(file, url, download);

	/// <summary>The built-in model's state for the HUD: status (off, missing, downloading,
	/// loading, ready, failed), progress, file, error, and whether a server overrides it.</summary>
	public Godot.Collections.Dictionary MindStatus() => new()
	{
		["status"] = LocalModel.Status.ToString().ToLowerInvariant(), ["progress"] = LocalModel.Progress,
		["file"] = System.IO.Path.GetFileName(LocalModel.File), ["error"] = LocalModel.Error, ["server"] = _llmUrl,
		["answers"] = ModelAnswers, ["failures"] = ModelFailures,
	};

	/// <summary>Unloads the built-in model: the procedural inventor invents again.</summary>
	public void StopMind() => LocalModel.Stop();

	/// <summary>Whether llama.cpp's native library loads on this computer, and why not.</summary>
	public string MindNativeCheck() => LocalModel.NativeLoads(out string detail) ? "ok: " + detail : "failed: " + detail;

	/// <summary>The grammar the built-in model samples under (tests, docs).</summary>
	public string MindGrammar() => LocalModel.Grammar();

	/// <summary>The JSON schema sent to model servers (tests).</summary>
	public string MindSchema() => InventionSchema();

	private void MindsStep()
	{
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive || kingdom.Capital < 0)
				continue;
			if (!_minds.TryGetValue(k, out var mind))
				_minds[k] = mind = new MindState { Next = Scheduler.Time + InventSeconds * (0.5 + _rng.NextDouble()) };
			// An answer from the model came back (or never will).
			if (mind.Pending != null)
			{
				if (mind.Pending.IsCompleted)
				{
					string json = mind.Pending.Status == System.Threading.Tasks.TaskStatus.RanToCompletion ? mind.Pending.Result : null;
					string why = mind.Pending.Exception?.GetBaseException().Message;
					mind.Pending = null;
					string error = json == null ? "no answer: " + why : SubmitInventionJson(k, json, "model");
					LastModelAnswer = json ?? "";
					LastModelError = error ?? "";
					if (error == null)
						ModelAnswers++;
					else
					{
						ModelFailures++;
						Submit(k, ProceduralInvention(k), "procedural");
					}
				}
				else if (Scheduler.Time - mind.Asked > ModelTimeout)
				{
					mind.Pending = null;
					ModelFailures++;
					Submit(k, ProceduralInvention(k), "procedural");
				}
				continue;
			}
			if (Scheduler.Time >= mind.Next && Villages[kingdom.Capital].Population >= 10)
				Think(k, force: false);
		}
	}

	/// <summary>Kingdom k invents: asks the model in the background, or the procedural inventor now.</summary>
	private void Think(int k, bool force)
	{
		if (!_minds.TryGetValue(k, out var mind))
			_minds[k] = mind = new MindState();
		mind.Next = Scheduler.Time + InventSeconds * (0.8 + 0.4 * _rng.NextDouble());
		if (_llmUrl != "" && !force)
		{
			// A model server the player runs (overrides the built-in model).
			mind.Asked = Scheduler.Time;
			mind.Pending = AskModel(Prompt(k), InventionSchema(), 400);
			return;
		}
		if (LocalModel.Status == LocalModel.State.Ready && !force)
		{
			// The model built into the game.
			mind.Asked = Scheduler.Time;
			mind.Pending = LocalModel.Generate(Prompt(k));
			return;
		}
		// The procedural inventor's drafts are valid by construction; a rejection is a bug.
		string error = Submit(k, ProceduralInvention(k), "procedural");
		if (error != null)
			Godot.GD.PushWarning($"procedural invention rejected: {error}");
	}

	// ------------------------------------------------------------------ the procedural inventor

	private static readonly Dictionary<string, string[]> Nouns = new()
	{
		["gatherer"] = new[] { "Basket", "Sling Bag", "Berry Rake" }, ["woodcutter"] = new[] { "Axe", "Saw", "Wedge" },
		["hunter"] = new[] { "Bow", "Snare", "Javelin" }, ["builder"] = new[] { "Hammer", "Hoist", "Plumb Line" },
		["farmer"] = new[] { "Plough", "Sickle", "Hoe" }, ["miner"] = new[] { "Pick", "Lamp", "Wedge Drill" },
		["fisher"] = new[] { "Net", "Harpoon", "Weir" }, ["blacksmith"] = new[] { "Bellows", "Anvil", "Tongs" },
		["weapon"] = new[] { "Spear", "Blade", "Mace", "Longbow", "Halberd" },
		["armour"] = new[] { "Shield", "Mail", "Helm", "Hide Armour" },
		["technique"] = new[] { "Rotation", "Lore", "Craft", "Way", "Rite" },
		["building"] = new[] { "Hall", "Lodge", "Granary", "Shrine", "Bastion", "Longhouse", "Tower" },
	};

	/// <summary>What the kingdom needs most, and an invention for it: weapons and armour at war,
	/// food when stores run low, homes when crowded, loyalty when restless, else a better tool
	/// for its busiest job. Half the time it improves something its people already know.</summary>
	private InventionDraft ProceduralInvention(int k)
	{
		var kingdom = Kingdoms[k];
		int cap = kingdom.Capital;
		var village = Villages[cap];
		var lang = _languages[kingdom.Species];
		float budget = Budget(k);
		bool atWar = Wars.Exists(w => w.A == k || w.B == k);
		bool hungry = village.Food < village.Population * 3f;
		bool crowded = village.Population + 3 > Homes(cap);
		bool restless = Villages.Exists(v => v.Alive && v.Kingdom == k && v.Loyalty < 10f);
		// Improve something known, of the kind needed, now and then.
		var known = new List<Invention>();
		foreach (int id in village.Known)
			known.Add(Inventions[id]);
		string kind;
		double r = _rng.NextDouble();
		if (atWar && r < 0.6)
			kind = _rng.NextDouble() < 0.55 ? "weapon" : "armour";
		else if (hungry && r < 0.7)
			kind = "technique";
		else if (crowded && r < 0.5 || restless && r < 0.3)
			kind = "building";
		else
			kind = _rng.NextDouble() < 0.6 ? "tool" : InventionKinds[_rng.Next(InventionKinds.Length)];
		var parents = known.FindAll(x => x.Kind == kind);
		Invention parent = parents.Count > 0 && _rng.NextDouble() < 0.6 ? parents[_rng.Next(parents.Count)] : null;

		var effects = new List<EffectDraft>();
		if (parent != null)
		{
			// A better version: each effect a little stronger.
			foreach (var e in parent.Effects)
				effects.Add(new EffectDraft { Do = e.Do, Job = e.Job, Amount = e.Amount * (1.15f + 0.25f * (float)_rng.NextDouble()) });
		}
		else
		{
			string job = BusiestJob(cap);
			switch (kind)
			{
				case "tool":
					effects.Add(new EffectDraft { Do = _rng.NextDouble() < 0.5 ? "work_speed" : "yield", Job = job, Amount = 10f + 15f * (float)_rng.NextDouble() });
					break;
				case "weapon":
					effects.Add(new EffectDraft { Do = "attack", Amount = 10f + 15f * (float)_rng.NextDouble() });
					break;
				case "armour":
					effects.Add(new EffectDraft { Do = "defense", Amount = 10f + 15f * (float)_rng.NextDouble() });
					break;
				case "technique":
					effects.Add(hungry || _rng.NextDouble() < 0.4
						? new EffectDraft { Do = "food", Amount = 2f + 4f * (float)_rng.NextDouble() }
						: new EffectDraft { Do = "yield", Job = hungry ? "farmer" : job, Amount = 10f + 15f * (float)_rng.NextDouble() });
					break;
				default:
					effects.Add(new EffectDraft { Do = "homes", Amount = 4f + _rng.Next(6) });
					if (_rng.NextDouble() < 0.5)
						effects.Add(new EffectDraft { Do = restless ? "loyalty" : atWar ? "defense" : "food", Amount = 3f + 4f * (float)_rng.NextDouble() });
					break;
			}
		}
		// Within the caps and the budget: scale down if needed.
		float power = 0f;
		foreach (var e in effects)
		{
			e.Amount = MathF.Round(Math.Min(e.Amount, EffectBlocks[e.Do].max), 1);
			power += e.Amount / EffectBlocks[e.Do].max;
		}
		if (power > budget)
			foreach (var e in effects)
				e.Amount = MathF.Max(0.1f, MathF.Floor(e.Amount * budget / power * 10f) / 10f);
		power = 0f;
		foreach (var e in effects)
			power += e.Amount / EffectBlocks[e.Do].max;
		// A cost that pays for its power, in the goods its kind needs.
		float need = power * 12f + 2f;
		var cost = kind switch
		{
			"weapon" or "armour" => new Dictionary<string, float> { ["metal"] = MathF.Ceiling(need / 2f * 0.6f), ["wood"] = MathF.Ceiling(need * 0.4f) },
			"building" => new Dictionary<string, float> { ["wood"] = MathF.Ceiling(need * 0.5f), ["stone"] = MathF.Ceiling(need * 0.5f) },
			_ => new Dictionary<string, float> { ["wood"] = MathF.Ceiling(need) },
		};
		string noun = kind is "tool" or "technique" && effects[0].Job != "" && Nouns.ContainsKey(effects[0].Job ?? "")
			? (kind == "tool" ? Nouns[effects[0].Job] : Nouns["technique"])[_rng.Next(3)]
			: Nouns[kind][_rng.Next(Nouns[kind].Length)];
		if (kind == "technique" && effects[0].Do == "yield")
			noun = Nouns[effects[0].Job][_rng.Next(3)] + " " + Nouns["technique"][_rng.Next(5)];
		// A word of their language: an inventor's or a place's name.
		string word = _rng.NextDouble() < 0.5 ? lang.PlaceName() : lang.PersonName();
		string name = word + " " + noun;
		if (name.Length > 28)
			name = name[..28].TrimEnd();
		return new InventionDraft
		{
			Name = name, Kind = kind, Improves = parent?.Name ?? "", Cost = cost, Effects = effects,
			Sprite = kind == "building" ? _rng.Next(InventionSprites) : 0,
			Description = parent != null ? $"A better {parent.Name}." : "",
		};
	}

	private string BusiestJob(int v)
	{
		var counts = new int[JobNames.Length];
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Village[i] == v)
				counts[Units.Job[i]]++;
		string best = "gatherer";
		int most = -1;
		foreach (var job in WorkJobs)
		{
			int j = Array.IndexOf(JobNames, job);
			if (counts[j] > most)
			{
				most = counts[j];
				best = job;
			}
		}
		return best;
	}

	// ------------------------------------------------------------------ the local model

	/// <summary>The kingdom's situation for the model: who they are, what they lack, what they
	/// know, and the rules of the invention language.</summary>
	public string Prompt(int k)
	{
		var kingdom = Kingdoms[k];
		var village = Villages[kingdom.Capital];
		var race = Assets.Species[kingdom.Species].Race;
		var sb = new StringBuilder();
		sb.Append($"You are the collective mind of the {Assets.Species[kingdom.Species].Name} of the kingdom of {kingdom.Name}, ");
		sb.Append($"in year {Year()} of their world. Temperament: aggression {race?.Temper("aggression") ?? 0.5f:0.0}, curiosity {race?.Temper("curiosity") ?? 0.5f:0.0}.\n");
		if (kingdom.Culture >= 0)
		{
			var c = Cultures[kingdom.Culture];
			sb.Append($"Their culture, the {c.Name} ways, values {TopValues(c, 3)}; their homes have {c.Roof} roofs, {c.Wall} walls and {c.Ornament}.\n");
		}
		sb.Append($"Their capital {village.Name} has {village.Population} people, {Homes(kingdom.Capital)} homes, food {village.Food:0}, wood {village.Wood:0}, stone {village.Stone:0}, metal {village.Metal:0}, gold {village.Gold:0}.\n");
		bool atWar = Wars.Exists(w => w.A == k || w.B == k);
		sb.Append(atWar ? "They are at war.\n" : "They are at peace.\n");
		sb.Append($"Their busiest work: {BusiestJob(kingdom.Capital)}.\n");
		if (village.Known.Count > 0)
		{
			sb.Append("They already know:\n");
			foreach (int id in village.Known)
				sb.Append($"- {Inventions[id].Name} ({Inventions[id].Kind}: {Describe(Inventions[id])})\n");
		}
		sb.Append("Invent ONE new thing they need, or improve one they know (set \"improves\" to its exact name). ");
		sb.Append($"Kinds: {string.Join(", ", InventionKinds)}. Effects (\"do\"): ");
		foreach (var (name, block) in EffectBlocks)
			sb.Append($"{name} (kinds {string.Join("/", block.kinds)}, amount up to {block.max}{(block.job ? ", with a job" : "")}); ");
		sb.Append($"jobs: {string.Join(", ", WorkJobs)}. 1 to 3 effects; the sum of amount/max must stay under {Budget(k):0.0}. ");
		sb.Append("Cost in wood, stone, metal, gold: wood counts 1, metal 2, gold 4, and the total must be at least 12 times that sum. ");
		sb.Append($"sprite: 0-{InventionSprites - 1} (buildings only). Name in their language's spirit, 2-28 letters. Answer with the JSON record only.\n");
		return sb.ToString();
	}

	/// <summary>The invention language as a JSON schema (forces the model's output): one branch
	/// per kind, each allowing only that kind's effects, with a job for work effects.</summary>
	public static string InventionSchema()
	{
		var branches = new List<object>();
		foreach (var kind in InventionKinds)
		{
			var effects = new List<object>();
			foreach (var (name, block) in EffectBlocks)
			{
				if (Array.IndexOf(block.kinds, kind) < 0)
					continue;
				var props = new Dictionary<string, object>
				{
					["do"] = new Dictionary<string, object> { ["enum"] = new[] { name } },
					["amount"] = new Dictionary<string, object> { ["type"] = "integer", ["minimum"] = 1, ["maximum"] = (int)block.max },
				};
				if (block.job)
					props["job"] = new Dictionary<string, object> { ["enum"] = WorkJobs };
				effects.Add(new Dictionary<string, object>
				{
					["type"] = "object", ["properties"] = props,
					["required"] = block.job ? new[] { "do", "job", "amount" } : new[] { "do", "amount" },
				});
			}
			branches.Add(KindSchema(kind, effects));
		}
		return JsonSerializer.Serialize(new Dictionary<string, object> { ["anyOf"] = branches });
	}

	private static Dictionary<string, object> KindSchema(string kind, List<object> effects) => new()
	{
		["type"] = "object",
		["properties"] = new Dictionary<string, object>
		{
			["name"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 28 },
			["kind"] = new Dictionary<string, object> { ["enum"] = new[] { kind } },
			["improves"] = new Dictionary<string, object> { ["type"] = "string" },
			["description"] = new Dictionary<string, object> { ["type"] = "string", ["maxLength"] = 160 },
			["cost"] = new Dictionary<string, object>
			{
				["type"] = "object",
				["properties"] = new Dictionary<string, object>
				{
					["wood"] = new Dictionary<string, object> { ["type"] = "number" }, ["stone"] = new Dictionary<string, object> { ["type"] = "number" },
					["metal"] = new Dictionary<string, object> { ["type"] = "number" }, ["gold"] = new Dictionary<string, object> { ["type"] = "number" },
				},
			},
			["effects"] = new Dictionary<string, object>
			{
				["type"] = "array", ["minItems"] = 1, ["maxItems"] = 3,
				["items"] = new Dictionary<string, object> { ["anyOf"] = effects },
			},
			["sprite"] = new Dictionary<string, object> { ["type"] = "integer", ["minimum"] = 0, ["maximum"] = InventionSprites - 1 },
		},
		["required"] = new[] { "name", "kind", "cost", "effects" },
	};

	/// <summary>Sends the prompt to the local model in the background; the task's result is the
	/// model's JSON answer.</summary>
	private static System.Threading.Tasks.Task<string> AskModel(string prompt, string schemaJson, int tokens)
	{
		_http ??= new HttpClient(new HttpClientHandler { UseProxy = false }) { Timeout = TimeSpan.FromSeconds(ModelTimeout) };
		string url = _llmUrl.TrimEnd('/');
		string mode = _llmMode;
		string model = _llmModel;
		return System.Threading.Tasks.Task.Run(async () =>
		{
			var schema = JsonDocument.Parse(schemaJson).RootElement;
			string body;
			string endpoint;
			if (mode == "ollama")
			{
				endpoint = url + "/api/generate";
				body = JsonSerializer.Serialize(new Dictionary<string, object>
				{
					["model"] = model, ["prompt"] = prompt, ["format"] = schema, ["stream"] = false,
					["options"] = new Dictionary<string, object> { ["temperature"] = 0.8 },
				});
			}
			else
			{
				endpoint = url + "/completion";
				body = JsonSerializer.Serialize(new Dictionary<string, object>
				{
					["prompt"] = prompt, ["json_schema"] = schema, ["n_predict"] = tokens, ["temperature"] = 0.8,
				});
			}
			using var response = await _http.PostAsync(endpoint, new StringContent(body, Encoding.UTF8, "application/json"));
			response.EnsureSuccessStatusCode();
			using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
			// llama.cpp answers {"content": "..."}, Ollama {"response": "..."}.
			if (doc.RootElement.TryGetProperty("content", out var content))
				return content.GetString();
			return doc.RootElement.GetProperty("response").GetString();
		});
	}
}
