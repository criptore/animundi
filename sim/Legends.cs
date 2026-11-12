using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// Legendary monsters (docs/LEGENDS.md). Common monsters are creatures like any other; a legend
/// is unique in its world, has a name, and has a mind. Each world draws which legends it holds
/// (data/legends.json: their lair must be in it too, and the dice must agree) and when each wakes;
/// the player can call one into the world with the creatures' power at any time, but never two
/// of the same.
///
/// Awake, a legend's mind chooses what it does about twice a year: slumber in its lair and heal,
/// roam its lands, hunt beasts, raid a village, or demand tribute of a kingdom. The local model
/// decides when one runs (a JSON record: goal, target, words), else a procedural mind from its
/// temper (wrath, greed, cunning, pride), its wounds, its hunger and its grudges.
///
/// Its deeds enter the world's lore: they are told in the chronicle (event filter "Legends"),
/// the kingdoms that live through them remember them and make myths and gods of them, and the
/// warrior who slays one is hailed a hero.
/// </summary>
public partial class Simulation
{
	public static readonly string[] LegendGoals = { "slumber", "roam", "hunt", "raid", "tribute" };

	public sealed class Legend
	{
		public LegendRecord Rec;
		public int Species;
		public string Name = "";
		/// <summary>absent (not in this world), dormant, awake, slain.</summary>
		public string State = "absent";
		public int WakeYear = -1;
		public int Unit = -1;
		public float Health;
		public float LairX, LairY;
		public string Goal = "slumber";
		/// <summary>The kingdom it raids or demands tribute of, and the village it falls upon.</summary>
		public int Target = -1, TargetVillage = -1;
		public double GoalUntil, NextThought, NextStrike, LastStrike = -10, LastMeal, Demanded = -1;
		public float Tribute;
		public string Words = "", Mind = "";
		public int Kills;
		public float Hoard;
		public int WokeYear = -1, SlainYear = -1;
		public string Slayer = "";
		public bool Summoned;
		public readonly List<string> Deeds = new();
		/// <summary>Kingdoms whose people have wounded it.</summary>
		public readonly HashSet<int> Grudges = new();
		public Question Asking;
	}

	/// <summary>A legend's decision as written by a mind, before validation.</summary>
	public sealed class LegendDraft
	{
		[JsonPropertyName("goal")] public string Goal { get; set; } = "";
		[JsonPropertyName("target")] public string Target { get; set; } = "";
		[JsonPropertyName("words")] public string Words { get; set; } = "";
	}

	public readonly List<Legend> Legends = new();
	private Random _legendRng = new(1);
	/// <summary>Who dealt the last blow to a legend (for the hero), or -1.</summary>
	private int _legendSlayer = -1;
	/// <summary>Seconds between a legend's strikes, and how long a raid lasts once it arrives.</summary>
	public const float StrikeSeconds = 1.6f, RaidSeconds = 22f;
	/// <summary>How far, in tiles, the peoples see a legend's deeds (and remember them).</summary>
	public const float LegendSight = 40f;

	private void SetupLegends(int seed)
	{
		Legends.Clear();
		_legendSlayer = -1;
		_legendRng = new Random(seed ^ 0x1e6e);
		foreach (var rec in Assets.Legends)
		{
			var l = new Legend { Rec = rec, Species = Assets.SpeciesIndex(rec.Id) };
			var n = rec.Names;
			int half = Math.Max(1, n.Count / 2);
			l.Name = n.Count >= 2 ? n[_legendRng.Next(half)] + n[half + _legendRng.Next(n.Count - half)] : rec.Title;
			// The memory of its deeds: the god and the myth it gives (Religion.cs).
			MemoryDomains[LegendMemory(rec)] = (rec.Domain, rec.Deed);
			bool holds = _legendRng.NextDouble() < rec.Chance;
			if (holds && LairTiles(rec).Count > 0)
			{
				l.State = "dormant";
				int from = rec.Wake.Count > 0 ? rec.Wake[0] : 5, to = rec.Wake.Count > 1 ? rec.Wake[1] : from + 20;
				l.WakeYear = from + _legendRng.Next(Math.Max(1, to - from + 1));
			}
			Legends.Add(l);
		}
	}

	private static string LegendMemory(LegendRecord rec) => "legend:" + rec.Id;

	private string FullName(Legend l) => $"{l.Name} the {l.Rec.Title}";

	private List<int> LairTiles(LegendRecord rec)
	{
		var tiles = new List<int>();
		var biomes = new HashSet<int>();
		foreach (var name in rec.Lair)
		{
			int b = Array.IndexOf(_biomeNames, name);
			if (b >= 0)
				biomes.Add(b);
		}
		for (int t = 0; t < World.Biome.Length; t++)
			if (World.Water[t] == SimWorld.WaterLand && biomes.Contains(World.Biome[t]))
				tiles.Add(t);
		return tiles;
	}

	private Legend LegendOfUnit(int i)
	{
		foreach (var l in Legends)
			if (l.State == "awake" && l.Unit == i)
				return l;
		return null;
	}

	/// <summary>The legend's name for a unit ("Vorthak the Ash Wyrm"), or null.</summary>
	private string LegendName(int i)
	{
		var l = LegendOfUnit(i);
		return l == null ? null : FullName(l);
	}

	// ------------------------------------------------------------------ waking

	/// <summary>A legend wakes at (x, y): in its lair, or where the player calls it.</summary>
	private void Awaken(Legend l, float x, float y, bool summoned)
	{
		int i = SpawnUnit(l.Species, x, y, false);
		Zones.Rebuild(Units);
		l.Unit = i;
		l.State = "awake";
		l.Summoned = summoned;
		l.Health = l.Rec.Health;
		l.LairX = x;
		l.LairY = y;
		l.Goal = "slumber";
		l.Target = l.TargetVillage = -1;
		l.Kills = 0;
		l.Hoard = 0f;
		l.Grudges.Clear();
		l.Deeds.Clear();
		l.WokeYear = Year();
		l.SlainYear = -1;
		l.Slayer = "";
		l.LastMeal = Scheduler.Time;
		l.NextThought = Scheduler.Time + 2.0;
		string place = PlaceNear(x, y);
		string text = summoned
			? $"{FullName(l)} is called into the world by the hand in the sky, {place}. {l.Rec.Lore}"
			: $"{FullName(l)} wakes {place}. {l.Rec.Lore}";
		LogEvent(text, "legends");
		Deed(l, summoned ? $"called into the world {place}" : $"woke {place}");
		RememberNear(l, x, y, $"{FullName(l)} woke {place}", 2f);
	}

	/// <summary>"near Tolm" for the village closest to (x, y) within 30 tiles, else "in the wilds".</summary>
	private string PlaceNear(float x, float y)
	{
		int v = -1;
		float best = 30f * 30f;
		for (int k = 0; k < Villages.Count; k++)
		{
			var o = Villages[k];
			float d = (o.X - x) * (o.X - x) + (o.Y - y) * (o.Y - y);
			if (o.Alive && d < best)
			{
				best = d;
				v = k;
			}
		}
		return v < 0 ? "in the wilds" : "near " + Villages[v].Name;
	}

	private void Deed(Legend l, string text)
	{
		l.Deeds.Add($"year {Year()}: {text}");
		if (l.Deeds.Count > 8)
			l.Deeds.RemoveAt(0);
	}

	/// <summary>The kingdoms with a village within sight of (x, y) remember this (Religion.cs):
	/// it may become a myth, and a god of the legend's domain.</summary>
	private void RememberNear(Legend l, float x, float y, string text, float weight)
	{
		var seen = new HashSet<int>();
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom >= 0 && (v.X - x) * (v.X - x) + (v.Y - y) * (v.Y - y) <= LegendSight * LegendSight && seen.Add(v.Kingdom))
				Remember(v.Kingdom, LegendMemory(l.Rec), text, weight);
	}

	// ------------------------------------------------------------------ every quarter second

	private void LegendStep(float dt)
	{
		if (World == null)
			return;
		foreach (var l in Legends)
		{
			if (l.State == "dormant")
			{
				if (Law("legends") && Year() >= l.WakeYear)
				{
					var tiles = LairTiles(l.Rec);
					if (tiles.Count > 0)
					{
						int t = tiles[_legendRng.Next(tiles.Count)];
						Awaken(l, t % World.Width + 0.5f, t / World.Width + 0.5f, false);
					}
					else
						l.State = "absent";
				}
				continue;
			}
			if (l.State != "awake" || l.Unit < 0 || !Units.Alive[l.Unit])
				continue;
			if (l.Asking != null)
			{
				if (l.Asking.Take(Scheduler.Time, out string json, out string why))
				{
					l.Asking = null;
					string error = json == null ? why : SubmitLegendJson(l, json, "model");
					LastModelAnswer = json ?? "";
					LastModelError = error ?? "";
					if (string.IsNullOrEmpty(error))
						ModelAnswers++;
					else
					{
						ModelFailures++;
						ApplyLegend(l, ProceduralLegend(l), "procedural");
					}
				}
			}
			else if (Scheduler.Time >= l.NextThought)
				ThinkLegend(l, force: false);
			Act(l, dt);
		}
	}

	/// <summary>What a legend does, by its goal; it heals (fast in its lair), takes blows from
	/// the warriors around it, and strikes back.</summary>
	private void Act(Legend l, float dt)
	{
		int i = l.Unit;
		float x = Units.X[i], y = Units.Y[i];
		float lairD = MathF.Sqrt((x - l.LairX) * (x - l.LairX) + (y - l.LairY) * (y - l.LairY));
		l.Health = Math.Min(l.Rec.Health, l.Health + l.Rec.Health * (l.Goal == "slumber" && lairD < 3f ? 0.02f : 0.002f) * dt);
		if (l.Rec.Power == "roots")
			l.Health = Math.Min(l.Rec.Health, l.Health + l.Rec.Health * 0.002f * dt);
		Fought(l, dt);
		if (l.State != "awake")
			return;
		switch (l.Goal)
		{
			case "slumber":
				WalkTo(l, l.LairX, l.LairY);
				break;
			case "roam":
				if (AtTarget(i))
				{
					for (int tries = 0; tries < 8; tries++)
					{
						float a = (float)(_legendRng.NextDouble() * Math.PI * 2), r = (float)_legendRng.NextDouble() * l.Rec.Roam;
						float tx = l.LairX + MathF.Cos(a) * r, ty = l.LairY + MathF.Sin(a) * r;
						if (World.IsLandAt(tx, ty))
						{
							WalkTo(l, tx, ty);
							break;
						}
					}
				}
				break;
			case "hunt":
				Hunt(l);
				break;
			case "raid":
				Raid(l);
				break;
			case "tribute":
				Tribute(l);
				break;
		}
	}

	private void WalkTo(Legend l, float x, float y)
	{
		Units.TargetX[l.Unit] = x;
		Units.TargetY[l.Unit] = y;
	}

	/// <summary>Warriors (and, in a raid, anyone grown) within reach strike the legend; when it
	/// falls, the last of them slays it. It strikes back at whoever stands closest.</summary>
	private void Fought(Legend l, float dt)
	{
		int i = l.Unit;
		_found.Clear();
		Zones.Query(Units, Units.X[i], Units.Y[i], 2.2f, _found);
		int closest = -1;
		foreach (int j in _found)
		{
			if (j == i || !Units.Alive[j] || !Assets.Species[Units.Species[j]].IsPeople || !IsAdult(j))
				continue;
			bool warrior = Units.Role[j] == (byte)Role.Warrior;
			int k = KingdomOfUnit(j);
			if (!warrior && !(l.Goal == "raid" && k == l.Target))
				continue;
			l.Health -= BlowDamage(j) * (warrior ? 0.3f : 0.1f) * dt;
			if (k >= 0)
				l.Grudges.Add(k);
			closest = j;
			_legendSlayer = j;
		}
		if (l.Health <= 0f)
		{
			KillUnit(i, Death.War);
			return;
		}
		_legendSlayer = -1;
		if (closest >= 0 && Scheduler.Time >= l.NextStrike)
			Strike(l, Units.X[closest], Units.Y[closest]);
	}

	/// <summary>One strike at (x, y), by the legend's power: it kills up to its strength of what
	/// stands there (never another legend), and fire burns, roots heal, the dead rise.</summary>
	private int Strike(Legend l, float x, float y)
	{
		l.NextStrike = Scheduler.Time + StrikeSeconds;
		l.LastStrike = Scheduler.Time;
		float radius = l.Rec.Power switch { "stomp" => 1.6f, "quake" => 2.2f, "lightning" => 1.4f, "fire" => 1.5f, _ => 1.2f };
		_found.Clear();
		Zones.Query(Units, x, y, radius, _found);
		int killed = 0;
		foreach (int j in _found.ToArray())
		{
			if (killed >= l.Rec.Strength)
				break;
			if (j == l.Unit || !Units.Alive[j] || Assets.Species[Units.Species[j]].IsLegend)
				continue;
			KillUnit(j, l.Rec.Power == "fire" || l.Rec.Power == "lightning" ? Death.Fire : Death.War);
			killed++;
		}
		l.Kills += killed;
		switch (l.Rec.Power)
		{
			case "fire":
				Ignite(x, y, 1.6f);
				break;
			case "lightning":
				Ignite(x, y, 1.0f);
				break;
			case "roots":
				l.Health = Math.Min(l.Rec.Health, l.Health + l.Rec.Health * 0.02f);
				break;
			case "raise_dead":
				for (int k = 0; k < Math.Min(killed, 2); k++)
					SpawnAt("skeleton", x + (float)_legendRng.NextDouble() - 0.5f, y + (float)_legendRng.NextDouble() - 0.5f, false);
				break;
		}
		return killed;
	}

	/// <summary>Whether a legend struck a moment ago (its sprite shows the attack).</summary>
	private bool LegendStriking(int i)
	{
		var l = LegendOfUnit(i);
		return l != null && Scheduler.Time - l.LastStrike < 0.6;
	}

	private void Hunt(Legend l)
	{
		int i = l.Unit;
		int prey = -1;
		float best = l.Rec.Roam * l.Rec.Roam;
		for (int j = 0; j < Units.Capacity; j++)
		{
			if (!Units.Alive[j])
				continue;
			var sp = Assets.Species[Units.Species[j]];
			if (sp.IsPeople || sp.IsLegend)
				continue;
			float d = (Units.X[j] - Units.X[i]) * (Units.X[j] - Units.X[i]) + (Units.Y[j] - Units.Y[i]) * (Units.Y[j] - Units.Y[i]);
			if (d < best)
			{
				best = d;
				prey = j;
			}
		}
		if (prey < 0)
		{
			l.Goal = "roam";
			return;
		}
		if (best < 1.5f * 1.5f)
		{
			KillUnit(prey, Death.Eaten);
			l.LastStrike = Scheduler.Time;
			l.LastMeal = Scheduler.Time;
			l.Goal = "roam";
			return;
		}
		WalkTo(l, Units.X[prey], Units.Y[prey]);
	}

	/// <summary>A raid: the legend walks to the village and strikes the people around it; a
	/// third of the gold it finds joins its hoard. It leaves when the raid is over, or flees
	/// to its lair, wounded.</summary>
	private void Raid(Legend l)
	{
		int v = l.TargetVillage;
		if (v < 0 || !Villages[v].Alive)
		{
			l.Goal = "roam";
			return;
		}
		var village = Villages[v];
		float vx = village.X + 0.5f, vy = village.Y + 0.5f;
		int i = l.Unit;
		float d = MathF.Sqrt((Units.X[i] - vx) * (Units.X[i] - vx) + (Units.Y[i] - vy) * (Units.Y[i] - vy));
		if (l.Health < l.Rec.Health * 0.35f)
		{
			LogEvent($"{FullName(l)} flees {village.Name}, wounded, back to its lair.", "legends");
			Deed(l, $"fled {village.Name}, wounded");
			if (village.Kingdom >= 0)
				Remember(village.Kingdom, LegendMemory(l.Rec), $"the people of {village.Name} drove off {FullName(l)}", 2.5f);
			l.Goal = "slumber";
			return;
		}
		if (d > 4f)
		{
			WalkTo(l, vx, vy);
			l.GoalUntil = 0;
			return;
		}
		if (l.GoalUntil == 0)
		{
			l.GoalUntil = Scheduler.Time + RaidSeconds;
			LogEvent($"{FullName(l)} falls upon {village.Name}!", "legends");
			Deed(l, $"fell upon {village.Name}");
			RememberNear(l, vx, vy, $"{FullName(l)} fell upon {village.Name}", 3f);
		}
		if (Scheduler.Time >= l.NextStrike)
		{
			// The nearest person around the village.
			_found.Clear();
			Zones.Query(Units, Units.X[i], Units.Y[i], 6f, _found);
			int target = -1;
			float best = float.MaxValue;
			foreach (int j in _found)
				if (Units.Alive[j] && Units.Village[j] == v)
				{
					float dj = MathF.Abs(Units.X[j] - Units.X[i]) + MathF.Abs(Units.Y[j] - Units.Y[i]);
					if (dj < best)
					{
						best = dj;
						target = j;
					}
				}
			if (target >= 0)
			{
				WalkTo(l, Units.X[target], Units.Y[target]);
				Strike(l, Units.X[target], Units.Y[target]);
			}
			else
				Strike(l, vx + (float)_legendRng.NextDouble() * 4f - 2f, vy + (float)_legendRng.NextDouble() * 4f - 2f);
			float gold = village.Gold * 0.33f;
			village.Gold -= gold;
			l.Hoard += gold;
		}
		if (Scheduler.Time >= l.GoalUntil)
		{
			LogEvent($"{FullName(l)} leaves {village.Name} in ruins, {l.Kills} slain in all.", "legends");
			l.Goal = "slumber";
		}
	}

	/// <summary>Tribute: the legend names its price; after a while the kingdom pays from its
	/// capital's gold, or refuses and is raided.</summary>
	private void Tribute(Legend l)
	{
		int k = l.Target;
		if (k < 0 || !Kingdoms[k].Alive || Kingdoms[k].Capital < 0)
		{
			l.Goal = "roam";
			return;
		}
		var capital = Villages[Kingdoms[k].Capital];
		if (l.Demanded < 0)
		{
			l.Demanded = Scheduler.Time;
			l.Tribute = MathF.Round(8f + 16f * l.Rec.T("greed"));
			LogEvent($"{FullName(l)} demands {l.Tribute} gold of {Kingdoms[k].Name}.", "legends");
			return;
		}
		if (Scheduler.Time - l.Demanded < 6.0)
			return;
		l.Demanded = -1;
		if (capital.Gold >= l.Tribute)
		{
			capital.Gold -= l.Tribute;
			l.Hoard += l.Tribute;
			LogEvent($"{Kingdoms[k].Name} pays {FullName(l)} its tribute of {l.Tribute} gold.", "legends");
			Deed(l, $"took {l.Tribute} gold of {Kingdoms[k].Name}");
			Remember(k, LegendMemory(l.Rec), $"{Kingdoms[k].Name} paid tribute to {FullName(l)}", 2f);
			l.Goal = "slumber";
		}
		else
		{
			LogEvent($"{Kingdoms[k].Name} cannot pay: {FullName(l)} comes for {capital.Name}.", "legends");
			l.Goal = "raid";
			l.TargetVillage = Kingdoms[k].Capital;
			l.GoalUntil = 0;
		}
	}

	/// <summary>When a legend's unit dies (KillUnit): it is slain. The warrior who dealt the last
	/// blow is a hero; the kingdoms around remember it.</summary>
	private void LegendDied(int i, Death cause)
	{
		var l = LegendOfUnit(i);
		if (l == null)
			return;
		l.State = "slain";
		l.SlainYear = Year();
		l.Asking = null;
		float x = Units.X[i], y = Units.Y[i];
		int j = _legendSlayer;
		_legendSlayer = -1;
		string by;
		if (j >= 0 && Units.Alive[j])
		{
			int k = KingdomOfUnit(j);
			string from = Units.Village[j] >= 0 ? Villages[Units.Village[j]].Name : "the wilds";
			l.Slayer = $"{NameOf(j)} of {from}";
			by = $"slain by {l.Slayer}";
			if (k >= 0)
			{
				_heroes.Add(j);
				LogEvent($"{NameOf(j)} of {from} slays {FullName(l)} and is hailed a hero of {Kingdoms[k].Name}!", "heroes");
				Remember(k, "hero", $"{NameOf(j)} of {from} slew {FullName(l)}", 3f);
			}
		}
		else
		{
			l.Slayer = cause == Death.Other ? "the hand in the sky" : cause == Death.Fire ? "the flames" : "";
			by = cause == Death.Other ? "struck down by the hand in the sky" : cause == Death.Fire ? "consumed by fire" : "slain";
		}
		LogEvent($"{FullName(l)} is {by}, {PlaceNear(x, y)}. Its hoard of {(int)l.Hoard} gold lies unguarded.", "legends");
		Deed(l, by);
		RememberNear(l, x, y, $"{FullName(l)} was {by}", 3f);
		l.Unit = -1;
	}

	// ------------------------------------------------------------------ the mind

	/// <summary>Kingdoms with a village within reach of the legend's lands, nearest first:
	/// (kingdom, its nearest village, distance).</summary>
	private List<(int k, int v, float d)> KingdomsAround(Legend l)
	{
		float reach = l.Rec.Roam * 2.5f;
		var best = new Dictionary<int, (int v, float d)>();
		for (int v = 0; v < Villages.Count; v++)
		{
			var o = Villages[v];
			if (!o.Alive || o.Kingdom < 0 || !Kingdoms[o.Kingdom].Alive)
				continue;
			float d = MathF.Sqrt((o.X - l.LairX) * (o.X - l.LairX) + (o.Y - l.LairY) * (o.Y - l.LairY));
			if (d <= reach && (!best.TryGetValue(o.Kingdom, out var b) || d < b.d))
				best[o.Kingdom] = (v, d);
		}
		var list = new List<(int k, int v, float d)>();
		foreach (var (k, b) in best)
			list.Add((k, b.v, b.d));
		list.Sort((a, b) => a.d.CompareTo(b.d));
		return list;
	}

	/// <summary>The legend's mind thinks: the model in the background, or the procedural mind now.</summary>
	private void ThinkLegend(Legend l, bool force)
	{
		l.NextThought = Scheduler.Time + YearSeconds * (0.4 + 0.3 * _legendRng.NextDouble());
		if (!force)
		{
			var task = AskAnyMind(LegendPrompt(l), LegendGrammar(l), LegendSchema(l),
				"You are the mind of a legendary monster in a world simulation. Answer with one JSON record.");
			if (task != null)
			{
				l.Asking = new Question { Pending = task, Asked = Scheduler.Time };
				return;
			}
		}
		ApplyLegend(l, ProceduralLegend(l), "procedural");
	}

	private static readonly Dictionary<string, string[]> LegendWords = new()
	{
		["slumber"] = new[] { "I will sleep, and dream of what I will take.", "Let them forget me. I will remember them.", "My wounds will close. Theirs will not." },
		["roam"] = new[] { "I walk my lands. Let the small ones hide.", "This land is mine, as it was before them.", "Every path here leads to me." },
		["hunt"] = new[] { "The beasts of my land will feed me.", "Hunger wakes me. The herds will answer it." },
		["raid"] = new[] { "Burn, {village}! Your walls are kindling to me.", "The {people} of {kingdom} have grown fat. I hunger.", "None shall stand before {name}. Not even {kingdom}." },
		["tribute"] = new[] { "Bring me gold, {kingdom}, or I bring you ruin.", "A gift for {name}, and your children may sleep.", "{kingdom} will pay, as all the small ones pay." },
	};

	/// <summary>What the legend wants, from its temper and its state: wounded, it sleeps; hungry,
	/// it hunts; else, by its wrath and grudges, it raids a kingdom near its lands, by its greed
	/// it demands tribute, else it roams or sleeps.</summary>
	private LegendDraft ProceduralLegend(Legend l)
	{
		string goal;
		int k = -1;
		var around = KingdomsAround(l);
		if (l.Health < l.Rec.Health * 0.5f)
			goal = "slumber";
		else if (Scheduler.Time - l.LastMeal > YearSeconds * 1.2)
			goal = "hunt";
		else
		{
			double r = _legendRng.NextDouble();
			int grudge = around.FindIndex(a => l.Grudges.Contains(a.k));
			double raid = around.Count == 0 ? 0 : l.Rec.T("wrath") * 0.5 + (grudge >= 0 ? 0.3 : 0);
			double tribute = around.Count == 0 ? 0 : l.Rec.T("greed") * 0.35;
			if (r < raid)
			{
				goal = "raid";
				k = grudge >= 0 ? around[grudge].k : around[0].k;
			}
			else if (r < raid + tribute)
			{
				goal = "tribute";
				k = around[0].k;
			}
			else
				goal = _legendRng.NextDouble() < 0.4 + 0.3 * l.Rec.T("pride") ? "roam" : "slumber";
		}
		var lines = LegendWords[goal];
		string words = lines[_legendRng.Next(lines.Length)];
		if (k >= 0)
		{
			int v = around.Find(a => a.k == k).v;
			words = words.Replace("{village}", Villages[v].Name).Replace("{kingdom}", Kingdoms[k].Name)
				.Replace("{people}", Assets.Species[Kingdoms[k].Species].Name);
		}
		words = Clean(words.Replace("{name}", l.Name));
		return new LegendDraft { Goal = goal, Target = k >= 0 ? Kingdoms[k].Name : "", Words = words };
	}

	/// <summary>Checks a legend's decision: a known goal; for a raid or a tribute, a living kingdom
	/// within reach of its lands; words of one plain sentence. Returns null when valid.</summary>
	private string ValidateLegend(Legend l, LegendDraft d, out int k)
	{
		k = -1;
		if (d == null)
			return "empty";
		if (Array.IndexOf(LegendGoals, d.Goal) < 0)
			return $"unknown goal '{d.Goal}'";
		string error = TextError(d.Words, 2, 160);
		if (error != null)
			return error;
		if (d.Goal == "raid" || d.Goal == "tribute")
		{
			foreach (var a in KingdomsAround(l))
				if (Clean(Kingdoms[a.k].Name) == (d.Target ?? "").Trim())
					k = a.k;
			if (k < 0)
				return $"no kingdom '{d.Target}' within reach";
		}
		return null;
	}

	/// <summary>A mind's decision (JSON) for a legend: validated, then followed. Returns "" when
	/// taken, else why it was refused.</summary>
	private string SubmitLegendJson(Legend l, string json, string mind)
	{
		LegendDraft d;
		try
		{
			d = JsonSerializer.Deserialize<LegendDraft>(json);
		}
		catch (Exception e)
		{
			return "not valid JSON: " + e.Message;
		}
		string error = ValidateLegend(l, d, out _);
		if (error != null)
			return error;
		ApplyLegend(l, d, mind);
		return "";
	}

	private void ApplyLegend(Legend l, LegendDraft d, string mind)
	{
		if (l.State != "awake" || ValidateLegend(l, d, out int k) != null)
			return;
		l.Goal = d.Goal;
		l.Words = d.Words.Trim();
		l.Mind = mind;
		l.Target = k;
		l.TargetVillage = -1;
		l.GoalUntil = 0;
		l.Demanded = -1;
		if (k >= 0)
		{
			// The village of that kingdom nearest to the legend.
			float best = float.MaxValue;
			for (int v = 0; v < Villages.Count; v++)
			{
				var o = Villages[v];
				if (!o.Alive || o.Kingdom != k)
					continue;
				float dv = (o.X - Units.X[l.Unit]) * (o.X - Units.X[l.Unit]) + (o.Y - Units.Y[l.Unit]) * (o.Y - Units.Y[l.Unit]);
				if (dv < best)
				{
					best = dv;
					l.TargetVillage = v;
				}
			}
		}
		if (d.Goal == "raid" || d.Goal == "tribute")
			LogEvent($"{FullName(l)}: \"{l.Words}\"", "legends");
	}

	public string LegendPrompt(Legend l)
	{
		var sb = new StringBuilder();
		sb.Append($"You are {FullName(l)}, a legendary being, the only one of your kind in this world. {l.Rec.Lore}\n");
		sb.Append($"Your temper: wrath {l.Rec.T("wrath"):0.0}, greed {l.Rec.T("greed"):0.0}, cunning {l.Rec.T("cunning"):0.0}, pride {l.Rec.T("pride"):0.0}.\n");
		sb.Append($"Year {Year()}. You are at {(int)(100 * l.Health / l.Rec.Health)}% of your strength. You have slain {l.Kills}; your hoard holds {(int)l.Hoard} gold. ");
		sb.Append(Scheduler.Time - l.LastMeal > YearSeconds ? "You are hungry.\n" : "You are fed.\n");
		if (l.Deeds.Count > 0)
			sb.Append($"What you have done: {string.Join("; ", l.Deeds)}.\n");
		var around = KingdomsAround(l);
		if (around.Count > 0)
		{
			sb.Append("Kingdoms within reach of your lands:\n");
			foreach (var (k, v, dist) in around)
				sb.Append($"- {Clean(Kingdoms[k].Name)} ({Assets.Species[Kingdoms[k].Species].Name}): its village {Villages[v].Name} is {(int)dist} tiles from your lair, {Strength(k)} soldiers, {(Kingdoms[k].Capital >= 0 ? (int)Villages[Kingdoms[k].Capital].Gold : 0)} gold{(l.Grudges.Contains(k) ? ", they have wounded you" : "")}.\n");
		}
		else
			sb.Append("No kingdom lives within reach of your lands.\n");
		sb.Append("Choose your \"goal\": slumber (rest in your lair and heal), roam (walk your lands), hunt (eat beasts), raid (attack a kingdom's village), tribute (demand gold of a kingdom). ");
		sb.Append("For raid and tribute, \"target\" is the kingdom's exact name, else \"\". \"words\": what you declare, one sentence in your voice. Answer with the JSON record only.\n");
		return sb.ToString();
	}

	private string LegendGrammar(Legend l)
	{
		var targets = new List<string> { "\"\\\"\\\"\"" };
		foreach (var a in KingdomsAround(l))
			targets.Add($"\"\\\"{Clean(Kingdoms[a.k].Name)}\\\"\"");
		var goals = new List<string>();
		foreach (var g in LegendGoals)
			goals.Add($"\"\\\"{g}\\\"\"");
		return "root ::= \"{\" ws \"\\\"goal\\\":\" ws goal \",\" ws \"\\\"target\\\":\" ws target \",\" ws \"\\\"words\\\":\" ws words ws \"}\"\n"
			+ $"goal ::= {string.Join(" | ", goals)}\ntarget ::= {string.Join(" | ", targets)}\nwords ::= {LocalModel.Text(150, 2)}\nws ::= [ ]?\n";
	}

	private string LegendSchema(Legend l)
	{
		var targets = new List<string> { "" };
		foreach (var a in KingdomsAround(l))
			targets.Add(Clean(Kingdoms[a.k].Name));
		return JsonSerializer.Serialize(new Dictionary<string, object>
		{
			["type"] = "object", ["required"] = new[] { "goal", "target", "words" },
			["properties"] = new Dictionary<string, object>
			{
				["goal"] = new Dictionary<string, object> { ["enum"] = LegendGoals },
				["target"] = new Dictionary<string, object> { ["enum"] = targets },
				["words"] = new Dictionary<string, object> { ["type"] = "string", ["minLength"] = 2, ["maxLength"] = 160 },
			},
		});
	}

	// ------------------------------------------------------------------ the player

	/// <summary>Whether `id` is a legend (data/legends.json).</summary>
	public bool IsLegend(string id)
	{
		int s = Assets.SpeciesIndex(id ?? "");
		return s >= 0 && Assets.Species[s].IsLegend;
	}

	/// <summary>The player calls a legend into the world at (x, y): refused while it walks the
	/// world already (there is only one). A slain legend can be called back. Returns 1 or 0.</summary>
	private int SummonLegend(string id, float x, float y)
	{
		var l = Legends.Find(o => o.Rec.Id == id);
		if (l == null || l.State == "awake" || !OnLand(x, y))
			return 0;
		Awaken(l, x, y, summoned: true);
		return 1;
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>The legends of this world: id, name, title, state (absent, dormant, awake, slain),
	/// goal, words, health (0..1), kills, hoard, deeds, years, slayer, where it is, lore.</summary>
	public Godot.Collections.Array LegendTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var l in Legends)
		{
			bool awake = l.State == "awake" && l.Unit >= 0 && Units.Alive[l.Unit];
			list.Add(new Godot.Collections.Dictionary
			{
				["id"] = l.Rec.Id, ["name"] = l.Name, ["title"] = l.Rec.Title, ["full_name"] = FullName(l), ["state"] = l.State,
				["goal"] = l.Goal, ["words"] = l.Words, ["mind"] = l.Mind, ["health"] = l.Rec.Health > 0 ? Math.Max(0f, l.Health / l.Rec.Health) : 0f,
				["kills"] = l.Kills, ["hoard"] = (int)l.Hoard, ["deeds"] = string.Join("\n", l.Deeds), ["woke"] = l.WokeYear,
				["slain"] = l.SlainYear, ["slayer"] = l.Slayer, ["summoned"] = l.Summoned, ["unit"] = awake ? l.Unit : -1,
				["x"] = awake ? Units.X[l.Unit] : l.LairX, ["y"] = awake ? Units.Y[l.Unit] : l.LairY, ["lore"] = l.Rec.Lore,
				["lair"] = string.Join(", ", l.Rec.Lair), ["domain"] = l.Rec.Domain,
				["target"] = l.Target >= 0 && l.Target < Kingdoms.Count ? Kingdoms[l.Target].Name : "",
			});
		}
		return list;
	}

	/// <summary>Names over the legends that walk the world: name, x, y (tiles, at the feet).</summary>
	public Godot.Collections.Array LegendLabels()
	{
		var list = new Godot.Collections.Array();
		foreach (var l in Legends)
			if (l.State == "awake" && l.Unit >= 0 && Units.Alive[l.Unit])
				list.Add(new Godot.Collections.Dictionary { ["name"] = FullName(l), ["x"] = Units.X[l.Unit], ["y"] = Units.Y[l.Unit] });
		return list;
	}

	/// <summary>A legend's line for the HUD and the inspector.</summary>
	private string LegendInfo(int i)
	{
		var l = LegendOfUnit(i);
		if (l == null)
			return "";
		string doing = l.Goal switch
		{
			"slumber" => "slumbers in its lair", "roam" => "roams its lands", "hunt" => "hunts",
			"raid" => l.TargetVillage >= 0 ? $"raids {Villages[l.TargetVillage].Name}" : "raids",
			"tribute" => l.Target >= 0 ? $"demands tribute of {Kingdoms[l.Target].Name}" : "demands tribute", _ => l.Goal,
		};
		return $"{FullName(l)} · legend · {doing} · strength {(int)(100 * l.Health / l.Rec.Health)}% · {l.Kills} slain · hoard {(int)l.Hoard} gold";
	}

	private Legend LegendById(string id) => Legends.Find(o => o.Rec.Id == id);

	/// <summary>Sets when a legend wakes (tests): it is in this world, dormant until that year.</summary>
	public void SetLegendWake(string id, int year)
	{
		var l = LegendById(id);
		if (l == null || l.State == "awake")
			return;
		l.State = "dormant";
		l.WakeYear = year;
	}

	/// <summary>Makes a legend's mind decide now with the procedural mind (tests).</summary>
	public void LegendThinkNow(string id)
	{
		var l = LegendById(id);
		if (l != null && l.State == "awake")
			ThinkLegend(l, force: true);
	}

	/// <summary>A mind's decision (JSON) for the legend `id` (tests): "" when taken.</summary>
	public string SubmitLegendJson(string id, string json)
	{
		var l = LegendById(id);
		return l == null || l.State != "awake" ? "no such legend awake" : SubmitLegendJson(l, json, "model");
	}

	/// <summary>Wounds a legend (tests): `fraction` of its full strength.</summary>
	public void WoundLegend(string id, float fraction)
	{
		var l = LegendById(id);
		if (l != null && l.State == "awake")
			l.Health -= l.Rec.Health * fraction;
	}
}
