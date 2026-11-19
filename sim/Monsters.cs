using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Animundi.Sim;

/// <summary>
/// Common monsters that change (0.7, docs/NATURE.md). Legends have a mind each (Legends.cs);
/// common monsters (data/monsters.json: spiders, skeletons, slimes, demons...) have one per
/// species, and it does two things.
///
/// Lairs. Where a few monsters of a kind gather, they make a lair: a nest, a crypt, a pit.
/// A lair left alone grows, and brings new monsters into the world, even those that do not
/// breed. Warriors of a village nearby burn it out when they outnumber its guards; the
/// player's meteors and lightning, earthquakes and lava destroy it too.
///
/// Mutations. Every few years a thriving species changes: it takes one of the mutations of
/// its pool (venomous, giant, swift, swarming, iron-hided, burning, plague-bearing, cunning),
/// its numbers and its name change ("Venomous Spider"), and the chronicle tells it, with its
/// lineage. The local model chooses when one runs (a JSON record: mutation, name), else a
/// procedural mind does, by what presses the species: hunted by the peoples, it grows
/// harder to kill; starving, faster; few, it breeds more.
///
/// Events bring monsters too: the dead of a rotting plague rise as zombies (Plagues.cs),
/// demons crawl out of eruptions (Disasters.cs), ghosts haunt abandoned villages.
/// </summary>
public partial class Simulation
{
	public sealed class Strain
	{
		public MonsterRecord Rec;
		public int Species;
		public string BaseName = "";
		public int Generation = 1;
		public readonly List<string> Mutations = new();
		public readonly List<string> Lineage = new();
		/// <summary>Multiplies people's chance to fight it off, and how fast its lairs spawn.</summary>
		public float Defend = 1f, Spawn = 1f, Scale = 1f;
		public bool Fire, Plague;
		/// <summary>The sickness a plague-bearing strain carries (index in Diseases), or -1.</summary>
		public int Disease = -1;
		/// <summary>When it changes next, once it thrives.</summary>
		public double ChangeAt;
		/// <summary>What pressed it since it last changed.</summary>
		public int SlainByPeople, Starved;
		public string Mind = "";
		public Question Asking;
	}

	public sealed class Lair
	{
		public int Species;
		public string Kind = "cave", Name = "lair", Place = "";
		public int X, Y, Year, Born;
		/// <summary>1 new .. 3 great.</summary>
		public float Size = 1f;
		public float Health = 1f;
		public bool Alive = true;
		public double NextSpawn, NextRaid;
		public string End = "";
	}

	/// <summary>A species' change as written by a mind, before validation.</summary>
	public sealed class MutationDraft
	{
		[JsonPropertyName("mutation")] public string Mutation { get; set; } = "";
		[JsonPropertyName("name")] public string Name { get; set; } = "";
	}

	public readonly List<Strain> Strains = new();
	public readonly List<Lair> Lairs = new();
	// Per species index: its strain, or null (animals, peoples, legends).
	private Strain[] _strainOf = Array.Empty<Strain>();
	private Random _monsterRng = new(1);
	// What each monster species was before any world changed it (the library outlives worlds).
	private readonly Dictionary<string, (string name, float speed, float roam, int size, int litter, float lifespan)> _monsterBase = new();
	public const int MaxLairsPerSpecies = 3, MaxLairs = 14;
	/// <summary>A species changes once this many of it live.</summary>
	public const int ThrivingMonsters = 6;

	private void SetupMonsters(int seed)
	{
		Strains.Clear();
		Lairs.Clear();
		_monsterRng = new Random(seed ^ 0x3a17);
		_strainOf = new Strain[Assets.Species.Count];
		foreach (var rec in Assets.Monsters)
		{
			int s = Assets.SpeciesIndex(rec.Id);
			if (s < 0)
				continue;
			var sp = Assets.Species[s];
			// Undo what the last world made of it.
			if (_monsterBase.TryGetValue(rec.Id, out var was))
				(sp.Name, sp.Speed, sp.Roam, sp.Size, sp.Litter, sp.Lifespan) = was;
			else
				_monsterBase[rec.Id] = (sp.Name, sp.Speed, sp.Roam, sp.Size, sp.Litter, sp.Lifespan);
			var strain = new Strain { Rec = rec, Species = s, BaseName = sp.Name };
			strain.ChangeAt = YearSeconds * (4.0 + 4.0 * _monsterRng.NextDouble());
			Strains.Add(strain);
			_strainOf[s] = strain;
		}
	}

	private Strain StrainOf(int species) => species >= 0 && species < _strainOf.Length ? _strainOf[species] : null;

	/// <summary>Whether a species is a common monster (data/monsters.json).</summary>
	private bool IsMonster(int species) => StrainOf(species) != null;

	// ------------------------------------------------------------------ every two seconds

	private void MonsterStep(float dt)
	{
		if (World == null || !Law("monsters"))
			return;
		foreach (var strain in Strains)
		{
			if (strain.Asking != null)
			{
				if (strain.Asking.Take(Scheduler.Time, out string json, out string why))
				{
					strain.Asking = null;
					string error = json == null ? why : SubmitMutationJson(strain, json, "model");
					LastModelAnswer = json ?? "";
					LastModelError = error ?? "";
					if (string.IsNullOrEmpty(error))
						ModelAnswers++;
					else
					{
						ModelFailures++;
						ApplyMutation(strain, ProceduralMutation(strain), "procedural");
					}
				}
				continue;
			}
			int pop = Population[strain.Species];
			// The clock only runs while the species thrives.
			if (pop < ThrivingMonsters)
				strain.ChangeAt = Math.Max(strain.ChangeAt, Scheduler.Time + YearSeconds * 3.0);
			else if (Scheduler.Time >= strain.ChangeAt && Unused(strain).Count > 0)
				ThinkStrain(strain, force: false);
			// Dark and magical eras (Eras.cs) bring monsters out: their clock runs faster too.
			if (EraMonsters() > 1f)
				strain.ChangeAt -= dt * (EraMonsters() - 1f);
			if (pop >= 4 && _monsterRng.NextDouble() < 0.04 * dt * EraMonsters())
				TryFoundLair(strain);
		}
		foreach (var lair in Lairs)
			if (lair.Alive)
				LairLives(lair, dt);
	}

	// ------------------------------------------------------------------ lairs

	private int LairsOf(int species)
	{
		int n = 0;
		foreach (var l in Lairs)
			if (l.Alive && l.Species == species)
				n++;
		return n;
	}

	private int LairsAlive()
	{
		int n = 0;
		foreach (var l in Lairs)
			if (l.Alive)
				n++;
		return n;
	}

	/// <summary>Monsters of a species gathered somewhere make a lair there: one of them is
	/// picked, and if three of its kin stand within six tiles and no lair is near, it digs.</summary>
	private void TryFoundLair(Strain strain)
	{
		if (LairsOf(strain.Species) >= MaxLairsPerSpecies || LairsAlive() >= MaxLairs)
			return;
		int skip = _monsterRng.Next(Math.Max(1, Population[strain.Species])), i = -1;
		for (int u = 0; u < Units.Capacity; u++)
			if (Units.Alive[u] && Units.Species[u] == strain.Species && skip-- <= 0)
			{
				i = u;
				break;
			}
		if (i >= 0)
			FoundLair(strain, (int)Units.X[i], (int)Units.Y[i], force: false);
	}

	private Lair FoundLair(Strain strain, int x, int y, bool force)
	{
		if (!World.IsLand(x, y))
			return null;
		int t = World.Index(x, y);
		if (_buildingAt[t] >= 0 || _ground[t] != 0 || World.Biome[t] == _bLava)
			return null;
		foreach (var l in Lairs)
			if (l.Alive && (l.X - x) * (l.X - x) + (l.Y - y) * (l.Y - y) < 12 * 12)
				return null;
		if (!force)
		{
			_found.Clear();
			Zones.Query(Units, x + 0.5f, y + 0.5f, 6f, _found);
			int kin = 0;
			foreach (int j in _found)
				if (Units.Alive[j] && Units.Species[j] == strain.Species)
					kin++;
			if (kin < 3)
				return null;
		}
		var lair = new Lair
		{
			Species = strain.Species, Kind = strain.Rec.Lair, Name = strain.Rec.LairName, X = x, Y = y, Year = Year(),
			Place = PlaceNear(x + 0.5f, y + 0.5f), NextSpawn = Scheduler.Time + 20.0, NextRaid = Scheduler.Time + YearSeconds * 3.0,
		};
		Lairs.Add(lair);
		LogEvent($"{Assets.Species[strain.Species].Name.ToLower()}s make a {lair.Name} {lair.Place}.", "nature");
		return lair;
	}

	/// <summary>A lair grows when left alone, brings new monsters while few guard it, and is
	/// burned out by the warriors of a village nearby when they outnumber its guards.</summary>
	private void LairLives(Lair lair, float dt)
	{
		var strain = StrainOf(lair.Species);
		var sp = Assets.Species[lair.Species];
		float before = lair.Size;
		lair.Size = Math.Min(3f, lair.Size + 0.25f * dt / YearSeconds);
		lair.Health = Math.Min(1f, lair.Health + 0.1f * dt / YearSeconds);
		if ((int)before != (int)lair.Size)
			LogEvent(lair.Size >= 3f ? $"the {lair.Name} {lair.Place} has become a great one: {sp.Name.ToLower()}s pour out of it."
				: $"the {lair.Name} {lair.Place} grows.", "nature");
		if (Scheduler.Time >= lair.NextSpawn)
		{
			lair.NextSpawn = Scheduler.Time + 34.0 / lair.Size / (strain?.Spawn ?? 1f) * (0.8 + 0.4 * _monsterRng.NextDouble()) / EraMonsters();
			if (Guards(lair) < 3 + 3 * (int)lair.Size && Population[lair.Species] < 50)
			{
				float x = lair.X + 0.5f + (float)_monsterRng.NextDouble() - 0.5f, y = lair.Y + 0.9f;
				if (World.IsLandAt(x, y))
				{
					SpawnUnit(lair.Species, x, y, false);
					lair.Born++;
				}
			}
		}
		if (Scheduler.Time >= lair.NextRaid)
		{
			lair.NextRaid = Scheduler.Time + YearSeconds * (1.5 + 1.5 * _monsterRng.NextDouble());
			if (_monsterRng.NextDouble() < 0.5)
				RaidLair(lair);
		}
	}

	/// <summary>Monsters of the lair's kind standing within ten tiles of it.</summary>
	private int Guards(Lair lair)
	{
		_found.Clear();
		Zones.Query(Units, lair.X + 0.5f, lair.Y + 0.5f, 10f, _found);
		int n = 0;
		foreach (int j in _found)
			if (Units.Alive[j] && Units.Species[j] == lair.Species)
				n++;
		return n;
	}

	/// <summary>The nearest village within 16 tiles sends its warriors against the lair, if
	/// they outnumber its guards by two: the guards die, some warriors with them, the lair burns.</summary>
	private void RaidLair(Lair lair)
	{
		int v = -1;
		float best = 16f * 16f;
		for (int k = 0; k < Villages.Count; k++)
		{
			var o = Villages[k];
			float d = (o.X - lair.X) * (o.X - lair.X) + (o.Y - lair.Y) * (o.Y - lair.Y);
			if (o.Alive && d < best)
			{
				best = d;
				v = k;
			}
		}
		if (v < 0)
			return;
		var warriors = new List<int>();
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Village[i] == v && Units.Role[i] == (byte)Role.Warrior && IsAdult(i) && Units.Army[i] < 0)
				warriors.Add(i);
		_found.Clear();
		Zones.Query(Units, lair.X + 0.5f, lair.Y + 0.5f, 10f, _found);
		var guards = new List<int>();
		foreach (int j in _found)
			if (Units.Alive[j] && Units.Species[j] == lair.Species)
				guards.Add(j);
		if (warriors.Count < guards.Count + 2)
			return;
		float defend = StrainOf(lair.Species)?.Defend ?? 1f;
		int lost = 0;
		foreach (int g in guards)
		{
			// Each guard may take a warrior with it.
			if (lost < warriors.Count - 1 && _monsterRng.NextDouble() > DefendChance(warriors[lost]) * defend)
				KillUnit(warriors[lost++], Death.Eaten);
			KillUnit(g, Death.Other);
		}
		var village = Villages[v];
		lair.Alive = false;
		lair.End = $"burned out by the warriors of {village.Name} in year {Year()}";
		LogEvent($"the warriors of {village.Name} burn out the {lair.Name} near their village: {guards.Count} monsters slain, {lost} warriors lost.", "nature");
		if (village.Kingdom >= 0)
			Remember(village.Kingdom, "hunt", $"the warriors of {village.Name} burned out a {lair.Name}", 2f);
	}

	/// <summary>Lairs within `radius` of (x, y) lose `damage` of their strength (1 = all of it);
	/// one that has none left is gone, and the chronicle says how (`how`: "caves in").</summary>
	private int DamageLairs(float x, float y, float radius, float damage, string how)
	{
		int gone = 0;
		foreach (var lair in Lairs)
		{
			if (!lair.Alive || (lair.X + 0.5f - x) * (lair.X + 0.5f - x) + (lair.Y + 0.5f - y) * (lair.Y + 0.5f - y) > radius * radius)
				continue;
			lair.Health -= damage;
			if (lair.Health > 0f)
				continue;
			lair.Alive = false;
			lair.End = $"{how} in year {Year()}";
			LogEvent($"the {lair.Name} {lair.Place} {how}.", "nature");
			gone++;
		}
		return gone;
	}

	// ------------------------------------------------------------------ mutations

	private List<MutationRecord> Unused(Strain strain)
	{
		var list = new List<MutationRecord>();
		foreach (string id in strain.Rec.Pool)
		{
			var m = Assets.Mutations.Find(o => o.Id == id);
			if (m != null && !strain.Mutations.Contains(id))
				list.Add(m);
		}
		return list;
	}

	private void ThinkStrain(Strain strain, bool force)
	{
		strain.ChangeAt = Scheduler.Time + YearSeconds * (6.0 + 6.0 * _monsterRng.NextDouble());
		if (!force)
		{
			var task = AskAnyMind(MutationPrompt(strain), MutationGrammar(strain), MutationSchema(strain),
				"You are the mind of a species of monsters in a world simulation. Answer with one JSON record.");
			if (task != null)
			{
				strain.Asking = new Question { Pending = task, Asked = Scheduler.Time };
				return;
			}
		}
		ApplyMutation(strain, ProceduralMutation(strain), "procedural");
	}

	/// <summary>What presses the species, in words (the model's prompt and the chronicle).</summary>
	private string Pressure(Strain strain)
	{
		if (strain.SlainByPeople >= 3 && strain.SlainByPeople >= strain.Starved)
			return "hunted by the peoples";
		if (strain.Starved >= 3)
			return "starving";
		return Population[strain.Species] < 12 ? "few" : "thriving";
	}

	/// <summary>The change that answers what presses the species: hunted, harder to kill;
	/// starving, faster and bigger; few, more of them; else any.</summary>
	private MutationDraft ProceduralMutation(Strain strain)
	{
		var unused = Unused(strain);
		if (unused.Count == 0)
			return null;
		string[] wanted = Pressure(strain) switch
		{
			"hunted by the peoples" => new[] { "armoured", "venom", "cunning" }, "starving" => new[] { "swift", "giant" },
			"few" => new[] { "swarm" }, _ => Array.Empty<string>(),
		};
		var weights = new List<float>();
		float total = 0f;
		foreach (var m in unused)
		{
			float w = Array.IndexOf(wanted, m.Id) >= 0 ? 4f : 1f;
			weights.Add(w);
			total += w;
		}
		float r = (float)_monsterRng.NextDouble() * total;
		var pick = unused[^1];
		for (int k = 0; k < unused.Count; k++)
		{
			r -= weights[k];
			if (r <= 0f)
			{
				pick = unused[k];
				break;
			}
		}
		return new MutationDraft { Mutation = pick.Id, Name = "" };
	}

	/// <summary>The name a strain takes with a new mutation: its two newest adjectives before
	/// the species' first name ("Swift Venomous Spider").</summary>
	private string StrainName(Strain strain, MutationRecord added)
	{
		var adjectives = new List<string> { added.Adjective };
		if (strain.Mutations.Count > 0)
		{
			var last = Assets.Mutations.Find(o => o.Id == strain.Mutations[^1]);
			if (last != null)
				adjectives.Add(last.Adjective);
		}
		return $"{string.Join(" ", adjectives)} {strain.BaseName}";
	}

	/// <summary>Checks a species' change: a mutation of its pool it has not taken yet; a name,
	/// if given, short and plain, that no other species bears. Returns null when valid.</summary>
	private string ValidateMutation(Strain strain, MutationDraft d, out MutationRecord m)
	{
		m = null;
		if (d == null)
			return "empty";
		string id = d.Mutation;
		m = Unused(strain).Find(o => o.Id == id);
		if (m == null)
			return $"'{d.Mutation}' is not a change this species can take";
		string name = (d.Name ?? "").Trim();
		if (name == "")
			return null;
		string error = NameError(name, 28);
		if (error != null)
			return error;
		for (int s = 0; s < Assets.Species.Count; s++)
			if (s != strain.Species && string.Equals(Assets.Species[s].Name, name, StringComparison.OrdinalIgnoreCase))
				return $"another species is already called '{name}'";
		return null;
	}

	private string SubmitMutationJson(Strain strain, string json, string mind)
	{
		MutationDraft d;
		try
		{
			d = JsonSerializer.Deserialize<MutationDraft>(json);
		}
		catch (Exception e)
		{
			return "not valid JSON: " + e.Message;
		}
		string error = ValidateMutation(strain, d, out _);
		if (error != null)
			return error;
		ApplyMutation(strain, d, mind);
		return "";
	}

	private void ApplyMutation(Strain strain, MutationDraft d, string mind)
	{
		if (ValidateMutation(strain, d, out var m) != null)
			return;
		var sp = Assets.Species[strain.Species];
		string old = sp.Name, pressure = Pressure(strain);
		string name = (d.Name ?? "").Trim();
		sp.Name = name != "" ? name : StrainName(strain, m);
		sp.Speed *= m.Speed;
		sp.Roam *= m.Roam;
		sp.Size = Math.Min(13, sp.Size + m.Size);
		sp.Litter += m.Litter;
		sp.Lifespan *= m.Lifespan;
		strain.Defend *= m.Defend;
		strain.Spawn *= m.Spawn;
		if (m.Size > 0)
			strain.Scale *= 1.25f;
		strain.Fire |= m.Ability == "fire";
		if (m.Ability == "plague" && !strain.Plague)
		{
			strain.Plague = true;
			// Its own sickness, which people catch from its bite.
			var disease = NewDisease($"the {strain.BaseName.ToLower()}s", "monsters", "people", $"the {strain.BaseName} Fever");
			strain.Disease = disease.Index;
		}
		strain.Mutations.Add(m.Id);
		strain.Generation++;
		strain.Mind = mind;
		strain.SlainByPeople = strain.Starved = 0;
		strain.Lineage.Add($"year {Year()}: {old} → {sp.Name} ({pressure}): {m.Text}");
		LogEvent($"the {old.ToLower()}s change, {pressure}: they are now the {sp.Name}s, generation {strain.Generation}; {m.Text}.", "nature");
	}

	/// <summary>A monster of a plague-bearing strain bit someone at (x, y): those who stand
	/// there may catch its sickness.</summary>
	private void MonsterBite(int hunter, float x, float y)
	{
		var strain = StrainOf(Units.Species[hunter]);
		if (strain == null)
			return;
		if (strain.Fire && World.InBounds((int)x, (int)y))
			IgniteTile(World.Index((int)x, (int)y));
		if (strain.Plague && strain.Disease >= 0 && strain.Disease < Diseases.Count)
		{
			var d = Diseases[strain.Disease];
			// (a sickness that died out sleeps eight years in them before it can break out again)
			if (d.Over && Year() - d.EndYear < 8)
				return;
			if (d.Over)
				Reawaken(d);
			_plagueFound.Clear();
			Zones.Query(Units, x, y, 2f, _plagueFound);
			int caught = 0;
			foreach (int j in _plagueFound)
				if (caught < 2 && Infect(j, d))
					caught++;
		}
	}

	/// <summary>A monster died (KillUnit): what killed it presses its species.</summary>
	private void MonsterDied(int i, Death cause)
	{
		var strain = StrainOf(Units.Species[i]);
		if (strain == null)
			return;
		if (cause == Death.Other || cause == Death.War)
			strain.SlainByPeople++;
		else if (cause == Death.Hunger || cause == Death.Thirst)
			strain.Starved++;
	}

	/// <summary>An abandoned village is haunted: ghosts walk its ruins.</summary>
	private void Haunt(Village village)
	{
		int ghost = Assets.SpeciesIndex("ghost");
		if (ghost < 0 || !Law("monsters") || _monsterRng.NextDouble() > 0.5 || Population[ghost] >= 30)
			return;
		int n = 2 + _monsterRng.Next(2), came = 0;
		for (int tries = 0; tries < 12 && came < n; tries++)
		{
			float x = village.X + 0.5f + _monsterRng.Next(-3, 4), y = village.Y + 0.5f + _monsterRng.Next(-3, 4);
			if (!World.IsLandAt(x, y))
				continue;
			SpawnUnit(ghost, x, y, false);
			came++;
		}
		if (came > 0)
			LogEvent($"ghosts are seen among the ruins of {village.Name}.", "nature");
	}

	// ------------------------------------------------------------------ the model's side

	public string MutationPrompt(Strain strain)
	{
		var sp = Assets.Species[strain.Species];
		var sb = new StringBuilder();
		sb.Append($"You are the mind of the {sp.Name}s, a species of monsters. {Population[strain.Species]} of you live, in {LairsOf(strain.Species)} lairs. Year {Year()}.\n");
		sb.Append($"Since you last changed: {strain.SlainByPeople} of you were slain by the peoples, {strain.Starved} starved. You are {Pressure(strain)}.\n");
		if (strain.Lineage.Count > 0)
			sb.Append($"Your lineage: {string.Join("; ", strain.Lineage)}.\n");
		sb.Append("Your kind can now change in one of these ways:\n");
		foreach (var m in Unused(strain))
			sb.Append($"- {m.Id}: {m.Text}\n");
		sb.Append("Choose the \"mutation\" that answers what presses you, and the \"name\" your kind will bear from now on (two or three words, or \"\" to let the world name you). Answer with the JSON record only.\n");
		return sb.ToString();
	}

	private string MutationGrammar(Strain strain)
	{
		var ids = new List<string>();
		foreach (var m in Unused(strain))
			ids.Add($"\"\\\"{m.Id}\\\"\"");
		return "root ::= \"{\" ws \"\\\"mutation\\\":\" ws mutation \",\" ws \"\\\"name\\\":\" ws name ws \"}\"\n"
			+ $"mutation ::= {string.Join(" | ", ids)}\nname ::= \"\\\"\\\"\" | {LocalModel.Text(26, 3)}\nws ::= [ ]?\n";
	}

	private string MutationSchema(Strain strain)
	{
		var ids = new List<string>();
		foreach (var m in Unused(strain))
			ids.Add(m.Id);
		return JsonSerializer.Serialize(new Dictionary<string, object>
		{
			["type"] = "object", ["required"] = new[] { "mutation", "name" },
			["properties"] = new Dictionary<string, object>
			{
				["mutation"] = new Dictionary<string, object> { ["enum"] = ids },
				["name"] = new Dictionary<string, object> { ["type"] = "string", ["maxLength"] = 28 },
			},
		});
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>The monster species of this world that live or have changed: id, name, base,
	/// generation, mutations, lineage, population, lairs, pressure, mind.</summary>
	public Godot.Collections.Array StrainTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var strain in Strains)
		{
			int pop = Population[strain.Species];
			if (pop == 0 && strain.Generation == 1 && LairsOf(strain.Species) == 0)
				continue;
			var adjectives = new Godot.Collections.Array();
			foreach (string id in strain.Mutations)
				adjectives.Add(Assets.Mutations.Find(o => o.Id == id)?.Adjective ?? id);
			list.Add(new Godot.Collections.Dictionary
			{
				["id"] = strain.Rec.Id, ["name"] = Assets.Species[strain.Species].Name, ["base"] = strain.BaseName, ["generation"] = strain.Generation,
				["mutations"] = adjectives, ["lineage"] = string.Join("\n", strain.Lineage), ["population"] = pop, ["lairs"] = LairsOf(strain.Species),
				["pressure"] = Pressure(strain), ["mind"] = strain.Mind, ["speed"] = Assets.Species[strain.Species].Speed,
				["size"] = Assets.Species[strain.Species].Size, ["defend"] = strain.Defend,
			});
		}
		return list;
	}

	/// <summary>The lairs of this world, standing ones first: species, name, kind, place, size,
	/// year, born, alive, end, x, y.</summary>
	public Godot.Collections.Array LairTable()
	{
		var list = new Godot.Collections.Array();
		for (int pass = 0; pass < 2; pass++)
			for (int k = Lairs.Count - 1; k >= 0; k--)
			{
				var l = Lairs[k];
				if (l.Alive != (pass == 0))
					continue;
				list.Add(new Godot.Collections.Dictionary
				{
					["species"] = Assets.Species[l.Species].Name, ["name"] = l.Name, ["kind"] = l.Kind, ["place"] = l.Place, ["size"] = l.Size,
					["year"] = l.Year, ["born"] = l.Born, ["alive"] = l.Alive, ["end"] = l.End, ["x"] = l.X, ["y"] = l.Y, ["health"] = l.Health,
				});
			}
		return list;
	}

	private Strain StrainById(string id) => Strains.Find(s => s.Rec.Id == id);

	/// <summary>Makes a monster species change now with the procedural mind (tests).</summary>
	public void MutateNow(string id)
	{
		var strain = StrainById(id);
		if (strain != null)
			ThinkStrain(strain, force: true);
	}

	/// <summary>A mind's change (JSON) for the monster species `id` (tests): "" when taken.</summary>
	public string SubmitMutationJson(string id, string json)
	{
		var strain = StrainById(id);
		return strain == null ? "no such monster" : SubmitMutationJson(strain, json, "model");
	}

	/// <summary>The monsters of species `id` make a lair at (x, y) (tests): true when they did.</summary>
	public bool FoundLairAt(string id, int x, int y)
	{
		var strain = StrainById(id);
		return strain != null && FoundLair(strain, x, y, force: true) != null;
	}

	/// <summary>Makes every lair grow and spawn as if `years` had gone by (tests).</summary>
	public void AgeLairs(float years)
	{
		foreach (var lair in Lairs)
			if (lair.Alive)
			{
				lair.Size = Math.Min(3f, lair.Size + 0.25f * years);
				lair.NextSpawn = Scheduler.Time;
				lair.NextRaid = Scheduler.Time;
			}
	}

	/// <summary>Everything the Nature book shows, in one call: spirits, disasters, diseases,
	/// strains, lairs.</summary>
	public Godot.Collections.Dictionary NatureTable() => new()
	{
		["spirits"] = SpiritTable(), ["disasters"] = DisasterTable(), ["diseases"] = DiseaseTable(),
		["strains"] = StrainTable(), ["lairs"] = LairTable(),
	};
}
