using System;
using System.Collections.Generic;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Animal life (0.2): needs (hunger, thirst, rest), grazing, hunting, breeding, ageing and death,
/// migration in winter, births over time by biome and extinctions.
///
/// Every unit thinks once a second (spread over 10 batches): its needs rise, it picks a task by
/// urgency (drink, eat, rest, breed, wander) and walks to it. Walking and the chase run every step.
/// </summary>
public partial class Simulation
{
	/// <summary>What a unit is doing.</summary>
	public enum Task : byte { Wander, Graze, Drink, Hunt, Rest, Work, Deliver, Feast, Home }

	/// <summary>Why a unit died (for statistics and the event log).</summary>
	public enum Death { OldAge, Hunger, Thirst, Eaten, Fire, Other, War }

	/// <summary>Seconds for hunger to go from full to starving (thirst: ThirstSeconds).</summary>
	public const float HungerSeconds = 50f;
	public const float ThirstSeconds = 70f;
	/// <summary>Seconds of moving before a unit is exhausted.</summary>
	public const float EnergySeconds = 120f;
	/// <summary>Seconds a unit survives once starving or parched.</summary>
	public const float SufferingLimit = 25f;
	/// <summary>A newborn is an adult at this share of its lifespan.</summary>
	public const float Maturity = 0.15f;
	/// <summary>No more births when this many of the same species stand within 5 tiles.</summary>
	public const int Crowded = 6;

	/// <summary>World laws (docs/WORLDBOX_WIKI_LESSONS.md): switches for each rule of nature.</summary>
	public readonly Dictionary<string, bool> Laws = new()
	{
		["animal_spawn"] = true,  // natural animals are born over time in their biomes
		["hunger"] = true,        // creatures need food and water
		["old_age"] = true,       // creatures die of old age
		["natural_disasters"] = true,  // lightning sets forests on fire
		["trees_growth"] = true,  // plants grow and spread
	};

	/// <summary>Living units per species.</summary>
	public int[] Population = Array.Empty<int>();
	/// <summary>How many of a species its habitat can feed: births slow down as the population
	/// nears it and stop there. Bigger creatures need more room.</summary>
	public int[] Capacity = Array.Empty<int>();
	/// <summary>Creatures per land tile of habitat, for a creature of size 1.</summary>
	public const float HabitatDensity = 0.06f;
	// Species that have had a real population since their last extinction (so a lone newcomer
	// dying out does not make the news).
	private bool[] _established = Array.Empty<bool>();
	/// <summary>Deaths by cause since the world started.</summary>
	public readonly int[] Deaths = new int[Enum.GetValues<Death>().Length];
	/// <summary>Deaths of people (not animals) by cause, and their births.</summary>
	public readonly int[] PeopleDeaths = new int[Enum.GetValues<Death>().Length];
	public int PeopleBirths;
	public int Births;

	// Per biome: species born there and cumulative weights, and the land tiles where something
	// is born (built at Start).
	private List<(int species, float upTo)>[] _spawnTables = Array.Empty<List<(int, float)>>();
	private float[] _spawnTotals = Array.Empty<float>();
	private readonly List<int> _spawnTiles = new();
	// For each land tile, the nearest water tile within reach, or -1.
	private int[] _nearestWater = Array.Empty<int>();
	private readonly List<int> _found = new();

	public void SetLaw(string name, bool on) => Laws[name] = on;
	public bool Law(string name) => Laws.TryGetValue(name, out bool on) && on;

	private void SetupLife()
	{
		Population = new int[Assets.Species.Count];
		Array.Clear(Deaths);
		Array.Clear(PeopleDeaths);
		PeopleBirths = 0;
		Births = 0;
		_remains.Clear();
		_spawnTables = new List<(int, float)>[_biomeNames.Length];
		_spawnTotals = new float[_biomeNames.Length];
		for (int s = 0; s < Assets.Species.Count; s++)
			foreach (var (name, weight) in Assets.Species[s].Natural)
			{
				int b = Array.IndexOf(_biomeNames, name);
				if (b < 0 || weight <= 0f)
					continue;
				_spawnTables[b] ??= new();
				_spawnTotals[b] += weight;
				_spawnTables[b].Add((s, _spawnTotals[b]));
			}
		_spawnTiles.Clear();
		var habitat = new int[Assets.Species.Count];
		for (int i = 0; i < World.Biome.Length; i++)
		{
			if (World.Water[i] != SimWorld.WaterLand || _spawnTables[World.Biome[i]] == null)
				continue;
			_spawnTiles.Add(i);
			foreach (var (s, _) in _spawnTables[World.Biome[i]])
				habitat[s]++;
		}
		Capacity = new int[Assets.Species.Count];
		_established = new bool[Assets.Species.Count];
		for (int s = 0; s < Assets.Species.Count; s++)
			Capacity[s] = Assets.Species[s].IsNatural
				? Math.Max(8, (int)(habitat[s] * HabitatDensity / Math.Max(1, Assets.Species[s].Size)))
				: int.MaxValue;
		_nearestWater = World.NearestWater(24);
	}

	/// <summary>A species born on tile `t` by its biome's weights, or -1.</summary>
	private int PickNatural(int t)
	{
		var table = _spawnTables[World.Biome[t]];
		if (table == null)
			return -1;
		float r = (float)_rng.NextDouble() * _spawnTotals[World.Biome[t]];
		foreach (var (species, upTo) in table)
			if (r < upTo)
				return species;
		return table[^1].species;
	}

	/// <summary>Spawns a unit; adults get a random age so they don't all die together.</summary>
	private int SpawnUnit(int species, float x, float y, bool newborn)
	{
		int i = Units.Spawn(species, x, y);
		var sp = Assets.Species[species];
		Units.Age[i] = newborn ? 0f : AdultAge(sp) + sp.Lifespan * (float)_rng.NextDouble() * 0.5f;
		Units.Hunger[i] = newborn ? 0f : (float)_rng.NextDouble() * 0.3f;
		Units.Thirst[i] = newborn ? 0f : (float)_rng.NextDouble() * 0.3f;
		Units.BreedWait[i] = YearSeconds * (0.2f + (float)_rng.NextDouble() * 0.5f);
		Population[species]++;
		if (Population[species] >= 5)
			_established[species] = true;
		return i;
	}

	/// <summary>Remains of a creature: drawn lying where it died for a few seconds.</summary>
	private struct Remains
	{
		public float x, y, scale, time;
		public int species;
		public bool left;
	}

	private readonly List<Remains> _remains = new();
	/// <summary>Seconds the remains of a dead creature stay on the ground.</summary>
	public const float RemainsSeconds = 5f;

	private void KillUnit(int i, Death cause)
	{
		if (!Units.Alive[i])
			return;
		int s = Units.Species[i];
		if (Assets.Species[s].IsPeople)
		{
			PersonDied(i);
			PeopleDeaths[(int)cause]++;
		}
		// The eaten leave nothing; the others lie where they fell for a while.
		if (cause != Death.Eaten && _remains.Count < 4000)
		{
			var sp = Assets.Species[s];
			_remains.Add(new Remains
			{
				x = Units.X[i], y = Units.Y[i], species = s, left = Units.FacingLeft[i], time = RemainsSeconds,
				scale = 0.6f + 0.4f * Math.Clamp(Units.Age[i] / AdultAge(sp), 0f, 1f),
			});
		}
		Units.Kill(i);
		Deaths[(int)cause]++;
		Population[s]--;
		if (Population[s] == 0 && _established[s])
		{
			_established[s] = false;
			LogEvent($"The last {Assets.Species[s].Name.ToLower()} has died: the species is extinct.");
		}
	}

	public bool IsAdult(int i) => Units.Age[i] >= AdultAge(Assets.Species[Units.Species[i]]);

	/// <summary>Age (years) at which a creature is grown: a share of its lifespan, but never more
	/// than 4 years for peoples: a village's children grow up to work within a few minutes, as in WorldBox.</summary>
	public static float AdultAge(SpeciesRecord sp) => sp.IsPeople ? Math.Min(sp.Lifespan * Maturity, 4f) : sp.Lifespan * Maturity;

	// ------------------------------------------------------------------ thinking (1 / s)

	private void Think(int a, int b, float dt)
	{
		bool hunger = Law("hunger");
		bool oldAge = Law("old_age");
		float cold = Coldness();
		for (int i = a; i < b; i++)
		{
			if (!Units.Alive[i])
				continue;
			var sp = Assets.Species[Units.Species[i]];
			Units.Age[i] += dt / YearSeconds;
			if (oldAge && sp.Lifespan < 500f && Units.Age[i] > sp.Lifespan * (0.85f + 0.3f * Hash01(i)))
			{
				KillUnit(i, Death.OldAge);
				continue;
			}
			Units.BreedWait[i] -= dt;
			bool moving = !AtTarget(i);
			Units.Energy[i] = Math.Clamp(Units.Energy[i] + (moving ? -dt / EnergySeconds : dt / EnergySeconds), 0f, 1f);

			if (hunger && sp.Eats)
			{
				// People live off their village's stores: they get hungry more slowly than animals.
				Units.Hunger[i] = Math.Min(1f, Units.Hunger[i] + dt / (sp.IsPeople ? HungerSeconds * 1.6f : HungerSeconds));
				Units.Thirst[i] = Math.Min(1f, Units.Thirst[i] + dt / ThirstSeconds);
				if (Units.Hunger[i] >= 1f || Units.Thirst[i] >= 1f)
				{
					Units.Suffering[i] += dt;
					if (Units.Suffering[i] > SufferingLimit)
					{
						KillUnit(i, Units.Thirst[i] >= 1f ? Death.Thirst : Death.Hunger);
						continue;
					}
				}
				else
					Units.Suffering[i] = 0f;
			}
			if (sp.IsPeople)
			{
				// Wounds heal slowly.
				Units.Health[i] = Math.Min(MaxHealth(i), Units.Health[i] + 3f * dt);
				ThinkPerson(i, sp, dt);
				continue;
			}

			var task = (Task)Units.Task[i];
			if (task == Task.Hunt && Units.Prey[i] >= 0)
				continue;  // the chase is run every step (Move)
			if (task == Task.Rest)
			{
				Units.Wait[i] -= dt;
				if (Units.Wait[i] > 0f)
					continue;
				Units.Energy[i] = 1f;
				Units.Task[i] = (byte)Task.Wander;
			}

			// Arrived somewhere: act on it.
			if (!moving)
			{
				if (task == Task.Drink && NearWater(i))
					Units.Thirst[i] = 0f;
				else if (task == Task.Graze && sp.Grazes)
					Graze(i);
			}

			// Pick what to do, most urgent first.
			if (hunger && sp.Eats && Units.Thirst[i] > 0.6f && Units.Thirst[i] >= Units.Hunger[i])
			{
				if (NearWater(i))
					Units.Thirst[i] = 0f;
				else
					GoToWater(i);
				continue;
			}
			if (hunger && sp.Eats && Units.Hunger[i] > 0.5f)
			{
				if (sp.Hunts && TryHunt(i, sp))
					continue;
				if (sp.Grazes && SeekGrass(i, sp))
					continue;
			}
			if (Units.Energy[i] < 0.15f)
			{
				Units.Task[i] = (byte)Task.Rest;
				Units.TargetX[i] = Units.X[i];
				Units.TargetY[i] = Units.Y[i];
				Units.Wait[i] = 4f;
				continue;
			}
			if (sp.Litter > 0 && Units.BreedWait[i] <= 0f && IsAdult(i) && Units.Hunger[i] < 0.4f && Units.Thirst[i] < 0.5f)
				TryBreed(i, sp);
			if (moving)
				continue;
			Units.Wait[i] -= dt;
			if (Units.Wait[i] > 0f)
				continue;
			WanderTo(i, sp, cold);
		}
	}

	private bool AtTarget(int i) =>
		MathF.Abs(Units.TargetX[i] - Units.X[i]) + MathF.Abs(Units.TargetY[i] - Units.Y[i]) < 0.01f;

	private static float Hash01(int i) => (float)((uint)(i * 2654435761u) % 1000u) / 1000f;

	private void WanderTo(int i, SpeciesRecord sp, float cold)
	{
		Units.Task[i] = (byte)Task.Wander;
		float roam = sp.Roam;
		// Migration: in winter, cold-latitude migrants head for the equator.
		float bias = 0f;
		if (sp.Migrates && cold > 0.3f)
		{
			float lat = (Units.Y[i] / World.Height - 0.5f) * 2f;
			if (MathF.Abs(lat) > 0.35f)
				bias = -MathF.Sign(lat) * roam * 0.9f;
		}
		for (int tries = 0; tries < 4; tries++)
		{
			float tx = Units.X[i] + ((float)_rng.NextDouble() * 2f - 1f) * roam;
			float ty = Units.Y[i] + ((float)_rng.NextDouble() * 2f - 1f) * roam + bias;
			if (World.IsLandAt(tx, ty) && !OnFire(tx, ty))
			{
				Units.TargetX[i] = tx;
				Units.TargetY[i] = ty;
				break;
			}
		}
		Units.Wait[i] = 1f + (float)_rng.NextDouble() * 4f;
	}

	// ------------------------------------------------------------------ water

	private bool NearWater(int i)
	{
		int x = (int)Units.X[i], y = (int)Units.Y[i];
		for (int dy = -1; dy <= 1; dy++)
			for (int dx = -1; dx <= 1; dx++)
				if (World.InBounds(x + dx, y + dy) && World.Water[World.Index(x + dx, y + dy)] != SimWorld.WaterLand)
					return true;
		return false;
	}

	private void GoToWater(int i)
	{
		int t = World.Index((int)Units.X[i], (int)Units.Y[i]);
		int w = _nearestWater[t];
		Units.Task[i] = (byte)Task.Drink;
		if (w < 0)
		{
			WanderTo(i, Assets.Species[Units.Species[i]], 0f);
			Units.Task[i] = (byte)Task.Drink;
			return;
		}
		// Walk towards the water; the walk stops on the shore (water is never entered).
		Units.TargetX[i] = w % World.Width + 0.5f;
		Units.TargetY[i] = w / World.Width + 0.5f;
	}

	// ------------------------------------------------------------------ grazing

	private void Graze(int i)
	{
		int t = World.Index((int)Units.X[i], (int)Units.Y[i]);
		float bite = Math.Min(Grass[t], 0.3f);
		if (bite < 0.05f)
			return;
		Grass[t] -= bite;
		Units.Hunger[i] = Math.Max(0f, Units.Hunger[i] - bite * 2.5f);
	}

	/// <summary>Walks to the best grass nearby (a few random looks). True when it found some.</summary>
	private bool SeekGrass(int i, SpeciesRecord sp)
	{
		int here = World.Index((int)Units.X[i], (int)Units.Y[i]);
		if (Grass[here] > 0.2f)
		{
			Units.Task[i] = (byte)Task.Graze;
			Graze(i);
			return true;
		}
		float best = 0.2f;
		float bx = 0, by = 0;
		float r = Math.Max(sp.Roam, 6f);
		for (int k = 0; k < 8; k++)
		{
			float tx = Units.X[i] + ((float)_rng.NextDouble() * 2f - 1f) * r;
			float ty = Units.Y[i] + ((float)_rng.NextDouble() * 2f - 1f) * r;
			if (!World.IsLandAt(tx, ty))
				continue;
			float g = Grass[World.Index((int)tx, (int)ty)];
			if (g > best)
			{
				best = g;
				bx = tx;
				by = ty;
			}
		}
		if (best <= 0.2f)
			return false;
		Units.Task[i] = (byte)Task.Graze;
		Units.TargetX[i] = bx;
		Units.TargetY[i] = by;
		return true;
	}

	// ------------------------------------------------------------------ hunting

	/// <summary>Picks the nearest catchable prey within sight. True when the hunt starts.</summary>
	private bool TryHunt(int i, SpeciesRecord sp)
	{
		_found.Clear();
		Zones.Query(Units, Units.X[i], Units.Y[i], 10f, _found);
		int best = -1;
		float bestD = float.MaxValue;
		foreach (int j in _found)
		{
			if (j == i || !Units.Alive[j] || Units.Species[j] == Units.Species[i])
				continue;
			var prey = Assets.Species[Units.Species[j]];
			// Only living flesh of its size or smaller; never undead or golems. People hunt animals,
			// never other people (war comes with kingdoms).
			if (prey.Size > sp.Size + (sp.IsPeople ? 2 : 0) || !prey.Eats || (sp.IsPeople && prey.IsPeople))
				continue;
			float dx = Units.X[j] - Units.X[i], dy = Units.Y[j] - Units.Y[i];
			float d = dx * dx + dy * dy;
			if (d < bestD)
			{
				bestD = d;
				best = j;
			}
		}
		if (best < 0)
			return false;
		Units.Task[i] = (byte)Task.Hunt;
		Units.Prey[i] = best;
		return true;
	}

	/// <summary>Every step: hunters chase their prey and catch it when close.</summary>
	private void Chase(int i, float dt)
	{
		int j = Units.Prey[i];
		if (j < 0 || !Units.Alive[j])
		{
			Units.Prey[i] = -1;
			Units.Task[i] = (byte)Task.Wander;
			return;
		}
		float dx = Units.X[j] - Units.X[i], dy = Units.Y[j] - Units.Y[i];
		float d2 = dx * dx + dy * dy;
		if (d2 > 20f * 20f)
		{
			Units.Prey[i] = -1;
			Units.Task[i] = (byte)Task.Wander;
			return;
		}
		// People of kingdoms at war: blows exchanged, not a hunt.
		if (d2 < 0.6f * 0.6f && Assets.Species[Units.Species[i]].IsPeople && Assets.Species[Units.Species[j]].IsPeople)
		{
			Units.TargetX[i] = Units.X[i];
			Units.TargetY[i] = Units.Y[i];
			Fight(i, j, dt);
			return;
		}
		if (d2 < 0.35f * 0.35f)
		{
			var hunter = Assets.Species[Units.Species[i]];
			// People fight back: warriors and the brave often win, and the beast dies instead.
			if (Assets.Species[Units.Species[j]].IsPeople)
			{
				if (_rng.NextDouble() < DefendChance(j))
				{
					KillUnit(i, Death.Other);
					return;
				}
			}
			KillUnit(j, Death.Eaten);
			Units.Prey[i] = -1;
			if (hunter.IsPeople)
			{
				// The hunter brings the meat home.
				Units.Carry[i] = (byte)Goods.Food;
				Units.CarryAmount[i] = 6f;
				Units.Task[i] = (byte)Task.Wander;
				Units.TargetX[i] = Units.X[i];
				Units.TargetY[i] = Units.Y[i];
				return;
			}
			Units.Hunger[i] = 0f;
			Units.Suffering[i] = 0f;
			Units.Prey[i] = -1;
			Units.Task[i] = (byte)Task.Wander;
			Units.TargetX[i] = Units.X[i];
			Units.TargetY[i] = Units.Y[i];
			return;
		}
		Units.TargetX[i] = Units.X[j];
		Units.TargetY[i] = Units.Y[j];
	}

	// ------------------------------------------------------------------ breeding

	private void TryBreed(int i, SpeciesRecord sp)
	{
		_found.Clear();
		Zones.Query(Units, Units.X[i], Units.Y[i], 5f, _found);
		int kin = 0, mate = -1;
		foreach (int j in _found)
		{
			if (j == i || Units.Species[j] != Units.Species[i])
				continue;
			kin++;
			if (mate < 0 && IsAdult(j) && Units.BreedWait[j] <= 0f)
				mate = j;
		}
		int s = Units.Species[i];
		// Births slow down as the species fills its habitat, and stop when it is full.
		if (mate < 0 || kin >= Crowded || _rng.NextDouble() < (double)Population[s] / Capacity[s])
			return;
		int litter = 1 + _rng.Next(sp.Litter);
		for (int k = 0; k < litter; k++)
		{
			float x = Units.X[i] + ((float)_rng.NextDouble() - 0.5f);
			float y = Units.Y[i] + ((float)_rng.NextDouble() - 0.5f);
			if (World.IsLandAt(x, y))
			{
				SpawnUnit(s, x, y, true);
				Births++;
			}
		}
		float wait = YearSeconds * (0.6f + 0.4f * (float)_rng.NextDouble());
		Units.BreedWait[i] = wait;
		Units.BreedWait[mate] = wait;
	}

	// ------------------------------------------------------------------ births over time

	/// <summary>World law "animal spawn": now and then, a natural creature is born on a quiet tile.</summary>
	private void SpawnOverTime(int a, int b, float dt)
	{
		// Remains fade away.
		for (int r = _remains.Count - 1; r >= 0; r--)
		{
			var rem = _remains[r];
			rem.time -= dt;
			if (rem.time <= 0f)
				_remains.RemoveAt(r);
			else
				_remains[r] = rem;
		}
		if (!Law("animal_spawn") || _spawnTiles.Count == 0)
			return;
		for (int k = 0; k < 3; k++)
		{
			int t = _spawnTiles[_rng.Next(_spawnTiles.Count)];
			if (Scorch[t] > 0)
				continue;
			int x = t % World.Width, y = t / World.Width;
			if (CountNearNoRebuild(x + 0.5f, y + 0.5f, 8f) > 2)
				continue;
			int s = PickNatural(t);
			// Nature only brings back what is scarce.
			if (s >= 0 && Population[s] < Capacity[s] / 2)
				SpawnUnit(s, x + (float)_rng.NextDouble(), y + (float)_rng.NextDouble(), false);
		}
	}

	private int CountNearNoRebuild(float x, float y, float r)
	{
		_found.Clear();
		Zones.Query(Units, x, y, r, _found);
		return _found.Count;
	}
}
