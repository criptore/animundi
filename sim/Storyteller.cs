using System;
using System.Collections.Generic;
using System.Text;

namespace Animundi.Sim;

/// <summary>
/// The last powers (1.0, docs/POWERS.md): hail and wind, a forgotten language, the storyteller
/// who chooses the stories the world tells, and faith mode, where the powers cost the faith the
/// peoples put in the player. Also what the inspector says of a person's family, story and mind.
/// </summary>
public partial class Simulation
{
	/// <summary>The wind the player called: a direction (unit vector) and the seconds it blows.</summary>
	public float WindX, WindY, WindSeconds;

	/// <summary>Faith mode (the law "faith_mode"): what the player has to spend, and the most it can hold.</summary>
	public float GodFaith { get; private set; } = 60f;
	public const float MaxGodFaith = 300f;
	private double _nextFaithIncome;

	/// <summary>What each power costs in faith mode (unlisted powers cost 2).</summary>
	public static readonly Dictionary<string, float> PowerCosts = new()
	{
		["inspect"] = 0, ["spawn"] = 3, ["settle"] = 15, ["fire"] = 2, ["lightning"] = 4, ["rain"] = 1, ["meteor"] = 25, ["smite"] = 6,
		["bless"] = 2, ["miracle"] = 12, ["biome"] = 1, ["wildfire"] = 10, ["drought"] = 15, ["tornado"] = 15, ["earthquake"] = 20,
		["flood"] = 15, ["eruption"] = 25, ["plague"] = 15, ["heal"] = 2, ["war"] = 10, ["peace"] = 10, ["alliance"] = 10, ["convert"] = 12,
		["enlighten"] = 30, ["dark_age"] = 30, ["nuke"] = 80, ["era"] = 40, ["raise"] = 1, ["lower"] = 1, ["water"] = 1, ["stamp"] = 15,
		["copy"] = 0, ["seeds"] = 1, ["blizzard"] = 10, ["curse"] = 4, ["madness"] = 8, ["resurrect"] = 10, ["rebellion"] = 15,
		["inspire"] = 10, ["forget_culture"] = 20, ["forget_faith"] = 20, ["forget_language"] = 20, ["trait"] = 2, ["hail"] = 6,
		["wind"] = 5, ["story"] = 30,
	};

	private void SetupStoryteller()
	{
		WindX = WindY = WindSeconds = 0f;
		GodFaith = 60f;
		_nextFaithIncome = YearSeconds;
	}

	// ------------------------------------------------------------------ weather

	/// <summary>Hail under the brush: wheat beaten down, small creatures killed, people hurt,
	/// fires out. Returns the creatures killed.</summary>
	public int PowerHail(float x, float y, float radius)
	{
		if (World == null)
			return 0;
		TilesWithin(x, y, radius, t =>
		{
			TileBurn[t] = 0f;
			if (_ground[t] == GroundField && _wheat[t] > 0f)
			{
				_wheat[t] = 0.0001f;
				_overlayChanged.Add(t);
			}
			Grass[t] *= 0.6f;
		});
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		int killed = 0;
		foreach (int i in UnitsWithin(x, y, radius).ToArray())
		{
			var sp = Assets.Species[Units.Species[i]];
			if (sp.IsLegend)
				continue;
			if (!sp.IsPeople && sp.Size <= 2 && _rng.NextDouble() < 0.5)
			{
				KillUnit(i, Death.Disaster);
				killed++;
			}
			else
				Units.Health[i] = Math.Max(1f, Units.Health[i] - 25f);
		}
		LogEvent($"hail beats down {PlaceNear(x, y)}.", "disasters");
		GodActs("storm", x, y, radius, Math.Max(1, killed));
		return killed;
	}

	/// <summary>A wind from (x0, y0) towards (x, y) for a year: fire runs with it (WindFactor) and
	/// the sparks of the fire power fly its way.</summary>
	public bool PowerWind(float x0, float y0, float x, float y)
	{
		float dx = x - x0, dy = y - y0;
		float d = MathF.Sqrt(dx * dx + dy * dy);
		if (d < 0.5f)
			return false;
		WindX = dx / d;
		WindY = dy / d;
		WindSeconds = YearSeconds;
		string[] names = { "east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east" };
		int dir = ((int)MathF.Round(MathF.Atan2(WindY, WindX) / (MathF.PI / 4f)) + 8) % 8;
		LogEvent($"a great wind blows to the {names[dir]}.", "nature");
		return true;
	}

	/// <summary>How much more likely fire is to spread from a tile to its neighbour (dx, dy) with
	/// the wind: three times downwind, a third upwind.</summary>
	private float WindFactor(int dx, int dy)
	{
		if (WindSeconds <= 0f)
			return 1f;
		float along = dx * WindX + dy * WindY;
		return along > 0.5f ? 3f : along < -0.5f ? 0.35f : 1f;
	}

	// ------------------------------------------------------------------ minds

	/// <summary>A kingdom's people forget their tongue: a new language is born, and their new
	/// villages and children are named in it.</summary>
	public bool PowerForgetLanguage(float x, float y)
	{
		int k = KingdomAt(x, y);
		if (k < 0 || !Kingdoms[k].Alive)
			return false;
		int s = Kingdoms[k].Species;
		var race = Assets.Species[s].Race;
		if (race == null)
			return false;
		_languages[s] = new Language(race.Language, _rng);
		LogEvent($"the {Assets.Species[s].Name} wake speaking a new tongue: their children will be named like {_languages[s].PersonName()}, their towns like {_languages[s].PlaceName()}.", "culture");
		GodActs("wrath", x, y, 4f, 3);
		return true;
	}

	/// <summary>The stories the storyteller can tell (power "story").</summary>
	public static readonly string[] Stories = { "war", "hero", "plague", "legend", "golden_age", "rebellion", "discovery", "fall" };

	/// <summary>The storyteller makes a story happen near (x, y): a war between the two strongest
	/// kingdoms near, a hero, a plague in the most crowded village, a legend wakes, a golden age
	/// (a bright era), a rebellion, a discovery (half an age of knowledge), the fall of a great
	/// kingdom's capital. Returns what happened, or "" when the story found no one to tell it of.</summary>
	public string PowerStory(string story, float x, float y)
	{
		var near = new List<int>();
		for (int k = 0; k < Kingdoms.Count; k++)
			if (Kingdoms[k].Alive && Kingdoms[k].Capital >= 0)
				near.Add(k);
		near.Sort((a, b) =>
		{
			var va = Villages[Kingdoms[a].Capital];
			var vb = Villages[Kingdoms[b].Capital];
			return ((va.X - x) * (va.X - x) + (va.Y - y) * (va.Y - y)).CompareTo((vb.X - x) * (vb.X - x) + (vb.Y - y) * (vb.Y - y));
		});
		switch (story)
		{
			case "war":
				for (int n = 1; n < near.Count; n++)
					if (!AtWar(near[0], near[n]) && ForcePlan(Plot("war", near[0], near[n])))
						return $"{Kingdoms[near[0]].Name} goes to war with {Kingdoms[near[n]].Name}";
				return "";
			case "hero":
			{
				int best = -1;
				for (int i = 0; i < Units.Capacity; i++)
					if (Units.Alive[i] && Units.Role[i] == (byte)Role.Warrior && !_heroes.Contains(i) && KingdomOfUnit(i) >= 0
						&& (best < 0 || Units.Training[i] > Units.Training[best]))
						best = i;
				if (best < 0)
					return "";
				Units.Kills[best] = HeroKills - 1;
				WarKill(best);
				return $"{NameOf(best)} becomes a hero";
			}
			case "plague":
			{
				int crowded = -1;
				for (int v = 0; v < Villages.Count; v++)
					if (Villages[v].Alive && (crowded < 0 || Villages[v].Population > Villages[crowded].Population))
						crowded = v;
				if (crowded < 0)
					return "";
				var d = NewDisease(Villages[crowded].Name, "nature", "people");
				return InfectVillage(crowded, d, 4) > 0 ? $"{d.Name} breaks out in {Villages[crowded].Name}" : "";
			}
			case "legend":
				foreach (var l in Legends)
					if (l.State == "dormant" || l.State == "absent" && l.SlainYear < 0)
					{
						var tiles = LairTiles(l.Rec);
						if (tiles.Count == 0)
							continue;
						int t = tiles[_legendRng.Next(tiles.Count)];
						Awaken(l, t % World.Width + 0.5f, t / World.Width + 0.5f, false);
						return $"{FullName(l)} wakes";
					}
				return "";
			case "golden_age":
				return SetEra("bright") ? "a golden age begins" : "";
			case "rebellion":
				for (int v = 0; v < Villages.Count; v++)
				{
					var village = Villages[v];
					if (village.Alive && village.Kingdom >= 0 && Kingdoms[village.Kingdom].Capital != v && village.Population >= 8)
					{
						int before = Kingdoms.Count;
						Secede(v);
						if (Kingdoms.Count > before)
							return $"{village.Name} rises against its kingdom";
					}
				}
				return "";
			case "discovery":
				if (near.Count == 0)
					return "";
				AddKnowledge(near[0], AgeRec(Kingdoms[near[0]].Age).Knowledge * 0.5f);
				return $"the scholars of {Kingdoms[near[0]].Name} make a great discovery";
			case "fall":
			{
				int great = -1;
				foreach (int k in near)
					if (great < 0 || Strength(k) > Strength(great))
						great = k;
				if (great < 0)
					return "";
				var capital = Villages[Kingdoms[great].Capital];
				StartDisaster("earthquake", capital.X + 0.5f, capital.Y + 0.5f, 7f, "the storyteller");
				Setback(great, 0.5f, $"the fall of {capital.Name}");
				return $"{capital.Name}, the pride of {Kingdoms[great].Name}, falls";
			}
		}
		return "";
	}

	// ------------------------------------------------------------------ faith mode

	/// <summary>In faith mode, spends what a power costs: false (and nothing spent) when the
	/// player's faith is too low. Always true outside faith mode.</summary>
	public bool SpendFaith(string power)
	{
		if (!Law("faith_mode"))
			return true;
		float cost = PowerCosts.TryGetValue(power ?? "", out float c) ? c : 2f;
		if (GodFaith < cost)
			return false;
		GodFaith -= cost;
		return true;
	}

	public float PowerCost(string power) => PowerCosts.TryGetValue(power ?? "", out float c) ? c : 2f;

	/// <summary>Once a year with the eras: the peoples who notice the player give faith, the most
	/// those who worship them, a little those who fear them.</summary>
	private void FaithIncome()
	{
		if (WindSeconds > 0f)
			WindSeconds = Math.Max(0f, WindSeconds - 1f);
		if (Scheduler.Time < _nextFaithIncome)
			return;
		_nextFaithIncome = Scheduler.Time + YearSeconds;
		float income = 8f;
		foreach (var k in Kingdoms)
		{
			if (!k.Alive)
				continue;
			int people = 0;
			foreach (var v in Villages)
				if (v.Alive && v.Kingdom == Kingdoms.IndexOf(k))
					people += v.Population;
			float share = k.Culture.Stance switch { "worshipped" => 1f, "feared" => 0.5f, "hated" => 0.1f, _ => 0f };
			income += share * people * 0.08f * (k.Culture.Faith / 50f);
		}
		GodFaith = Math.Min(MaxGodFaith, GodFaith + income);
	}

	/// <summary>Gives the player faith (tests).</summary>
	public void AddGodFaith(float amount) => GodFaith = Math.Clamp(GodFaith + amount, 0f, MaxGodFaith);

	// ------------------------------------------------------------------ the inspector

	/// <summary>A person's family: partner, parents, children (living and dead by name).</summary>
	public string FamilyOf(int i)
	{
		if (i < 0 || i >= Units.Capacity || !Units.Alive[i] || !Assets.Species[Units.Species[i]].IsPeople)
			return "";
		var sb = new StringBuilder();
		int p = Units.Partner[i];
		sb.Append(p >= 0 && p < Units.Capacity && Units.Alive[p] ? $"Partner: {NameOf(p)}" : "No partner");
		var parents = new List<string>();
		foreach (int q in new[] { Units.Mother[i], Units.Father[i] })
			if (q >= 0 && q < Units.Capacity && Units.Alive[q] && Units.Name[q] >= 0)
				parents.Add(NameOf(q));
		sb.Append(parents.Count > 0 ? $"\nParents: {string.Join(", ", parents)}" : "\nParents: gone");
		var children = new List<string>();
		for (int c = 0; c < Units.Capacity; c++)
			if (Units.Alive[c] && (Units.Mother[c] == i || Units.Father[c] == i))
				children.Add($"{NameOf(c)} ({(int)Units.Age[c]})");
		sb.Append(children.Count > 0 ? $"\nChildren: {string.Join(", ", children)}" : "\nNo children");
		return sb.ToString();
	}

	/// <summary>What the chronicle tells of someone or something: the last annals naming it.</summary>
	public string StoryOf(string name)
	{
		if (string.IsNullOrEmpty(name))
			return "";
		var lines = new List<string>();
		for (int n = _annals.Count - 1; n >= 0 && lines.Count < 6; n--)
			if (_annals[n].text.Contains(name))
				lines.Add($"Year {_annals[n].year}: {_annals[n].text}");
		lines.Reverse();
		return lines.Count > 0 ? string.Join("\n", lines) : "The chronicle has not spoken of it yet.";
	}

	/// <summary>What a creature has in mind: what it does, what it needs, what moves it.</summary>
	public string MindOf(int i)
	{
		if (i < 0 || i >= Units.Capacity || !Units.Alive[i])
			return "";
		var sb = new StringBuilder();
		sb.Append($"Doing: {((Task)Units.Task[i]).ToString().ToLower()}");
		if (Units.Prey[i] >= 0 && Units.Prey[i] < Units.Capacity && Units.Alive[Units.Prey[i]])
			sb.Append($" ({Assets.Species[Units.Species[Units.Prey[i]]].Name.ToLower()})");
		sb.Append($"\nHunger {(int)(Units.Hunger[i] * 100)}% · thirst {(int)(Units.Thirst[i] * 100)}% · energy {(int)(Units.Energy[i] * 100)}%");
		if (Units.Army[i] >= 0 && Units.Army[i] < Villages.Count)
			sb.Append($"\nMarching on {Villages[Units.Army[i]].Name}");
		if (Units.Mad[i] > 0f)
			sb.Append("\nMad with rage");
		if (Units.Cursed[i] > 0f)
			sb.Append("\nUnder a curse");
		if (Units.Kills[i] > 0)
			sb.Append($"\n{Units.Kills[i]} foes slain");
		return sb.ToString();
	}
}
