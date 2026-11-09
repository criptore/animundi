using System;
using System.Collections.Generic;
using System.Diagnostics;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// The simulation core: the world object holding the tile grid, one manager per kind of entity
/// (units for now; kingdoms, cities, cultures come later), zones for spatial queries, and the
/// scheduler that runs systems at their own rates, in batches.
///
/// It is also the node that draws the units: every frame their sprites go into one MultiMesh,
/// sorted by feet height, written straight into the MultiMesh buffer (no per-unit node).
///
/// GDScript drives it through the methods below (scripts/main.gd).
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
	private double _drawMs;
	private int _drawSamples;

	// Rendering.
	private MultiMesh _mesh;
	private MultiMesh _shadowMesh;
	private ShaderMaterial _material;
	private float[] _buffer = Array.Empty<float>();
	private float[] _shadowBuffer = Array.Empty<float>();
	private int[] _order = Array.Empty<int>();
	private float[] _keys = Array.Empty<float>();
	// Per species: sprite size in world pixels, atlas rectangle (UV), average colour.
	private Vector2[] _spriteSize = Array.Empty<Vector2>();
	private Rect2[] _spriteRect = Array.Empty<Rect2>();
	private Color[] _spriteColor = Array.Empty<Color>();

	public override void _Ready()
	{
		Assets ??= AssetLibrary.Load();
		if (_mesh == null)
			SetupRendering();
	}

	/// <summary>Starts over on a new world. `worldData` is a GDScript WorldData, `biomeNames`
	/// is Biomes.NAMES (biome ids are indices into it).</summary>
	public void Start(GodotObject worldData, string[] biomeNames)
	{
		Assets ??= AssetLibrary.Load();
		if (_mesh == null)
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

		// Walking: every step, every unit.
		Scheduler.UnitSystems.Add(new Scheduler.UnitSystem { Name = "move", Interval = Scheduler.Step, Batches = 1, Run = Move });
		// Deciding where to go: each unit once a second, spread over 10 batches.
		Scheduler.UnitSystems.Add(new Scheduler.UnitSystem { Name = "wander", Interval = 1f, Batches = 10, Run = Wander });
		// Zones: rebuilt 4 times a second.
		Scheduler.UnitSystems.Add(new Scheduler.UnitSystem { Name = "zones", Interval = 0.25f, Batches = 1, Run = (_, _, _) => Zones.Rebuild(Units) });
	}

	/// <summary>Spawns up to `count` animals of a species on random tiles of its biomes.
	/// Returns how many were placed.</summary>
	public int SpawnSpecies(string id, int count)
	{
		int s = Assets.SpeciesIndex(id);
		if (s < 0 || World == null)
			return 0;
		var allowed = new HashSet<int>();
		foreach (var name in Assets.Species[s].Biomes)
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
			Units.Spawn(s, t % World.Width + (float)_rng.NextDouble(), t / World.Width + (float)_rng.NextDouble());
		}
		Zones.Rebuild(Units);
		return count;
	}

	/// <summary>Spawns `count` animals spread over every species (for tests and the
	/// performance check). Returns how many were placed.</summary>
	public int SpawnMany(int count)
	{
		int placed = 0;
		int per = Math.Max(1, count / Math.Max(Assets.Species.Count, 1));
		foreach (var s in Assets.Species)
		{
			if (placed >= count)
				break;
			placed += SpawnSpecies(s.Id, Math.Min(per, count - placed));
		}
		// Whatever is left (rounding, species without land) goes to the first species that fits.
		foreach (var s in Assets.Species)
			if (placed < count)
				placed += SpawnSpecies(s.Id, count - placed);
		return placed;
	}

	public void ClearUnits()
	{
		Units.Clear();
		Zones?.Rebuild(Units);
	}

	public int UnitCount() => Units.Count;

	/// <summary>Average milliseconds of one simulation step since the last call.</summary>
	public double TakeStepMs()
	{
		double ms = _stepSamples > 0 ? _stepMs / _stepSamples : 0.0;
		_stepMs = 0;
		_stepSamples = 0;
		return ms;
	}

	/// <summary>Average milliseconds spent writing the units into the MultiMesh per frame since
	/// the last call (CPU side of drawing).</summary>
	public double TakeDrawMs()
	{
		double ms = _drawSamples > 0 ? _drawMs / _drawSamples : 0.0;
		_drawMs = 0;
		_drawSamples = 0;
		return ms;
	}

	/// <summary>Writes the units into the MultiMesh `frames` times (tools: measures drawing).</summary>
	public void DrawFrames(int frames)
	{
		for (int k = 0; k < frames; k++)
			DrawUnits();
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

	public override void _Process(double delta)
	{
		if (World == null)
			return;
		_accumulate += (float)delta;
		while (_accumulate >= Scheduler.Step && _budget < 5)
		{
			_accumulate -= Scheduler.Step;
			TimedStep();
			_budget++;
		}
		if (_budget >= 5)
			_accumulate = 0f;
		_budget = 0;
		DrawUnits();
	}

	private float _accumulate;
	private int _budget;

	private void TimedStep()
	{
		long t = Stopwatch.GetTimestamp();
		Scheduler.DoStep(Units.Capacity, World.Height);
		_stepMs += Stopwatch.GetElapsedTime(t).TotalMilliseconds;
		_stepSamples++;
	}

	// ------------------------------------------------------------------ systems

	private void Move(int a, int b, float dt)
	{
		for (int i = a; i < b; i++)
		{
			if (!Units.Alive[i])
				continue;
			float dx = Units.TargetX[i] - Units.X[i];
			float dy = Units.TargetY[i] - Units.Y[i];
			float d2 = dx * dx + dy * dy;
			if (d2 < 1e-4f)
				continue;
			float d = MathF.Sqrt(d2);
			float step = Assets.Species[Units.Species[i]].Speed * dt;
			float nx = step >= d ? Units.TargetX[i] : Units.X[i] + dx / d * step;
			float ny = step >= d ? Units.TargetY[i] : Units.Y[i] + dy / d * step;
			if (!World.IsLandAt(nx, ny))
			{
				// Water ahead: stop and think again.
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

	private void Wander(int a, int b, float dt)
	{
		for (int i = a; i < b; i++)
		{
			if (!Units.Alive[i])
				continue;
			bool idle = MathF.Abs(Units.TargetX[i] - Units.X[i]) + MathF.Abs(Units.TargetY[i] - Units.Y[i]) < 0.01f;
			if (!idle)
				continue;
			Units.Wait[i] -= dt;
			if (Units.Wait[i] > 0f)
				continue;
			float roam = Assets.Species[Units.Species[i]].Roam;
			for (int tries = 0; tries < 4; tries++)
			{
				float tx = Units.X[i] + ((float)_rng.NextDouble() * 2f - 1f) * roam;
				float ty = Units.Y[i] + ((float)_rng.NextDouble() * 2f - 1f) * roam;
				if (World.IsLandAt(tx, ty))
				{
					Units.TargetX[i] = tx;
					Units.TargetY[i] = ty;
					break;
				}
			}
			Units.Wait[i] = 1f + (float)_rng.NextDouble() * 4f;
		}
	}

	// ------------------------------------------------------------------ drawing

	/// <summary>Follows the camera zoom (screen pixels per world pixel): far away, units are dots
	/// and their shadows are hidden.</summary>
	public void SetZoom(float zoom)
	{
		_material?.SetShaderParameter("zoom", zoom);
		if (_shadowInstance != null)
			_shadowInstance.Visible = zoom >= 0.6f;
	}

	private MultiMeshInstance2D _shadowInstance;

	private void SetupRendering()
	{
		var batchScript = GD.Load<GDScript>("res://scripts/render2d/sprite_batch.gd");
		var atlas = GD.Load<GDScript>("res://scripts/render2d/sprite_atlas.gd").Call("shared").AsGodotObject();
		var library = GD.Load<GDScript>("res://scripts/render3d/sprite_library.gd");
		var regions = atlas.Get("regions").AsGodotDictionary();
		var colors = atlas.Get("colors").AsGodotDictionary();

		int n = Assets.Species.Count;
		_spriteSize = new Vector2[n];
		_spriteRect = new Rect2[n];
		_spriteColor = new Color[n];
		for (int s = 0; s < n; s++)
		{
			string id = Assets.Species[s].Sprite;
			_spriteSize[s] = library.Call("world_size", id).AsVector2() * Tile;
			_spriteRect[s] = regions.ContainsKey(id) ? regions[id].AsRect2() : new Rect2();
			_spriteColor[s] = colors.ContainsKey(id) ? colors[id].AsColor() : Colors.Magenta;
		}

		var quad = batchScript.Call("unit_quad").As<Mesh>();
		_shadowMesh = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform2D, Mesh = quad };
		var shadowMaterial = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/sprite_batch.gdshader") };
		shadowMaterial.SetShaderParameter("from_atlas", false);
		_shadowInstance = new MultiMeshInstance2D
		{
			Multimesh = _shadowMesh, Material = shadowMaterial,
			Texture = batchScript.Call("shadow_texture").As<Texture2D>(),
			TextureFilter = TextureFilterEnum.NearestWithMipmaps,
		};
		AddChild(_shadowInstance);

		_mesh = new MultiMesh
		{
			TransformFormat = MultiMesh.TransformFormatEnum.Transform2D,
			UseColors = true, UseCustomData = true, Mesh = quad,
		};
		_material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/sprite_batch.gdshader") };
		_material.SetShaderParameter("wind", 0.0f);
		AddChild(new MultiMeshInstance2D
		{
			Multimesh = _mesh, Material = _material,
			Texture = atlas.Get("texture").As<Texture2D>(),
			TextureFilter = TextureFilterEnum.NearestWithMipmaps,
		});
	}

	/// <summary>Writes every living unit into the MultiMesh buffers, nearest (lowest) last.</summary>
	private void DrawUnits()
	{
		long started = Stopwatch.GetTimestamp();
		int cap = Units.Capacity;
		if (_order.Length < cap)
		{
			_order = new int[cap];
			_keys = new float[cap];
		}
		int n = 0;
		for (int i = 0; i < cap; i++)
		{
			if (!Units.Alive[i])
				continue;
			_order[n] = i;
			_keys[n] = Units.Y[i];
			n++;
		}
		Array.Sort(_keys, _order, 0, n);

		if (_mesh.InstanceCount < n)
		{
			int size = Math.Max(n, _mesh.InstanceCount * 2);
			_mesh.InstanceCount = size;
			_shadowMesh.InstanceCount = size;
			_buffer = new float[size * 16];
			_shadowBuffer = new float[size * 8];
		}
		for (int k = 0; k < n; k++)
		{
			int i = _order[k];
			int s = Units.Species[i];
			Vector2 size = _spriteSize[s];
			float ox = Units.X[i] * Tile;
			float oy = Units.Y[i] * Tile;
			float sx = Units.FacingLeft[i] ? -size.X : size.X;
			int o = k * 16;
			// Transform2D rows: (x.x, y.x, 0, origin.x), (x.y, y.y, 0, origin.y).
			_buffer[o] = sx; _buffer[o + 1] = 0f; _buffer[o + 2] = 0f; _buffer[o + 3] = ox;
			_buffer[o + 4] = 0f; _buffer[o + 5] = size.Y; _buffer[o + 6] = 0f; _buffer[o + 7] = oy;
			Color c = _spriteColor[s];
			_buffer[o + 8] = c.R; _buffer[o + 9] = c.G; _buffer[o + 10] = c.B; _buffer[o + 11] = size.Y / 256f;
			Rect2 r = _spriteRect[s];
			_buffer[o + 12] = r.Position.X; _buffer[o + 13] = r.Position.Y; _buffer[o + 14] = r.Size.X; _buffer[o + 15] = r.Size.Y;

			float w = size.X * 0.75f, h = size.X * 0.28f;
			int q = k * 8;
			_shadowBuffer[q] = w; _shadowBuffer[q + 1] = 0f; _shadowBuffer[q + 2] = 0f; _shadowBuffer[q + 3] = ox + size.X * 0.08f;
			_shadowBuffer[q + 4] = 0f; _shadowBuffer[q + 5] = h; _shadowBuffer[q + 6] = 0f; _shadowBuffer[q + 7] = oy + h * 0.45f;
		}
		_mesh.VisibleInstanceCount = n;
		_shadowMesh.VisibleInstanceCount = n;
		if (n > 0)
		{
			RenderingServer.MultimeshSetBuffer(_mesh.GetRid(), _buffer);
			RenderingServer.MultimeshSetBuffer(_shadowMesh.GetRid(), _shadowBuffer);
		}
		_drawMs += Stopwatch.GetElapsedTime(started).TotalMilliseconds;
		_drawSamples++;
	}
}
