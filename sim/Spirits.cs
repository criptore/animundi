using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// Nature spirits (0.7, docs/NATURE.md). When a world is made, each large stretch of forest, sea,
/// mountains, plains, desert, swamp or snow gets a spirit of its own (data/spirits.json), with a
/// name and a place ("Sylwen, spirit of the Northern Woods"). A volcano the player raises gets
/// one too, later.
///
/// A spirit has a mood, from wrathful (-1) to content (1). What is done in its lands grieves
/// it: trees felled, land burned, beasts hunted, houses raised, mines dug, docks built; and it
/// knows which kingdom did it. Time heals it, and so do the kingdoms around that worship
/// nature or have a god of its domain.
///
/// Once a year its mood moves, and unless it acted in the last years (a spirit that has acted
/// keeps still for a while) its mind decides what it does: rest, warn (an omen), punish a kingdom (by the
/// disasters of its kind: beasts, overgrowth, flood, storm, quake, eruption, drought, tornado,
/// plague, wildfire) or bless one (bounty, fish, ore, bloom, rain, healing). The local model
/// decides when one runs (a JSON record: act, target, words), validated by the engine: a spirit
/// only punishes when it is angry, only blesses when it is not. Else a procedural mind does.
///
/// What a spirit does to a kingdom is remembered there, and becomes a myth and a god of its
/// domain (Religion.cs): spirits are worshipped as gods.
/// </summary>
public partial class Simulation
{
	public static readonly string[] SpiritActs = { "rest", "warn", "punish", "bless" };

	public sealed class Spirit
	{
		public int Index;
		public SpiritRecord Rec;
		public string Name = "", Place = "";
		public int[] Tiles = Array.Empty<int>();
		public float X, Y;
		/// <summary>-1 wrathful .. 1 content.</summary>
		public float Mood;
		/// <summary>What was done to it since it last thought, and by which kingdoms.</summary>
		public float Grief;
		public readonly Dictionary<string, int> Wounds = new();
		public readonly Dictionary<int, float> Blame = new();
		public string LastWounds = "";
		public string Act = "rest", Words = "", Mind = "";
		public int Target = -1, Born = 1, Worshippers;
		public double NextThought;
		/// <summary>Until then it only watches: a spirit that has acted keeps still for years.</summary>
		public double QuietUntil;
		public readonly List<string> Deeds = new();
		public Question Asking;
		public string FullName => $"{Name}, spirit of {Place}";
	}

	/// <summary>A spirit's decision as written by a mind, before validation.</summary>
	public sealed class SpiritDraft
	{
		[JsonPropertyName("act")] public string Act { get; set; } = "";
		[JsonPropertyName("target")] public string Target { get; set; } = "";
		[JsonPropertyName("words")] public string Words { get; set; } = "";
	}

	public readonly List<Spirit> Spirits = new();
	// The spirit each tile belongs to, or -1.
	private int[] _spiritAt = Array.Empty<int>();
	private Random _spiritRng = new(1);
	private double _nextSpiritWatch;
	/// <summary>A spirit's mood below this is anger: it may punish. Above BlessAbove, it may bless.</summary>
	public const float AngryBelow = -0.2f, WrathBelow = -0.55f, BlessAbove = 0.6f;
	/// <summary>How far from a spirit's lands (tiles) a village still lives "near" them.</summary>
	public const int SpiritReach = 10;

	private static string SpiritMemory(SpiritRecord rec) => "spirit:" + rec.Kind;

	private void SetupSpirits(int seed)
	{
		Spirits.Clear();
		int n = World.Width * World.Height;
		_spiritAt = new int[n];
		Array.Fill(_spiritAt, -1);
		_spiritRng = new Random(seed ^ 0x5b1a);
		_nextSpiritWatch = YearSeconds;
		int min = Math.Max(80, n / 150);
		var found = new List<(SpiritRecord rec, List<int> tiles)>();
		foreach (var rec in Assets.Spirits)
		{
			// The memory of its deeds: the god and the myth it gives (Religion.cs).
			MemoryDomains[SpiritMemory(rec)] = (rec.Domain, rec.Deed);
			if (rec.Late)
				continue;
			var regions = Regions(rec, min);
			regions.Sort((a, b) => b.Count.CompareTo(a.Count));
			for (int k = 0; k < Math.Min(2, regions.Count); k++)
				found.Add((rec, regions[k]));
		}
		// The largest lands first; a world holds nine spirits at most.
		found.Sort((a, b) => b.tiles.Count.CompareTo(a.tiles.Count));
		foreach (var (rec, tiles) in found)
			if (Spirits.Count < 9)
				AddSpirit(rec, tiles);
	}

	/// <summary>The stretches of a kind's biomes of at least `min` tiles that have no spirit yet.</summary>
	private List<List<int>> Regions(SpiritRecord rec, int min)
	{
		var biomes = new HashSet<int>();
		foreach (var name in rec.Biomes)
		{
			int b = Array.IndexOf(_biomeNames, name);
			if (b >= 0)
				biomes.Add(b);
		}
		var regions = new List<List<int>>();
		if (biomes.Count == 0)
			return regions;
		int n = World.Width * World.Height;
		var seen = new bool[n];
		var queue = new Queue<int>();
		for (int start = 0; start < n; start++)
		{
			if (seen[start] || !biomes.Contains(World.Biome[start]) || _spiritAt[start] >= 0)
				continue;
			var tiles = new List<int>();
			seen[start] = true;
			queue.Enqueue(start);
			while (queue.Count > 0)
			{
				int t = queue.Dequeue();
				tiles.Add(t);
				int x = t % World.Width, y = t / World.Width;
				for (int k = 0; k < 4; k++)
				{
					int nx = x + (k == 0 ? 1 : k == 1 ? -1 : 0), ny = y + (k == 2 ? 1 : k == 3 ? -1 : 0);
					if (!World.InBounds(nx, ny))
						continue;
					int nt = World.Index(nx, ny);
					if (!seen[nt] && biomes.Contains(World.Biome[nt]) && _spiritAt[nt] < 0)
					{
						seen[nt] = true;
						queue.Enqueue(nt);
					}
				}
			}
			if (tiles.Count >= min)
				regions.Add(tiles);
		}
		return regions;
	}

	private Spirit AddSpirit(SpiritRecord rec, List<int> tiles)
	{
		var s = new Spirit { Index = Spirits.Count, Rec = rec, Tiles = tiles.ToArray(), Born = Year() };
		double sx = 0, sy = 0;
		foreach (int t in tiles)
		{
			sx += t % World.Width;
			sy += t / World.Width;
			_spiritAt[t] = s.Index;
		}
		float cx = (float)(sx / tiles.Count), cy = (float)(sy / tiles.Count);
		// It dwells on the tile of its lands nearest to their middle.
		float best = float.MaxValue;
		foreach (int t in tiles)
		{
			float d = (t % World.Width - cx) * (t % World.Width - cx) + (t / World.Width - cy) * (t / World.Width - cy);
			if (d < best)
			{
				best = d;
				s.X = t % World.Width + 0.5f;
				s.Y = t / World.Width + 0.5f;
			}
		}
		var names = rec.Names;
		int half = Math.Max(1, names.Count / 2);
		s.Name = names.Count >= 2 ? names[_spiritRng.Next(half)] + names[half + _spiritRng.Next(names.Count - half)] : "The Nameless";
		float fx = (cx / World.Width - 0.5f) * 2f, fy = (cy / World.Height - 0.5f) * 2f;
		string ns = fy < -0.25f ? "North" : fy > 0.25f ? "South" : "", ew = fx < -0.25f ? "West" : fx > 0.25f ? "East" : "";
		string compass = ns == "" && ew == "" ? "Inner" : ns != "" && ew != "" ? $"{ns}-{ew}ern" : $"{ns}{ew}ern";
		for (int k = 0; k < Math.Max(1, rec.Places.Count); k++)
		{
			string word = rec.Places.Count > 0 ? rec.Places[(s.Index + k) % rec.Places.Count] : "Wilds";
			s.Place = rec.Late ? $"the {word}" : $"the {compass} {word}";
			if (!Spirits.Exists(o => o.Place == s.Place))
				break;
		}
		s.Mood = 0.25f + 0.3f * (float)_spiritRng.NextDouble();
		s.NextThought = Scheduler.Time + YearSeconds * (2.0 + _spiritRng.NextDouble());
		Spirits.Add(s);
		return s;
	}

	/// <summary>Land the world did not have at first (the player's volcanoes) gets its spirit
	/// once it is large enough.</summary>
	private void LateSpirits()
	{
		foreach (var rec in Assets.Spirits)
		{
			if (!rec.Late || Spirits.Count >= 12 || Spirits.Exists(s => s.Rec == rec))
				continue;
			var regions = Regions(rec, 12);
			if (regions.Count == 0)
				continue;
			regions.Sort((a, b) => b.Count.CompareTo(a.Count));
			var s = AddSpirit(rec, regions[0]);
			s.Mood = 0f;
			LogEvent($"a spirit wakes {PlaceNear(s.X, s.Y)}: {s.FullName}. {rec.Lore}", "nature");
		}
	}

	// ------------------------------------------------------------------ what grieves it

	/// <summary>Something was done on tile t that grieves the spirit of that land: `what` is
	/// felled, burned, hunted, built, mined, fished or struck; `kingdom` did it, or -1.</summary>
	private void Grieve(int t, float amount, string what, int kingdom = -1)
	{
		if (t < 0 || t >= _spiritAt.Length || _spiritAt[t] < 0)
			return;
		var s = Spirits[_spiritAt[t]];
		s.Grief += amount;
		s.Wounds[what] = (s.Wounds.TryGetValue(what, out int n) ? n : 0) + 1;
		if (kingdom >= 0)
			s.Blame[kingdom] = (s.Blame.TryGetValue(kingdom, out float b) ? b : 0f) + amount;
	}

	/// <summary>The year's toll of what stands in a spirit's lands: every building weighs a
	/// little, mines weigh on the mountains, docks on the sea.</summary>
	private void StandingToll(Spirit s)
	{
		for (int b = 0; b < Buildings.Count; b++)
		{
			var bld = Buildings[b];
			if (!bld.Alive || bld.Type == _tRuin || !Villages[bld.Village].Alive)
				continue;
			int k = Villages[bld.Village].Kingdom;
			int t = World.Index(bld.X, bld.Y);
			if (_spiritAt[t] == s.Index)
			{
				if (bld.Type == _tMine)
					Grieve(t, 1.5f, "mined", k);
				else
				{
					s.Grief += 0.12f;
					if (k >= 0)
						s.Blame[k] = (s.Blame.TryGetValue(k, out float old) ? old : 0f) + 0.12f;
				}
			}
			else if (bld.Type == _tDock)
				for (int d = 0; d < 4; d++)
				{
					int nx = bld.X + (d == 0 ? 1 : d == 1 ? -1 : 0), ny = bld.Y + (d == 2 ? 1 : d == 3 ? -1 : 0);
					if (World.InBounds(nx, ny) && _spiritAt[World.Index(nx, ny)] == s.Index)
					{
						Grieve(World.Index(nx, ny), 0.8f, "fished", k);
						break;
					}
				}
		}
	}

	private static string WoundsText(Spirit s)
	{
		var parts = new List<string>();
		foreach (var (what, n) in s.Wounds)
			parts.Add(what switch
			{
				"felled" => $"{n} trees felled", "burned" => $"{n} tiles burned", "hunted" => $"{n} beasts hunted", "built" => $"{n} buildings raised",
				"mined" => $"{n} mines dug", "fished" => $"{n} docks on its shores", "struck" => $"struck {n} times from the sky",
				"polluted" => $"choked by smoke {n} times", _ => $"{n} {what}",
			});
		return string.Join(", ", parts);
	}

	/// <summary>Kingdoms with a village in or near the spirit's lands: (kingdom, its village
	/// nearest to where the spirit dwells), the most blamed first.</summary>
	private List<(int k, int v)> KingdomsNearSpirit(Spirit s)
	{
		var best = new Dictionary<int, (int v, float d)>();
		for (int v = 0; v < Villages.Count; v++)
		{
			var o = Villages[v];
			if (!o.Alive || o.Kingdom < 0 || !Kingdoms[o.Kingdom].Alive)
				continue;
			bool near = false;
			for (int dy = -SpiritReach; dy <= SpiritReach && !near; dy += 5)
				for (int dx = -SpiritReach; dx <= SpiritReach && !near; dx += 5)
					near = World.InBounds(o.X + dx, o.Y + dy) && _spiritAt[World.Index(o.X + dx, o.Y + dy)] == s.Index;
			if (!near)
				continue;
			float d = (o.X - s.X) * (o.X - s.X) + (o.Y - s.Y) * (o.Y - s.Y);
			if (!best.TryGetValue(o.Kingdom, out var b) || d < b.d)
				best[o.Kingdom] = (v, d);
		}
		var list = new List<(int k, int v)>();
		foreach (var (k, b) in best)
			list.Add((k, b.v));
		list.Sort((a, b) => (s.Blame.TryGetValue(b.k, out float bb) ? bb : 0f).CompareTo(s.Blame.TryGetValue(a.k, out float ab) ? ab : 0f));
		return list;
	}

	/// <summary>Whether kingdom k worships this spirit: it worships nature, or has a god of the
	/// spirit's domain.</summary>
	private bool Worships(int k, Spirit s)
	{
		var c = Kingdoms[k].Culture;
		return NatureOf(c) == "worship nature" || c.Gods.Exists(g => !g.Player && g.Domain == s.Rec.Domain);
	}

	// ------------------------------------------------------------------ every second

	private void SpiritStep(float dt)
	{
		if (World == null || !Law("spirits"))
			return;
		if (Scheduler.Time >= _nextSpiritWatch)
		{
			_nextSpiritWatch = Scheduler.Time + YearSeconds;
			LateSpirits();
		}
		foreach (var s in Spirits)
		{
			if (s.Asking != null)
			{
				if (s.Asking.Take(Scheduler.Time, out string json, out string why))
				{
					s.Asking = null;
					string error = json == null ? why : SubmitSpiritJson(s, json, "model");
					LastModelAnswer = json ?? "";
					LastModelError = error ?? "";
					if (string.IsNullOrEmpty(error))
						ModelAnswers++;
					else
					{
						ModelFailures++;
						ApplySpirit(s, ProceduralSpirit(s), "procedural");
					}
				}
			}
			else if (Scheduler.Time >= s.NextThought)
				ThinkSpirit(s, force: false);
		}
	}

	/// <summary>Once a year: the year's griefs move the spirit's mood, then its mind decides
	/// (the model in the background, or the procedural mind now).</summary>
	private void ThinkSpirit(Spirit s, bool force)
	{
		s.NextThought = Scheduler.Time + YearSeconds * (0.9 + 0.3 * _spiritRng.NextDouble());
		StandingToll(s);
		var around = KingdomsNearSpirit(s);
		s.Worshippers = 0;
		foreach (var (k, _) in around)
			if (Worships(k, s))
				s.Worshippers++;
		// A wide land bears more than a small one.
		float bears = 6f + s.Tiles.Length / 150f;
		// The mood of the world (Eras.cs): spirits heal faster in bright and magical eras.
		s.Mood = Math.Clamp(s.Mood - 0.5f * s.Grief / bears + 0.12f * EraSpirits() + 0.1f * s.Worshippers, -1f, 1f);
		s.LastWounds = WoundsText(s);
		s.Grief = 0f;
		s.Wounds.Clear();
		if (!force && Scheduler.Time < s.QuietUntil)
		{
			s.Act = "rest";
			s.Target = -1;
			return;
		}
		if (!force)
		{
			var task = AskAnyMind(SpiritPrompt(s), SpiritGrammar(s), SpiritSchema(s),
				"You are the mind of a spirit of nature in a world simulation. Answer with one JSON record.");
			if (task != null)
			{
				s.Asking = new Question { Pending = task, Asked = Scheduler.Time };
				return;
			}
		}
		ApplySpirit(s, ProceduralSpirit(s), "procedural");
	}

	private static readonly Dictionary<string, string[]> SpiritWords = new()
	{
		["rest"] = new[] { "I watch.", "The seasons turn. I turn with them.", "Let them be, for now." },
		["warn"] = new[] { "I count what {kingdom} takes from {place}. The count grows long.", "{kingdom} walks too loudly in {place}.", "Take less, {kingdom}, or I will take from you." },
		["punish"] = new[] { "{kingdom} has taken enough. Now I take.", "Let {kingdom} learn what {place} remembers.", "I warned {kingdom}. I do not warn twice." },
		["bless"] = new[] { "{kingdom} has walked softly in {place}. Let them eat.", "The quiet years have been good. I give.", "Those who honour {place} shall not want." },
	};

	/// <summary>What the spirit does, from its mood: wrathful, it punishes the kingdom it blames
	/// most; angry, it warns it; content, it blesses a kingdom that worships it (or any near);
	/// else it rests.</summary>
	private SpiritDraft ProceduralSpirit(Spirit s)
	{
		var around = KingdomsNearSpirit(s);
		string act = "rest";
		int k = -1;
		int blamed = around.FindIndex(a => s.Blame.TryGetValue(a.k, out float b) && b > 0.5f);
		if (s.Mood <= WrathBelow && blamed >= 0)
		{
			act = "punish";
			k = around[blamed].k;
		}
		else if (s.Mood <= AngryBelow && blamed >= 0)
		{
			act = "warn";
			k = around[blamed].k;
		}
		else if (s.Mood >= BlessAbove && around.Count > 0)
		{
			act = "bless";
			int devout = around.FindIndex(a => Worships(a.k, s));
			k = around[devout >= 0 ? devout : around.Count - 1].k;
		}
		var lines = SpiritWords[act];
		string words = lines[_spiritRng.Next(lines.Length)].Replace("{place}", s.Place);
		if (k >= 0)
			words = words.Replace("{kingdom}", Kingdoms[k].Name);
		return new SpiritDraft { Act = act, Target = k >= 0 ? Clean(Kingdoms[k].Name) : "", Words = Clean(words) };
	}

	/// <summary>Checks a spirit's decision: a known act; a kingdom near its lands to warn, punish
	/// or bless; it only warns or punishes when angry, only blesses when it is not; words of one
	/// plain sentence. Returns null when valid.</summary>
	private string ValidateSpirit(Spirit s, SpiritDraft d, out int k)
	{
		k = -1;
		if (d == null)
			return "empty";
		if (Array.IndexOf(SpiritActs, d.Act) < 0)
			return $"unknown act '{d.Act}'";
		string error = TextError(d.Words, 2, 160);
		if (error != null)
			return error;
		if (d.Act == "rest")
			return null;
		foreach (var a in KingdomsNearSpirit(s))
			if (Clean(Kingdoms[a.k].Name) == (d.Target ?? "").Trim())
				k = a.k;
		if (k < 0)
			return $"no kingdom '{d.Target}' near its lands";
		if ((d.Act == "punish" || d.Act == "warn") && s.Mood > AngryBelow)
			return "a spirit at peace neither warns nor punishes";
		if (d.Act == "bless" && s.Mood < 0f)
			return "an angry spirit does not bless";
		return null;
	}

	private string SubmitSpiritJson(Spirit s, string json, string mind)
	{
		SpiritDraft d;
		try
		{
			d = JsonSerializer.Deserialize<SpiritDraft>(json);
		}
		catch (Exception e)
		{
			return "not valid JSON: " + e.Message;
		}
		string error = ValidateSpirit(s, d, out _);
		if (error != null)
			return error;
		ApplySpirit(s, d, mind);
		return "";
	}

	private void SpiritDeed(Spirit s, string text)
	{
		s.Deeds.Add($"year {Year()}: {text}");
		if (s.Deeds.Count > 6)
			s.Deeds.RemoveAt(0);
	}

	private void ApplySpirit(Spirit s, SpiritDraft d, string mind)
	{
		if (ValidateSpirit(s, d, out int k) != null)
			return;
		s.Act = d.Act;
		s.Words = d.Words.Trim();
		s.Mind = mind;
		s.Target = k;
		if (k < 0)
			return;
		// It has acted: it keeps still for years (a warning less long than a blow or a gift).
		s.QuietUntil = Scheduler.Time + YearSeconds * (d.Act == "warn" ? 3.0 + 2.0 * _spiritRng.NextDouble() : 6.0 + 5.0 * _spiritRng.NextDouble());
		int v = KingdomsNearSpirit(s).Find(a => a.k == k).v;
		var village = Villages[v];
		var culture = Kingdoms[k].Culture;
		switch (d.Act)
		{
			case "warn":
				LogEvent($"{s.FullName}, sends an omen over {village.Name}: \"{s.Words}\"", "nature");
				SpiritDeed(s, $"warned {Kingdoms[k].Name}");
				Remember(k, SpiritMemory(s.Rec), $"{s.FullName}, sent an omen over {village.Name}", 1.5f);
				culture.Faith = Math.Min(100f, culture.Faith + 3f);
				break;
			case "punish":
			{
				LogEvent($"{s.FullName}: \"{s.Words}\"", "nature");
				string done = Punish(s, k, v);
				SpiritDeed(s, $"{done} {village.Name}");
				Remember(k, SpiritMemory(s.Rec), $"{s.FullName}, {done} {village.Name}", 3f);
				// Its wrath is spent, and the debt is paid.
				s.Mood = Math.Min(1f, s.Mood + 0.55f);
				s.Blame.Remove(k);
				break;
			}
			case "bless":
			{
				string gift = Bless(s, k, v);
				LogEvent($"{s.FullName}, blesses {village.Name} with {gift}: \"{s.Words}\"", "nature");
				SpiritDeed(s, $"blessed {village.Name} with {gift}");
				Remember(k, SpiritMemory(s.Rec), $"{s.FullName}, blessed {village.Name} with {gift}", 2f);
				culture.Faith = Math.Min(100f, culture.Faith + 4f);
				s.Mood -= 0.25f;
				break;
			}
		}
		// Old grudges fade.
		foreach (int other in new List<int>(s.Blame.Keys))
			s.Blame[other] *= 0.5f;
	}

	// ------------------------------------------------------------------ wrath and gifts

	/// <summary>The tile of the spirit's lands nearest to (x, y), among a sample of them.</summary>
	private int SpiritTileNear(Spirit s, float x, float y, bool land)
	{
		int best = -1;
		float bestD = float.MaxValue;
		for (int n = 0; n < 240; n++)
		{
			int t = s.Tiles[_spiritRng.Next(s.Tiles.Length)];
			if (land && World.Water[t] != SimWorld.WaterLand)
				continue;
			float d = (t % World.Width - x) * (t % World.Width - x) + (t / World.Width - y) * (t / World.Width - y);
			if (d < bestD)
			{
				bestD = d;
				best = t;
			}
		}
		return best;
	}

	/// <summary>The spirit strikes village v of kingdom k with one of the wraths of its kind.
	/// Returns what it did, as told ("sent its beasts against").</summary>
	private string Punish(Spirit s, int k, int v)
	{
		var village = Villages[v];
		float x = village.X + 0.5f, y = village.Y + 0.5f;
		string wrath = s.Rec.Wrath.Count > 0 ? s.Rec.Wrath[_spiritRng.Next(s.Rec.Wrath.Count)] : "storm";
		string cause = s.FullName;
		switch (wrath)
		{
			case "flood":
				if (StartDisaster("flood", x, y, 8f, cause) != null)
					return "raised the waters over";
				break;
			case "quake":
				if (StartDisaster("earthquake", x, y, 7f, cause) != null)
					return "shook the ground under";
				break;
			case "drought":
				if (StartDisaster("drought", x, y, 13f, cause) != null)
					return "dried up the land of";
				break;
			case "tornado":
				if (StartDisaster("tornado", x + 3f, y, 1.8f, cause) != null || StartDisaster("tornado", x, y, 1.8f, cause) != null)
					return "sent a whirlwind at";
				break;
			case "eruption":
			{
				// The fire opens in its own lands, on the side of the village.
				int t = SpiritTileNear(s, x, y, land: true);
				if (t >= 0 && StartDisaster("eruption", t % World.Width + 0.5f, t / World.Width + 0.5f, 2f, cause) != null)
					return "opened the earth in fire above";
				break;
			}
			case "wildfire":
			{
				int t = SpiritTileNear(s, x, y, land: true);
				if (t >= 0 && StartDisaster("wildfire", t % World.Width + 0.5f, t / World.Width + 0.5f, 3f, cause) != null)
					return "sent fire towards";
				if (StartDisaster("wildfire", x + 4f, y, 3f, cause) != null)
					return "sent fire towards";
				break;
			}
			case "plague":
			{
				var d = NewDisease(s.Place, cause);
				if (InfectVillage(v, d, 4) > 0)
				{
					LogEvent($"a sickness rises from {s.Place} into {village.Name}: {d.Name}, {d.SymptomText}.", "disasters");
					return "breathed a sickness on";
				}
				d.EndYear = Year();
				break;
			}
			case "overgrowth":
				Overgrow(v);
				LogEvent($"the wild swallows the fields of {village.Name} in a night.", "disasters");
				return "swallowed the fields of";
			case "beasts":
				if (Beasts(s, v) > 0)
					return "sent its beasts against";
				break;
		}
		// A storm, when its own wrath finds no hold there.
		for (int n = 0; n < 3; n++)
			Bolt(x + (float)_spiritRng.NextDouble() * 8f - 4f, y + (float)_spiritRng.NextDouble() * 8f - 4f);
		StartDisaster("tornado", x, y, 1.8f, cause);
		LogEvent($"a storm breaks over {village.Name}.", "disasters");
		return "threw a storm at";
	}

	/// <summary>A bolt of lightning at (x, y): it kills what stands there and lights the land.</summary>
	private void Bolt(float x, float y)
	{
		if (!World.IsLandAt(x, y))
			return;
		foreach (int i in UnitsWithin(x, y, 1.2f).ToArray())
			if (!Assets.Species[Units.Species[i]].IsLegend)
				KillUnit(i, Death.Disaster);
		Ignite(x, y, 1.3f);
	}

	/// <summary>The fiercest hunters born in the spirit's biomes come out of the wild around
	/// village v, hungry. Returns how many.</summary>
	private int Beasts(Spirit s, int v)
	{
		int species = -1;
		for (int k = 0; k < Assets.Species.Count; k++)
		{
			var sp = Assets.Species[k];
			if (sp.IsPeople || sp.IsLegend || !sp.Hunts || !sp.IsNatural || IsMonster(k))
				continue;
			bool lives = false;
			foreach (var biome in s.Rec.Biomes)
				lives |= sp.Natural.ContainsKey(biome);
			if (lives && (species < 0 || sp.Size > Assets.Species[species].Size))
				species = k;
		}
		if (species < 0)
			species = Assets.SpeciesIndex("wolf");
		if (species < 0)
			return 0;
		var village = Villages[v];
		int want = 4 + _spiritRng.Next(3), came = 0;
		for (int tries = 0; tries < 40 && came < want; tries++)
		{
			double a = _spiritRng.NextDouble() * Math.PI * 2;
			float far = 4f + 3f * (float)_spiritRng.NextDouble();
			float x = village.X + 0.5f + (float)Math.Cos(a) * far, y = village.Y + 0.5f + (float)Math.Sin(a) * far;
			if (!World.IsLandAt(x, y))
				continue;
			int i = SpawnUnit(species, x, y, false);
			Units.Hunger[i] = 0.9f;
			came++;
		}
		if (came > 0)
			LogEvent($"{came} {Assets.Species[species].Name.ToLower()}s come out of {s.Place} upon {village.Name}.", "disasters");
		return came;
	}

	/// <summary>The wild takes back village v's fields: the wheat is lost, a third of its food
	/// spoils, and saplings sprout all over its land.</summary>
	private void Overgrow(int v)
	{
		var village = Villages[v];
		foreach (int t in village.Fields)
			if (_wheat[t] > 0f)
			{
				_wheat[t] = 0.0001f;
				_overlayChanged.Add(t);
			}
		village.Food *= 0.67f;
		int planted = 0;
		for (int tries = 0; tries < 300 && planted < 50; tries++)
		{
			int x = village.X + _spiritRng.Next(-9, 10), y = village.Y + _spiritRng.Next(-9, 10);
			if (!World.IsLand(x, y))
				continue;
			int t = World.Index(x, y);
			var list = _biomePlants[World.Biome[t]];
			if (list == null || list.Count == 0 || _buildingAt[t] >= 0 || _ground[t] == GroundRoad || _tileCount[t] > 2)
				continue;
			int sprite = list[_spiritRng.Next(list.Count)].sprite;
			float px = x + 0.1f + (float)_spiritRng.NextDouble() * 0.8f, py = y + 0.2f + (float)_spiritRng.NextDouble() * 0.75f;
			if (OnLandFootprint(sprite, px, py) && AddPlant(sprite, px, py, _spiritRng.Next(2) == 0, 0.9f + (float)_spiritRng.NextDouble() * 0.3f) >= 0)
				planted++;
		}
	}

	/// <summary>The spirit's gift to village v of kingdom k. Returns what it gave, as told.</summary>
	private string Bless(Spirit s, int k, int v)
	{
		var village = Villages[v];
		switch (s.Rec.Gift)
		{
			case "fish":
				village.Food += 30f + village.Population;
				return "nets full of fish";
			case "ore":
				village.Stone += 30f;
				village.Metal += 12f;
				return "veins of ore";
			case "rain":
				EndDroughts(village.X, village.Y, 12f);
				Bloom(s, village.X, village.Y, 14f);
				return "rain";
			case "healing":
			{
				int healed = 0;
				for (int i = 0; i < Units.Capacity; i++)
					if (Units.Alive[i] && Units.Sick[i] > 0 && KingdomOfUnit(i) == k)
					{
						Recover(i, immune: true);
						healed++;
					}
				village.Food += 15f;
				return healed > 0 ? $"healing herbs ({healed} of the sick rise)" : "healing herbs";
			}
			case "bloom":
				Bloom(s, village.X, village.Y, 14f);
				foreach (int t in village.Fields)
					if (_wheat[t] > 0f && _wheat[t] < 1f)
					{
						_wheat[t] = 1f;
						_overlayChanged.Add(t);
					}
				return "a flowering of the land";
			default:
				village.Food += 40f + village.Population;
				return "a rich hunt and harvest";
		}
	}

	/// <summary>The land greens around (x, y): ash heals, grass is full.</summary>
	private void Bloom(Spirit s, float x, float y, float radius)
	{
		TilesWithin(x, y, radius, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand || Parched[t] > 0)
				return;
			if (Scorch[t] > 0)
			{
				Scorch[t] = 0;
				_scorchChanged.Add(t);
			}
			Grass[t] = _fertility[World.Biome[t]];
		});
	}

	// ------------------------------------------------------------------ the model's side

	private static string MoodWord(float mood) =>
		mood >= BlessAbove ? "content" : mood >= 0.2f ? "calm" : mood > AngryBelow ? "watchful" : mood > WrathBelow ? "angry" : "wrathful";

	public string SpiritPrompt(Spirit s)
	{
		var sb = new StringBuilder();
		sb.Append($"You are {s.FullName}, a spirit of nature: your body is {s.Tiles.Length} tiles of {string.Join(", ", s.Rec.Biomes).ToLower()}. {s.Rec.Lore}\n");
		sb.Append($"Year {Year()}. Your mood is {s.Mood:0.00} on a scale from -1 (wrathful) to 1 (content): you are {MoodWord(s.Mood)}.\n");
		sb.Append(s.LastWounds != "" ? $"This year in your lands: {s.LastWounds}.\n" : "This year no one harmed your lands.\n");
		if (s.Deeds.Count > 0)
			sb.Append($"What you have done: {string.Join("; ", s.Deeds)}.\n");
		var around = KingdomsNearSpirit(s);
		if (around.Count > 0)
		{
			sb.Append("Kingdoms that live in or near your lands:\n");
			foreach (var (k, v) in around)
				sb.Append($"- {Clean(Kingdoms[k].Name)} ({Assets.Species[Kingdoms[k].Species].Name}, they {NatureOf(Kingdoms[k].Culture)}): village {Villages[v].Name}, "
					+ $"harm done to you {(s.Blame.TryGetValue(k, out float b) ? b : 0f):0.0}{(Worships(k, s) ? ", they worship you" : "")}\n");
		}
		else
			sb.Append("No kingdom lives near your lands.\n");
		sb.Append($"Choose your \"act\": rest; warn (an omen over a kingdom, only if your mood is below {AngryBelow}); punish (strike a kingdom with {string.Join(" or ", s.Rec.Wrath)}, only if your mood is below {AngryBelow}); ");
		sb.Append($"bless (give a kingdom {s.Rec.Gift}, only if your mood is 0 or more). \"target\" is the kingdom's exact name, or \"\" to rest. \"words\": what you say, one sentence in your voice. Answer with the JSON record only.\n");
		return sb.ToString();
	}

	private string SpiritGrammar(Spirit s)
	{
		var targets = new List<string> { "\"\\\"\\\"\"" };
		foreach (var a in KingdomsNearSpirit(s))
			targets.Add($"\"\\\"{Clean(Kingdoms[a.k].Name)}\\\"\"");
		var acts = new List<string>();
		foreach (var a in SpiritActs)
			acts.Add($"\"\\\"{a}\\\"\"");
		return "root ::= \"{\" ws \"\\\"act\\\":\" ws act \",\" ws \"\\\"target\\\":\" ws target \",\" ws \"\\\"words\\\":\" ws words ws \"}\"\n"
			+ $"act ::= {string.Join(" | ", acts)}\ntarget ::= {string.Join(" | ", targets)}\nwords ::= {LocalModel.Text(150, 2)}\nws ::= [ ]?\n";
	}

	private string SpiritSchema(Spirit s)
	{
		var targets = new List<string> { "" };
		foreach (var a in KingdomsNearSpirit(s))
			targets.Add(Clean(Kingdoms[a.k].Name));
		return JsonSerializer.Serialize(new Dictionary<string, object>
		{
			["type"] = "object", ["required"] = new[] { "act", "target", "words" },
			["properties"] = new Dictionary<string, object>
			{
				["act"] = new Dictionary<string, object> { ["enum"] = SpiritActs },
				["target"] = new Dictionary<string, object> { ["enum"] = targets },
				["words"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 160 },
			},
		});
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>The spirits of this world: index, name, full_name, kind, place, tiles, mood
	/// (-1..1), mood_word, act, words, mind, target, wounds, deeds, worshippers, wrath, gift,
	/// lore, x, y.</summary>
	public Godot.Collections.Array SpiritTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var s in Spirits)
			list.Add(new Godot.Collections.Dictionary
			{
				["index"] = s.Index, ["name"] = s.Name, ["full_name"] = s.FullName, ["kind"] = s.Rec.Kind, ["place"] = s.Place, ["tiles"] = s.Tiles.Length,
				["mood"] = s.Mood, ["mood_word"] = MoodWord(s.Mood), ["act"] = s.Act, ["words"] = s.Words, ["mind"] = s.Mind,
				["target"] = s.Target >= 0 && s.Target < Kingdoms.Count ? Kingdoms[s.Target].Name : "",
				["wounds"] = s.LastWounds, ["deeds"] = string.Join("\n", s.Deeds), ["worshippers"] = s.Worshippers,
				["wrath"] = string.Join(", ", s.Rec.Wrath), ["gift"] = s.Rec.Gift, ["lore"] = s.Rec.Lore, ["domain"] = s.Rec.Domain,
				["x"] = s.X, ["y"] = s.Y, ["born"] = s.Born, ["grief"] = s.Grief,
			});
		return list;
	}

	/// <summary>The spirit of the land at (x, y): its index, or -1.</summary>
	public int SpiritAt(float x, float y) => World != null && World.InBounds((int)x, (int)y) ? _spiritAt[World.Index((int)x, (int)y)] : -1;

	private Spirit SpiritByIndex(int index) => index >= 0 && index < Spirits.Count ? Spirits[index] : null;

	public void SetSpiritMood(int index, float mood)
	{
		var s = SpiritByIndex(index);
		if (s != null)
			s.Mood = Math.Clamp(mood, -1f, 1f);
	}

	/// <summary>Grieves a spirit as if kingdom `k` had harmed its lands (tests).</summary>
	public void GrieveSpirit(int index, float amount, int k)
	{
		var s = SpiritByIndex(index);
		if (s != null)
			Grieve(s.Tiles[0], amount, "felled", k);
	}

	/// <summary>Makes a spirit's mind decide now with the procedural mind (tests).</summary>
	public void SpiritThinkNow(int index)
	{
		var s = SpiritByIndex(index);
		if (s != null)
			ThinkSpirit(s, force: true);
	}

	/// <summary>A mind's decision (JSON) for a spirit (tests): "" when taken.</summary>
	public string SubmitSpiritJson(int index, string json)
	{
		var s = SpiritByIndex(index);
		return s == null ? "no such spirit" : SubmitSpiritJson(s, json, "model");
	}

	/// <summary>Looks for spirits of new lands now (tests): volcanoes the player raised.</summary>
	public void SpiritWatchNow() => LateSpirits();
}
