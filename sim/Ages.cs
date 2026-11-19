using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// Ages (0.8, docs/AGES.md). Every kingdom climbs the ages of data/ages.json one by one, from the
/// Stone Age to the Future Age, and then into the ages beyond, which are named when a people first
/// reaches them and never end.
///
/// Knowledge comes once a year from its people, its temples, libraries and universities, what it
/// knows, its trade partners, neighbours further ahead (the young copy the old), what its culture
/// thinks of learning, and the mood of the world (Eras.cs). Enough of it and the kingdom enters
/// the next age: its soldiers strike harder, its people work faster, its inventions may be
/// stronger and use new blocks (vehicles, energy, knowledge), new buildings open (universities,
/// factories, power plants, missile silos, launch pads), its carts and boats change.
///
/// When it enters an age, its mind (the local model, or a procedural one from its culture) writes
/// how the age's things look to them: the vehicle, the ship, the home and the weapon of the age,
/// named in their spirit, each one descending from the one before (the ox cart becomes the wagon,
/// then the steam train...). Peoples keep the lineage of their things.
///
/// Peoples can fall back: a capital taken, libraries burned, plagues, nuclear strikes and nuclear
/// winters cost knowledge, and a kingdom whose knowledge runs out drops an age. What was lost is
/// found again faster (the ruins remember).
///
/// Progress has a price: from the Industrial Age, villages pollute the air around them (smog that
/// withers plants and grieves the spirits) and the whole world warms; warming brings droughts and
/// wildfires and melts the snow. Atomic kingdoms with a missile silo may use the bomb when a war
/// goes badly; bombs bring nuclear winter. Space kingdoms with a launch pad send rockets up.
/// </summary>
public partial class Simulation
{
	/// <summary>The things of an age a people's mind names (Kingdom.Designs).</summary>
	public static readonly string[] DesignKinds = { "vehicle", "ship", "home", "weapon" };

	/// <summary>A people's designs for its new age as written by a mind, before validation.</summary>
	public sealed class DesignDraft
	{
		[JsonPropertyName("age")] public string Age { get; set; } = "";
		[JsonPropertyName("vehicle")] public string Vehicle { get; set; } = "";
		[JsonPropertyName("ship")] public string Ship { get; set; } = "";
		[JsonPropertyName("home")] public string Home { get; set; } = "";
		[JsonPropertyName("weapon")] public string Weapon { get; set; } = "";
		[JsonPropertyName("words")] public string Words { get; set; } = "";

		public string Of(string kind) => kind switch { "vehicle" => Vehicle, "ship" => Ship, "home" => Home, _ => Weapon };
	}

	/// <summary>Names of the ages beyond the last of data/ages.json, as they were reached.</summary>
	public readonly List<string> BeyondNames = new();
	/// <summary>Pollution in the air over each zone of 8x8 tiles (Villages.cs zones).</summary>
	public float[] Smog = Array.Empty<float>();
	/// <summary>Tiles withered by smog or fallout: years left (ground code 8 on the map).</summary>
	public byte[] Blight = Array.Empty<byte>();
	/// <summary>What all the world's chimneys have put in the air, slowly fading.</summary>
	public float Carbon { get; private set; }
	/// <summary>How much warmer the world is than when it began, in degrees.</summary>
	public float Warming => Carbon / CarbonPerDegree;
	public const float CarbonPerDegree = 15000f;
	/// <summary>Years of nuclear winter left (0: none).</summary>
	public float NuclearWinter { get; private set; }
	public int NukesFallen { get; private set; }
	public int RocketsLaunched { get; private set; }
	/// <summary>Firsts of the whole world: "the first rocket", "the moon"... (feat → kingdom).</summary>
	private readonly Dictionary<string, int> _worldFirsts = new();
	private double _nextAgeYear;
	private Random _ageRng = new(1);
	private int _warmingTold;
	/// <summary>Mushroom clouds and rockets in the sky: where, when, what (Draw.cs).</summary>
	private readonly List<(string kind, float x, float y, double at)> _skyFx = new();
	/// <summary>Smog above this over a zone withers what grows there.</summary>
	public const float SmogBlight = 30f;
	private int _tUniversity = -2, _tFactory = -2, _tPowerPlant = -2, _tSilo = -2, _tLaunchPad = -2, _tLibrary = -2;

	private void SetupAges(int seed)
	{
		BeyondNames.Clear();
		_worldFirsts.Clear();
		_skyFx.Clear();
		_ageRng = new Random(seed ^ 0xa9e5);
		_nextAgeYear = YearSeconds;
		Carbon = 0f;
		NuclearWinter = 0f;
		NukesFallen = 0;
		RocketsLaunched = 0;
		_warmingTold = 0;
		int n = World.Width * World.Height;
		Smog = new float[((World.Width + ZoneSize - 1) / ZoneSize) * ((World.Height + ZoneSize - 1) / ZoneSize)];
		Blight = new byte[n];
		_tUniversity = Assets.BuildingIndex("university");
		_tFactory = Assets.BuildingIndex("factory");
		_tPowerPlant = Assets.BuildingIndex("power_plant");
		_tSilo = Assets.BuildingIndex("silo");
		_tLaunchPad = Assets.BuildingIndex("launch_pad");
		_tLibrary = Assets.BuildingIndex("library");
		MemoryDomains["progress"] = ("wisdom", "Lit the Lamp");
		MemoryDomains["regress"] = ("forgetting", "Took Back the Fire");
		MemoryDomains["bomb"] = ("the burning sun", "Unmade the Cities");
		MemoryDomains["winter"] = ("the long night", "Hid the Sun");
		MemoryDomains["stars"] = ("the stars", "Opened the Sky");
	}

	/// <summary>A kingdom is born in the age of its mother (rebels) or in the Stone Age, with the
	/// age's designs.</summary>
	private void StartAge(Kingdom k, Kingdom mother)
	{
		k.Age = mother?.Age ?? 0;
		k.Peak = mother?.Peak ?? k.Age;
		k.Knowledge = mother != null ? mother.Knowledge * 0.5f : 0f;
		k.AgeSince = Year();
		foreach (var kind in DesignKinds)
		{
			string name = mother != null && mother.Designs.TryGetValue(kind, out string m) ? m : DefaultDesign(k.Age, kind);
			k.Designs[kind] = name;
			k.Lineage[kind] = mother != null && mother.Lineage.TryGetValue(kind, out var line) ? new List<string>(line) : new List<string> { name };
		}
	}

	// ------------------------------------------------------------------ the ages

	/// <summary>How many ages data/ages.json holds (more come beyond, without end).</summary>
	public int AgeCount => Assets.Ages.Count;

	/// <summary>Age a of the peoples: a record of data/ages.json, or an age beyond them, made from
	/// the last one (each a third dearer and stronger).</summary>
	private AgeRecord AgeRec(int a)
	{
		var ages = Assets.Ages;
		if (ages.Count == 0)
			return new AgeRecord { Id = "stone", Name = "Stone Age", Knowledge = 120f };
		a = Math.Max(0, a);
		if (a < ages.Count)
			return ages[a];
		var last = ages[^1];
		int past = a - ages.Count + 1;
		var b = Assets.Beyond;
		return new AgeRecord
		{
			Id = $"beyond_{past}", Name = BeyondName(past - 1),
			Knowledge = last.Knowledge * MathF.Pow(b.Growth, past), Strength = last.Strength + 0.8f * past,
			Work = last.Work + 0.2f * past, Pollution = 0.02f, Lore = "An age no one has seen before.",
			Designs = new Dictionary<string, string>
			{
				["vehicle"] = Pick(b.Vehicle, past, "Skimmer"), ["ship"] = Pick(b.Vehicle, past + 2, "Lightship"),
				["home"] = Pick(b.Home, past, "Spire"), ["weapon"] = Pick(b.Weapon, past, "Unmaker"),
			},
		};
	}

	private static string Pick(List<string> list, int n, string fallback) => list.Count > 0 ? list[n % list.Count] : fallback;

	/// <summary>The name of the n-th age beyond (from 0): known once a people reached it.</summary>
	private string BeyondName(int n) => n < BeyondNames.Count ? BeyondNames[n] : $"Age Beyond {n + 1}";

	/// <summary>Names the next age beyond, when a people first reaches it: its mind's name, else
	/// one made of data/ages.json's words.</summary>
	private void NameBeyond(int a, string wanted)
	{
		int n = a - AgeCount;
		while (BeyondNames.Count <= n)
		{
			string name = BeyondNames.Count == n && !string.IsNullOrWhiteSpace(wanted) ? wanted.Trim() : null;
			var b = Assets.Beyond;
			for (int tries = 0; name == null || BeyondNames.Contains(name); tries++)
			{
				string first = Pick(b.First, _ageRng.Next(1000), "Star"), second = Pick(b.Second, _ageRng.Next(1000), "Ascension");
				name = tries < 20 ? $"The {first} {second}" : $"The {first} {second} {BeyondNames.Count + 1}";
			}
			BeyondNames.Add(name);
		}
	}

	private string AgeTitle(int a) => AgeRec(a).Name;

	/// <summary>"the Bronze Age", but "The Void Exodus" for a name that has its own article.</summary>
	private static string The(string age) => age.StartsWith("The ") ? age : "the " + age;

	private string DefaultDesign(int a, string kind) => AgeRec(a).Designs.TryGetValue(kind, out string d) ? d : kind;

	/// <summary>How much harder its soldiers strike than in the Stone Age.</summary>
	private float AgeStrength(int k) => k >= 0 && k < Kingdoms.Count ? AgeRec(Kingdoms[k].Age).Strength : 1f;

	/// <summary>How much faster its people work than in the Stone Age.</summary>
	private float AgeWork(int v) => v >= 0 && v < Villages.Count && Villages[v].Kingdom >= 0 ? AgeRec(Kingdoms[Villages[v].Kingdom].Age).Work : 1f;

	/// <summary>The age of the kingdom village v belongs to (0 for none).</summary>
	private int VillageAge(int v) => v >= 0 && v < Villages.Count && Villages[v].Kingdom >= 0 ? Kingdoms[Villages[v].Kingdom].Age : 0;

	/// <summary>Whether an invention language block is open to a people of age a.</summary>
	public bool BlockOpen(string block, int a)
	{
		for (int n = 0; n <= Math.Min(a, AgeCount - 1); n++)
			if (Assets.Ages[n].Blocks.Contains(block))
				return true;
		return Assets.Ages.Count == 0 || !Assets.Ages.Exists(r => r.Blocks.Contains(block));
	}

	// ------------------------------------------------------------------ every year

	/// <summary>Every 2 s with the kingdoms: once a year, knowledge, ages, pollution, the bomb and
	/// rockets; answers of the minds that named an age's things are taken.</summary>
	private void AgesStep(float dt)
	{
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (kingdom.AgeAsking == null || !kingdom.Alive)
				continue;
			if (kingdom.AgeAsking.Take(Scheduler.Time, out string json, out string why))
			{
				kingdom.AgeAsking = null;
				string error = json == null ? why : SubmitDesignJson(k, json, "model");
				LastModelAnswer = json ?? "";
				LastModelError = error ?? "";
				if (string.IsNullOrEmpty(error))
					ModelAnswers++;
				else
				{
					ModelFailures++;
					ApplyDesigns(k, ProceduralDesigns(k), "procedural");
				}
			}
		}
		_skyFx.RemoveAll(f => Scheduler.Time - f.at > SkyFxSeconds(f.kind));
		if (Scheduler.Time < _nextAgeYear)
			return;
		_nextAgeYear = Scheduler.Time + YearSeconds;
		AgesYear();
	}

	private void AgesYear()
	{
		if (Law("ages"))
			for (int k = 0; k < Kingdoms.Count; k++)
			{
				var kingdom = Kingdoms[k];
				if (!kingdom.Alive || kingdom.Capital < 0)
					continue;
				kingdom.LastGain = KnowledgeGain(k);
				kingdom.Knowledge += kingdom.LastGain;
				// Several ages at once are never crossed in a year.
				if (kingdom.Knowledge >= AgeRec(kingdom.Age).Knowledge)
					Advance(k, "");
			}
		PollutionYear();
		WinterYear();
		if (Law("nuclear_war"))
			BombYear();
		SpaceYear();
	}

	/// <summary>A year's knowledge for kingdom k.</summary>
	private float KnowledgeGain(int k)
	{
		var kingdom = Kingdoms[k];
		int people = 0, libraries = 0, temples = 0, universities = 0;
		float taught = 0f;
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive || village.Kingdom != k)
				continue;
			people += village.Population;
			libraries += CountOf(v, _tLibrary, true);
			temples += _tTemple >= 0 ? CountOf(v, _tTemple, true) : 0;
			universities += _tUniversity >= 0 ? CountOf(v, _tUniversity, true) : 0;
			taught += village.KnowledgeBonus;
		}
		var capital = Villages[kingdom.Capital];
		int partners = 0;
		foreach (var r in _trade)
			if (r.A >= 0 && r.B >= 0 && r.A < Villages.Count && r.B < Villages.Count
				&& (Villages[r.A].Kingdom == k) != (Villages[r.B].Kingdom == k))
				partners++;
		// More people think more, but a crowd is not a school: the square root of the people.
		float gain = 2f + MathF.Sqrt(people) * 0.8f + libraries * 3f + temples * 1f + universities * 6f + Math.Min(capital.Known.Count, 10) * 0.3f
			+ Math.Min(partners, 6) * 1.5f + Math.Min(taught, 15f) + Math.Min(kingdom.Satellites, 10) * 2f;
		// The young learn from those ahead of them: neighbours, partners, foes.
		int ahead = 0;
		for (int o = 0; o < Kingdoms.Count; o++)
			if (o != k && Kingdoms[o].Alive && Kingdoms[o].Age > kingdom.Age && Kingdoms[o].Capital >= 0)
			{
				var oc = Villages[Kingdoms[o].Capital];
				int d = Math.Abs(oc.X - capital.X) + Math.Abs(oc.Y - capital.Y);
				if (d < 120)
					ahead = Math.Max(ahead, Kingdoms[o].Age - kingdom.Age);
			}
		gain *= 1f + 0.15f * Math.Min(ahead, 4);
		// A culture that prizes knowledge learns faster; one bound to tradition, slower.
		var c = kingdom.Culture;
		if (c != null)
			gain *= 0.75f + c.Values[Array.IndexOf(ValueNames, "knowledge")] * 0.6f - c.Values[Array.IndexOf(ValueNames, "tradition")] * 0.15f;
		// What was known once is found again quickly.
		if (kingdom.Age < kingdom.Peak)
			gain *= 1.6f;
		if (Wars.Exists(w => w.A == k || w.B == k))
			gain *= 0.85f;
		gain *= EraKnowledge();
		if (NuclearWinter > 0f)
			gain *= 0.5f;
		return Math.Max(0f, gain);
	}

	/// <summary>Kingdom k enters the next age: what its mind wants to call things comes now (the
	/// procedural mind) or later (the model). `wanted` names an age beyond (tests, the model).</summary>
	private void Advance(int k, string wanted)
	{
		var kingdom = Kingdoms[k];
		kingdom.Knowledge = Math.Max(0f, kingdom.Knowledge - AgeRec(kingdom.Age).Knowledge);
		kingdom.Age++;
		bool again = kingdom.Age <= kingdom.Peak;
		kingdom.Peak = Math.Max(kingdom.Peak, kingdom.Age);
		kingdom.AgeSince = Year();
		if (kingdom.Age >= AgeCount)
			NameBeyond(kingdom.Age, wanted);
		var rec = AgeRec(kingdom.Age);
		string first = "";
		if (!_worldFirsts.ContainsKey("age:" + kingdom.Age))
		{
			_worldFirsts["age:" + kingdom.Age] = k;
			first = " The first people of the world to do so.";
		}
		string people = Assets.Species[kingdom.Species].Name;
		LogEvent(again ? $"the {people} of {kingdom.Name} find their way back into {The(rec.Name)}."
			: $"the {people} of {kingdom.Name} enter {The(rec.Name)}: {rec.Lore.TrimEnd('.').ToLower()}.{first}", "ages");
		Remember(k, "progress", $"{kingdom.Name} entered {The(rec.Name)}", again ? 1f : 1.5f + (first != "" ? 1f : 0f));
		Feat(kingdom, again ? $"back in {The(rec.Name)}" : $"entered {The(rec.Name)}");
		// The new age's buildings and blocks: the villages see what they may build again.
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == k)
				v.ModsDirty = true;
		ThinkDesigns(k, force: false);
	}

	/// <summary>Kingdom k loses `share` of an age's knowledge (why: "the fall of its capital").
	/// Knowledge run out: it drops back an age, keeping some of what it knew.</summary>
	private void Setback(int k, float share, string why)
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive || !Law("ages"))
			return;
		var kingdom = Kingdoms[k];
		kingdom.Knowledge -= share * AgeRec(kingdom.Age).Knowledge;
		if (kingdom.Knowledge >= 0f)
			return;
		if (kingdom.Age == 0)
		{
			kingdom.Knowledge = 0f;
			return;
		}
		string from = AgeTitle(kingdom.Age);
		kingdom.Age--;
		kingdom.AgeSince = Year();
		kingdom.Knowledge = Math.Max(0f, AgeRec(kingdom.Age).Knowledge * 0.6f + kingdom.Knowledge);
		foreach (var kind in DesignKinds)
			if (kingdom.Lineage.TryGetValue(kind, out var line) && line.Count > 1)
			{
				// They go back to the things of the age before.
				line.Add(DefaultDesign(kingdom.Age, kind));
				kingdom.Designs[kind] = line[^1];
			}
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom == k)
				v.ModsDirty = true;
		LogEvent($"{kingdom.Name} falls back from {The(from)} into {The(AgeTitle(kingdom.Age))}: {why} cost them what they knew.", "ages");
		Remember(k, "regress", $"{kingdom.Name} lost {The(from)} after {why}", 2f);
		Feat(kingdom, $"fell back into {The(AgeTitle(kingdom.Age))} after {why}");
	}

	private void Feat(Kingdom kingdom, string text)
	{
		kingdom.Feats.Add($"year {Year()}: {text}");
		if (kingdom.Feats.Count > 8)
			kingdom.Feats.RemoveAt(0);
	}

	/// <summary>A building lost (to fire, war, quakes): libraries and universities take knowledge
	/// with them.</summary>
	private void KnowledgeLost(int b)
	{
		var bld = Buildings[b];
		if (!bld.Done || bld.Village < 0 || !Villages[bld.Village].Alive)
			return;
		int k = Villages[bld.Village].Kingdom;
		if (bld.Type == _tLibrary && _tLibrary >= 0)
			Setback(k, 0.12f, $"the burning of the library of {Villages[bld.Village].Name}");
		else if (bld.Type == _tUniversity && _tUniversity >= 0)
			Setback(k, 0.2f, $"the ruin of the university of {Villages[bld.Village].Name}");
	}

	// ------------------------------------------------------------------ designs: things evolve

	/// <summary>The mind of kingdom k names the things of its new age: the model in the
	/// background, or the procedural mind now.</summary>
	private void ThinkDesigns(int k, bool force)
	{
		var kingdom = Kingdoms[k];
		if (!force)
		{
			var task = AskAnyMind(DesignPrompt(k), DesignGrammar(k), DesignSchema(k),
				"You are the collective mind of a people in a world simulation. Answer with one JSON record.");
			if (task != null)
			{
				kingdom.AgeAsking = new Question { Pending = task, Asked = Scheduler.Time };
				return;
			}
		}
		ApplyDesigns(k, ProceduralDesigns(k), "procedural");
	}

	/// <summary>A word their culture would put before the things they make.</summary>
	private static readonly Dictionary<string, string[]> CultureWords = new()
	{
		["war"] = new[] { "War", "Iron", "Battle" }, ["honour"] = new[] { "Royal", "Noble", "Banner" },
		["nature"] = new[] { "Living", "Green", "Leaf" }, ["wealth"] = new[] { "Gilded", "Grand", "Merchant" },
		["knowledge"] = new[] { "Clever", "Clockwork", "Scholar's" }, ["faith"] = new[] { "Holy", "Blessed", "Temple" },
		["freedom"] = new[] { "Free", "Wild", "Open" }, ["tradition"] = new[] { "Old", "Elder", "Ancestral" },
	};

	/// <summary>The things of the new age, named in the spirit of the people: the age's own thing,
	/// now and then marked by what their culture prizes most or by a word of their language.</summary>
	private DesignDraft ProceduralDesigns(int k)
	{
		var kingdom = Kingdoms[k];
		var c = kingdom.Culture;
		string value = "tradition";
		if (c != null)
		{
			float best = -1f;
			for (int n = 0; n < ValueNames.Length; n++)
				if (c.Values[n] > best)
				{
					best = c.Values[n];
					value = ValueNames[n];
				}
		}
		var lang = _languages.Count > kingdom.Species && _languages[kingdom.Species] != null ? _languages[kingdom.Species] : null;
		string Name(string kind)
		{
			string basic = DefaultDesign(kingdom.Age, kind);
			double r = _ageRng.NextDouble();
			string named = r < 0.3 ? CultureWords[value][_ageRng.Next(3)] + " " + basic
				: r < 0.5 && lang != null ? Clean(lang.PlaceName()) + " " + basic : basic;
			return named.Length <= 28 ? named : basic.Length <= 28 ? basic : basic[..28].TrimEnd();
		}
		var d = new DesignDraft { Vehicle = Name("vehicle"), Ship = Name("ship"), Home = Name("home"), Weapon = Name("weapon") };
		string[] sayings =
		{
			"What our fathers carried, we now drive.", "The old ways served; the new ways serve better.",
			"Let the world see what {kingdom} has made.", "We build higher than those before us.",
			"Our hands have learned new tricks.", "Nothing stands still, not even stone.",
		};
		d.Words = Clean(sayings[_ageRng.Next(sayings.Length)].Replace("{kingdom}", kingdom.Name));
		return d;
	}

	/// <summary>Checks a mind's designs: four names of 2-28 letters, and a sentence. Returns null
	/// when valid.</summary>
	public static string ValidateDesigns(DesignDraft d)
	{
		if (d == null)
			return "empty";
		foreach (var kind in DesignKinds)
		{
			string name = d.Of(kind) ?? "";
			if (name.Trim().Length < 2 || name.Length > 28)
				return $"{kind} name must be 2-28 characters";
			foreach (char ch in name)
				if (!char.IsLetter(ch) && ch != ' ' && ch != '-' && ch != '\'')
					return $"{kind} name has a forbidden character";
		}
		if (!string.IsNullOrEmpty(d.Age))
		{
			if (d.Age.Length > 32)
				return "age name too long";
			foreach (char ch in d.Age)
				if (!char.IsLetter(ch) && ch != ' ' && ch != '-' && ch != '\'')
					return "age name has a forbidden character";
		}
		return TextError(d.Words, 2, 160);
	}

	private string SubmitDesignJson(int k, string json, string mind)
	{
		DesignDraft d;
		try
		{
			d = JsonSerializer.Deserialize<DesignDraft>(json);
		}
		catch (Exception e)
		{
			return "not valid JSON: " + e.Message;
		}
		string error = ValidateDesigns(d);
		if (error != null)
			return error;
		ApplyDesigns(k, d, mind);
		return "";
	}

	/// <summary>The people's things of this age: each descends from the one before, and the
	/// change is told.</summary>
	private void ApplyDesigns(int k, DesignDraft d, string mind)
	{
		if (ValidateDesigns(d) != null || k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive)
			return;
		var kingdom = Kingdoms[k];
		// An age beyond named by the first people to reach it, if it has no name yet.
		if (kingdom.Age >= AgeCount && !string.IsNullOrWhiteSpace(d.Age) && kingdom.Age - AgeCount == BeyondNames.Count - 1
			&& _worldFirsts.TryGetValue("age:" + kingdom.Age, out int firstK) && firstK == k && !_worldFirsts.ContainsKey("named:" + kingdom.Age))
		{
			string old = BeyondNames[^1];
			string name = d.Age.Trim();
			if (!name.StartsWith("The ") && !name.StartsWith("the "))
				name = "The " + name;
			if (!BeyondNames.Contains(name))
			{
				BeyondNames[^1] = name;
				_worldFirsts["named:" + kingdom.Age] = k;
				LogEvent($"{kingdom.Name} names the age it has opened: {old} is {name}.", "ages");
			}
		}
		var changes = new List<string>();
		foreach (var kind in DesignKinds)
		{
			string name = d.Of(kind).Trim();
			kingdom.Designs.TryGetValue(kind, out string was);
			if (!kingdom.Lineage.TryGetValue(kind, out var line))
				kingdom.Lineage[kind] = line = new List<string>();
			if (line.Count == 0 || line[^1] != name)
				line.Add(name);
			if (line.Count > 12)
				line.RemoveAt(0);
			kingdom.Designs[kind] = name;
			if (!string.IsNullOrEmpty(was) && was != name && changes.Count < 2 && (kind == "vehicle" || kind == "weapon" || kind == "home"))
				changes.Add($"the {was} becomes the {name}");
		}
		kingdom.DesignMind = mind;
		kingdom.DesignWords = (d.Words ?? "").Trim();
		if (changes.Count > 0)
			LogEvent($"in {kingdom.Name}, {string.Join(", and ", changes)}: \"{kingdom.DesignWords}\"", "ages");
	}

	public string DesignPrompt(int k)
	{
		var kingdom = Kingdoms[k];
		var rec = AgeRec(kingdom.Age);
		var c = kingdom.Culture;
		var sb = new StringBuilder();
		sb.Append($"You are the collective mind of the {Assets.Species[kingdom.Species].Name} of the kingdom of {Clean(kingdom.Name)}, in year {Year()} of their world.\n");
		sb.Append($"They have just entered {The(rec.Name)}: {rec.Lore}\n");
		if (c != null)
		{
			var values = new List<(float v, string n)>();
			for (int n = 0; n < ValueNames.Length; n++)
				values.Add((c.Values[n], ValueNames[n]));
			values.Sort((a, b) => b.v.CompareTo(a.v));
			sb.Append($"They prize {values[0].n}, {values[1].n} and {values[2].n}; they build with {Walls[c.Wall]} walls and {Roofs[c.Roof]} roofs.\n");
		}
		sb.Append("Until now they used:\n");
		foreach (var kind in DesignKinds)
			sb.Append($"- {kind}: {(kingdom.Designs.TryGetValue(kind, out string was) ? was : "nothing")}\n");
		sb.Append("Name the things of their new age, each grown out of the old one, in their spirit:\n");
		foreach (var kind in DesignKinds)
			sb.Append($"- {kind}: what they make in this age (like a {DefaultDesign(kingdom.Age, kind)})\n");
		if (kingdom.Age >= AgeCount)
			sb.Append("No one has ever been this far: give this age a name in \"age\" (2-32 letters), else \"\".\n");
		else
			sb.Append("\"age\" is \"\".\n");
		sb.Append("Names: 2-28 letters, spaces, hyphens. \"words\": what their people say of this change, one sentence. Answer with the JSON record only.\n");
		return sb.ToString();
	}

	private string DesignGrammar(int k)
	{
		string name = LocalModel.Name(28);
		bool beyond = Kingdoms[k].Age >= AgeCount;
		return "root ::= \"{\" ws \"\\\"age\\\":\" ws age \",\" ws \"\\\"vehicle\\\":\" ws name \",\" ws \"\\\"ship\\\":\" ws name \",\" ws "
			+ "\"\\\"home\\\":\" ws name \",\" ws \"\\\"weapon\\\":\" ws name \",\" ws \"\\\"words\\\":\" ws words ws \"}\"\n"
			+ $"age ::= {(beyond ? LocalModel.Name(30) : "\"\\\"\\\"\"")}\nname ::= {name}\nwords ::= {LocalModel.Text(150, 2)}\nws ::= [ ]?\n";
	}

	private string DesignSchema(int k)
	{
		var name = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 28 };
		return JsonSerializer.Serialize(new Dictionary<string, object>
		{
			["type"] = "object", ["required"] = new[] { "age", "vehicle", "ship", "home", "weapon", "words" },
			["properties"] = new Dictionary<string, object>
			{
				["age"] = new Dictionary<string, object> { ["type"] = "string", ["maxLength"] = Kingdoms[k].Age >= AgeCount ? 32 : 0 },
				["vehicle"] = name, ["ship"] = name, ["home"] = name, ["weapon"] = name,
				["words"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 160 },
			},
		});
	}

	// ------------------------------------------------------------------ pollution and climate

	/// <summary>Once a year: chimneys fill the air over their villages (factories and power plants
	/// most, inventions that clean less); smog drifts and thins; where it is thick, plants wither,
	/// the ground blights and spirits grieve. What goes up warms the world.</summary>
	private void PollutionYear()
	{
		for (int t = 0; t < Blight.Length; t++)
			if (Blight[t] > 0 && --Blight[t] == 0)
				_overlayChanged.Add(t);
		if (!Law("pollution"))
		{
			Array.Clear(Smog);
			return;
		}
		float emitted = 0f;
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive || village.Kingdom < 0)
				continue;
			var rec = AgeRec(Kingdoms[village.Kingdom].Age);
			float e = village.Population * rec.Pollution
				+ (_tFactory >= 0 ? CountOf(v, _tFactory, true) * 4f : 0f) + (_tPowerPlant >= 0 ? CountOf(v, _tPowerPlant, true) * 6f : 0f);
			if (e <= 0f)
				continue;
			e *= Math.Clamp(1f - village.Clean / 100f, 0.1f, 1f);
			emitted += e;
			int z = (village.Y / ZoneSize) * _zw + village.X / ZoneSize;
			if (z >= 0 && z < Smog.Length)
				Smog[z] += e;
		}
		Carbon = Math.Max(0f, Carbon * 0.99f + emitted);
		// Smog drifts into the zones around and thins.
		var next = new float[Smog.Length];
		for (int z = 0; z < Smog.Length; z++)
		{
			if (Smog[z] <= 0.01f)
				continue;
			int zx = z % _zw, zy = z / _zw;
			float keep = Smog[z] * 0.55f;
			next[z] += keep;
			float share = Smog[z] * 0.07f;
			for (int d = 0; d < 4; d++)
			{
				int nx = zx + (d == 0 ? 1 : d == 1 ? -1 : 0), ny = zy + (d == 2 ? 1 : d == 3 ? -1 : 0);
				if (nx >= 0 && ny >= 0 && nx < _zw && ny < _zh)
					next[ny * _zw + nx] += share;
			}
		}
		Smog = next;
		for (int z = 0; z < Smog.Length; z++)
			if (Smog[z] > SmogBlight)
				Wither(z, Smog[z]);
		ClimateYear();
	}

	/// <summary>Thick smog over zone z: grass and plants wither, some ground blights, and the
	/// spirit of that land grieves the kingdom that owns it.</summary>
	private void Wither(int z, float smog)
	{
		int x0 = z % _zw * ZoneSize, y0 = z / _zw * ZoneSize;
		float harm = Math.Min(1f, (smog - SmogBlight) / (SmogBlight * 3f));
		int owner = _zoneOwner.Length > z && _zoneOwner[z] >= 0 ? Villages[_zoneOwner[z]].Kingdom : -1;
		for (int y = y0; y < Math.Min(World.Height, y0 + ZoneSize); y++)
			for (int x = x0; x < Math.Min(World.Width, x0 + ZoneSize); x++)
			{
				int t = World.Index(x, y);
				if (World.Water[t] != SimWorld.WaterLand)
					continue;
				Grass[t] *= 1f - 0.5f * harm;
				if (_ageRng.NextDouble() < 0.25 * harm && _buildingAt[t] < 0 && _ground[t] != GroundRoad && _ground[t] != GroundField)
				{
					if (Blight[t] == 0)
						_overlayChanged.Add(t);
					Blight[t] = (byte)Math.Max((int)Blight[t], 3);
				}
				if (_tileFirst[t] >= 0 && _ageRng.NextDouble() < 0.2 * harm)
				{
					MarkStrip((int)_pY[_tileFirst[t]]);
					RemovePlant(_tileFirst[t]);
				}
			}
		Grieve(World.Index(Math.Min(World.Width - 1, x0 + ZoneSize / 2), Math.Min(World.Height - 1, y0 + ZoneSize / 2)), 1.5f * harm + 0.5f, "polluted", owner);
	}

	/// <summary>The warmer world: told by the degree; above a degree and a half, snow melts into
	/// tundra and ice into water at its edges.</summary>
	private void ClimateYear()
	{
		int degrees = (int)Warming;
		if (degrees > _warmingTold)
		{
			_warmingTold = degrees;
			LogEvent(degrees == 1 ? "the smoke of the chimneys has warmed the world: winters grow mild, summers burn."
				: $"the world is {degrees} degrees warmer than it was: the snows retreat, the deserts creep.", "ages");
			for (int k = 0; k < Kingdoms.Count; k++)
				if (Kingdoms[k].Alive && Kingdoms[k].Age >= 5)
					Remember(k, "drought", $"the world grew {degrees} degrees warmer in their time", 1f + degrees * 0.5f);
		}
		if (Warming < 1.5f)
			return;
		int snow = Array.IndexOf(_biomeNames, "Snow"), tundra = Array.IndexOf(_biomeNames, "Tundra"), ice = Array.IndexOf(_biomeNames, "Ice"),
			water = Array.IndexOf(_biomeNames, "Water"), grass = Array.IndexOf(_biomeNames, "Grassland"), savanna = Array.IndexOf(_biomeNames, "Savanna"),
			desert = Array.IndexOf(_biomeNames, "Desert");
		int melt = (int)(World.Width * World.Height * 0.0015f * Math.Min(3f, Warming - 1f));
		for (int n = 0; n < melt * 4 && melt > 0; n++)
		{
			int t = _ageRng.Next(World.Width * World.Height);
			int b = World.Biome[t];
			int to = b == snow ? tundra : b == tundra && Warming > 2.5f ? grass : b == savanna && Warming > 2.5f ? desert : -1;
			if (to >= 0 && World.Water[t] == SimWorld.WaterLand && Touches(t, to))
			{
				SetBiome(t, to);
				melt--;
			}
			else if (b == ice && water >= 0 && Touches(t, water))
			{
				World.Biome[t] = (byte)water;
				_biomeChanged.Add(t);
				melt--;
			}
		}
	}

	/// <summary>Whether a tile next to t has biome b (change spreads from edges).</summary>
	private bool Touches(int t, int b)
	{
		if (b < 0)
			return false;
		int x = t % World.Width, y = t / World.Width;
		for (int d = 0; d < 4; d++)
		{
			int nx = x + (d == 0 ? 1 : d == 1 ? -1 : 0), ny = y + (d == 2 ? 1 : d == 3 ? -1 : 0);
			if (World.InBounds(nx, ny) && World.Biome[World.Index(nx, ny)] == b)
				return true;
		}
		return false;
	}

	/// <summary>How much the warming takes off the cold of the seasons, 0..0.4.</summary>
	private float WarmingMildness() => Math.Min(0.4f, Warming * 0.1f);

	// ------------------------------------------------------------------ the bomb

	/// <summary>Once a year: an atomic kingdom with a missile silo, at war and losing (or warlike
	/// and hating its foe), may drop the bomb on the foe's biggest village. A foe that has the bomb
	/// too gives pause.</summary>
	private void BombYear()
	{
		foreach (var w in Wars.ToArray())
			foreach (var (k, foe) in new[] { (w.A, w.B), (w.B, w.A) })
			{
				if (k < 0 || foe < 0 || !Kingdoms[k].Alive || !Kingdoms[foe].Alive || Kingdoms[k].Age < BombAge
					|| Scheduler.Time < Kingdoms[k].NextBomb || !HasSilo(k))
					continue;
				var c = Kingdoms[k].Culture;
				float warlike = c != null ? c.Values[Array.IndexOf(ValueNames, "war")] : 0.5f;
				float losing = Strength(foe) > Strength(k) * 1.3f ? 0.2f : 0f;
				float hate = Kingdoms[k].Memory.TryGetValue(foe, out float m) && m < -40f ? 0.08f : 0f;
				float deterred = HasSilo(foe) ? 0.5f : 1f;
				float chance = (0.02f + 0.12f * warlike + losing + hate + Kingdoms[k].Weariness * 0.1f) * deterred;
				if (_ageRng.NextDouble() >= chance)
					continue;
				int target = -1;
				for (int v = 0; v < Villages.Count; v++)
					if (Villages[v].Alive && Villages[v].Kingdom == foe && (target < 0 || Villages[v].Population > Villages[target].Population))
						target = v;
				if (target < 0)
					continue;
				Kingdoms[k].NextBomb = Scheduler.Time + YearSeconds * (10.0 + 10.0 * _ageRng.NextDouble());
				Nuke(Villages[target].X + 0.5f, Villages[target].Y + 0.5f, k);
				break;
			}
	}

	/// <summary>The age from which kingdoms can make the bomb (the Atomic Age).</summary>
	public int BombAge => Math.Max(0, Assets.Ages.FindIndex(a => a.Id == "atomic"));

	private bool HasSilo(int k)
	{
		if (_tSilo < 0)
			return false;
		for (int v = 0; v < Villages.Count; v++)
			if (Villages[v].Alive && Villages[v].Kingdom == k && CountOf(v, _tSilo, true) > 0)
				return true;
		return false;
	}

	/// <summary>A nuclear blast at (x, y), dropped by kingdom `by` (-1: the player). Everything
	/// within the blast dies, buildings fall, the land burns and blights, the air fills with
	/// fallout; the struck kingdom loses knowledge; each bomb brings the nuclear winter nearer.
	/// Returns the dead.</summary>
	public int Nuke(float x, float y, int by)
	{
		if (World == null || !World.InBounds((int)x, (int)y))
			return 0;
		const float Blast = 6f;
		int victimV = -1;
		int victim = KingdomNear(x, y, Blast + 4f, out victimV);
		string place = victimV >= 0 ? Villages[victimV].Name : PlaceNear(x, y).Replace("near ", "");
		int killed = 0;
		foreach (int i in UnitsWithin(x, y, Blast).ToArray())
		{
			KillUnit(i, Death.Disaster);
			killed++;
		}
		int ruined = 0;
		TilesWithin(x, y, Blast + 2f, t =>
		{
			float d = MathF.Sqrt((t % World.Width + 0.5f - x) * (t % World.Width + 0.5f - x) + (t / World.Width + 0.5f - y) * (t / World.Width + 0.5f - y));
			int b = _buildingAt.Length > t ? _buildingAt[t] : -1;
			if (b >= 0 && Buildings[b].Alive && Buildings[b].Type != _tRuin)
			{
				if (d <= Blast)
				{
					KnowledgeLost(b);
					ToRuin(b);
					ruined++;
				}
				else if (Buildings[b].Burning == 0f)
					SetBuildingOnFire(b);
			}
			if (World.Water[t] != SimWorld.WaterLand)
				return;
			if (d <= Blast)
			{
				while (_tileFirst[t] >= 0)
				{
					MarkStrip((int)_pY[_tileFirst[t]]);
					RemovePlant(_tileFirst[t]);
				}
				Grass[t] = 0f;
				Scorch[t] = 255;
				_scorchChanged.Add(t);
				Blight[t] = 12;
				_overlayChanged.Add(t);
			}
		});
		Ignite(x, y, Blast + 2.5f);
		DamageLairs(x, y, Blast, 1f, "is burned away by the blast");
		int z = ((int)y / ZoneSize) * _zw + (int)x / ZoneSize;
		if (z >= 0 && z < Smog.Length)
			Smog[z] += 260f;
		Carbon += 150f;
		Grieve(World.Index((int)x, (int)y), 12f, "struck", by);
		NukesFallen++;
		_skyFx.Add(("mushroom", x, y, Scheduler.Time));
		string who = by >= 0 ? Kingdoms[by].Name : "a fire from the heavens";
		LogEvent(by >= 0
			? $"{who} drops the bomb on {place}! {killed} die in a flash, {ruined} buildings are gone."
			: $"a sun falls on {place} by your hand: {killed} die in a flash, {ruined} buildings are gone.", "wars");
		if (by >= 0)
		{
			Remember(by, "bomb", $"{who} dropped the bomb on {place}", 3f);
			Feat(Kingdoms[by], $"dropped the bomb on {place}");
		}
		if (victim >= 0)
		{
			Remember(victim, "bomb", $"{place} burned under the bomb of {who}", 4f);
			Feat(Kingdoms[victim], $"{place} struck by the bomb");
			Setback(victim, 0.6f, $"the bomb on {place}");
			if (by >= 0 && by != victim)
				Kingdoms[victim].Memory[by] = Math.Max(-100f, (Kingdoms[victim].Memory.TryGetValue(by, out float m) ? m : 0f) - 60f);
		}
		else
			GodActs("meteor", x, y, Blast, 1);
		// Ash in the sky: enough bombs in a few years and the sun hides.
		float before = NuclearWinter;
		NuclearWinter = Math.Min(15f, NuclearWinter + 1.6f);
		if (before < 2f && NuclearWinter >= 2f)
		{
			LogEvent("ash covers the sky: the nuclear winter begins. Harvests fail and the snow comes in summer.", "disasters");
			for (int k = 0; k < Kingdoms.Count; k++)
				Remember(k, "winter", "the sun hid behind the ash of the bombs", 3f);
		}
		return killed;
	}

	/// <summary>Once a year: the ash thins; while it lasts, every people loses knowledge.</summary>
	private void WinterYear()
	{
		if (NuclearWinter <= 0f)
			return;
		bool deep = NuclearWinter >= 2f;
		NuclearWinter = Math.Max(0f, NuclearWinter - 1f);
		if (deep)
			for (int k = 0; k < Kingdoms.Count; k++)
				if (Kingdoms[k].Alive)
				{
					Setback(k, 0.08f, "the nuclear winter");
					foreach (var v in Villages)
						if (v.Alive && v.Kingdom == k)
							v.Food *= 0.6f;
				}
		if (deep && NuclearWinter < 2f)
			LogEvent("the ash thins and the sun comes back: the nuclear winter is over.", "disasters");
	}

	/// <summary>How much colder the world is under the ash, 0..0.7.</summary>
	private float WinterCold() => NuclearWinter >= 2f ? 0.7f : NuclearWinter * 0.35f;

	// ------------------------------------------------------------------ to the stars

	/// <summary>Once a year: kingdoms of the Space Age with a launch pad send rockets up: the
	/// first rocket, satellites (knowledge), the moon; in the Future Age, orbital cities.</summary>
	private void SpaceYear()
	{
		int space = Assets.Ages.FindIndex(a => a.Id == "space");
		if (space < 0 || _tLaunchPad < 0)
			return;
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive || kingdom.Age < space || _ageRng.NextDouble() > 0.5)
				continue;
			int pad = -1;
			foreach (var bld in Buildings)
				if (bld.Alive && bld.Done && bld.Type == _tLaunchPad && Villages[bld.Village].Kingdom == k)
				{
					pad = Buildings.IndexOf(bld);
					break;
				}
			if (pad >= 0)
				Launch(k, pad);
		}
	}

	/// <summary>Kingdom k sends a rocket up from building `pad`. Returns what it did.</summary>
	private string Launch(int k, int pad)
	{
		var kingdom = Kingdoms[k];
		var bld = Buildings[pad];
		RocketsLaunched++;
		kingdom.Rockets++;
		_skyFx.Add(("rocket", bld.X + 0.5f, bld.Y + 0.9f, Scheduler.Time));
		string from = Villages[bld.Village].Name;
		string feat;
		if (kingdom.Rockets == 1)
			feat = WorldFirst("rocket", k) ? "sends the first rocket of the world into the sky" : "sends its first rocket into the sky";
		else if (kingdom.Satellites < 3 || _ageRng.NextDouble() < 0.5)
		{
			kingdom.Satellites++;
			feat = $"puts a satellite in orbit (it has {kingdom.Satellites})";
		}
		else if (!kingdom.Moon)
		{
			kingdom.Moon = true;
			feat = WorldFirst("moon", k) ? "lands on the moon, the first people ever to walk there" : "lands on the moon";
		}
		else if (kingdom.Age > Assets.Ages.FindIndex(a => a.Id == "space") && !kingdom.Orbital)
		{
			kingdom.Orbital = true;
			feat = WorldFirst("orbital", k) ? "raises the first city in orbit" : "raises a city in orbit";
		}
		else
		{
			kingdom.Satellites++;
			feat = $"puts another satellite in orbit (it has {kingdom.Satellites})";
		}
		LogEvent($"{kingdom.Name} {feat}, from {from}.", "ages");
		Feat(kingdom, feat);
		if (!feat.StartsWith("puts"))
			Remember(k, "stars", $"{kingdom.Name} {feat}", 2f);
		return feat;
	}

	private bool WorldFirst(string what, int k)
	{
		if (_worldFirsts.ContainsKey(what))
			return false;
		_worldFirsts[what] = k;
		return true;
	}

	private static double SkyFxSeconds(string kind) => kind == "rocket" ? 7.0 : 9.0;

	// ------------------------------------------------------------------ powers

	/// <summary>The player lights a lamp in a kingdom's mind: half an age of knowledge.</summary>
	public bool PowerEnlighten(float x, float y)
	{
		int k = KingdomAt(x, y);
		if (k < 0 || !Kingdoms[k].Alive)
			return false;
		var kingdom = Kingdoms[k];
		kingdom.Knowledge += AgeRec(kingdom.Age).Knowledge * 0.5f;
		LogEvent($"a light from the sky falls on the scholars of {kingdom.Name}: they understand.", "ages");
		GodActs("bless", x, y, 6f, 4);
		if (kingdom.Knowledge >= AgeRec(kingdom.Age).Knowledge)
			Advance(k, "");
		return true;
	}

	/// <summary>The player makes a kingdom forget: it falls back an age.</summary>
	public bool PowerDarkAge(float x, float y)
	{
		int k = KingdomAt(x, y);
		if (k < 0 || !Kingdoms[k].Alive)
			return false;
		var kingdom = Kingdoms[k];
		if (kingdom.Age == 0)
		{
			kingdom.Knowledge = 0f;
			LogEvent($"the people of {kingdom.Name} forget what little they knew.", "ages");
			return true;
		}
		kingdom.Knowledge = Math.Min(kingdom.Knowledge, 0f);
		Setback(k, 0.01f, "a darkness that fell on their minds");
		GodActs("wrath", x, y, 6f, 4);
		return true;
	}

	/// <summary>The player drops the bomb.</summary>
	public int PowerNuke(float x, float y) => OnLand(x, y) ? Nuke(x, y, -1) : -1;

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>The ages of the kingdoms: index, name, people, age (index), age_name, knowledge
	/// (0..1 of the way to the next), gain (last year), peak_name, since, next_name, designs
	/// (kind → name), lineage (kind → "a → b → c"), feats, words, mind, rockets, satellites, moon,
	/// silo, color.</summary>
	public Godot.Collections.Array ProgressTable()
	{
		var list = new Godot.Collections.Array();
		for (int k = 0; k < Kingdoms.Count; k++)
		{
			var kingdom = Kingdoms[k];
			if (!kingdom.Alive)
				continue;
			var designs = new Godot.Collections.Dictionary();
			var lineage = new Godot.Collections.Dictionary();
			foreach (var kind in DesignKinds)
			{
				designs[kind] = kingdom.Designs.TryGetValue(kind, out string d) ? d : "";
				lineage[kind] = kingdom.Lineage.TryGetValue(kind, out var line) ? string.Join(" → ", line) : "";
			}
			list.Add(new Godot.Collections.Dictionary
			{
				["index"] = k, ["name"] = kingdom.Name, ["people"] = Assets.Species[kingdom.Species].Name, ["age"] = kingdom.Age,
				["age_name"] = AgeTitle(kingdom.Age), ["knowledge"] = Math.Clamp(kingdom.Knowledge / AgeRec(kingdom.Age).Knowledge, 0f, 1f),
				["points"] = kingdom.Knowledge, ["gain"] = kingdom.LastGain, ["peak"] = kingdom.Peak, ["peak_name"] = AgeTitle(kingdom.Peak),
				["since"] = kingdom.AgeSince, ["next_name"] = AgeTitle(kingdom.Age + 1), ["designs"] = designs, ["lineage"] = lineage,
				["feats"] = string.Join("\n", kingdom.Feats), ["words"] = kingdom.DesignWords, ["mind"] = kingdom.DesignMind,
				["rockets"] = kingdom.Rockets, ["satellites"] = kingdom.Satellites, ["moon"] = kingdom.Moon, ["silo"] = HasSilo(k),
				["color"] = kingdom.Color, ["strength"] = AgeRec(kingdom.Age).Strength,
			});
		}
		return list;
	}

	/// <summary>The world's state of progress: smog over the land, warming (degrees), carbon,
	/// nuclear winter (years), bombs fallen, rockets, the ages beyond named so far, the era.</summary>
	public Godot.Collections.Dictionary WorldAges()
	{
		float smog = 0f, worst = 0f;
		int smoggy = 0;
		foreach (float s in Smog)
		{
			smog += s;
			worst = Math.Max(worst, s);
			if (s > SmogBlight)
				smoggy++;
		}
		int blighted = 0;
		foreach (byte b in Blight)
			if (b > 0)
				blighted++;
		return new Godot.Collections.Dictionary
		{
			["warming"] = Warming, ["carbon"] = Carbon, ["smog"] = smog, ["worst_smog"] = worst, ["smoggy_zones"] = smoggy,
			["blighted"] = blighted, ["winter"] = NuclearWinter, ["nukes"] = NukesFallen, ["rockets"] = RocketsLaunched,
			["beyond"] = string.Join(", ", BeyondNames), ["ages"] = AgeCount,
			["era"] = EraTable(),
		};
	}

	/// <summary>The names of the ages of data/ages.json, in order (tests, interface).</summary>
	public string[] AgeNames()
	{
		var names = new string[AgeCount];
		for (int a = 0; a < names.Length; a++)
			names[a] = Assets.Ages[a].Name;
		return names;
	}

	public int KingdomAge(int k) => k >= 0 && k < Kingdoms.Count ? Kingdoms[k].Age : -1;

	public string KingdomAgeName(int k) => k >= 0 && k < Kingdoms.Count ? AgeTitle(Kingdoms[k].Age) : "";

	public float KingdomKnowledge(int k) => k >= 0 && k < Kingdoms.Count ? Kingdoms[k].Knowledge : 0f;

	/// <summary>Knowledge kingdom k would gain this year (tests).</summary>
	public float KnowledgeGainOf(int k) => k >= 0 && k < Kingdoms.Count && Kingdoms[k].Alive && Kingdoms[k].Capital >= 0 ? KnowledgeGain(k) : 0f;

	/// <summary>A kingdom's current design of a kind (vehicle, ship, home, weapon).</summary>
	public string KingdomDesign(int k, string kind) => k >= 0 && k < Kingdoms.Count && Kingdoms[k].Designs.TryGetValue(kind, out string d) ? d : "";

	/// <summary>Gives kingdom k knowledge; ages it crosses are entered at once (tests, tools).</summary>
	public void AddKnowledge(int k, float amount)
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive)
			return;
		Kingdoms[k].Knowledge += amount;
		while (Kingdoms[k].Knowledge >= AgeRec(Kingdoms[k].Age).Knowledge)
			Advance(k, "");
	}

	/// <summary>Takes kingdom k forward to age a, an age at a time, with the procedural minds
	/// (tests, tools).</summary>
	public void SetKingdomAge(int k, int a)
	{
		if (k < 0 || k >= Kingdoms.Count || !Kingdoms[k].Alive)
			return;
		while (Kingdoms[k].Age < a)
		{
			Kingdoms[k].Knowledge = AgeRec(Kingdoms[k].Age).Knowledge;
			Advance(k, "");
			if (Kingdoms[k].AgeAsking != null)
			{
				Kingdoms[k].AgeAsking = null;
				ApplyDesigns(k, ProceduralDesigns(k), "procedural");
			}
		}
		Kingdoms[k].Knowledge = 0f;
	}

	/// <summary>Kingdom k loses `share` of an age's knowledge (tests).</summary>
	public void SetbackNow(int k, float share, string why) => Setback(k, share, why);

	/// <summary>Runs the yearly turn of the ages now (tests).</summary>
	public void AgesYearNow() => AgesYear();

	/// <summary>Asks kingdom k's mind to name its age's things the usual way: the model if there is
	/// one (the answer comes later), else procedurally (tests).</summary>
	public void AskDesigns(int k)
	{
		if (k >= 0 && k < Kingdoms.Count && Kingdoms[k].Alive)
			ThinkDesigns(k, force: false);
	}

	/// <summary>The grammar the built-in model names an age's things under (tests).</summary>
	public string DesignGrammarOf(int k) => k >= 0 && k < Kingdoms.Count ? DesignGrammar(k) : "";

	/// <summary>Makes kingdom k's mind name its age's things now, procedurally (tests).</summary>
	public void DesignsNow(int k)
	{
		if (k >= 0 && k < Kingdoms.Count && Kingdoms[k].Alive)
			ThinkDesigns(k, force: true);
	}

	/// <summary>A mind's designs (JSON) for kingdom k (tests): "" when taken, else why not.</summary>
	public string SubmitDesigns(int k, string json) => k >= 0 && k < Kingdoms.Count && Kingdoms[k].Alive ? SubmitDesignJson(k, json, "model") : "no such kingdom";

	/// <summary>Puts smog over the zone of tile (x, y) (tests).</summary>
	public void AddSmog(int x, int y, float amount)
	{
		int z = (y / ZoneSize) * _zw + x / ZoneSize;
		if (z >= 0 && z < Smog.Length)
			Smog[z] += amount;
	}

	public float SmogAt(int x, int y)
	{
		int z = (y / ZoneSize) * _zw + x / ZoneSize;
		return z >= 0 && z < Smog.Length ? Smog[z] : 0f;
	}

	public int BlightAt(int x, int y) => World.InBounds(x, y) ? Blight[World.Index(x, y)] : 0;

	/// <summary>Adds carbon to the air (tests): CarbonPerDegree is a degree of warming.</summary>
	public void AddCarbon(float amount) => Carbon = Math.Max(0f, Carbon + amount);

	/// <summary>Kingdom k launches from its pad now, if it has one (tests). Returns what it did, or "".</summary>
	public string LaunchNow(int k)
	{
		for (int b = 0; b < Buildings.Count; b++)
			if (Buildings[b].Alive && Buildings[b].Done && Buildings[b].Type == _tLaunchPad && Villages[Buildings[b].Village].Kingdom == k)
				return Launch(k, b);
		return "";
	}

	/// <summary>Whether village v's age lets it build building `id` (tests, interface).</summary>
	public bool AgeAllows(int v, string id)
	{
		int type = Assets.BuildingIndex(id);
		return type >= 0 && v >= 0 && v < Villages.Count && Assets.Buildings[type].Age <= VillageAge(v);
	}

	/// <summary>Raises a finished building `id` in village v at once, on a free spot of its land
	/// (tests, tools). Returns its index, or -1.</summary>
	public int BuildNow(int v, string id)
	{
		int type = Assets.BuildingIndex(id);
		if (type < 0 || v < 0 || v >= Villages.Count || !Villages[v].Alive)
			return -1;
		int spot = FindSpot(v, Assets.Buildings[type]);
		if (spot < 0)
			return -1;
		return AddBuilding(type, spot % World.Width, spot / World.Width, v, 1f);
	}

	/// <summary>The bombs and rockets in the sky now: [kind, x, y, seconds since], ... (tests, drawing).</summary>
	public int SkyEffects() => _skyFx.Count;
}
