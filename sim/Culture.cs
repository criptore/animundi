using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// Cultures (0.6, docs/CULTURE.md): every kingdom has a culture. It holds what its people value
/// (eight weights), how they build, and their customs: laws, rituals and taboos, written by the
/// kingdom's mind once a year in the custom language, a JSON record the engine validates like an
/// invention. A custom changes how the kingdom's villages work, fight and believe, and most have
/// a price. A kingdom keeps three customs of each kind: an old one gives way to a new one, so
/// cultures drift. A kingdom born of a rebellion inherits its mother's culture and gods.
///
/// The mind is the local model when there is one (Minds.cs), else a procedural writer.
/// Religion, myths and what peoples think of the player are in Religion.cs.
/// </summary>
public partial class Simulation
{
	public static readonly string[] ValueNames = { "war", "honour", "nature", "wealth", "knowledge", "faith", "freedom", "tradition" };
	public static readonly string[] CustomKinds = { "law", "ritual", "taboo" };
	public static readonly string[] Roofs = { "gabled", "domed", "conical", "flat", "stepped" };
	public static readonly string[] Walls = { "stone", "plank", "plaster", "mud", "log", "shell" };
	private static readonly string[] Ornaments = { "banners", "carved posts", "painted doors", "hanging lanterns", "bone charms", "shell inlays", "woven mats", "standing stones" };

	/// <summary>The blocks of the custom language: the most an effect can give or take in one
	/// custom, and whether it names a job.</summary>
	public static readonly Dictionary<string, (float max, bool job)> CustomBlocks = new()
	{
		["attack"] = (15f, false), ["defense"] = (15f, false), ["food"] = (5f, false), ["loyalty"] = (10f, false),
		["faith"] = (10f, false), ["work_speed"] = (15f, true), ["yield"] = (20f, true), ["aggression"] = (20f, false),
	};
	/// <summary>What a custom may give in all (sum of amount / cap; aggression is a leaning, not
	/// a gain, and is not counted): more must be paid for by a negative effect.</summary>
	public const float CustomBudget = 0.6f;
	public const int CustomsPerKind = 3;

	/// <summary>A custom as written by a mind, before validation (the custom language).</summary>
	public sealed class CustomDraft
	{
		[JsonPropertyName("name")] public string Name { get; set; } = "";
		[JsonPropertyName("kind")] public string Kind { get; set; } = "";
		[JsonPropertyName("about")] public string About { get; set; } = "";
		[JsonPropertyName("text")] public string Text { get; set; } = "";
		[JsonPropertyName("effects")] public List<EffectDraft> Effects { get; set; } = new();
	}

	public sealed class Custom
	{
		public string Name, Kind, About, Text, Mind;
		public int Year;
		public List<EffectDraft> Effects = new();
	}

	public sealed class Culture
	{
		public readonly float[] Values = new float[ValueNames.Length];
		public int Roof, Wall, Ornament;
		public readonly List<Custom> Customs = new();
		/// <summary>Sums over the customs: leaning to war (-100..100) and faith a season.</summary>
		public float AggressionBonus, FaithBonus;
		public double NextThought;
		public Question Asking;
		/// <summary>What the pending question was about: "custom", or "myth" and its memory.</summary>
		public string AskingKind;
		public Memory AskingMemory;

		// Religion (Religion.cs).
		public int Religion;
		/// <summary>Years (of Faiths.cs) since the kingdom took up its faith.</summary>
		public int FaithYears;
		public string Creed = "";
		public readonly List<God> Gods = new();
		public readonly List<Myth> Myths = new();
		public readonly List<Memory> Memories = new();
		public float Faith = 30f;
		/// <summary>What the player's acts left behind, 0..100 each, fading.</summary>
		public float Gratitude, Dread;
		/// <summary>unnoticed, worshipped, feared, hated.</summary>
		public string Stance = "unnoticed";
		/// <summary>The name they give the player ("" until they notice).</summary>
		public string GodName = "";
		public readonly Dictionary<string, double> LastAct = new();
		/// <summary>When each kind of act was last felt, in the player's time (ms).</summary>
		public readonly Dictionary<string, ulong> LastFelt = new();
	}

	private Random _cultureRng = new(1);
	private int _nextReligion;
	private double _nextCultureSeason;
	public int CustomsRejected { get; private set; }

	private void SetupCulture()
	{
		_nextReligion = 0;
		_nextCultureSeason = 0;
		_nextFaithYear = 0;
		CustomsRejected = 0;
		SetupChronicle();
	}

	/// <summary>A new people's culture: values from its temperament and the world's seed, a way
	/// of building, and a first god.</summary>
	private Culture NewCulture(int species)
	{
		var race = Assets.Species[species].Race;
		var c = new Culture();
		for (int n = 0; n < c.Values.Length; n++)
			c.Values[n] = 0.2f + 0.6f * (float)_cultureRng.NextDouble();
		c.Values[0] = Math.Clamp(0.15f + 0.7f * (race?.Temper("aggression") ?? 0.5f) + 0.2f * ((float)_cultureRng.NextDouble() - 0.5f), 0f, 1f);
		c.Values[4] = Math.Clamp(0.15f + 0.7f * (race?.Temper("curiosity") ?? 0.5f) + 0.2f * ((float)_cultureRng.NextDouble() - 0.5f), 0f, 1f);
		c.Roof = _cultureRng.Next(Roofs.Length);
		c.Wall = _cultureRng.Next(Walls.Length);
		c.Ornament = _cultureRng.Next(Ornaments.Length);
		c.NextThought = Scheduler.Time + YearSeconds * (0.3 + _cultureRng.NextDouble());
		FoundReligion(c, species);
		return c;
	}

	/// <summary>The rebels keep their mother's culture: the same values (a little shifted), the
	/// same way of building, the same customs, gods and myths.</summary>
	private void InheritCulture(int from, int to)
	{
		var a = Kingdoms[from].Culture;
		var c = Kingdoms[to].Culture;
		for (int n = 0; n < c.Values.Length; n++)
			c.Values[n] = Math.Clamp(a.Values[n] + 0.2f * ((float)_cultureRng.NextDouble() - 0.5f), 0f, 1f);
		// Those who break away prize freedom.
		c.Values[6] = Math.Min(1f, c.Values[6] + 0.15f);
		c.Roof = a.Roof;
		c.Wall = a.Wall;
		c.Ornament = a.Ornament;
		c.Customs.Clear();
		c.Customs.AddRange(a.Customs);
		c.Religion = a.Religion;
		c.FaithYears = 0;
		c.Creed = a.Creed;
		c.Gods.Clear();
		c.Gods.AddRange(a.Gods.FindAll(g => !g.Player));
		c.Myths.Clear();
		c.Myths.AddRange(a.Myths);
		c.Faith = a.Faith;
		CultureChanged(to);
	}

	/// <summary>The customs changed (or the kingdom's villages did): sums and village bonuses.</summary>
	private void CultureChanged(int k)
	{
		var c = Kingdoms[k].Culture;
		c.AggressionBonus = c.FaithBonus = 0f;
		foreach (var custom in c.Customs)
			foreach (var e in custom.Effects)
			{
				if (e.Do == "aggression")
					c.AggressionBonus += e.Amount;
				else if (e.Do == "faith")
					c.FaithBonus += e.Amount;
			}
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == k)
				v.ModsDirty = true;
	}

	/// <summary>A kingdom's customs on one of its villages (called by RefreshMods).</summary>
	private void ApplyCustoms(Village village)
	{
		if (village.Kingdom < 0)
			return;
		foreach (var custom in Kingdoms[village.Kingdom].Culture.Customs)
			foreach (var e in custom.Effects)
			{
				int j = Array.IndexOf(JobNames, e.Job ?? "");
				switch (e.Do)
				{
					case "work_speed": if (j >= 0) village.JobSpeed[j] += e.Amount; break;
					case "yield": if (j >= 0) village.JobYield[j] += e.Amount; break;
					case "attack": village.Attack += e.Amount; break;
					case "defense": village.Defense += e.Amount; break;
					case "food": village.FoodBonus += e.Amount; break;
					case "loyalty": village.LoyaltyBonus += e.Amount; break;
				}
			}
	}

	/// <summary>How eager for war a kingdom is, 0..1: its people's temperament, what its culture
	/// values, its customs, and a hatred of the player's hand.</summary>
	public float Aggression(int k)
	{
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		float a = Assets.Species[kingdom.Species].Race?.Temper("aggression") ?? 0.5f;
		return Math.Clamp(a + (c.Values[0] - 0.5f) * 0.3f + c.AggressionBonus / 100f + (c.Stance == "hated" ? 0.1f : 0f), 0f, 1f);
	}

	/// <summary>How alike two cultures' values are, 0..1.</summary>
	private float Kinship(Culture a, Culture b)
	{
		float d = 0f;
		for (int n = 0; n < a.Values.Length; n++)
			d += Math.Abs(a.Values[n] - b.Values[n]);
		return 1f - d / a.Values.Length;
	}

	/// <summary>How a kingdom rules itself, from what it values most and how big it has grown.</summary>
	public string StructureOf(int k)
	{
		var c = Kingdoms[k].Culture;
		int rank = 0;
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == k)
				rank = Math.Max(rank, v.Rank);
		if (rank == 0)
			return "tribe";
		int top = 0;
		for (int n = 1; n < c.Values.Length; n++)
			if (c.Values[n] > c.Values[top])
				top = n;
		return ValueNames[top] switch
		{
			"war" => "warrior chiefdom", "faith" => "theocracy", "freedom" => "council of equals", "wealth" => "merchant league",
			"knowledge" => "council of elders", "nature" => "tribal league", _ => "monarchy",
		};
	}

	private static string NatureOf(Culture c) => c.Values[2] > 0.62f ? "worship nature" : c.Values[2] > 0.38f ? "live with nature" : "use nature";

	/// <summary>The sprite of an invented building in the kingdom's style (art/homes.py builds
	/// sprite n with wall n % 6 and roof n / 6 % 5): its walls always, its roof when it can.</summary>
	private int StyleSprite(int k)
	{
		var c = Kingdoms[k].Culture;
		var same = new List<int>();
		for (int n = c.Wall; n < InventionSprites; n += Walls.Length)
			same.Add(n);
		int own = c.Roof * Walls.Length + c.Wall;
		return _cultureRng.NextDouble() < 0.6 && own < InventionSprites ? own : same[_cultureRng.Next(same.Count)];
	}

	// ------------------------------------------------------------------ validation

	/// <summary>Null, or why a name a mind wrote is refused: 2 to `max` letters, spaces, hyphens
	/// or apostrophes.</summary>
	private static string NameError(string name, int max)
	{
		if (string.IsNullOrWhiteSpace(name) || name.Trim().Length < 2 || name.Length > max)
			return $"name must be 2-{max} characters";
		foreach (char ch in name)
			if (!char.IsLetter(ch) && ch != ' ' && ch != '-' && ch != '\'')
				return "name has a forbidden character";
		return null;
	}

	/// <summary>Null, or why a text a mind wrote is refused: plain sentences only.</summary>
	private static string TextError(string text, int min, int max)
	{
		text ??= "";
		if (text.Length < min || text.Length > max)
			return $"text must be {min}-{max} characters";
		foreach (char ch in text)
			if (!char.IsLetterOrDigit(ch) && " ,.'!?;:-".IndexOf(ch) < 0)
				return "text has a forbidden character";
		return null;
	}

	/// <summary>Checks a custom against the language's rules. Returns null when valid, else why
	/// it is rejected.</summary>
	public static string ValidateCustom(CustomDraft d)
	{
		if (d == null)
			return "empty";
		string error = NameError(d.Name, 28) ?? TextError(d.Text, 0, 160);
		if (error != null)
			return error;
		if (Array.IndexOf(CustomKinds, d.Kind) < 0)
			return $"unknown kind '{d.Kind}'";
		if (Array.IndexOf(ValueNames, d.About) < 0)
			return $"unknown value '{d.About}'";
		if (d.Effects == null || d.Effects.Count < 1 || d.Effects.Count > 2)
			return "1 or 2 effects";
		float power = 0f;
		bool price = false;
		foreach (var e in d.Effects)
		{
			if (e == null || !CustomBlocks.TryGetValue(e.Do ?? "", out var block))
				return $"unknown effect '{e?.Do}'";
			if (block.job && Array.IndexOf(WorkJobs, e.Job ?? "") < 0)
				return $"'{e.Do}' needs a job ({string.Join(", ", WorkJobs)})";
			if (!(Math.Abs(e.Amount) >= 1f) || Math.Abs(e.Amount) > block.max)
				return $"'{e.Do}' amount must be 1-{block.max}, given or taken";
			if (e.Do != "aggression")
			{
				power += e.Amount / block.max;
				price |= e.Amount < 0f;
			}
		}
		if (power > CustomBudget + 0.001f)
			return $"gives too much ({power:0.00} > {CustomBudget:0.0}): it needs a price";
		if (d.Kind == "taboo" && !price)
			return "a taboo forbids something: it needs a negative effect";
		return null;
	}

	/// <summary>A mind's answer (JSON in the custom language) for kingdom k. Returns "" when
	/// the custom is adopted, else why it was rejected.</summary>
	public string SubmitCustomJson(int k, string json, string mind = "model")
	{
		CustomDraft d;
		try
		{
			d = JsonSerializer.Deserialize<CustomDraft>(json);
		}
		catch (Exception e)
		{
			CustomsRejected++;
			return "not valid JSON: " + e.Message;
		}
		return SubmitCustom(k, d, mind) ?? "";
	}

	private string SubmitCustom(int k, CustomDraft d, string mind)
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive)
			return "no such kingdom";
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		string error = ValidateCustom(d);
		if (error == null && c.Customs.Exists(x => x.Name == d.Name.Trim()))
			error = "they already have this custom";
		if (error != null)
		{
			CustomsRejected++;
			return error;
		}
		var custom = new Custom
		{
			Name = d.Name.Trim(), Kind = d.Kind, About = d.About, Text = (d.Text ?? "").Trim(), Mind = mind, Year = Year(), Effects = d.Effects,
		};
		string people = Assets.Species[kingdom.Species].Name;
		// The oldest custom of its kind gives way.
		var same = c.Customs.FindAll(x => x.Kind == custom.Kind);
		string dropped = "";
		if (same.Count >= CustomsPerKind)
		{
			c.Customs.Remove(same[0]);
			dropped = $", and give up the {same[0].Name}";
		}
		c.Customs.Add(custom);
		int value = Array.IndexOf(ValueNames, custom.About);
		c.Values[value] = Math.Min(1f, c.Values[value] + 0.05f);
		CultureChanged(k);
		string what = custom.Kind == "law" ? "pass a law" : custom.Kind == "ritual" ? "take up a ritual" : "now hold a taboo";
		LogEvent($"the {people} of {kingdom.Name} {what}: the {custom.Name} ({DescribeCustom(custom)}){dropped}.", "culture");
		return null;
	}

	public static string DescribeCustom(Custom custom)
	{
		var parts = new List<string>();
		foreach (var e in custom.Effects)
		{
			string n = (e.Amount > 0f ? "+" : "-") + Math.Abs(e.Amount).ToString("0");
			parts.Add(e.Do switch
			{
				"work_speed" => $"{e.Job}s' speed {n}%",
				"yield" => $"{e.Job}s' yield {n}%",
				"attack" => $"{n}% attack",
				"defense" => $"{n}% defence",
				"food" => $"{n} food a month",
				"loyalty" => $"{n} loyalty",
				"faith" => $"{n} faith",
				"aggression" => e.Amount > 0f ? "more warlike" : "more peaceful",
				_ => e.Do,
			});
		}
		return string.Join(", ", parts);
	}

	// ------------------------------------------------------------------ the culture mind

	/// <summary>Every 2 s with the kingdoms: answers that came back are read; each kingdom's
	/// mind thinks of its culture once a year; faith and feelings move every season; the
	/// chronicler writes.</summary>
	private void CultureStep(float dt)
	{
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			var c = kingdom.Culture;
			if (!kingdom.Alive || kingdom.Capital < 0)
			{
				c.Asking = null;
				continue;
			}
			if (c.Asking != null)
			{
				if (!c.Asking.Take(Scheduler.Time, out string json, out string why))
					continue;
				c.Asking = null;
				string error = json == null ? why : c.AskingKind == "myth" ? SubmitMythJson(k, json, c.AskingMemory, "model") : SubmitCustomJson(k, json, "model");
				LastModelAnswer = json ?? "";
				LastModelError = error ?? "";
				if (string.IsNullOrEmpty(error))
					ModelAnswers++;
				else
				{
					ModelFailures++;
					WriteProcedural(k, c.AskingKind, c.AskingMemory);
				}
				continue;
			}
			if (Scheduler.Time >= c.NextThought && Villages[kingdom.Capital].Population >= 10)
				ThinkCulture(k, force: false);
		}
		if (Scheduler.Time >= _nextCultureSeason)
		{
			_nextCultureSeason = Scheduler.Time + YearSeconds / 4f;
			for (int k = 0; k < Kingdoms.Count; k++)
				if (Kingdoms[k].Alive)
					FaithSeason(k);
		}
		FaithsStep();
		ChronicleStep();
	}

	/// <summary>Kingdom k's mind thinks of its culture: a myth about what it lived through when
	/// something worth telling happened, else a new custom. The model in the background, or the
	/// procedural writer now.</summary>
	private void ThinkCulture(int k, bool force, string want = null)
	{
		var c = Kingdoms[k].Culture;
		c.NextThought = Scheduler.Time + YearSeconds * (0.8 + 0.4 * _cultureRng.NextDouble());
		var memory = HeaviestMemory(c);
		string kind = want ?? (memory != null && _cultureRng.NextDouble() < 0.6 ? "myth" : "custom");
		if (kind == "myth" && memory == null)
			kind = "custom";
		if (!force)
		{
			var task = kind == "myth"
				? AskAnyMind(MythPrompt(k, memory), MythGrammar(), MythSchema(), "You tell the myths of a people in a world simulation. Answer with one JSON record.")
				: AskAnyMind(CulturePrompt(k), CultureGrammar(), CultureSchema(), "You write the customs of a people in a world simulation. Answer with one JSON record.");
			if (task != null)
			{
				c.Asking = new Question { Pending = task, Asked = Scheduler.Time };
				c.AskingKind = kind;
				c.AskingMemory = memory;
				return;
			}
		}
		WriteProcedural(k, kind, memory);
	}

	private void WriteProcedural(int k, string kind, Memory memory)
	{
		if (kind == "myth" && memory != null)
		{
			SubmitMyth(k, ProceduralMyth(k, memory), memory, "procedural");
			return;
		}
		// The procedural writer's customs are valid by construction; a rejection is a bug.
		string error = SubmitCustom(k, ProceduralCustom(k), "procedural");
		if (error != null && error != "they already have this custom")
			Godot.GD.PushWarning($"procedural custom rejected: {error}");
	}

	private static readonly Dictionary<string, string[]> CustomNouns = new()
	{
		["law"] = new[] { "Law", "Oath", "Code", "Edict", "Charter" },
		["ritual"] = new[] { "Feast", "Dance", "Vigil", "Rite", "Procession" },
		["taboo"] = new[] { "Ban", "Silence", "Fast", "Forbidding" },
	};

	/// <summary>What each kind of custom says, by the value it is about.</summary>
	private static readonly Dictionary<string, string[]> CustomTexts = new()
	{
		["law"] = new[]
		{
			"Every grown hand owes a season to the army.", "A broken oath is paid in exile.", "No tree is felled without planting another.",
			"A tenth of all trade goes to the stores.", "The old teach the young before the harvest.", "The shrine is served before the table.",
			"No one is bound to a master.", "The ways of the founders are not to be changed.",
		},
		["ritual"] = new[]
		{
			"Warriors dance before the march.", "The dead are named aloud each spring.", "The first fruit is given back to the soil.",
			"Gifts are traded at midsummer.", "Riddles are told through the longest night.", "Fires are lit for the gods at dusk.",
			"For one day a year no one commands.", "The founding is played out each year.",
		},
		["taboo"] = new[]
		{
			"It is forbidden to turn one's back on a foe.", "Lying under one's own roof is forbidden.", "Hunting the young is forbidden.",
			"Hoarding in a lean year is forbidden.", "Burning anything written is forbidden.", "Work on holy days is forbidden.",
			"Chains are forbidden.", "Foreign ways are forbidden.",
		},
	};

	/// <summary>A custom from what the kingdom values: a gain that fits the value, and a price
	/// when the gain is large (always for a taboo).</summary>
	private CustomDraft ProceduralCustom(int k)
	{
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		var rng = _cultureRng;
		// A value, the dearer the likelier.
		float total = 0f;
		foreach (float v in c.Values)
			total += v * v;
		double roll = rng.NextDouble() * total;
		int value = 0;
		for (; value < c.Values.Length - 1; value++)
		{
			roll -= c.Values[value] * c.Values[value];
			if (roll <= 0)
				break;
		}
		string kind = CustomKinds[rng.Next(CustomKinds.Length)];
		string job = BusiestJob(kingdom.Capital);
		var gain = ValueNames[value] switch
		{
			"war" => new EffectDraft { Do = "attack" },
			"honour" => new EffectDraft { Do = rng.NextDouble() < 0.5 ? "defense" : "loyalty" },
			"nature" => rng.NextDouble() < 0.5 ? new EffectDraft { Do = "food" } : new EffectDraft { Do = "yield", Job = "gatherer" },
			"wealth" => new EffectDraft { Do = "yield", Job = rng.NextDouble() < 0.5 ? "miner" : job },
			"knowledge" => new EffectDraft { Do = "work_speed", Job = rng.NextDouble() < 0.5 ? "blacksmith" : "builder" },
			"faith" => new EffectDraft { Do = "faith" },
			"freedom" => new EffectDraft { Do = "work_speed", Job = job },
			_ => new EffectDraft { Do = "loyalty" },
		};
		float cap = CustomBlocks[gain.Do].max;
		gain.Amount = Math.Max(1f, MathF.Round(cap * (0.4f + 0.6f * (float)rng.NextDouble())));
		var effects = new List<EffectDraft> { gain };
		float over = gain.Amount / cap - CustomBudget;
		if (over > 0f || kind == "taboo")
		{
			// The price: something else, taken.
			string[] prices = { "food", "loyalty", "attack", "defense", "faith", "yield", "work_speed" };
			string pay = prices[rng.Next(prices.Length)];
			while (pay == gain.Do)
				pay = prices[rng.Next(prices.Length)];
			float payCap = CustomBlocks[pay].max;
			float amount = Math.Max(1f, MathF.Ceiling(payCap * Math.Max(over, 0.1f + 0.2f * (float)rng.NextDouble())));
			effects.Add(new EffectDraft { Do = pay, Job = CustomBlocks[pay].job ? WorkJobs[rng.Next(WorkJobs.Length)] : "", Amount = -Math.Min(amount, payCap) });
		}
		else if (ValueNames[value] == "war" || ValueNames[value] == "freedom" && rng.NextDouble() < 0.4)
			effects.Add(new EffectDraft { Do = "aggression", Amount = ValueNames[value] == "war" ? 8f : -8f });
		string name = _languages[kingdom.Species].PlaceName() + " " + CustomNouns[kind][rng.Next(CustomNouns[kind].Length)];
		if (name.Length > 28)
			name = name[..28].TrimEnd();
		return new CustomDraft { Name = name, Kind = kind, About = ValueNames[value], Text = CustomTexts[kind][value], Effects = effects };
	}

	// ------------------------------------------------------------------ the local model

	/// <summary>The kingdom's culture for the model, and the rules of the custom language.</summary>
	public string CulturePrompt(int k)
	{
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		var sb = new StringBuilder();
		sb.Append($"You are the collective mind of the {Assets.Species[kingdom.Species].Name} of the kingdom of {kingdom.Name}, a {StructureOf(k)}, in year {Year()} of their world.\n");
		sb.Append("What they value, from 0 to 1: ");
		for (int n = 0; n < ValueNames.Length; n++)
			sb.Append($"{ValueNames[n]} {c.Values[n]:0.0}{(n < ValueNames.Length - 1 ? ", " : ".\n")}");
		sb.Append(Wars.Exists(w => w.A == k || w.B == k) ? "They are at war. " : "They are at peace. ");
		sb.Append($"Their faith is {c.Faith:0} of 100. They {NatureOf(c)}.\n");
		if (c.Customs.Count > 0)
		{
			sb.Append("Their customs:\n");
			foreach (var custom in c.Customs)
				sb.Append($"- {custom.Name} ({custom.Kind}: {DescribeCustom(custom)})\n");
		}
		sb.Append("Write ONE new custom for them: a law, a ritual or a taboo, about one of their values. ");
		sb.Append("Effects (\"do\"), each with a whole amount, positive (given) or negative (taken): ");
		foreach (var (name, block) in CustomBlocks)
			sb.Append($"{name} (up to {block.max}{(block.job ? ", with a job" : "")}); ");
		sb.Append($"jobs: {string.Join(", ", WorkJobs)}. 1 or 2 effects. The sum of amount/max must stay under {CustomBudget:0.0}: a strong gain needs a price, ");
		sb.Append("and a taboo always takes something. \"text\" says the custom in one plain sentence. Name in their language's spirit, 2-28 letters. Answer with the JSON record only.\n");
		return sb.ToString();
	}

	/// <summary>The custom language as a GBNF grammar (what the built-in model samples under).</summary>
	public string CultureGrammar()
	{
		static string Alt(IEnumerable<string> words)
		{
			var parts = new List<string>();
			foreach (var w in words)
				parts.Add($"\"\\\"{w}\\\"\"");
			return string.Join(" | ", parts);
		}
		var lines = new List<string>
		{
			"root ::= \"{\" ws \"\\\"name\\\":\" ws name \",\" ws \"\\\"kind\\\":\" ws kind \",\" ws \"\\\"about\\\":\" ws about \",\" ws \"\\\"text\\\":\" ws text \",\" ws \"\\\"effects\\\":\" ws \"[\" ws eff (ws \",\" ws eff)? ws \"]\" ws \"}\"",
			$"name ::= {LocalModel.Name(27)}",
			$"text ::= {LocalModel.Text(140)}",
			$"kind ::= {Alt(CustomKinds)}",
			$"about ::= {Alt(ValueNames)}",
			$"job ::= {Alt(WorkJobs)}",
			"ws ::= [ ]?",
		};
		var effects = new List<string>();
		foreach (var (name, block) in CustomBlocks)
		{
			string rule = "do-" + name.Replace('_', '-');
			effects.Add(rule);
			lines.Add($"{rule} ::= \"{{\" ws \"\\\"do\\\":\" ws \"\\\"{name}\\\"\" \",\" ws " + (block.job ? "\"\\\"job\\\":\" ws job \",\" ws " : "")
				+ $"\"\\\"amount\\\":\" ws \"-\"? ({LocalModel.Whole((int)block.max)}) ws \"}}\"");
		}
		lines.Insert(1, $"eff ::= {string.Join(" | ", effects)}");
		return string.Join("\n", lines) + "\n";
	}

	/// <summary>The custom language as a JSON schema (what model servers are sent).</summary>
	public string CultureSchema()
	{
		var effects = new List<object>();
		foreach (var (name, block) in CustomBlocks)
		{
			var props = new Dictionary<string, object>
			{
				["do"] = new Dictionary<string, object> { ["enum"] = new[] { name } },
				["amount"] = new Dictionary<string, object> { ["type"] = "integer", ["minimum"] = -(int)block.max, ["maximum"] = (int)block.max },
			};
			if (block.job)
				props["job"] = new Dictionary<string, object> { ["enum"] = WorkJobs };
			effects.Add(new Dictionary<string, object>
			{
				["type"] = "object", ["properties"] = props, ["required"] = block.job ? new[] { "do", "job", "amount" } : new[] { "do", "amount" },
			});
		}
		return JsonSerializer.Serialize(new Dictionary<string, object>
		{
			["type"] = "object",
			["properties"] = new Dictionary<string, object>
			{
				["name"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 28 },
				["kind"] = new Dictionary<string, object> { ["enum"] = CustomKinds },
				["about"] = new Dictionary<string, object> { ["enum"] = ValueNames },
				["text"] = new Dictionary<string, object> { ["type"] = "string", ["maxLength"] = 160 },
				["effects"] = new Dictionary<string, object>
				{
					["type"] = "array", ["minItems"] = 1, ["maxItems"] = 2, ["items"] = new Dictionary<string, object> { ["anyOf"] = effects },
				},
			},
			["required"] = new[] { "name", "kind", "about", "text", "effects" },
		});
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>Living kingdoms' cultures: values, structure, style, customs, faith, gods, myths
	/// and what they make of the player.</summary>
	public Godot.Collections.Array CultureTable()
	{
		var list = new Godot.Collections.Array();
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive)
				continue;
			var c = kingdom.Culture;
			var values = new Godot.Collections.Dictionary();
			for (int n = 0; n < ValueNames.Length; n++)
				values[ValueNames[n]] = c.Values[n];
			var customs = new Godot.Collections.Array();
			foreach (var custom in c.Customs)
				customs.Add(new Godot.Collections.Dictionary
				{
					["name"] = custom.Name, ["kind"] = custom.Kind, ["about"] = custom.About, ["text"] = custom.Text,
					["effects"] = DescribeCustom(custom), ["year"] = custom.Year, ["mind"] = custom.Mind,
				});
			var gods = new Godot.Collections.Array();
			foreach (var g in c.Gods)
				gods.Add(new Godot.Collections.Dictionary
				{
					["name"] = g.Name, ["domain"] = g.Domain, ["temper"] = g.Temper, ["year"] = g.Year, ["player"] = g.Player,
				});
			var myths = new Godot.Collections.Array();
			foreach (var m in c.Myths)
				myths.Add(new Godot.Collections.Dictionary
				{
					["title"] = m.Title, ["text"] = m.Text, ["god"] = m.God, ["year"] = m.Year, ["source"] = m.Source, ["mind"] = m.Mind,
				});
			list.Add(new Godot.Collections.Dictionary
			{
				["index"] = k, ["kingdom"] = kingdom.Name, ["people"] = Assets.Species[kingdom.Species].Name, ["values"] = values,
				["structure"] = StructureOf(k), ["nature"] = NatureOf(c), ["aggression"] = Aggression(k),
				["roof"] = Roofs[c.Roof], ["walls"] = Walls[c.Wall], ["ornament"] = Ornaments[c.Ornament],
				["customs"] = customs, ["religion"] = c.Religion, ["creed"] = c.Creed, ["faith"] = c.Faith, ["gods"] = gods, ["myths"] = myths,
				["stance"] = c.Stance, ["god_name"] = c.GodName, ["gratitude"] = c.Gratitude, ["dread"] = c.Dread,
			});
		}
		return list;
	}

	/// <summary>Makes a kingdom's mind write a custom now with the procedural writer (tests).</summary>
	public void CultureNow(int k) => ThinkCulture(k, force: true, want: "custom");

	/// <summary>Makes a kingdom's mind tell a myth now, about the heaviest thing it remembers,
	/// with the procedural writer (tests). False when it remembers nothing worth a myth.</summary>
	public bool MythNow(int k)
	{
		if (HeaviestMemory(Kingdoms[k].Culture) == null)
			return false;
		ThinkCulture(k, force: true, want: "myth");
		return true;
	}

	/// <summary>Makes a kingdom's mind think of its culture the usual way: the model if there is
	/// one (the answer comes later), else the procedural writer. `want`: "custom" or "myth".</summary>
	public void AskCultureMind(int k, string want) => ThinkCulture(k, force: false, want: want);
}
