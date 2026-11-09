using System;
using System.Collections.Generic;
using System.Diagnostics;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// The simulation core: the world object holding the tile grid, one manager per kind of entity
/// (units and plants for now; kingdoms, cities, cultures come later), zones for spatial queries,
/// and the scheduler that runs systems at their own rates, in batches.
///
/// The rest of the class is split by topic: Life.cs (animals), Nature.cs (seasons, grass, plants,
/// fire) and Draw.cs (drawing units, plants and flames).
///
/// GDScript drives it through the public methods (scripts/main.gd).
/// </summary>
public partial class Simulation : Node2D
{
	/// <summary>World pixels per tile (scripts/render2d/world_map.gd TILE).</summary>
	public const int Tile = 8;

	public SimWorld World { get; private set; }
	public readonly UnitManager Units = new();
	public ZoneGrid Zones { get; private set; }
	public readonly Scheduler Scheduler = new();
	public AssetLibrary Assets { get; private set; }

	private Random _rng = new(1);
	private string[] _biomeNames = Array.Empty<string>();
	private readonly Dictionary<string, int> _processRows = new();
	private double _stepMs;
	private int _stepSamples;
	private float _accumulate;

	public override void _Ready()
	{
		Assets ??= AssetLibrary.Load();
		if (!_renderingReady)
			SetupRendering();
	}

	/// <summary>Starts over on a new world. `worldData` is a GDScript WorldData, `biomeNames`
	/// is Biomes.NAMES (biome ids are indices into it). Plants come next, with LoadPlants.</summary>
	public void Start(GodotObject worldData, string[] biomeNames)
	{
		Assets ??= AssetLibrary.Load();
		if (!_renderingReady)
			SetupRendering();
		World = SimWorld.FromWorldData(worldData);
		_biomeNames = biomeNames;
		_rng = new Random(worldData.Get("seed_value").AsInt32());
		Units.Clear();
		Zones = new ZoneGrid(World.Width, World.Height);
		Scheduler.UnitSystems.Clear();
		Scheduler.WorldProcesses.Clear();
		Scheduler.Time = 0;
		_processRows.Clear();
		SetupPeoples();
		SetupLife();
		SetupNature();
		ClearDrawing();

		// Walking and chasing: every step, every unit.
		Scheduler.UnitSystems.Add(new Scheduler.UnitSystem { Name = "move", Interval = Scheduler.Step, Batches = 1, Run = Move });
		// Needs and decisions: each unit once a second, spread over 10 batches.
		Scheduler.UnitSystems.Add(new Scheduler.UnitSystem { Name = "think", Interval = 1f, Batches = 10, Run = Think });
		// Zones: rebuilt 4 times a second.
		Scheduler.UnitSystems.Add(new Scheduler.UnitSystem { Name = "zones", Global = true, Interval = 0.25f, Batches = 1, Run = (_, _, _) => Zones.Rebuild(Units) });
		// Fire: every step. Births over time: twice a second.
		Scheduler.UnitSystems.Add(new Scheduler.UnitSystem { Name = "fire", Global = true, Interval = Scheduler.Step, Batches = 1, Run = (_, _, dt) => FireStep(0, 0, dt) });
		Scheduler.UnitSystems.Add(new Scheduler.UnitSystem { Name = "spawn", Global = true, Interval = 0.5f, Batches = 1, Run = (_, _, dt) => SpawnOverTime(0, 0, dt) });
		// Villages hand out work and plan houses every two seconds.
		Scheduler.UnitSystems.Add(new Scheduler.UnitSystem { Name = "villages", Global = true, Interval = 2f, Batches = 1, Run = VillageStep });
		// Nature (grass, ash, plants): one slice of the map at a time.
		Scheduler.WorldProcesses.Add(new Scheduler.WorldProcess { Name = "nature", Interval = NatureInterval, Slices = NatureSlices, Run = NatureSlice });
	}

	// ------------------------------------------------------------------ spawning

	/// <summary>Spawns `count` creatures of one species, as a god power: on random tiles of the
	/// biomes it lives in, or anywhere on land for a creature that never appears by itself.
	/// Returns how many were placed.</summary>
	public int SpawnSpecies(string id, int count)
	{
		int s = Assets.SpeciesIndex(id);
		if (s < 0 || World == null)
			return 0;
		var allowed = new HashSet<int>();
		foreach (var name in Assets.Species[s].Natural.Keys)
		{
			int b = Array.IndexOf(_biomeNames, name);
			if (b >= 0)
				allowed.Add(b);
		}
		var tiles = new List<int>();
		for (int i = 0; i < World.Biome.Length; i++)
			if (World.Water[i] == SimWorld.WaterLand && (allowed.Count == 0 || allowed.Contains(World.Biome[i])))
				tiles.Add(i);
		if (tiles.Count == 0)
			return 0;
		for (int k = 0; k < count; k++)
		{
			int t = tiles[_rng.Next(tiles.Count)];
			SpawnUnit(s, t % World.Width + (float)_rng.NextDouble(), t / World.Width + (float)_rng.NextDouble(), false);
		}
		Zones.Rebuild(Units);
		return count;
	}

	/// <summary>Spawns `count` creatures the way nature would (WorldBox's "Animal Spawn"): on random
	/// land tiles, each tile's biome picking a species among those born there, by weight. Tiles of
	/// biomes where nothing lives are skipped, and species that never appear by themselves are
	/// never chosen. Returns how many were placed.</summary>
	public int SpawnNatural(int count)
	{
		if (World == null || _spawnTiles.Count == 0)
			return 0;
		for (int k = 0; k < count; k++)
		{
			int t = _spawnTiles[_rng.Next(_spawnTiles.Count)];
			SpawnUnit(PickNatural(t), t % World.Width + (float)_rng.NextDouble(), t / World.Width + (float)_rng.NextDouble(), false);
		}
		Zones.Rebuild(Units);
		return count;
	}

	/// <summary>Spawns one creature of species `id` at (x, y) in tiles (tests, god powers).
	/// Returns its unit index, or -1.</summary>
	public int SpawnAt(string id, float x, float y, bool newborn)
	{
		int s = Assets.SpeciesIndex(id);
		if (s < 0 || !World.IsLandAt(x, y))
			return -1;
		int i = SpawnUnit(s, x, y, newborn);
		Zones.Rebuild(Units);
		return i;
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>How many living units belong to species that never appear by themselves.</summary>
	public int CountUnnatural()
	{
		int n = 0;
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && !Assets.Species[Units.Species[i]].IsNatural && !Assets.Species[Units.Species[i]].IsPeople)
				n++;
		return n;
	}

	/// <summary>How many living units stand on a biome where their species is not born.</summary>
	public int CountOutOfHabitat()
	{
		int n = 0;
		for (int i = 0; i < Units.Capacity; i++)
		{
			if (!Units.Alive[i])
				continue;
			int tile = World.Index((int)Units.X[i], (int)Units.Y[i]);
			if (!Assets.Species[Units.Species[i]].Natural.ContainsKey(_biomeNames[World.Biome[tile]]))
				n++;
		}
		return n;
	}

	public void ClearUnits()
	{
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i])
				Population[Units.Species[i]]--;
		Units.Clear();
		Zones?.Rebuild(Units);
	}

	public int UnitCount() => Units.Count;

	/// <summary>Dead creatures still lying on the ground.</summary>
	public int RemainsCount() => _remains.Count;

	public bool UnitAlive(int i) => i >= 0 && i < Units.Capacity && Units.Alive[i];

	/// <summary>Living units of species `id`.</summary>
	public int PopulationOf(string id)
	{
		int s = Assets.SpeciesIndex(id);
		return s >= 0 ? Population[s] : 0;
	}

	/// <summary>Species names and living counts (HUD).</summary>
	public Godot.Collections.Dictionary PopulationTable()
	{
		var table = new Godot.Collections.Dictionary();
		for (int s = 0; s < Assets.Species.Count; s++)
			if (Population[s] > 0)
				table[Assets.Species[s].Name] = Population[s];
		return table;
	}

	/// <summary>How many of species `id` its habitat can feed.</summary>
	public int CapacityOf(string id)
	{
		int s = Assets.SpeciesIndex(id);
		return s >= 0 ? Capacity[s] : 0;
	}

	/// <summary>Deaths by cause and births since the world started.</summary>
	public Godot.Collections.Dictionary LifeStats()
	{
		var d = new Godot.Collections.Dictionary { ["births"] = Births, ["plants_burned"] = PlantsBurned };
		foreach (Death c in Enum.GetValues<Death>())
		{
			d[c.ToString()] = Deaths[(int)c];
			d["people_" + c.ToString()] = PeopleDeaths[(int)c];
		}
		d["people_births"] = PeopleBirths;
		return d;
	}

	/// <summary>Grass on tile (x, y), 0..1.</summary>
	public float GrassAt(int x, int y) => Grass[World.Index(x, y)];

	public void SetGrass(int x, int y, float value) => Grass[World.Index(x, y)] = value;

	public int ScorchAt(int x, int y) => Scorch[World.Index(x, y)];

	/// <summary>Sets a unit's needs (tests): hunger and thirst, 0..1.</summary>
	public void SetNeeds(int i, float hunger, float thirst)
	{
		Units.Hunger[i] = hunger;
		Units.Thirst[i] = thirst;
	}

	public float UnitHunger(int i) => Units.Hunger[i];

	public float UnitThirst(int i) => Units.Thirst[i];

	public float UnitAge(int i) => Units.Age[i];

	/// <summary>Average milliseconds of one simulation step since the last call.</summary>
	public double TakeStepMs()
	{
		double ms = _stepSamples > 0 ? _stepMs / _stepSamples : 0.0;
		_stepMs = 0;
		_stepSamples = 0;
		return ms;
	}

	/// <summary>Runs `steps` simulation steps right away (tests and tools).</summary>
	public void RunSteps(int steps)
	{
		for (int k = 0; k < steps; k++)
			TimedStep();
	}

	/// <summary>Number of living units within `radius` tiles of (x, y).</summary>
	public int CountNear(float x, float y, float radius)
	{
		Zones.Rebuild(Units);
		var found = new List<int>();
		Zones.Query(Units, x, y, radius, found);
		return found.Count;
	}

	/// <summary>Number of living units standing on water (should stay 0).</summary>
	public int CountOnWater()
	{
		int n = 0;
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && !World.IsLandAt(Units.X[i], Units.Y[i]))
				n++;
		return n;
	}

	/// <summary>Feet position of unit `i`, in tiles.</summary>
	public Vector2 UnitPosition(int i) => new(Units.X[i], Units.Y[i]);

	/// <summary>Adds a world process that only counts the rows it visits (tests and tools).</summary>
	public void AddCountingProcess(string name, float interval, int slices)
	{
		_processRows[name] = 0;
		Scheduler.WorldProcesses.Add(new Scheduler.WorldProcess
		{
			Name = name, Interval = interval, Slices = slices,
			Run = (a, b) => _processRows[name] += b - a,
		});
	}

	public int RowsVisited(string name) => _processRows.TryGetValue(name, out int n) ? n : 0;

	public double SimTime() => Scheduler.Time;

	/// <summary>Speed of time: 0 = paused, 1 = normal, up to MaxTimeScale.</summary>
	public float TimeScale { get; private set; } = 1f;
	public const float MaxTimeScale = 10f;

	/// <summary>Sets the speed of time (0 pauses). The simulation stays the same, only faster:
	/// more fixed steps run per frame.</summary>
	public void SetTimeScale(float scale) => TimeScale = Math.Clamp(scale, 0f, MaxTimeScale);

	public float GetTimeScale() => TimeScale;

	public override void _Process(double delta)
	{
		if (World == null)
			return;
		_accumulate += (float)delta * TimeScale;
		// At most a few frames' worth of steps, so a slow frame never snowballs.
		int maxSteps = Math.Max(5, (int)MathF.Ceiling(TimeScale * 5f));
		int steps = 0;
		while (_accumulate >= Scheduler.Step && steps < maxSteps)
		{
			_accumulate -= Scheduler.Step;
			TimedStep();
			steps++;
		}
		if (steps == maxSteps)
			_accumulate = 0f;
		DrawAll();
	}

	private void TimedStep()
	{
		long t = Stopwatch.GetTimestamp();
		Scheduler.DoStep(Units.Capacity, World.Height);
		_stepMs += Stopwatch.GetElapsedTime(t).TotalMilliseconds;
		_stepSamples++;
	}

	// ------------------------------------------------------------------ walking

	private void Move(int a, int b, float dt)
	{
		for (int i = a; i < b; i++)
		{
			if (!Units.Alive[i])
				continue;
			bool hunting = Units.Task[i] == (byte)Task.Hunt;
			if (hunting)
			{
				Chase(i);
				if (!Units.Alive[i] || Units.Task[i] != (byte)Task.Hunt)
					continue;
			}
			float dx = Units.TargetX[i] - Units.X[i];
			float dy = Units.TargetY[i] - Units.Y[i];
			float d2 = dx * dx + dy * dy;
			if (d2 < 1e-4f)
				continue;
			float d = MathF.Sqrt(d2);
			// Hunters run a little faster than they walk.
			float step = Assets.Species[Units.Species[i]].Speed * dt * (hunting ? 1.25f : 1f);
			float nx = step >= d ? Units.TargetX[i] : Units.X[i] + dx / d * step;
			float ny = step >= d ? Units.TargetY[i] : Units.Y[i] + dy / d * step;
			if (!World.IsLandAt(nx, ny))
			{
				// Water ahead: stop on the shore and think again.
				Units.TargetX[i] = Units.X[i];
				Units.TargetY[i] = Units.Y[i];
				continue;
			}
			Units.X[i] = nx;
			Units.Y[i] = ny;
			if (MathF.Abs(dx) > 0.01f)
				Units.FacingLeft[i] = dx < 0f;
		}
	}
}
