using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Inventions (0.5 AI minds, docs/INVENTIONS.md): every kingdom has a mind that, once a year,
/// invents something its people need (a tool, a weapon, armour, a technique or a building),
/// written in the invention language: a JSON record of blocks (effects from a fixed list, costs,
/// a sprite template) that the engine validates before it exists. The mind is a local language
/// model when one is running (Minds.cs), else a procedural inventor; the world never waits.
///
/// Inventions change the world (faster work, bigger yields, stronger soldiers, better armour,
/// homes, food, loyalty), spread to villages of the same kingdom, trade partners and neighbours,
/// are forgotten where they are useless, and evolve by descent: most inventions improve one the
/// people already know, and every invention remembers its parent.
/// </summary>
public partial class Simulation
{
	/// <summary>An invention as written by a mind, before validation (the invention language).</summary>
	public sealed class InventionDraft
	{
		[JsonPropertyName("name")] public string Name { get; set; } = "";
		[JsonPropertyName("kind")] public string Kind { get; set; } = "";
		[JsonPropertyName("improves")] public string Improves { get; set; } = "";
		[JsonPropertyName("description")] public string Description { get; set; } = "";
		[JsonPropertyName("cost")] public Dictionary<string, float> Cost { get; set; } = new();
		[JsonPropertyName("effects")] public List<EffectDraft> Effects { get; set; } = new();
		[JsonPropertyName("sprite")] public int Sprite { get; set; }
	}

	public sealed class EffectDraft
	{
		[JsonPropertyName("do")] public string Do { get; set; } = "";
		[JsonPropertyName("job")] public string Job { get; set; } = "";
		[JsonPropertyName("amount")] public float Amount { get; set; }
	}

	public sealed class Invention
	{
		public int Id;
		public string Name, Kind, Description, Mind;
		public int Parent = -1;
		public int Kingdom, Species, Village, Year;
		public Dictionary<string, float> Cost = new();
		public List<EffectDraft> Effects = new();
		public int Sprite;
		/// <summary>The building type it adds (kind "building"), or -1.</summary>
		public int Building = -1;
		public bool Lost;
		public int Generation;
	}

	/// <summary>The blocks of the invention language: what an effect can do, for which kinds,
	/// and the most it can do in one invention.</summary>
	public static readonly Dictionary<string, (string[] kinds, float max, bool job)> EffectBlocks = new()
	{
		["work_speed"] = (new[] { "tool", "technique" }, 30f, true),
		["yield"] = (new[] { "tool", "technique" }, 40f, true),
		["attack"] = (new[] { "weapon" }, 35f, false),
		["defense"] = (new[] { "armour", "building" }, 35f, false),
		["homes"] = (new[] { "building" }, 12f, false),
		["food"] = (new[] { "technique", "building" }, 10f, false),
		["loyalty"] = (new[] { "building", "technique" }, 15f, false),
	};
	public static readonly string[] InventionKinds = { "tool", "weapon", "armour", "technique", "building" };
	/// <summary>Jobs an effect can name (work_speed, yield).</summary>
	public static readonly string[] WorkJobs = { "gatherer", "woodcutter", "hunter", "builder", "farmer", "miner", "fisher", "blacksmith" };
	public const int InventionSprites = 32;

	public readonly List<Invention> Inventions = new();
	private int _firstInventedBuilding = -1;
	public const float InventSeconds = YearSeconds;
	private double _nextSpread;
	public int InventionsRejected { get; private set; }

	private void SetupInventions()
	{
		Inventions.Clear();
		_nextSpread = 0;
		InventionsRejected = 0;
		// Buildings invented in an earlier world are gone.
		if (_firstInventedBuilding >= 0)
			Assets.Buildings.RemoveRange(_firstInventedBuilding, Assets.Buildings.Count - _firstInventedBuilding);
		_firstInventedBuilding = Assets.Buildings.Count;
		_minds.Clear();
	}

	// ------------------------------------------------------------------ validation

	/// <summary>Checks a draft against the language's rules: known kind and blocks, amounts within
	/// their caps, the power of the whole within the people's budget, a cost that pays for it.
	/// Returns null when valid, else why it is rejected.</summary>
	public static string ValidateDraft(InventionDraft d, float budget)
	{
		if (d == null)
			return "empty";
		if (string.IsNullOrWhiteSpace(d.Name) || d.Name.Length < 2 || d.Name.Length > 28)
			return "name must be 2-28 characters";
		foreach (char c in d.Name)
			if (!char.IsLetter(c) && c != ' ' && c != '-' && c != '\'')
				return "name has a forbidden character";
		if (Array.IndexOf(InventionKinds, d.Kind) < 0)
			return $"unknown kind '{d.Kind}'";
		if (d.Effects == null || d.Effects.Count < 1 || d.Effects.Count > 3)
			return "1 to 3 effects";
		float power = 0f;
		foreach (var e in d.Effects)
		{
			if (!EffectBlocks.TryGetValue(e.Do ?? "", out var block))
				return $"unknown effect '{e.Do}'";
			if (Array.IndexOf(block.kinds, d.Kind) < 0)
				return $"a {d.Kind} cannot '{e.Do}'";
			if (block.job && Array.IndexOf(WorkJobs, e.Job ?? "") < 0)
				return $"'{e.Do}' needs a job ({string.Join(", ", WorkJobs)})";
			if (!(e.Amount > 0f) || e.Amount > block.max)
				return $"'{e.Do}' amount must be in 0-{block.max}";
			power += e.Amount / block.max;
		}
		if (d.Kind == "building" && !d.Effects.Exists(e => e.Do == "homes" || e.Do == "food" || e.Do == "defense" || e.Do == "loyalty"))
			return "a building needs an effect";
		if (power > budget)
			return $"too powerful ({power:0.00} > budget {budget:0.00})";
		float paid = 0f;
		foreach (var (goods, n) in d.Cost ?? new())
		{
			if (goods != "wood" && goods != "stone" && goods != "metal" && goods != "gold")
				return $"unknown cost '{goods}'";
			if (n < 0f || n > 80f)
				return "costs must be 0-80";
			paid += goods == "gold" ? n * 4f : goods == "metal" ? n * 2f : n;
		}
		if (paid < power * 12f)
			return $"too cheap for its power (pays {paid:0}, needs {power * 12f:0})";
		if (d.Sprite < 0 || d.Sprite >= InventionSprites)
			return $"sprite must be 0-{InventionSprites - 1}";
		if ((d.Description ?? "").Length > 160)
			return "description too long";
		return null;
	}

	/// <summary>Power a kingdom's inventions may have (sum over effects of amount / cap): grows
	/// with its biggest settlement's rank.</summary>
	private float Budget(int k)
	{
		int rank = 0;
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == k)
				rank = Math.Max(rank, v.Rank);
		return 1.0f + 0.5f * rank;
	}

	/// <summary>A mind's answer (JSON in the invention language) for kingdom k: parsed, validated
	/// and, if it holds, invented in the kingdom's capital. Returns null or why it was rejected.</summary>
	public string SubmitInventionJson(int k, string json, string mind = "model")
	{
		InventionDraft d;
		try
		{
			d = JsonSerializer.Deserialize<InventionDraft>(json);
		}
		catch (Exception e)
		{
			InventionsRejected++;
			return "not valid JSON: " + e.Message;
		}
		return Submit(k, d, mind);
	}

	private string Submit(int k, InventionDraft d, string mind)
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive)
			return "no such kingdom";
		string error = ValidateDraft(d, Budget(k));
		if (error != null)
		{
			InventionsRejected++;
			return error;
		}
		var kingdom = Kingdoms[k];
		int parent = string.IsNullOrEmpty(d.Improves) ? -1 : Inventions.FindLastIndex(x => x.Name == d.Improves && !x.Lost);
		var inv = new Invention
		{
			Id = Inventions.Count, Name = d.Name.Trim(), Kind = d.Kind, Description = d.Description ?? "", Mind = mind,
			Parent = parent, Kingdom = k, Species = kingdom.Species, Village = kingdom.Capital, Year = Year(),
			Cost = new Dictionary<string, float>(d.Cost ?? new()), Effects = d.Effects, Sprite = d.Sprite,
			Generation = parent >= 0 ? Inventions[parent].Generation + 1 : 0,
		};
		Inventions.Add(inv);
		if (inv.Kind == "building")
			inv.Building = AddInventedBuilding(inv);
		Learn(kingdom.Capital, inv.Id);
		string people = Assets.Species[kingdom.Species].Name;
		LogEvent($"the {people} of {Villages[kingdom.Capital].Name} invent the {inv.Name}"
			+ (parent >= 0 ? $", a better {Inventions[parent].Name}" : "") + $" ({Describe(inv)}).", "inventions");
		return null;
	}

	/// <summary>A building invention becomes a building type of data/buildings.json's kind, known
	/// only to the villages that know the invention.</summary>
	private int AddInventedBuilding(Invention inv)
	{
		int homes = 0;
		foreach (var e in inv.Effects)
			if (e.Do == "homes")
				homes += (int)e.Amount;
		var rec = new BuildingRecord
		{
			Id = $"inv_{inv.Id}", Name = inv.Name, Homes = homes, Cost = new Dictionary<string, float>(inv.Cost), Build = 14f,
			Pop = 10, Limit = 1, Per = 40, Place = "cluster", Material = "stone", Sprite = $"inv_{inv.Sprite}", Invention = inv.Id,
		};
		Assets.Buildings.Add(rec);
		return Assets.Buildings.Count - 1;
	}

	public static string Describe(Invention inv)
	{
		var parts = new List<string>();
		foreach (var e in inv.Effects)
			parts.Add(e.Do switch
			{
				"work_speed" => $"{e.Job}s work {e.Amount:0}% faster",
				"yield" => $"{e.Job}s bring {e.Amount:0}% more",
				"attack" => $"+{e.Amount:0}% attack",
				"defense" => $"+{e.Amount:0}% defence",
				"homes" => $"{e.Amount:0} homes",
				"food" => $"+{e.Amount:0} food a month",
				"loyalty" => $"+{e.Amount:0} loyalty",
				_ => e.Do,
			});
		return string.Join(", ", parts);
	}

	// ------------------------------------------------------------------ knowing and effects

	private void Learn(int v, int id)
	{
		if (Villages[v].Known.Add(id))
			Villages[v].ModsDirty = true;
	}

	private void Forget(int v, int id)
	{
		if (Villages[v].Known.Remove(id))
			Villages[v].ModsDirty = true;
	}

	/// <summary>The village's bonuses from what it knows (objects and techniques; invented
	/// buildings count where they stand).</summary>
	private void RefreshMods(int v)
	{
		var village = Villages[v];
		if (!village.ModsDirty)
			return;
		village.ModsDirty = false;
		Array.Clear(village.JobSpeed);
		Array.Clear(village.JobYield);
		village.Attack = village.Defense = village.FoodBonus = village.LoyaltyBonus = 0f;
		foreach (int id in village.Known)
		{
			var inv = Inventions[id];
			if (inv.Kind == "building")
				continue;
			ApplyEffects(village, inv, 1f);
		}
		foreach (int b in village.Buildings)
		{
			var bld = Buildings[b];
			if (bld.Alive && bld.Done && Assets.Buildings[bld.Type].Invention >= 0)
				ApplyEffects(village, Inventions[Assets.Buildings[bld.Type].Invention], 1f);
		}
		// The kingdom's customs (Culture.cs): they give and they take.
		ApplyCustoms(village);
		// Bonuses of the same kind don't stack without limit, and customs can't cripple.
		for (int j = 0; j < village.JobSpeed.Length; j++)
		{
			village.JobSpeed[j] = Math.Clamp(village.JobSpeed[j], -40f, 80f);
			village.JobYield[j] = Math.Clamp(village.JobYield[j], -50f, 100f);
		}
		village.Attack = Math.Clamp(village.Attack, -40f, 80f);
		village.Defense = Math.Clamp(village.Defense, -40f, 60f);
	}

	private static void ApplyEffects(Village village, Invention inv, float f)
	{
		foreach (var e in inv.Effects)
		{
			int j = Array.IndexOf(JobNames, e.Job ?? "");
			switch (e.Do)
			{
				case "work_speed": if (j >= 0) village.JobSpeed[j] += e.Amount * f; break;
				case "yield": if (j >= 0) village.JobYield[j] += e.Amount * f; break;
				case "attack": village.Attack += e.Amount * f; break;
				case "defense": village.Defense += e.Amount * f; break;
				case "food": village.FoodBonus += e.Amount * f; break;
				case "loyalty": village.LoyaltyBonus += e.Amount * f; break;
			}
		}
	}

	/// <summary>Work speed of a job in a village from its inventions (1 = none).</summary>
	private float InventedSpeed(int v, int job) => v < 0 ? 1f : 1f + Villages[v].JobSpeed[job] / 100f;

	/// <summary>Yield of a job in a village from its inventions (1 = none).</summary>
	private float InventedYield(int v, int job) => v < 0 ? 1f : 1f + Villages[v].JobYield[job] / 100f;

	// ------------------------------------------------------------------ minds, spread, oblivion

	/// <summary>Every 2 s with the kingdoms: minds think once a year (asking the model, or the
	/// procedural inventor); answers that came back are submitted; once a year inventions spread
	/// and are forgotten.</summary>
	private void InventionStep(float dt)
	{
		for (int v = 0; v < Villages.Count; v++)
			if (Villages[v].Alive)
				RefreshMods(v);
		MindsStep();
		if (Scheduler.Time >= _nextSpread)
		{
			_nextSpread = Scheduler.Time + YearSeconds;
			Spread();
		}
	}

	/// <summary>How much an invention helps a village, 0..1: tools for jobs it works, weapons and
	/// armour at war, homes when crowded, food when short, loyalty when restless.</summary>
	private float Usefulness(int v, Invention inv)
	{
		var village = Villages[v];
		float best = 0f;
		bool atWar = village.Kingdom >= 0 && Wars.Exists(w => w.A == village.Kingdom || w.B == village.Kingdom);
		foreach (var e in inv.Effects)
		{
			float u = e.Do switch
			{
				"work_speed" or "yield" => JobShare(v, e.Job) > 0f ? 0.4f + 0.6f * Math.Min(1f, JobShare(v, e.Job) * 5f) : 0.05f,
				"attack" or "defense" => atWar ? 1f : 0.35f,
				"homes" => village.Population + 3 > Homes(v) ? 1f : 0.4f,
				"food" => village.Food < village.Population * 3f ? 1f : 0.3f,
				"loyalty" => village.Loyalty < 20f ? 1f : 0.3f,
				_ => 0.2f,
			};
			best = Math.Max(best, u);
		}
		return best;
	}

	private float JobShare(int v, string job)
	{
		int j = Array.IndexOf(JobNames, job ?? "");
		if (j < 0 || Villages[v].Population == 0)
			return 0f;
		int n = 0;
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Village[i] == v && Units.Job[i] == j)
				n++;
		return (float)n / Villages[v].Population;
	}

	/// <summary>Once a year: villages copy what their kingdom, their trade partners and their
	/// neighbours know (the more useful, the likelier); they forget what is useless to them;
	/// an invention no one knows any more is lost.</summary>
	private void Spread()
	{
		if (Inventions.Count == 0)
			return;
		var learned = new List<(int v, int id, int from)>();
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive)
				continue;
			for (int w = 0; w < Villages.Count; w++)
			{
				var other = Villages[w];
				if (w == v || !other.Alive || other.Known.Count == 0)
					continue;
				int d = Math.Abs(other.X - village.X) + Math.Abs(other.Y - village.Y);
				bool kin = other.Kingdom == village.Kingdom;
				bool partner = _trade.Exists(r => r.A == v && r.B == w || r.A == w && r.B == v);
				float chance = kin && d < 80 ? 0.5f : partner ? 0.35f : d < 35 ? 0.12f : 0f;
				if (chance <= 0f)
					continue;
				foreach (int id in other.Known)
					if (!village.Known.Contains(id) && _rng.NextDouble() < chance * (0.3f + Usefulness(v, Inventions[id])))
						learned.Add((v, id, w));
			}
		}
		foreach (var (v, id, from) in learned)
		{
			if (Villages[v].Known.Contains(id))
				continue;
			Learn(v, id);
			var inv = Inventions[id];
			// News when an invention crosses into another kingdom.
			if (Villages[v].Kingdom != inv.Kingdom && Villages[v].Kingdom >= 0
				&& !Villages.Exists(o => o != Villages[v] && o.Alive && o.Kingdom == Villages[v].Kingdom && o.Known.Contains(id)))
				LogEvent($"{Villages[v].Name} of {Kingdoms[Villages[v].Kingdom].Name} copies the {inv.Name} from {Villages[from].Name}.", "inventions");
		}
		// Forgetting what does not help (an improved version replaces its parent too).
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive)
				continue;
			foreach (int id in new List<int>(village.Known))
			{
				var inv = Inventions[id];
				bool replaced = Inventions.Exists(c => c.Parent == id && village.Known.Contains(c.Id));
				float u = Usefulness(v, inv);
				if (replaced && _rng.NextDouble() < 0.5 || u < 0.2f && _rng.NextDouble() < 0.25)
					Forget(v, id);
			}
		}
		foreach (var inv in Inventions)
		{
			if (inv.Lost)
				continue;
			bool known = Villages.Exists(v => v.Alive && v.Known.Contains(inv.Id));
			if (!known)
			{
				inv.Lost = true;
				LogEvent($"the {inv.Name} of the {Assets.Species[inv.Species].Name} is forgotten.", "inventions");
			}
		}
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>Inventions, newest first: name, kind, effects, inventor, year, parent, villages that
	/// know it, mind (model or procedural), lost.</summary>
	public Godot.Collections.Array InventionTable()
	{
		var list = new Godot.Collections.Array();
		for (int n = Inventions.Count - 1; n >= 0; n--)
		{
			var inv = Inventions[n];
			int knowers = 0;
			foreach (var v in Villages)
				if (v.Alive && v.Known.Contains(inv.Id))
					knowers++;
			list.Add(new Godot.Collections.Dictionary
			{
				["id"] = inv.Id, ["name"] = inv.Name, ["kind"] = inv.Kind, ["effects"] = Describe(inv),
				["people"] = Assets.Species[inv.Species].Name, ["kingdom"] = Kingdoms[inv.Kingdom].Name, ["year"] = inv.Year,
				["parent"] = inv.Parent >= 0 ? Inventions[inv.Parent].Name : "", ["generation"] = inv.Generation,
				["villages"] = knowers, ["mind"] = inv.Mind, ["lost"] = inv.Lost, ["sprite"] = inv.Sprite,
				["description"] = inv.Description,
			});
		}
		return list;
	}

	/// <summary>A village's bonuses from inventions (tests, inspector).</summary>
	public Godot.Collections.Dictionary VillageMods(int v)
	{
		RefreshMods(v);
		var village = Villages[v];
		var d = new Godot.Collections.Dictionary
		{
			["attack"] = village.Attack, ["defense"] = village.Defense, ["food"] = village.FoodBonus,
			["loyalty"] = village.LoyaltyBonus, ["known"] = village.Known.Count,
		};
		for (int j = 0; j < JobNames.Length; j++)
			if (village.JobSpeed[j] > 0f || village.JobYield[j] > 0f)
				d[JobNames[j]] = $"speed +{village.JobSpeed[j]:0}% yield +{village.JobYield[j]:0}%";
		return d;
	}

	/// <summary>Makes a kingdom's mind invent now with the procedural inventor (tests; god powers later).</summary>
	public void InventNow(int k) => Think(k, force: true);

	/// <summary>Makes a kingdom's mind think now the usual way: the local model if one is set (the
	/// answer comes later), else the procedural inventor.</summary>
	public void AskMind(int k) => Think(k, force: false);
}
