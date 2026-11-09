using System;
using System.Collections.Generic;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Peoples (0.3): the races chosen for a world (data/races.json, varied by the world's seed), their
/// languages, individuals with families and traits, and their first villages.
///
/// Villages, their buildings and territory are in Villages.cs, their jobs in Jobs.cs (docs/VILLAGES.md).
/// People choose what to do themselves, once
/// a second, with a small utility AI made of "neurons" (as in WorldBox): each possible action has a
/// weight, a cooldown and a priority; the most urgent action whose cooldown is over fires.
/// </summary>
public partial class Simulation
{
	public enum Role : byte { Villager, Warrior, Chief, Shaman }

	[Flags]
	public enum Trait { Brave = 1, Lazy = 2, Kind = 4, Greedy = 8, Wise = 16, Strong = 32 }

	public static readonly string[] RoleNames = { "villager", "warrior", "chief", "shaman" };

	/// <summary>One action a person can take, as in WorldBox's neuron system: a weight (how much it
	/// matters), a cooldown (seconds before it can fire again), a priority layer and a switch.</summary>
	public sealed class Neuron
	{
		public string Name;
		public float Weight;
		public float Cooldown;
		public int Priority;
		public bool Enabled = true;
	}

	/// <summary>The neurons of every person (switchable: the unit inspector will show them).</summary>
	public readonly Neuron[] Neurons =
	{
		new() { Name = "drink", Weight = 1.2f, Cooldown = 2f, Priority = 3 },
		new() { Name = "eat", Weight = 1.1f, Cooldown = 2f, Priority = 3 },
		new() { Name = "rest", Weight = 0.8f, Cooldown = 8f, Priority = 2 },
		new() { Name = "breed", Weight = 0.7f, Cooldown = 10f, Priority = 1 },
		new() { Name = "pair", Weight = 0.9f, Cooldown = 6f, Priority = 1 },
		new() { Name = "work", Weight = 0.6f, Cooldown = 1f, Priority = 1 },
		new() { Name = "play", Weight = 0.3f, Cooldown = 4f, Priority = 0 },
		new() { Name = "wander", Weight = 0.1f, Cooldown = 3f, Priority = 0 },
	};
	private const int NDrink = 0, NEat = 1, NRest = 2, NBreed = 3, NPair = 4, NWork = 5, NPlay = 6, NWander = 7;

	// Name of each person, by unit slot (reused when the slot is).
	private string[] _names = Array.Empty<string>();
	private readonly Dictionary<int, Language> _languages = new();
	// Per unit and neuron: the time when the neuron can fire again.
	private float[] _neuronReady = Array.Empty<float>();
	private const float Reach = 1.3f;

	// ------------------------------------------------------------------ setup

	private void SetupPeoples()
	{
		Assets.RemovePeoples();
		SetupVillages();
		SetupKingdoms();
		_names = Array.Empty<string>();
		_languages.Clear();
	}

	/// <summary>Brings the chosen peoples into the world (ids from data/races.json): each founds a
	/// village in a biome it likes, with `perRace` people (a chief, a shaman, two warriors and
	/// villagers, of both sexes, some children). Returns how many villages were founded.</summary>
	public int StartPeoples(string[] raceIds, int perRace)
	{
		int founded = 0;
		foreach (string id in raceIds)
		{
			var rec = Assets.Races.Find(r => r.Id == id);
			if (rec == null)
				continue;
			var race = rec.Vary(_rng);
			int s = Assets.SpeciesIndex(id);
			if (s < 0)
			{
				s = Assets.AddSpecies(new SpeciesRecord
				{
					Id = race.Id, Name = race.Name, Sprite = $"creatures/{race.Id}", Speed = race.Speed * 0.8f,
					Roam = 6f, Diet = "omnivore", Size = race.Size, Lifespan = race.Lifespan, Litter = 1,
					IsPeople = true, Race = race,
				});
				_languages[s] = new Language(race.Language, _rng);
				if (Population.Length < Assets.Species.Count)
				{
					Array.Resize(ref Population, Assets.Species.Count);
					Array.Resize(ref Capacity, Assets.Species.Count);
					Array.Resize(ref _established, Assets.Species.Count);
					Capacity[s] = int.MaxValue;
				}
			}
			int tile = FindHome(race);
			if (tile < 0)
				continue;
			int v = FoundVillage(s, tile % World.Width, tile / World.Width);
			var sp = Assets.Species[s];
			for (int k = 0; k < perRace; k++)
			{
				float x = Villages[v].X + 0.5f + ((float)_rng.NextDouble() * 2f - 1f) * 3f;
				float y = Villages[v].Y + 0.5f + ((float)_rng.NextDouble() * 2f - 1f) * 3f;
				if (!World.IsLandAt(x, y))
				{
					x = Villages[v].X + 0.5f;
					y = Villages[v].Y + 0.8f;
				}
				bool child = k >= perRace - perRace / 5;
				int i = SpawnPerson(s, v, x, y, child, k % 2 == 0);
				if (!child)
					Units.Age[i] = AdultAge(sp) + Math.Min(sp.Lifespan * 0.3f, 40f) * (float)_rng.NextDouble();
				Units.Role[i] = (byte)(k == 0 ? Role.Chief : k == 1 ? Role.Shaman : k <= 3 ? Role.Warrior : Role.Villager);
			}
			int kingdom = CreateKingdom(s, v);
			LogEvent($"the {race.Name} found the village of {Villages[v].Name}, heart of the kingdom of {Kingdoms[kingdom].Name}.", "kings");
			founded++;
		}
		Zones.Rebuild(Units);
		return founded;
	}

	/// <summary>A tile for a people's first village: in a biome it likes, near fresh water, far from
	/// other villages. -1 if the world has none.</summary>
	private int FindHome(RaceRecord race)
	{
		var liked = new HashSet<int>();
		foreach (var name in race.Biomes)
		{
			int b = Array.IndexOf(_biomeNames, name);
			if (b >= 0)
				liked.Add(b);
		}
		int fallback = -1;
		for (int tries = 0; tries < 20000; tries++)
		{
			int x = 4 + _rng.Next(World.Width - 8), y = 4 + _rng.Next(World.Height - 8);
			int t = World.Index(x, y);
			if (World.Water[t] != SimWorld.WaterLand || _buildingAt[t] >= 0)
				continue;
			bool far = true;
			foreach (var v in Villages)
				far &= Math.Abs(v.X - x) + Math.Abs(v.Y - y) > 40;
			if (!far)
				continue;
			bool likes = liked.Contains(World.Biome[t]);
			int w = _nearestWater[t];
			bool water = w >= 0 && Math.Abs(w % World.Width - x) + Math.Abs(w / World.Width - y) <= 8;
			if (likes && water)
				return t;
			if (fallback < 0 && (likes || water))
				fallback = t;
		}
		return fallback;
	}

	private int SpawnPerson(int species, int village, float x, float y, bool newborn, bool female)
	{
		int i = SpawnUnit(species, x, y, newborn);
		Units.Village[i] = village;
		Units.Female[i] = female;
		if (_names.Length < Units.Capacity)
			Array.Resize(ref _names, Math.Max(Units.Capacity, _names.Length * 2));
		Units.Name[i] = i;
		_names[i] = _languages[species].PersonName();
		int traits = 0;
		for (int k = 0; k < 2; k++)
			traits |= 1 << _rng.Next(6);
		Units.Traits[i] = traits;
		Units.Health[i] = MaxHealth(i);
		Units.BreedWait[i] = YearSeconds * 0.3f;
		Villages[village].Population++;
		EnsureNeurons();
		return i;
	}

	private void EnsureNeurons()
	{
		int need = Units.Capacity * Neurons.Length;
		if (_neuronReady.Length < need)
			Array.Resize(ref _neuronReady, Math.Max(need, _neuronReady.Length * 2));
	}

	/// <summary>When a person dies: their partner is free again, the village counts one less.</summary>
	private void PersonDied(int i)
	{
		int p = Units.Partner[i];
		if (p >= 0 && p < Units.Capacity && Units.Partner[p] == i)
			Units.Partner[p] = -1;
		RulerDied(i);
		int v = Units.Village[i];
		if (v >= 0)
		{
			Villages[v].Population--;
			if (Units.Role[i] == (byte)Role.Chief)
				LogEvent($"{NameOf(i)}, chief of {Villages[v].Name}, has died.", "cities");
		}
	}

	public string NameOf(int i) => Units.Name[i] >= 0 ? _names[Units.Name[i]] : Assets.Species[Units.Species[i]].Name;

	// ------------------------------------------------------------------ people (1 / s)

	/// <summary>A person's decision, once a second: each enabled neuron whose cooldown is over is
	/// scored (weight x urgency); the best fires. Arriving somewhere finishes the task first.</summary>
	private void ThinkPerson(int i, SpeciesRecord sp, float dt)
	{
		EnsureNeurons();
		int v = Units.Village[i];
		float now0 = (float)Scheduler.Time;
		// Aboard a war boat: nothing to do until ashore (or home again if peace came first).
		if (Units.Task[i] == (byte)Task.Sail)
		{
			if (Units.Army[i] < 0 && !_vehicles.Exists(b => b.Crew != null && b.Crew.Contains(i)))
				Units.Task[i] = (byte)Task.Wander;
			else
			{
				Units.Hunger[i] = Math.Min(Units.Hunger[i], 0.5f);
				Units.Thirst[i] = Math.Min(Units.Thirst[i], 0.5f);
				return;
			}
		}
		// Pairing and having a child need no walking: they can happen whatever the person is doing.
		if (Neurons[NPair].Enabled && IsAdult(i) && Units.Partner[i] < 0 && _neuronReady[i * Neurons.Length + NPair] <= now0)
		{
			_neuronReady[i * Neurons.Length + NPair] = now0 + Neurons[NPair].Cooldown;
			Pair(i);
		}
		if (Neurons[NBreed].Enabled && CanBreed(i) && _neuronReady[i * Neurons.Length + NBreed] <= now0)
		{
			_neuronReady[i * Neurons.Length + NBreed] = now0 + Neurons[NBreed].Cooldown;
			Breed(i);
		}
		// Fire where one stands: run from it, whatever one was doing.
		if (OnFire(Units.X[i], Units.Y[i]))
		{
			Units.Prey[i] = -1;
			for (int tries = 0; tries < 8; tries++)
			{
				float fx = Units.X[i] + ((float)_rng.NextDouble() * 2f - 1f) * 4f, fy = Units.Y[i] + ((float)_rng.NextDouble() * 2f - 1f) * 4f;
				if (World.IsLandAt(fx, fy) && !OnFire(fx, fy))
				{
					GoTo(i, fx, fy, Task.Wander);
					break;
				}
			}
			return;
		}
		// Thirst and hunger that become urgent interrupt any task (a hunt, a walk to work).
		bool urgent = Units.Thirst[i] > 0.65f || (Units.Hunger[i] > 0.75f && v >= 0 && Villages[v].Food >= 1f);
		var task = (Task)Units.Task[i];
		if (urgent && task != Task.Drink && task != Task.Feast)
		{
			Units.Prey[i] = -1;
			Units.TargetX[i] = Units.X[i];
			Units.TargetY[i] = Units.Y[i];
			Units.Task[i] = (byte)Task.Wander;
			task = Task.Wander;
		}
		if (task == Task.Hunt && Units.Prey[i] >= 0)
			return;
		if (task == Task.Rest)
		{
			Units.Wait[i] -= dt;
			if (Units.Wait[i] > 0f)
				return;
			Units.Energy[i] = 1f;
			Units.Task[i] = (byte)Task.Wander;
		}
		bool arrived = AtTarget(i);
		if (arrived && Arrive(i, v, sp, dt))
			return;
		if (!arrived && task != Task.Wander)
			return;  // on the way somewhere: keep going

		float now = (float)Scheduler.Time;
		int best = -1;
		float bestScore = 0f;
		bool adult = IsAdult(i);
		bool lazy = (Units.Traits[i] & (int)Trait.Lazy) != 0;
		for (int n = 0; n < Neurons.Length; n++)
		{
			var neuron = Neurons[n];
			if (!neuron.Enabled || _neuronReady[i * Neurons.Length + n] > now)
				continue;
			float urgency = n switch
			{
				NDrink => Units.Thirst[i] > 0.5f ? Units.Thirst[i] : 0f,
				NEat => Units.Hunger[i] > 0.45f ? Units.Hunger[i] : 0f,
				NRest => Units.Energy[i] < 0.25f ? 1f - Units.Energy[i] : 0f,
				NBreed => 0f,  // handled above, without walking
				NPair => 0f,
				NWork => adult && Units.Job[i] != (byte)Job.None && v >= 0 ? (lazy ? 0.7f : 1f) : 0f,
				NPlay => adult ? 0f : 1f,
				_ => 1f,
			};
			float score = neuron.Weight * urgency + neuron.Priority * 0.01f * (urgency > 0f ? 1f : 0f);
			if (score > bestScore)
			{
				bestScore = score;
				best = n;
			}
		}
		if (best < 0)
			return;
		_neuronReady[i * Neurons.Length + best] = now + Neurons[best].Cooldown;
		switch (best)
		{
			case NDrink:
				if (NearWater(i) || NearWell(i))
					Units.Thirst[i] = 0f;
				else if (!GoToWell(i, v))
					GoToWater(i);
				break;
			case NEat:
				// Soldiers on campaign eat rations from their village's stores where they are.
				if (Units.Army[i] >= 0 && v >= 0 && Villages[v].Food >= 1f)
				{
					Villages[v].Food -= 1f;
					Units.Hunger[i] = 0f;
					Units.Suffering[i] = 0f;
					break;
				}
				if (v >= 0 && Villages[v].Food >= 1f)
				{
					// The village's food is eaten at home or at its stores, whichever is nearer.
					int store = NearestStore(i, v);
					int home = Units.Home[i];
					if (home >= 0 && Buildings[home].Alive && Buildings[home].Village == v && (store < 0
						|| MathF.Abs(Buildings[home].X - Units.X[i]) + MathF.Abs(Buildings[home].Y - Units.Y[i])
						< MathF.Abs(Buildings[store].X - Units.X[i]) + MathF.Abs(Buildings[store].Y - Units.Y[i])))
						store = home;
					var at = store >= 0 ? Buildings[store] : null;
					GoTo(i, (at?.X ?? Villages[v].X) + 0.5f + ((float)_rng.NextDouble() - 0.5f), (at?.Y ?? Villages[v].Y) + 1.1f, Task.Feast);
				}
				else if (!SeekGrass(i, sp))
					WanderNear(i, v, 6f);
				break;
			case NRest:
			{
				// At home; the homeless by the bonfire; soldiers on campaign where they stand.
				int home = Units.Home[i];
				if (Units.Army[i] >= 0)
					RestHere(i);
				else if (home >= 0 && Buildings[home].Alive)
					GoTo(i, Buildings[home].X + 0.5f + ((float)_rng.NextDouble() - 0.5f) * 0.6f, Buildings[home].Y + 1.15f, Task.Home);
				else if (v >= 0)
					GoTo(i, Villages[v].X + 0.5f + (float)_rng.NextDouble() - 0.5f, Villages[v].Y + 1.2f, Task.Home);
				else
					RestHere(i);
				break;
			}
			case NBreed:
				Breed(i);
				break;
			case NPair:
				Pair(i);
				break;
			case NWork:
				Work(i, v, sp);
				break;
			default:
				WanderNear(i, v, best == NPlay ? 3f : 6f);
				break;
		}
	}

	private void GoTo(int i, float x, float y, Task task)
	{
		// A spot on water: take the nearest land around it instead.
		if (!World.IsLandAt(x, y))
		{
			bool found = false;
			for (int r = 1; r <= 2 && !found; r++)
				for (int dy = -r; dy <= r && !found; dy++)
					for (int dx = -r; dx <= r && !found; dx++)
						if (World.IsLandAt(x + dx, y + dy))
						{
							x += dx;
							y += dy;
							found = true;
						}
			if (!found)
				return;
		}
		Units.TargetX[i] = x;
		Units.TargetY[i] = y;
		Units.Task[i] = (byte)task;
	}

	private void RestHere(int i)
	{
		Units.Task[i] = (byte)Task.Rest;
		Units.Wait[i] = 5f;
	}

	private void WanderNear(int i, int v, float r)
	{
		float cx = v >= 0 ? Villages[v].X + 0.5f : Units.X[i];
		float cy = v >= 0 ? Villages[v].Y + 0.5f : Units.Y[i];
		for (int tries = 0; tries < 4; tries++)
		{
			float x = cx + ((float)_rng.NextDouble() * 2f - 1f) * r;
			float y = cy + ((float)_rng.NextDouble() * 2f - 1f) * r;
			if (World.IsLandAt(x, y) && !OnFire(x, y))
			{
				GoTo(i, x, y, Task.Wander);
				return;
			}
		}
	}

	/// <summary>Finishes what the person walked to do. True when it did something this second.</summary>
	private bool Arrive(int i, int v, SpeciesRecord sp, float dt)
	{
		var task = (Task)Units.Task[i];
		switch (task)
		{
			case Task.Drink:
				if (NearWater(i) || NearWell(i))
					Units.Thirst[i] = 0f;
				Units.Task[i] = (byte)Task.Wander;
				return false;
			case Task.Graze:
				Graze(i);
				Units.Task[i] = (byte)Task.Wander;
				return false;
			case Task.Feast:
				if (v >= 0 && Villages[v].Food >= 1f)
				{
					Villages[v].Food -= 1f;
					Units.Hunger[i] = 0f;
					Units.Suffering[i] = 0f;
				}
				Units.Task[i] = (byte)Task.Wander;
				return true;
			case Task.Home:
				RestHere(i);
				return true;
			case Task.Deliver:
				if (v >= 0)
					Deliver(i, v);
				Units.Carry[i] = 0;
				Units.CarryAmount[i] = 0f;
				Units.Task[i] = (byte)Task.Wander;
				return false;
			case Task.Work:
				return DoWork(i, v, dt);
		}
		return false;
	}

	/// <summary>Whether a well of the person's village is right there.</summary>
	private bool NearWell(int i)
	{
		int v = Units.Village[i];
		if (v < 0)
			return false;
		int b = BuildingWithin((int)Units.X[i], (int)(Units.Y[i] - 0.5f), 1, _tWell);
		return b >= 0 && Buildings[b].Village == v && Buildings[b].Done;
	}

	/// <summary>Goes to drink at the village's nearest well when it is closer than open water.</summary>
	private bool GoToWell(int i, int v)
	{
		if (v < 0)
			return false;
		int b = Nearest(v, _tWell, i);
		if (b < 0)
			return false;
		var well = Buildings[b];
		float dx = well.X - Units.X[i], dy = well.Y - Units.Y[i];
		int w = _nearestWater[World.Index((int)Units.X[i], (int)Units.Y[i])];
		if (w >= 0)
		{
			float wx = w % World.Width - Units.X[i], wy = w / World.Width - Units.Y[i];
			if (wx * wx + wy * wy < dx * dx + dy * dy)
				return false;
		}
		GoTo(i, well.X + 0.5f + ((float)_rng.NextDouble() - 0.5f), well.Y + 1.15f, Task.Drink);
		return true;
	}

	// ------------------------------------------------------------------ families

	private bool CanBreed(int i)
	{
		int p = Units.Partner[i];
		int v = Units.Village[i];
		if (!Units.Female[i] || p < 0 || v < 0 || !Units.Alive[p] || Units.BreedWait[i] > 0f || !IsAdult(i))
			return false;
		var village = Villages[v];
		return village.Population < Homes(v) && village.Food >= 4f && Units.Hunger[i] < 0.5f;
	}

	private void Breed(int i)
	{
		int p = Units.Partner[i];
		int v = Units.Village[i];
		// Born next to its mother, or right where she stands when that is the shore.
		float cx = Units.X[i] + 0.3f, cy = Units.Y[i] + 0.2f;
		if (!World.IsLandAt(cx, cy))
		{
			cx = Units.X[i];
			cy = Units.Y[i];
		}
		int child = SpawnPerson(Units.Species[i], v, cx, cy, true, _rng.Next(2) == 0);
		Units.Mother[child] = i;
		Units.Father[child] = p;
		Units.Age[child] = 0f;
		// Plenty of food and room: children come sooner.
		var village = Villages[v];
		float plenty = village.Food > village.Population * 5f && Homes(v) > village.Population + 4 ? 0.5f : 1f;
		float wait = YearSeconds * plenty * (0.5f + 0.4f * (float)_rng.NextDouble());
		Units.BreedWait[i] = wait;
		Units.BreedWait[p] = wait;
		Births++;
		PeopleBirths++;
	}

	private void Pair(int i)
	{
		_found.Clear();
		Zones.Query(Units, Units.X[i], Units.Y[i], 6f, _found);
		foreach (int j in _found)
			if (j != i && Units.Alive[j] && Units.Village[j] == Units.Village[i] && Units.Female[j] != Units.Female[i]
				&& Units.Partner[j] < 0 && IsAdult(j) && Units.Mother[j] != i && Units.Mother[i] != j)
			{
				Units.Partner[i] = j;
				Units.Partner[j] = i;
				return;
			}
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>Villages for the HUD: name, people, population, stores, homes, buildings, land.</summary>
	public Godot.Collections.Array VillageTable()
	{
		var list = new Godot.Collections.Array();
		for (int k = 0; k < Villages.Count; k++)
		{
			var v = Villages[k];
			if (!v.Alive)
				continue;
			string site = "";
			if (v.Site >= 0 && Buildings[v.Site].Alive)
			{
				var bld = Buildings[v.Site];
				site = Assets.Buildings[bld.UpgradeTo >= 0 ? bld.UpgradeTo : bld.Type].Name.ToLower();
			}
			list.Add(new Godot.Collections.Dictionary
			{
				["index"] = k, ["name"] = v.Name, ["people"] = Assets.Species[v.Species].Name, ["population"] = v.Population,
				["food"] = (int)v.Food, ["wood"] = (int)v.Wood, ["stone"] = (int)v.Stone, ["metal"] = (int)v.Metal,
				["gold"] = (int)v.Gold, ["tools"] = v.Tools, ["weapons"] = v.Weapons, ["houses"] = v.Houses,
				["homes"] = Homes(k), ["zones"] = v.Zones.Count, ["fields"] = v.Fields.Count, ["x"] = v.X, ["y"] = v.Y,
				["site"] = v.Site >= 0 && Buildings[v.Site].Alive ? Buildings[v.Site].Progress : -1f, ["building"] = site,
				["buildings"] = BuildingSummary(k), ["jobs"] = JobCounts(v), ["founded"] = v.Founded, ["mother"] = v.Mother,
				["rank"] = RankNames[v.Rank], ["kingdom"] = v.Kingdom >= 0 ? Kingdoms[v.Kingdom].Name : "",
				["capital"] = v.Kingdom >= 0 && Kingdoms[v.Kingdom].Capital == k, ["siege"] = v.Siege, ["loyalty"] = (int)v.Loyalty,
			});
		}
		return list;
	}

	private string JobCounts(Village v)
	{
		var counts = new int[JobNames.Length];
		int vi = Villages.IndexOf(v);
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Village[i] == vi)
				counts[Units.Job[i]]++;
		var parts = new List<string>();
		for (int j = 1; j < JobNames.Length; j++)
			if (counts[j] > 0)
				parts.Add($"{counts[j]} {JobNames[j]}s");
		return string.Join(", ", parts);
	}

	public int VillageCount() => Villages.FindAll(v => v.Alive).Count;

	/// <summary>Living people of all races.</summary>
	public int PeopleCount()
	{
		int n = 0;
		foreach (var v in Villages)
			if (v.Alive)
				n += v.Population;
		return n;
	}

	/// <summary>The unit nearest to (x, y) in tiles within `r`, or -1 (hovering in the HUD).</summary>
	public int UnitAt(float x, float y, float r)
	{
		_found.Clear();
		Zones.Query(Units, x, y, r, _found);
		int best = -1;
		float bestD = float.MaxValue;
		foreach (int j in _found)
		{
			float d = MathF.Abs(Units.X[j] - x) + MathF.Abs(Units.Y[j] - 0.5f - y);
			if (d < bestD)
			{
				bestD = d;
				best = j;
			}
		}
		return best;
	}

	/// <summary>One line about a unit for the HUD: name, people, role, age, job, needs.</summary>
	public string UnitInfo(int i)
	{
		if (i < 0 || !Units.Alive[i])
			return "";
		var sp = Assets.Species[Units.Species[i]];
		string needs = $"hunger {(int)(Units.Hunger[i] * 100)}% · thirst {(int)(Units.Thirst[i] * 100)}%";
		if (!sp.IsPeople)
			return $"{sp.Name}, {(int)Units.Age[i]} years · {needs}";
		string traits = "";
		foreach (Trait t in Enum.GetValues<Trait>())
			if ((Units.Traits[i] & (int)t) != 0)
				traits += (traits.Length > 0 ? ", " : "") + t.ToString().ToLower();
		int v = Units.Village[i];
		string job = IsAdult(i) ? JobNames[Units.Job[i]] : "child";
		return $"{NameOf(i)} · {sp.Name} {(Units.Female[i] ? "woman" : "man")}, {RoleNames[Units.Role[i]]}, {(int)Units.Age[i]} years · "
			+ $"{job}{(v >= 0 ? " of " + Villages[v].Name : "")} · {traits} · {needs}";
	}

	public int UnitVillage(int i) => Units.Village[i];
	public int UnitMother(int i) => Units.Mother[i];
	public int UnitFather(int i) => Units.Father[i];
	public bool UnitIsPeople(int i) => Assets.Species[Units.Species[i]].IsPeople;
	public string UnitName(int i) => NameOf(i);

	/// <summary>Switches a neuron on or off for everyone (the inspector will do it per person).</summary>
	public void SetNeuron(string name, bool on)
	{
		foreach (var n in Neurons)
			if (n.Name == name)
				n.Enabled = on;
	}

	/// <summary>A sample of names in the language of people `id` (tests, the setup screen).</summary>
	public string[] SampleNames(string id, int count)
	{
		int s = Assets.SpeciesIndex(id);
		if (s < 0 || !_languages.ContainsKey(s))
			return Array.Empty<string>();
		var names = new string[count];
		for (int k = 0; k < count; k++)
			names[k] = _languages[s].PersonName();
		return names;
	}

	/// <summary>The race as varied for this world: stats and temperament (setup screen, tests).</summary>
	public Godot.Collections.Dictionary RaceOf(string id)
	{
		int s = Assets.SpeciesIndex(id);
		var d = new Godot.Collections.Dictionary();
		if (s < 0 || Assets.Species[s].Race == null)
			return d;
		var r = Assets.Species[s].Race;
		d["lifespan"] = r.Lifespan;
		d["adult_age"] = AdultAge(Assets.Species[s]);
		d["speed"] = r.Speed;
		foreach (var (k, val) in r.Stats)
			d[k] = val;
		foreach (var (k, val) in r.Temperament)
			d[k] = val;
		return d;
	}
}
