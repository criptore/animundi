using System;
using System.Collections.Generic;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Peoples (0.3): the races chosen for a world (data/races.json, varied by the world's seed), their
/// languages, individuals with families and traits, and their first villages.
///
/// A village is a bonfire with houses around it and two stocks, food and wood. Every two seconds
/// it hands out work to its adults (gatherers, woodcutters, hunters, builders) by what it lacks,
/// and plans a new house when people run out of room. People choose what to do themselves, once
/// a second, with a small utility AI made of "neurons" (as in WorldBox): each possible action has a
/// weight, a cooldown and a priority; the most urgent action whose cooldown is over fires.
/// </summary>
public partial class Simulation
{
	public enum Role : byte { Villager, Warrior, Chief, Shaman }
	public enum Job : byte { None, Gatherer, Woodcutter, Hunter, Builder }
	public enum Goods : byte { None, Food, Wood }
	public enum BuildingKind : byte { Bonfire, House, Site }

	[Flags]
	public enum Trait { Brave = 1, Lazy = 2, Kind = 4, Greedy = 8, Wise = 16, Strong = 32 }

	public static readonly string[] RoleNames = { "villager", "warrior", "chief", "shaman" };
	public static readonly string[] JobNames = { "idle", "gatherer", "woodcutter", "hunter", "builder" };

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

	public sealed class Village
	{
		public string Name;
		public int Species;
		public int X, Y;
		public float Food, Wood;
		public int Population, Houses;
		public bool Alive = true;
		public int Founded;
		public int Site = -1;
	}

	public sealed class Building
	{
		public BuildingKind Kind;
		public int X, Y;
		public int Village;
		public float Progress;
		public bool Alive = true;
	}

	public readonly List<Village> Villages = new();
	public readonly List<Building> Buildings = new();
	private readonly List<string> _names = new();
	private readonly Dictionary<int, Language> _languages = new();
	// Per unit and neuron: the time when the neuron can fire again.
	private float[] _neuronReady = Array.Empty<float>();
	// Building on each tile, or -1.
	private int[] _buildingAt = Array.Empty<int>();
	private const int HouseRoom = 5, CampRoom = 6;
	private const float Reach = 1.3f;

	// ------------------------------------------------------------------ setup

	private void SetupPeoples()
	{
		Assets.RemovePeoples();
		Villages.Clear();
		Buildings.Clear();
		_names.Clear();
		_languages.Clear();
		_buildingAt = new int[World.Width * World.Height];
		Array.Fill(_buildingAt, -1);
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
			LogEvent($"the {race.Name} found the village of {Villages[v].Name}.");
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

	private int FoundVillage(int species, int x, int y)
	{
		var v = new Village
		{
			Name = _languages[species].PlaceName(), Species = species, X = x, Y = y,
			Food = 30f, Wood = 12f, Founded = Year(),
		};
		Villages.Add(v);
		int id = Villages.Count - 1;
		AddBuilding(BuildingKind.Bonfire, x, y, id);
		return id;
	}

	private int AddBuilding(BuildingKind kind, int x, int y, int village)
	{
		Buildings.Add(new Building { Kind = kind, X = x, Y = y, Village = village, Progress = kind == BuildingKind.Site ? 0f : 1f });
		int b = Buildings.Count - 1;
		_buildingAt[World.Index(x, y)] = b;
		// No trees where people build.
		for (int p = _tileFirst[World.Index(x, y)]; p >= 0; p = _pNext[p])
			RemovePlant(p);
		return b;
	}

	private int SpawnPerson(int species, int village, float x, float y, bool newborn, bool female)
	{
		int i = SpawnUnit(species, x, y, newborn);
		Units.Village[i] = village;
		Units.Female[i] = female;
		Units.Name[i] = _names.Count;
		_names.Add(_languages[species].PersonName());
		int traits = 0;
		for (int k = 0; k < 2; k++)
			traits |= 1 << _rng.Next(6);
		Units.Traits[i] = traits;
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
		int v = Units.Village[i];
		if (v >= 0)
		{
			Villages[v].Population--;
			if (Units.Role[i] == (byte)Role.Chief)
				LogEvent($"{NameOf(i)}, chief of {Villages[v].Name}, has died.");
		}
	}

	public string NameOf(int i) => Units.Name[i] >= 0 ? _names[Units.Name[i]] : Assets.Species[Units.Species[i]].Name;

	// ------------------------------------------------------------------ villages (every 2 s)

	private void VillageStep(int a, int b, float dt)
	{
		if (Villages.Count == 0)
			return;
		var members = new List<int>[Villages.Count];
		for (int v = 0; v < Villages.Count; v++)
			members[v] = new List<int>();
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Village[i] >= 0)
				members[Units.Village[i]].Add(i);
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive)
				continue;
			var people = members[v];
			if (people.Count == 0)
			{
				village.Alive = false;
				LogEvent($"{village.Name} is abandoned: no one lives there any more.");
				continue;
			}
			// A new chief when the old one is gone: the eldest adult.
			int chief = -1, eldest = -1;
			foreach (int i in people)
			{
				if (Units.Role[i] == (byte)Role.Chief)
					chief = i;
				if (IsAdult(i) && (eldest < 0 || Units.Age[i] > Units.Age[eldest]))
					eldest = i;
			}
			if (chief < 0 && eldest >= 0)
			{
				Units.Role[eldest] = (byte)Role.Chief;
				LogEvent($"{NameOf(eldest)} becomes chief of {village.Name}.");
			}
			// A new house when people run out of room and there is wood for it.
			int room = CampRoom + HouseRoom * village.Houses;
			if (village.Site < 0 && people.Count + 2 > room && village.Wood >= 5f)
				PlanHouse(v);
			HandOutWork(v, people);
		}
	}

	private void PlanHouse(int v)
	{
		var village = Villages[v];
		for (int tries = 0; tries < 40; tries++)
		{
			int r = 2 + tries / 8;
			int x = village.X + _rng.Next(-r, r + 1), y = village.Y + _rng.Next(-r, r + 1);
			if (!World.IsLand(x, y) || _buildingAt[World.Index(x, y)] >= 0)
				continue;
			// Keep a free tile around every building.
			bool clear = true;
			for (int dy = -1; dy <= 1 && clear; dy++)
				for (int dx = -1; dx <= 1 && clear; dx++)
					clear = !World.InBounds(x + dx, y + dy) || _buildingAt[World.Index(x + dx, y + dy)] < 0;
			if (!clear)
				continue;
			village.Site = AddBuilding(BuildingKind.Site, x, y, v);
			return;
		}
	}

	/// <summary>Work by what the village lacks: builders for a house being built, hunters and
	/// gatherers when food runs short, woodcutters when wood does. Chiefs and shamans and the young
	/// don't take jobs.</summary>
	private void HandOutWork(int v, List<int> people)
	{
		var village = Villages[v];
		var workers = new List<int>();
		foreach (int i in people)
			if (IsAdult(i) && Units.Role[i] != (byte)Role.Chief && Units.Role[i] != (byte)Role.Shaman)
				workers.Add(i);
			else
				Units.Job[i] = (byte)Job.None;
		if (workers.Count == 0)
			return;
		int n = workers.Count;
		int builders = village.Site >= 0 ? Math.Min(2, n) : 0;
		bool hungry = village.Food < people.Count * 3f;
		int hunters = Math.Min(n - builders, hungry ? Math.Max(1, n / 3) : n / 8);
		int woodcutters = Math.Min(n - builders - hunters, village.Wood < 30f ? Math.Max(1, n / 4) : n / 10);
		int[] want = new int[5];
		want[(int)Job.Builder] = builders;
		want[(int)Job.Hunter] = hunters;
		want[(int)Job.Woodcutter] = woodcutters;
		want[(int)Job.Gatherer] = n - builders - hunters - woodcutters;
		// Keep people at the job they have when it is still wanted; move the others.
		int[] have = new int[5];
		var free = new List<int>();
		foreach (int i in workers)
		{
			int j = Units.Job[i];
			// Warriors prefer the hunt.
			if (j != 0 && have[j] < want[j])
				have[j]++;
			else
				free.Add(i);
		}
		foreach (int i in free)
		{
			int best = (int)Job.Gatherer;
			if (Units.Role[i] == (byte)Role.Warrior && have[(int)Job.Hunter] < want[(int)Job.Hunter])
				best = (int)Job.Hunter;
			else
				for (int j = 1; j < 5; j++)
					if (have[j] < want[j])
					{
						best = j;
						break;
					}
			if (Units.Job[i] != best)
			{
				Units.Job[i] = (byte)best;
				Units.WorkTarget[i] = -1;
			}
			have[best]++;
		}
	}

	// ------------------------------------------------------------------ people (1 / s)

	/// <summary>A person's decision, once a second: each enabled neuron whose cooldown is over is
	/// scored (weight x urgency); the best fires. Arriving somewhere finishes the task first.</summary>
	private void ThinkPerson(int i, SpeciesRecord sp, float dt)
	{
		EnsureNeurons();
		int v = Units.Village[i];
		float now0 = (float)Scheduler.Time;
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
		// Thirst and hunger that become urgent interrupt any task (a hunt, a walk to work).
		bool urgent = Units.Thirst[i] > 0.75f || (Units.Hunger[i] > 0.75f && v >= 0 && Villages[v].Food >= 1f);
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
				if (NearWater(i)) Units.Thirst[i] = 0f; else GoToWater(i);
				break;
			case NEat:
				if (v >= 0 && Villages[v].Food >= 1f)
					GoTo(i, Villages[v].X + 0.5f, Villages[v].Y + 0.9f, Task.Feast);
				else if (!SeekGrass(i, sp))
					WanderNear(i, v, 6f);
				break;
			case NRest:
				if (v >= 0)
					GoTo(i, Villages[v].X + 0.5f + (float)_rng.NextDouble() - 0.5f, Villages[v].Y + 1.2f, Task.Home);
				else
					RestHere(i);
				break;
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
				if (NearWater(i))
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
				{
					if (Units.Carry[i] == (byte)Goods.Food) Villages[v].Food += Units.CarryAmount[i];
					else if (Units.Carry[i] == (byte)Goods.Wood) Villages[v].Wood += Units.CarryAmount[i];
				}
				Units.Carry[i] = 0;
				Units.CarryAmount[i] = 0f;
				Units.Task[i] = (byte)Task.Wander;
				return false;
			case Task.Work:
				return DoWork(i, v, dt);
		}
		return false;
	}

	private void Work(int i, int v, SpeciesRecord sp)
	{
		var village = Villages[v];
		if (Units.Carry[i] != 0)
		{
			GoTo(i, village.X + 0.5f, village.Y + 0.9f, Task.Deliver);
			return;
		}
		switch ((Job)Units.Job[i])
		{
			case Job.Gatherer:
			{
				// The best grass (wild grains, berries, herbs) near the village.
				float best = 0.45f;
				int bt = -1;
				// Further afield when the stores run low.
				int r = village.Food < village.Population * 2f ? 18 : 12;
				for (int k = 0; k < 12; k++)
				{
					int x = village.X + _rng.Next(-r, r + 1), y = village.Y + _rng.Next(-r, r + 1);
					if (!World.IsLand(x, y))
						continue;
					int t = World.Index(x, y);
					if (Grass[t] > best && _buildingAt[t] < 0)
					{
						best = Grass[t];
						bt = t;
					}
				}
				if (bt >= 0)
				{
					Units.WorkTarget[i] = bt;
					Units.WorkTimer[i] = 2f;
					GoTo(i, bt % World.Width + 0.5f, bt / World.Width + 0.6f, Task.Work);
				}
				else
					WanderNear(i, v, 8f);
				break;
			}
			case Job.Woodcutter:
			{
				int tree = FindTree(village.X, village.Y, 12);
				if (tree < 0)
					tree = FindTree(village.X, village.Y, 22);
				if (tree >= 0)
				{
					Units.WorkTarget[i] = tree;
					Units.WorkTimer[i] = 3f;
					GoTo(i, _pX[tree] - 0.4f, _pY[tree], Task.Work);
				}
				else
					WanderNear(i, v, 10f);
				break;
			}
			case Job.Hunter:
				if (!TryHunt(i, sp))
					WanderNear(i, v, 12f);
				break;
			case Job.Builder:
				if (village.Site >= 0 && village.Wood >= 0.5f)
				{
					var site = Buildings[village.Site];
					Units.WorkTarget[i] = village.Site;
					Units.WorkTimer[i] = 1f;
					GoTo(i, site.X + 0.5f + ((float)_rng.NextDouble() - 0.5f), site.Y + 1.1f, Task.Work);
				}
				else
					WanderNear(i, v, 4f);
				break;
		}
	}

	/// <summary>A tree near (x, y), or -1 (a few random looks).</summary>
	private int FindTree(int cx, int cy, int r)
	{
		for (int k = 0; k < 40; k++)
		{
			int x = cx + _rng.Next(-r, r + 1), y = cy + _rng.Next(-r, r + 1);
			if (!World.InBounds(x, y))
				continue;
			for (int p = _tileFirst[World.Index(x, y)]; p >= 0; p = _pNext[p])
				if (_pBurn[p] == 0f && _pGrowth[p] >= 1f && _plantSprites[_pSprite[p]].StartsWith("trees/"))
					return p;
		}
		return -1;
	}

	/// <summary>Working at the spot: harvesting, chopping or building, a second at a time.</summary>
	private bool DoWork(int i, int v, float dt)
	{
		Units.WorkTimer[i] -= dt;
		int target = Units.WorkTarget[i];
		switch ((Job)Units.Job[i])
		{
			case Job.Gatherer:
				if (Units.WorkTimer[i] > 0f)
					return true;
				if (target >= 0 && Grass[target] > 0.2f)
				{
					Grass[target] -= 0.35f;
					Units.Carry[i] = (byte)Goods.Food;
					Units.CarryAmount[i] = 3f;
				}
				break;
			case Job.Woodcutter:
				if (target < 0 || !_pAlive[target])
					break;
				if (Units.WorkTimer[i] > 0f)
					return true;
				RemovePlant(target);
				Units.Carry[i] = (byte)Goods.Wood;
				Units.CarryAmount[i] = 3f;
				break;
			case Job.Builder:
			{
				if (v < 0 || target < 0 || target != Villages[v].Site || Villages[v].Wood < 0.5f)
					break;
				var site = Buildings[target];
				Villages[v].Wood -= 0.5f;
				site.Progress += 0.1f;
				if (site.Progress < 1f)
					return true;
				site.Kind = BuildingKind.House;
				Villages[v].Houses++;
				Villages[v].Site = -1;
				break;
			}
		}
		Units.Task[i] = (byte)Task.Wander;
		Units.WorkTarget[i] = -1;
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
		int room = CampRoom + HouseRoom * village.Houses;
		return village.Population < room && village.Food >= 4f && Units.Hunger[i] < 0.5f;
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
		float wait = YearSeconds * (0.7f + 0.6f * (float)_rng.NextDouble());
		Units.BreedWait[i] = wait;
		Units.BreedWait[p] = wait;
		Births++;
		PeopleBirths++;
	}

	private void Pair(int i)
	{
		_found.Clear();
		Zones.Query(Units, Units.X[i], Units.Y[i], 12f, _found);
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

	/// <summary>Villages for the HUD: name, people, population, food, wood, houses.</summary>
	public Godot.Collections.Array VillageTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var v in Villages)
			if (v.Alive)
				list.Add(new Godot.Collections.Dictionary
				{
					["name"] = v.Name, ["people"] = Assets.Species[v.Species].Name, ["population"] = v.Population,
					["food"] = (int)v.Food, ["wood"] = (int)v.Wood, ["houses"] = v.Houses, ["x"] = v.X, ["y"] = v.Y,
					["site"] = v.Site >= 0 ? Buildings[v.Site].Progress : -1f, ["jobs"] = JobCounts(v),
				});
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
