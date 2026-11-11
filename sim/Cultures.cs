using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// Cultures (0.6, docs/CULTURES.md). Every kingdom lives by a culture: values (war, honour,
/// nature, wealth, knowledge, faith, freedom, tradition), a social structure, a way with nature,
/// an architecture, and customs its mind writes in the culture language: laws, rituals and
/// taboos, JSON records the engine validates before they exist, each with effect blocks (loyalty,
/// faith, fertility, food, attack, defence, warlike, peaceful).
///
/// Cultures drift with what their people live (wars, hunger, wealth, temples, neighbours, the god
/// in the sky), abandon old customs for new ones, and split when a village breaks away: the new
/// kingdom's culture is a child of the old one. Heroes and great deeds become their legends.
/// </summary>
public partial class Simulation
{
	public static readonly string[] CultureValues = { "war", "honour", "nature", "wealth", "knowledge", "faith", "freedom", "tradition" };
	public static readonly string[] CustomKinds = { "law", "ritual", "taboo" };
	/// <summary>When a ritual is held.</summary>
	public static readonly string[] Occasions = { "birth", "coming_of_age", "marriage", "funeral", "harvest", "midwinter", "battle", "victory" };

	/// <summary>The blocks of the culture language: what a custom can do, for which kinds, and the
	/// most one custom can do.</summary>
	public static readonly Dictionary<string, (string[] kinds, float max)> CustomBlocks = new()
	{
		["loyalty"] = (new[] { "law", "ritual", "taboo" }, 10f),
		["faith"] = (new[] { "law", "ritual", "taboo" }, 10f),
		["fertility"] = (new[] { "law", "ritual" }, 25f),
		["food"] = (new[] { "law", "ritual", "taboo" }, 4f),
		["attack"] = (new[] { "law", "ritual" }, 15f),
		["defense"] = (new[] { "law", "ritual" }, 15f),
		["warlike"] = (new[] { "law", "ritual" }, 30f),
		["peaceful"] = (new[] { "law", "ritual", "taboo" }, 30f),
	};
	/// <summary>A custom's power (sum of amount / cap over its effects) stays within this.</summary>
	public const float CustomBudget = 1.2f;
	/// <summary>Customs a culture keeps of each kind; a new one replaces the oldest.</summary>
	public static readonly Dictionary<string, int> CustomLimit = new() { ["law"] = 4, ["ritual"] = 4, ["taboo"] = 3 };
	/// <summary>A culture's mind writes a custom about every three years.</summary>
	public const float CultureSeconds = YearSeconds * 3f;

	/// <summary>A custom as written by a mind (the culture language), before validation.</summary>
	public sealed class CustomDraft
	{
		[JsonPropertyName("kind")] public string Kind { get; set; } = "";
		[JsonPropertyName("name")] public string Name { get; set; } = "";
		[JsonPropertyName("text")] public string Text { get; set; } = "";
		[JsonPropertyName("occasion")] public string Occasion { get; set; } = "";
		[JsonPropertyName("effects")] public List<EffectDraft> Effects { get; set; } = new();
	}

	public sealed class Custom
	{
		public string Kind, Name, Text, Occasion, Mind;
		public int Year;
		public List<EffectDraft> Effects = new();
	}

	public sealed class Culture
	{
		public int Id;
		public string Name;
		public int Species;
		public int Parent = -1;
		public int Founded;
		public float[] Values = new float[CultureValues.Length];
		/// <summary>tribe, chiefdom, monarchy, theocracy, council.</summary>
		public string Society = "tribe";
		/// <summary>exploit, coexist, worship.</summary>
		public string NatureWay = "coexist";
		public string Roof, Wall, Ornament;
		public readonly List<Custom> Customs = new();
		/// <summary>Songs and stories of real deeds (heroes, conquests, disasters).</summary>
		public readonly List<string> Legends = new();
		public double NextThought;
		public string Top = "";
		/// <summary>Sum of each effect over its customs (refreshed when they change).</summary>
		public readonly Dictionary<string, float> Mods = new();
	}

	public readonly List<Culture> Cultures = new();
	private double _nextCultureYear;

	private static readonly string[] Roofs = { "pointed", "flat", "domed", "thatched", "tiered", "turf", "hide" };
	private static readonly string[] Walls = { "timber", "stone", "mud brick", "woven reed", "living wood", "hewn log", "white plaster" };
	private static readonly string[] Ornaments = { "carved posts", "painted banners", "bones and antlers", "bright tiles", "hanging flowers", "iron spikes", "carved faces", "shell strings" };

	private void SetupCultures()
	{
		Cultures.Clear();
		_nextCultureYear = 0;
		_thoughts.Clear();
	}

	private float Val(Culture c, string value) => c.Values[Array.IndexOf(CultureValues, value)];

	private void AddVal(Culture c, string value, float by)
	{
		int i = Array.IndexOf(CultureValues, value);
		c.Values[i] = Math.Clamp(c.Values[i] + by, 0.02f, 0.98f);
	}

	/// <summary>The `n` values a culture holds highest, as words.</summary>
	public static string TopValues(Culture c, int n)
	{
		var order = new List<int>();
		for (int i = 0; i < CultureValues.Length; i++)
			order.Add(i);
		order.Sort((a, b) => c.Values[b].CompareTo(c.Values[a]));
		var words = new List<string>();
		for (int i = 0; i < n && i < order.Count; i++)
			words.Add(CultureValues[order[i]]);
		return string.Join(", ", words);
	}

	// ------------------------------------------------------------------ birth of a culture

	/// <summary>A new culture for a people: drawn from its temperament and the seed, or from the
	/// culture it parts from (a rebellion: its values drift, half its customs are kept).</summary>
	private int CreateCulture(int species, int parent)
	{
		var race = Assets.Species[species].Race;
		var lang = _languages[species];
		float R() => (float)_rng.NextDouble();
		var c = new Culture { Id = Cultures.Count, Species = species, Parent = parent, Founded = Year(), Name = lang.PlaceName() };
		if (parent >= 0)
		{
			var p = Cultures[parent];
			for (int i = 0; i < c.Values.Length; i++)
				c.Values[i] = Math.Clamp(p.Values[i] + (R() * 2f - 1f) * 0.18f, 0.02f, 0.98f);
			// Rebels value freedom more than the ways they leave.
			AddVal(c, "freedom", 0.1f);
			AddVal(c, "tradition", -0.08f);
			c.Roof = R() < 0.5 ? p.Roof : Roofs[_rng.Next(Roofs.Length)];
			c.Wall = p.Wall;
			c.Ornament = R() < 0.5 ? p.Ornament : Ornaments[_rng.Next(Ornaments.Length)];
			foreach (var old in p.Customs)
				if (R() < 0.5)
					c.Customs.Add(new Custom { Kind = old.Kind, Name = old.Name, Text = old.Text, Occasion = old.Occasion, Mind = old.Mind, Year = old.Year, Effects = old.Effects });
			c.Legends.AddRange(p.Legends);
		}
		else
		{
			for (int i = 0; i < c.Values.Length; i++)
				c.Values[i] = 0.15f + 0.7f * R();
			float aggression = race?.Temper("aggression") ?? 0.5f;
			float curiosity = race?.Temper("curiosity") ?? 0.5f;
			float settled = race?.Temper("settled") ?? 0.5f;
			c.Values[0] = Math.Clamp(0.6f * aggression + 0.4f * R(), 0.02f, 0.98f);
			c.Values[4] = Math.Clamp(0.6f * curiosity + 0.4f * R(), 0.02f, 0.98f);
			c.Values[7] = Math.Clamp(0.6f * settled + 0.4f * R(), 0.02f, 0.98f);
			c.Values[6] = Math.Clamp(0.6f * (1f - settled) + 0.4f * R(), 0.02f, 0.98f);
			// Peoples of the woods and the waters hold nature higher.
			if (race != null && race.Biomes.Exists(b => b.Contains("Forest") || b.Contains("Jungle") || b.Contains("Swamp") || b.Contains("Mushroom")))
				AddVal(c, "nature", 0.15f);
			c.Roof = Roofs[_rng.Next(Roofs.Length)];
			c.Wall = Val(c, "nature") > 0.7f ? "living wood" : Val(c, "wealth") > 0.7f ? "stone" : Walls[_rng.Next(Walls.Length)];
			c.Ornament = Val(c, "war") > 0.7f ? "iron spikes" : Ornaments[_rng.Next(Ornaments.Length)];
		}
		c.NatureWay = NatureWayOf(c);
		c.Top = TopValues(c, 1);
		c.NextThought = Scheduler.Time + CultureSeconds * (0.3 + 0.7 * R());
		Cultures.Add(c);
		RefreshCultureMods(c);
		return c.Id;
	}

	private string NatureWayOf(Culture c) => Val(c, "nature") > 0.66f ? "worship" : Val(c, "nature") < 0.34f || Val(c, "wealth") > 0.75f ? "exploit" : "coexist";

	/// <summary>The social structure that follows a culture's values and its kingdom's size.</summary>
	private string SocietyOf(Culture c, int rank)
	{
		if (Val(c, "faith") > 0.72f && Val(c, "faith") >= Val(c, "war"))
			return "theocracy";
		if (Val(c, "freedom") > 0.7f && Val(c, "tradition") < 0.5f)
			return "council";
		return rank <= 0 ? "tribe" : rank == 1 ? "chiefdom" : "monarchy";
	}

	// ------------------------------------------------------------------ the culture language

	/// <summary>Checks a custom against the culture language's rules. Returns null when valid,
	/// else why it is rejected.</summary>
	public static string ValidateCustom(CustomDraft d)
	{
		if (d == null)
			return "empty";
		if (Array.IndexOf(CustomKinds, d.Kind) < 0)
			return $"unknown kind '{d.Kind}'";
		if (!PlainName(d.Name, 32))
			return "name must be 2-32 letters, spaces, hyphens or apostrophes";
		if (!PlainText(d.Text ?? "", 160))
			return "text must be at most 160 plain characters";
		if (d.Kind == "ritual" && Array.IndexOf(Occasions, d.Occasion ?? "") < 0)
			return $"a ritual needs an occasion ({string.Join(", ", Occasions)})";
		if (d.Effects == null || d.Effects.Count < 1 || d.Effects.Count > 2)
			return "1 or 2 effects";
		float power = 0f;
		foreach (var e in d.Effects)
		{
			if (!CustomBlocks.TryGetValue(e.Do ?? "", out var block))
				return $"unknown effect '{e.Do}'";
			if (Array.IndexOf(block.kinds, d.Kind) < 0)
				return $"a {d.Kind} cannot '{e.Do}'";
			if (!(e.Amount > 0f) || e.Amount > block.max)
				return $"'{e.Do}' amount must be in 0-{block.max}";
			power += e.Amount / block.max;
		}
		if (d.Effects.Exists(e => e.Do == "warlike") && d.Effects.Exists(e => e.Do == "peaceful"))
			return "warlike and peaceful at once";
		if (power > CustomBudget + 1e-4f)
			return $"too powerful ({power:0.00} > {CustomBudget:0.0})";
		return null;
	}

	/// <summary>A mind's answer (JSON in the culture language) for kingdom k's culture: parsed,
	/// validated and, if it holds, adopted. Returns null or why it was rejected.</summary>
	public string SubmitCustomJson(int k, string json, string mind = "model")
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive || Kingdoms[k].Culture < 0)
			return "no such kingdom";
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
		return AdoptCustom(Kingdoms[k].Culture, d, mind, k);
	}

	public int CustomsRejected { get; private set; }

	/// <summary>A culture adopts a custom; when it already keeps as many of that kind as it may,
	/// the oldest is abandoned. Returns null or why it was rejected.</summary>
	private string AdoptCustom(int ci, CustomDraft d, string mind, int k)
	{
		string error = ValidateCustom(d);
		if (error != null)
		{
			CustomsRejected++;
			return error;
		}
		var c = Cultures[ci];
		string name = d.Name.Trim();
		// (not a broken rule: the procedural mind sometimes draws a name twice)
		if (c.Customs.Exists(x => x.Name == name))
			return "they already keep the " + name;
		var custom = new Custom
		{
			Kind = d.Kind, Name = name, Text = (d.Text ?? "").Trim(), Occasion = d.Kind == "ritual" ? d.Occasion : "",
			Mind = mind, Year = Year(), Effects = d.Effects,
		};
		string who = k >= 0 ? $"the {Assets.Species[c.Species].Name} of {Kingdoms[k].Name}" : $"the {c.Name} ways";
		int kept = c.Customs.FindAll(x => x.Kind == d.Kind).Count;
		if (kept >= CustomLimit[d.Kind])
		{
			var old = c.Customs.Find(x => x.Kind == d.Kind);
			c.Customs.Remove(old);
			LogEvent($"{who} abandon the {old.Name} for a new {d.Kind}, the {custom.Name}: {custom.Text}", "culture");
		}
		else
			LogEvent($"{who} adopt a {d.Kind}, the {custom.Name}: {custom.Text}", "culture");
		c.Customs.Add(custom);
		RefreshCultureMods(c);
		return null;
	}

	/// <summary>The sum of each effect over a culture's customs; the villages that live by it
	/// count them again.</summary>
	private void RefreshCultureMods(Culture c)
	{
		c.Mods.Clear();
		foreach (var custom in c.Customs)
			foreach (var e in custom.Effects)
				c.Mods[e.Do] = (c.Mods.TryGetValue(e.Do, out float m) ? m : 0f) + e.Amount;
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom >= 0 && Kingdoms[v.Kingdom].Culture == c.Id)
				v.ModsDirty = true;
	}

	private float CultureMod(int k, string effect) =>
		k >= 0 && Kingdoms[k].Culture >= 0 && Cultures[Kingdoms[k].Culture].Mods.TryGetValue(effect, out float m) ? m : 0f;

	/// <summary>A village's bonuses from the customs of its kingdom's culture (with RefreshMods).</summary>
	private void ApplyCulture(Village village)
	{
		int k = village.Kingdom;
		village.Fertility = Math.Min(CultureMod(k, "fertility"), 50f);
		village.FaithBonus = Math.Min(CultureMod(k, "faith"), 30f);
		village.LoyaltyBonus += Math.Min(CultureMod(k, "loyalty"), 25f);
		village.FoodBonus += Math.Min(CultureMod(k, "food"), 10f);
		village.Attack += CultureMod(k, "attack");
		village.Defense += CultureMod(k, "defense");
	}

	/// <summary>How much a kingdom's culture (and how it feels about the god in the sky) pushes it
	/// to war: a factor on the chance its ruler plots one.</summary>
	private float WarLean(int k)
	{
		float lean = 1f + (CultureMod(k, "warlike") - CultureMod(k, "peaceful")) / 100f;
		if (Kingdoms[k].Culture >= 0)
			lean *= 0.6f + 0.8f * Val(Cultures[Kingdoms[k].Culture], "war");
		// They dare not anger the sky; or they defy it.
		lean *= 1f - Kingdoms[k].Fear / 160f + Kingdoms[k].Hate / 220f;
		return Math.Clamp(lean, 0.1f, 2.5f);
	}

	// ------------------------------------------------------------------ once a year

	/// <summary>Every 2 s with the kingdoms: once a year cultures drift; their minds write customs.</summary>
	private void CultureStep()
	{
		ThoughtsStep();
		if (Scheduler.Time < _nextCultureYear || !Law("cultures"))
			return;
		_nextCultureYear = Scheduler.Time + YearSeconds;
		for (int k = 0; k < Kingdoms.Count; k++)
			if (Kingdoms[k].Alive && Kingdoms[k].Culture >= 0 && Kingdoms[k].Capital >= 0)
				Drift(k);
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive || kingdom.Culture < 0 || kingdom.Capital < 0)
				continue;
			var c = Cultures[kingdom.Culture];
			if (Scheduler.Time >= c.NextThought && Villages[kingdom.Capital].Population >= 8)
				ThinkCulture(k, force: false);
		}
	}

	/// <summary>A culture's values move with what its kingdom lives: war, peace, hunger, wealth,
	/// temples, what it knows, its neighbours' ways and the god in the sky.</summary>
	private void Drift(int k)
	{
		var kingdom = Kingdoms[k];
		var c = Cultures[kingdom.Culture];
		var capital = Villages[kingdom.Capital];
		const float d = 0.03f;
		bool atWar = Wars.Exists(w => w.A == k || w.B == k);
		if (atWar)
		{
			AddVal(c, "war", d);
			AddVal(c, "honour", d / 2f);
			AddVal(c, "freedom", -d / 2f);
		}
		else
			AddVal(c, "war", -d / 3f);
		if (capital.Food < capital.Population * 2f)
		{
			AddVal(c, "faith", d / 2f);
			AddVal(c, "nature", d / 2f);
		}
		if (capital.Gold > 40f)
			AddVal(c, "wealth", d / 2f);
		if (capital.Known.Count >= 4)
			AddVal(c, "knowledge", d / 2f);
		if (_tTemple >= 0 && CountOf(kingdom.Capital, _tTemple, true) > 0)
			AddVal(c, "faith", d / 2f);
		if (kingdom.Love > 40f)
			AddVal(c, "faith", d);
		if (kingdom.Fear > 40f)
			AddVal(c, "tradition", d / 2f);
		if (kingdom.Hate > 40f)
			AddVal(c, "freedom", d / 2f);
		// Allies and trade partners rub off on each other.
		for (int o = 0; o < Kingdoms.Count; o++)
		{
			if (o == k || !Kingdoms[o].Alive || Kingdoms[o].Culture < 0 || Kingdoms[o].Culture == kingdom.Culture)
				continue;
			bool partner = kingdom.Allies.Contains(o) || _trade.Exists(r => KingdomOf(r.A) == k && KingdomOf(r.B) == o || KingdomOf(r.A) == o && KingdomOf(r.B) == k);
			if (!partner)
				continue;
			var other = Cultures[Kingdoms[o].Culture];
			for (int i = 0; i < c.Values.Length; i++)
				c.Values[i] += (other.Values[i] - c.Values[i]) * 0.05f;
		}
		for (int i = 0; i < c.Values.Length; i++)
			c.Values[i] = Math.Clamp(c.Values[i] + ((float)_rng.NextDouble() * 2f - 1f) * 0.01f, 0.02f, 0.98f);

		string people = Assets.Species[c.Species].Name;
		string top = TopValues(c, 1);
		if (top != c.Top && Val(c, top) > Val(c, c.Top) + 0.05f)
		{
			c.Top = top;
			LogEvent($"the {people} of {kingdom.Name} now hold {top} above all.", "culture");
		}
		int rank = 0;
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == k)
				rank = Math.Max(rank, v.Rank);
		string society = SocietyOf(c, rank);
		if (society != c.Society)
		{
			bool first = c.Society == "tribe" && society == "chiefdom";
			c.Society = society;
			if (!first)
				LogEvent($"the {people} of {kingdom.Name} become a {society}.", "culture");
		}
		string way = NatureWayOf(c);
		if (way != c.NatureWay)
		{
			c.NatureWay = way;
			LogEvent($"the {people} of {kingdom.Name} now {way} nature.", "culture");
		}
	}

	/// <summary>Kingdom k's culture writes a custom: asks the model in the background, or the
	/// procedural mind now.</summary>
	private void ThinkCulture(int k, bool force)
	{
		int ci = Kingdoms[k].Culture;
		var c = Cultures[ci];
		c.NextThought = Scheduler.Time + CultureSeconds * (0.8 + 0.4 * _rng.NextDouble());
		void Procedural()
		{
			if (k < Kingdoms.Count && Kingdoms[k].Alive && Kingdoms[k].Culture == ci)
			{
				string error = AdoptCustom(ci, ProceduralCustom(k), "procedural", k);
				if (error != null && !error.StartsWith("they already"))
					Godot.GD.PushWarning($"procedural custom rejected: {error}");
			}
		}
		if (force)
		{
			Procedural();
			return;
		}
		Ponder("custom", CulturePrompt(k), CustomGrammar(), CustomSchema(),
			"You shape the culture of a people in a world simulation. Answer with one JSON record.", 300,
			json => k < Kingdoms.Count && Kingdoms[k].Alive && Kingdoms[k].Culture == ci ? SubmitCustomJson(k, json, "model") : null,
			Procedural);
	}

	// ------------------------------------------------------------------ the procedural mind

	private static readonly Dictionary<string, string[]> LawNouns = new()
	{
		["loyalty"] = new[] { "Oath", "Crown", "Bond" }, ["faith"] = new[] { "Altar", "Offering", "Prayer" },
		["fertility"] = new[] { "Hearth", "Cradle", "Family" }, ["food"] = new[] { "Granary", "Tithe", "Share" },
		["attack"] = new[] { "Spear", "Drill", "Arms" }, ["defense"] = new[] { "Shield", "Wall", "Watch" },
		["warlike"] = new[] { "Blade", "Banner", "Glory" }, ["peaceful"] = new[] { "Open Hand", "Truce", "Guest" },
	};

	private static readonly Dictionary<string, string> LawTexts = new()
	{
		["loyalty"] = "Every grown one of the {0} swears an oath to the throne.",
		["faith"] = "The first fruits of every season belong to the gods.",
		["fertility"] = "Families with many children are given land and grain.",
		["food"] = "A tenth of every harvest goes to the common granary.",
		["attack"] = "All grown {0} train with the spear each spring.",
		["defense"] = "Every village keeps a wall and a watch at night.",
		["warlike"] = "Glory goes to those who bring back enemy banners.",
		["peaceful"] = "No blade is drawn against a neighbour without the elders' word.",
	};

	private static readonly Dictionary<string, string> RitualActs = new()
	{
		["loyalty"] = "gather around their ruler and renew their vows",
		["faith"] = "light fires and sing to the gods",
		["fertility"] = "dance until dawn and bless the young",
		["food"] = "share bread with every household",
		["attack"] = "paint their faces red and beat the drums",
		["defense"] = "walk the borders singing to keep the land safe",
		["warlike"] = "swear to avenge their dead",
		["peaceful"] = "exchange gifts with strangers",
	};

	private static readonly Dictionary<string, string> OccasionWords = new()
	{
		["birth"] = "each birth", ["coming_of_age"] = "each coming of age", ["marriage"] = "every marriage",
		["funeral"] = "every funeral", ["harvest"] = "the harvest", ["midwinter"] = "midwinter",
		["battle"] = "the eve of battle", ["victory"] = "every victory",
	};

	private static readonly string[] RitualNouns = { "Feast", "Vigil", "Dance", "Rite", "Fires", "Song", "Procession" };
	private static readonly string[] TabooPlaces = { "the deep forest", "the high peaks", "the burned lands", "the old ruins", "the dark water", "the graves" };
	private static readonly string[] TabooFoods = { "red meat", "fish", "mushrooms", "eggs", "honey" };
	private static readonly string[] TabooActs = { "spill blood at home", "cut a living tree in spring", "speak the names of the dead", "sleep under the open sky", "count the stars" };

	/// <summary>A custom the culture needs, from its kingdom's situation and its values: laws of
	/// loyalty when restless, rituals of war at war, of harvest when hungry, taboos when faith is
	/// high, fertility when the people are few; else what its values favour.</summary>
	private CustomDraft ProceduralCustom(int k)
	{
		var kingdom = Kingdoms[k];
		var c = Cultures[kingdom.Culture];
		var lang = _languages[c.Species];
		string people = Assets.Species[c.Species].Name;
		var capital = kingdom.Capital >= 0 ? Villages[kingdom.Capital] : null;
		bool atWar = Wars.Exists(w => w.A == k || w.B == k);
		bool hungry = capital != null && capital.Food < capital.Population * 3f;
		bool restless = Villages.Exists(v => v.Alive && v.Kingdom == k && v.Loyalty < 10f);
		bool few = capital != null && capital.Population < 25 && Homes(kingdom.Capital) > capital.Population + 3;
		double r = _rng.NextDouble();
		string kind, effect, occasion = "";
		if (atWar && r < 0.6)
		{
			kind = _rng.NextDouble() < 0.5 ? "ritual" : "law";
			effect = Val(c, "war") > 0.5f ? (_rng.NextDouble() < 0.5 ? "attack" : "warlike") : (_rng.NextDouble() < 0.5 ? "defense" : "peaceful");
			occasion = _rng.NextDouble() < 0.5 ? "battle" : "victory";
		}
		else if (restless && r < 0.6)
		{
			kind = "law";
			effect = "loyalty";
		}
		else if (hungry && r < 0.6)
		{
			kind = "ritual";
			effect = "food";
			occasion = "harvest";
		}
		else if (few && r < 0.4)
		{
			kind = _rng.NextDouble() < 0.5 ? "law" : "ritual";
			effect = "fertility";
			occasion = _rng.NextDouble() < 0.5 ? "birth" : "marriage";
		}
		else
		{
			// What its values favour.
			var lean = new List<(string effect, float weight)>
			{
				("warlike", Val(c, "war")), ("attack", Val(c, "war") * 0.6f), ("defense", Val(c, "honour") * 0.7f),
				("loyalty", Val(c, "tradition") * 0.8f + Val(c, "honour") * 0.3f), ("faith", Val(c, "faith")),
				("food", Val(c, "nature") * 0.5f + Val(c, "wealth") * 0.5f), ("peaceful", (1f - Val(c, "war")) * 0.8f + Val(c, "knowledge") * 0.3f),
				("fertility", Val(c, "freedom") * 0.4f + Val(c, "nature") * 0.4f),
			};
			float total = 0f;
			foreach (var l in lean)
				total += l.weight * l.weight;
			float pick = (float)_rng.NextDouble() * total;
			effect = lean[^1].effect;
			foreach (var l in lean)
			{
				pick -= l.weight * l.weight;
				if (pick <= 0f)
				{
					effect = l.effect;
					break;
				}
			}
			var kinds = new List<string>();
			foreach (var kd in CustomBlocks[effect].kinds)
				kinds.Add(kd);
			kind = kinds[_rng.Next(kinds.Count)];
			occasion = Occasions[_rng.Next(Occasions.Length)];
		}
		if (Array.IndexOf(CustomBlocks[effect].kinds, kind) < 0)
			kind = CustomBlocks[effect].kinds[0];
		var effects = new List<EffectDraft> { new() { Do = effect, Amount = MathF.Round(CustomBlocks[effect].max * (0.4f + 0.45f * (float)_rng.NextDouble()), 1) } };
		// Now and then a second effect, within the budget.
		if (_rng.NextDouble() < 0.3)
		{
			string second = kind == "taboo" ? "faith" : Val(c, "faith") > 0.5f ? "faith" : "loyalty";
			if (second != effect)
			{
				float room = CustomBudget - effects[0].Amount / CustomBlocks[effect].max;
				float amount = MathF.Floor(CustomBlocks[second].max * Math.Min(room, 0.4f) * 10f) / 10f;
				if (amount >= 0.5f)
					effects.Add(new EffectDraft { Do = second, Amount = amount });
			}
		}
		string name, text;
		string word = lang.Word(Language.Roots[_rng.Next(Language.Roots.Length)]);
		word = word.Length > 10 ? word[..10] : word;
		switch (kind)
		{
			case "law":
				string noun = LawNouns[effect][_rng.Next(LawNouns[effect].Length)];
				name = _rng.NextDouble() < 0.5 ? $"Law of the {noun}" : $"{word} {noun}";
				text = string.Format(LawTexts[effect], people);
				break;
			case "ritual":
				if (Array.IndexOf(Occasions, occasion) < 0)
					occasion = Occasions[_rng.Next(Occasions.Length)];
				name = $"{word} {RitualNouns[_rng.Next(RitualNouns.Length)]}";
				text = $"At {OccasionWords[occasion]}, the {people} {RitualActs[effect]}.";
				break;
			default:
				int t = _rng.Next(4);
				string what;
				if (t == 0)
				{
					var beasts = Assets.Species.FindAll(s => !s.IsPeople && s.IsNatural);
					string beast = beasts.Count > 0 ? beasts[_rng.Next(beasts.Count)].Name.ToLowerInvariant() : "wolf";
					what = $"hunt the {beast}";
					name = $"Taboo of the {Capitalise(beast)}";
				}
				else if (t == 1)
				{
					string place = TabooPlaces[_rng.Next(TabooPlaces.Length)];
					what = $"enter {place}";
					name = $"Taboo of {Capitalise(place)}";
				}
				else if (t == 2)
				{
					string food = TabooFoods[_rng.Next(TabooFoods.Length)];
					what = $"eat {food}";
					name = $"Taboo of {Capitalise(food)}";
				}
				else
				{
					what = TabooActs[_rng.Next(TabooActs.Length)];
					name = $"{word} Taboo";
				}
				text = $"None of the {people} may {what}.";
				break;
		}
		if (name.Length > 32)
			name = name[..32].TrimEnd();
		return new CustomDraft { Kind = kind, Name = name, Text = text, Occasion = kind == "ritual" ? occasion : "", Effects = effects };
	}

	private static string Capitalise(string s)
	{
		var words = s.Split(' ');
		for (int i = 0; i < words.Length; i++)
			if (words[i].Length > 0 && words[i] != "the" && words[i] != "of")
				words[i] = char.ToUpperInvariant(words[i][0]) + words[i][1..];
		return string.Join(' ', words);
	}

	// ------------------------------------------------------------------ the model

	/// <summary>The culture's situation for the model, and the rules of the culture language.</summary>
	public string CulturePrompt(int k)
	{
		var c = Cultures[Kingdoms[k].Culture];
		var sb = new StringBuilder();
		sb.Append("You are the collective mind of a people, shaping its culture. ");
		sb.Append(Situation(k)).Append('\n');
		sb.Append($"Their homes have {c.Roof} roofs, {c.Wall} walls and {c.Ornament}.\n");
		if (c.Customs.Count > 0)
		{
			sb.Append("They keep:\n");
			foreach (var x in c.Customs)
				sb.Append($"- {x.Name} ({x.Kind}{(x.Occasion != "" ? ", at " + x.Occasion : "")}): {x.Text}\n");
		}
		if (c.Legends.Count > 0)
			sb.Append($"Their legends: {string.Join("; ", c.Legends)}.\n");
		sb.Append("Write ONE new law, ritual or taboo that fits who they are and what they live now. ");
		sb.Append($"Rituals need an occasion: {string.Join(", ", Occasions)}. Effects (\"do\"): ");
		foreach (var (name, block) in CustomBlocks)
			sb.Append($"{name} (kinds {string.Join("/", block.kinds)}, up to {block.max}); ");
		sb.Append($"1 or 2 effects, the sum of amount/max at most {CustomBudget}. Name 2-32 letters, text one sentence. Answer with the JSON record only.\n");
		return sb.ToString();
	}

	/// <summary>The culture language as a GBNF grammar: one record per kind, each with only its
	/// effects; rituals name an occasion, laws and taboos leave it empty.</summary>
	public static string CustomGrammar()
	{
		static string Rule(string w) => w.Replace('_', '-');
		var lines = new List<string>();
		var records = new List<string>();
		foreach (var kind in CustomKinds)
		{
			records.Add("rec-" + kind);
			string occasion = kind == "ritual" ? "occasion" : "\"\\\"\\\"\"";
			lines.Add($"rec-{kind} ::= \"{{\" ws {GbnfKey("kind")} \"\\\"{kind}\\\"\" \",\" ws {GbnfKey("name")} name \",\" ws {GbnfKey("text")} text \",\" ws {GbnfKey("occasion")} {occasion} \",\" ws {GbnfKey("effects")} \"[\" ws eff-{kind} (ws \",\" ws eff-{kind})? ws \"]\" ws \"}}\"");
			var allowed = new List<string>();
			foreach (var (name, block) in CustomBlocks)
				if (Array.IndexOf(block.kinds, kind) >= 0)
					allowed.Add("do-" + Rule(name));
			lines.Add($"eff-{kind} ::= {string.Join(" | ", allowed)}");
		}
		foreach (var (name, block) in CustomBlocks)
			lines.Add($"do-{Rule(name)} ::= \"{{\" ws {GbnfKey("do")} \"\\\"{name}\\\"\" \",\" ws {GbnfKey("amount")} ({GbnfUpTo((int)block.max)}) ws \"}}\"");
		lines.Insert(0, $"root ::= {string.Join(" | ", records)}");
		lines.Add($"occasion ::= {GbnfWords(Occasions)}");
		return string.Join("\n", lines) + "\n" + GbnfCommon(150);
	}

	/// <summary>The culture language as a JSON schema (model servers).</summary>
	public static string CustomSchema()
	{
		var branches = new List<object>();
		foreach (var kind in CustomKinds)
		{
			var effects = new List<object>();
			foreach (var (name, block) in CustomBlocks)
				if (Array.IndexOf(block.kinds, kind) >= 0)
					effects.Add(new Dictionary<string, object>
					{
						["type"] = "object", ["required"] = new[] { "do", "amount" },
						["properties"] = new Dictionary<string, object>
						{
							["do"] = EnumSchema(new[] { name }),
							["amount"] = new Dictionary<string, object> { ["type"] = "integer", ["minimum"] = 1, ["maximum"] = (int)block.max },
						},
					});
			branches.Add(new Dictionary<string, object>
			{
				["type"] = "object", ["required"] = new[] { "kind", "name", "text", "occasion", "effects" },
				["properties"] = new Dictionary<string, object>
				{
					["kind"] = EnumSchema(new[] { kind }),
					["name"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 32 },
					["text"] = StringSchema(160),
					["occasion"] = kind == "ritual" ? EnumSchema(Occasions) : EnumSchema(new[] { "" }),
					["effects"] = new Dictionary<string, object>
					{
						["type"] = "array", ["minItems"] = 1, ["maxItems"] = 2, ["items"] = new Dictionary<string, object> { ["anyOf"] = effects },
					},
				},
			});
		}
		return SchemaJson(new Dictionary<string, object> { ["anyOf"] = branches });
	}

	// ------------------------------------------------------------------ legends

	/// <summary>A song or a story of a real deed joins a culture's legends (the newest eight).</summary>
	private void AddLegend(int k, string legend)
	{
		if (k < 0 || k >= Kingdoms.Count || Kingdoms[k].Culture < 0)
			return;
		var c = Cultures[Kingdoms[k].Culture];
		if (c.Legends.Contains(legend))
			return;
		c.Legends.Add(legend);
		if (c.Legends.Count > 8)
			c.Legends.RemoveAt(0);
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	public static string DescribeCustom(Custom x)
	{
		var parts = new List<string>();
		foreach (var e in x.Effects)
			parts.Add(e.Do switch
			{
				"fertility" => $"+{e.Amount:0}% births",
				"food" => $"+{e.Amount:0.#} food a month",
				"attack" => $"+{e.Amount:0}% attack",
				"defense" => $"+{e.Amount:0}% defence",
				"warlike" => $"+{e.Amount:0}% eager for war",
				"peaceful" => $"-{e.Amount:0}% eager for war",
				_ => $"+{e.Amount:0} {e.Do}",
			});
		return string.Join(", ", parts);
	}

	/// <summary>Living cultures: name, people, kingdoms, society, values, way with nature,
	/// architecture, customs (kind, name, text, occasion, effects, year, mind), legends, parent.</summary>
	public Godot.Collections.Array CultureTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var c in Cultures)
		{
			var kingdoms = new List<string>();
			Godot.Color colour = new(1, 1, 1);
			foreach (var k in Kingdoms)
				if (k.Alive && k.Culture == c.Id)
				{
					if (kingdoms.Count == 0)
						colour = k.Color;
					kingdoms.Add(k.Name);
				}
			if (kingdoms.Count == 0)
				continue;
			var customs = new Godot.Collections.Array();
			foreach (var x in c.Customs)
				customs.Add(new Godot.Collections.Dictionary
				{
					["kind"] = x.Kind, ["name"] = x.Name, ["text"] = x.Text, ["occasion"] = x.Occasion,
					["effects"] = DescribeCustom(x), ["year"] = x.Year, ["mind"] = x.Mind,
				});
			var values = new Godot.Collections.Dictionary();
			for (int i = 0; i < CultureValues.Length; i++)
				values[CultureValues[i]] = Math.Round(c.Values[i], 2);
			list.Add(new Godot.Collections.Dictionary
			{
				["index"] = c.Id, ["name"] = c.Name, ["people"] = Assets.Species[c.Species].Name, ["kingdoms"] = string.Join(", ", kingdoms),
				["society"] = c.Society, ["nature"] = c.NatureWay, ["top"] = TopValues(c, 3), ["values"] = values,
				["architecture"] = $"{c.Roof} roofs, {c.Wall} walls, {c.Ornament}", ["customs"] = customs,
				["legends"] = string.Join("\n", c.Legends), ["parent"] = c.Parent >= 0 ? Cultures[c.Parent].Name : "",
				["founded"] = c.Founded, ["color"] = colour,
			});
		}
		return list;
	}

	/// <summary>Makes kingdom k's culture write a custom now with the procedural mind (tests).</summary>
	public void CultureNow(int k)
	{
		if (k >= 0 && k < Kingdoms.Count && Kingdoms[k].Alive && Kingdoms[k].Culture >= 0)
			ThinkCulture(k, force: true);
	}

	/// <summary>Makes kingdom k's culture think the usual way (the model if one is ready).</summary>
	public void AskCulture(int k)
	{
		if (k >= 0 && k < Kingdoms.Count && Kingdoms[k].Alive && Kingdoms[k].Culture >= 0)
			ThinkCulture(k, force: false);
	}

	/// <summary>Runs one year of cultural drift for every kingdom now (tests).</summary>
	public void DriftNow()
	{
		for (int k = 0; k < Kingdoms.Count; k++)
			if (Kingdoms[k].Alive && Kingdoms[k].Culture >= 0 && Kingdoms[k].Capital >= 0)
				Drift(k);
	}
}
