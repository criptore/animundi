using System;
using System.Collections.Generic;
using System.Text.Json;

namespace Animundi.Sim;

/// <summary>
/// The terrain tools (0.9, docs/POWERS.md): the player raises and lowers the land, pours and dries
/// water, and pastes stamps: ready-made volcanoes, islands, craters, oases and mountains, or an
/// area of a map the player saved earlier (scripts/world/stamp_store.gd keeps those on disk).
///
/// The land has five levels (deep sea, shallow water, plain, hill, mountain). After every change
/// the levels around are fixed so the terrain stays valid, as the world generator leaves it: two
/// land neighbours differ by one level at most, deep sea never touches land. A tile that changes
/// level takes the biome of its new height (hills, mountains, water; new plains keep or take a
/// land biome). What stood on land that goes under drowns: creatures, plants, buildings, fields.
///
/// The map is told through TakeTerrainChanges (tile, level, water, biome), which the main scene
/// copies into its world and redraws, flat and tilted.
/// </summary>
public partial class Simulation
{
	public const byte LevelDeep = 0, LevelShallow = 1, LevelPlain = 2, LevelHill = 3, LevelMountain = 4;
	public const byte WaterOcean = 1, WaterLake = 2, WaterRiver = 3;

	/// <summary>A stamp: a grid of cells, each a level, water and biome, or nothing (-1 level).</summary>
	public sealed class Stamp
	{
		public string Id = "", Name = "";
		public int W, H;
		public sbyte[] Level = Array.Empty<sbyte>();
		public byte[] Water = Array.Empty<byte>();
		public byte[] Biome = Array.Empty<byte>();
		public bool Mine;
	}

	private readonly List<int> _terrainChanged = new();
	private readonly Dictionary<string, Stamp> _stamps = new();
	private readonly List<string> _stampOrder = new();
	/// <summary>The built-in stamps: id, name.</summary>
	public static readonly (string id, string name)[] BuiltinStamps =
	{
		("volcano_small", "Small volcano"), ("volcano_big", "Great volcano"), ("island", "Island"),
		("crater", "Crater"), ("oasis", "Oasis"), ("mountain", "Mountain"), ("lake", "Lake"),
	};

	private int B(string name) => Array.IndexOf(_biomeNames, name);

	// ------------------------------------------------------------------ changing a tile

	/// <summary>Tile t becomes `level` with `water` and `biome`: what stands there and cannot
	/// any more goes (drowned, buried), the map is told. True when something changed.</summary>
	private bool SetTerrain(int t, byte level, byte water, int biome)
	{
		if (biome < 0)
			biome = World.Biome[t];
		bool wasLand = World.Water[t] == SimWorld.WaterLand;
		int oldBiome = World.Biome[t];
		if (World.Level[t] == level && World.Water[t] == water && World.Biome[t] == biome)
			return false;
		World.Level[t] = level;
		World.Water[t] = water;
		World.Biome[t] = (byte)biome;
		_terrainChanged.Add(t);
		_biomeChanged.Add(t);
		bool land = water == SimWorld.WaterLand;
		if (!land || oldBiome != biome || !wasLand)
		{
			while (_tileFirst[t] >= 0)
			{
				MarkStrip((int)_pY[_tileFirst[t]]);
				RemovePlant(_tileFirst[t]);
			}
		}
		TileBurn[t] = 0f;
		if (Scorch[t] > 0 && !land)
		{
			Scorch[t] = 0;
			_scorchChanged.Add(t);
		}
		Grass[t] = land ? Math.Min(Grass[t], _fertility[biome]) : 0f;
		if (!land)
		{
			if (_ground[t] != 0)
				BuryField(t);
			int b = _buildingAt[t];
			if (b >= 0 && Buildings[b].Alive)
				Wash(b);
			if (Blight.Length > t)
				Blight[t] = 0;
			if (Parched.Length > t)
				Parched[t] = 0;
		}
		return true;
	}

	/// <summary>A building the water takes: gone at once, without a ruin.</summary>
	private void Wash(int b)
	{
		var bld = Buildings[b];
		if (bld.Type != _tRuin)
			ToRuin(b);
		bld.Alive = false;
		_buildingAt[World.Index(bld.X, bld.Y)] = -1;
		Villages[bld.Village].Buildings.Remove(b);
		_ruins.Remove(b);
		_freeBuildings.Push(b);
	}

	/// <summary>The biome of a land tile at a new level: hills and mountains their own; a plain
	/// keeps a plain biome, or takes the one most of its land neighbours have.</summary>
	private int LandBiome(int t, byte level)
	{
		int hills = B("Hills"), mountain = B("Mountain"), peak = B("Peak");
		int cur = World.Biome[t];
		string curName = cur >= 0 && cur < _biomeNames.Length ? _biomeNames[cur] : "";
		if (level == LevelMountain)
			return curName is "Volcanic rock" or "Lava" or "Peak" or "Snow" ? cur : mountain;
		bool special = curName is "Volcanic rock" or "Lava" or "Mushroom land" or "Cursed land";
		if (level == LevelHill)
			return special ? cur : hills;
		if (World.Water[t] == SimWorld.WaterLand && cur != hills && cur != mountain && cur != peak && !IsWaterBiome(curName))
			return cur;
		// From the neighbours' plain biomes, else grassland.
		var votes = new Dictionary<int, int>();
		int x = t % World.Width, y = t / World.Width;
		for (int dy = -2; dy <= 2; dy++)
			for (int dx = -2; dx <= 2; dx++)
			{
				if (!World.InBounds(x + dx, y + dy))
					continue;
				int n = World.Index(x + dx, y + dy);
				int nb = World.Biome[n];
				if (World.Water[n] != SimWorld.WaterLand || nb == hills || nb == mountain || nb == peak || nb == B("Beach"))
					continue;
				votes[nb] = (votes.TryGetValue(nb, out int c) ? c : 0) + 1;
			}
		int best = B("Grassland"), most = 0;
		foreach (var (nb, c) in votes)
			if (c > most)
			{
				most = c;
				best = nb;
			}
		return best;
	}

	/// <summary>Water of a tile going under: the sea if it touches the sea, else a lake.</summary>
	private byte WaterKind(int t)
	{
		int x = t % World.Width, y = t / World.Width;
		for (int d = 0; d < 4; d++)
		{
			int nx = x + (d == 0 ? 1 : d == 1 ? -1 : 0), ny = y + (d == 2 ? 1 : d == 3 ? -1 : 0);
			if (!World.InBounds(nx, ny) || World.Water[World.Index(nx, ny)] == WaterOcean)
				return WaterOcean;
		}
		return WaterLake;
	}

	/// <summary>Tile t one level up (water becomes a plain) or down (a plain becomes shallow water).</summary>
	private bool StepTile(int t, int by)
	{
		int level = Math.Clamp(World.Level[t] + by, LevelDeep, LevelMountain);
		if (level == World.Level[t])
			return false;
		if (level >= LevelPlain)
			return SetTerrain(t, (byte)level, SimWorld.WaterLand, LandBiomeAfter(t, (byte)level));
		byte water = World.Water[t] != SimWorld.WaterLand ? World.Water[t] : WaterKind(t);
		if (water == WaterRiver)
			water = WaterLake;
		// Lakes are shallow; only the sea is deep.
		if (water != WaterOcean)
			level = LevelShallow;
		return SetTerrain(t, (byte)level, water, level == LevelDeep ? B("Deep water") : B("Water"));
	}

	private int LandBiomeAfter(int t, byte level)
	{
		// Decided as if the tile were already land at that level.
		return LandBiome(t, level);
	}

	/// <summary>Keeps the terrain valid around the tiles changed since `from` in _terrainChanged:
	/// land neighbours differ by one level at most (the higher side wins when raising, the lower
	/// when lowering), deep sea next to land becomes shallow.</summary>
	private void SettleTerrain(int from, bool raising)
	{
		var queue = new Queue<int>();
		for (int k = from; k < _terrainChanged.Count; k++)
			queue.Enqueue(_terrainChanged[k]);
		int guard = World.Width * World.Height * 4;
		while (queue.Count > 0 && guard-- > 0)
		{
			int t = queue.Dequeue();
			int x = t % World.Width, y = t / World.Width;
			for (int d = 0; d < 4; d++)
			{
				int nx = x + (d == 0 ? 1 : d == 1 ? -1 : 0), ny = y + (d == 2 ? 1 : d == 3 ? -1 : 0);
				if (!World.InBounds(nx, ny))
					continue;
				int n = World.Index(nx, ny);
				int lt = World.Level[t], ln = World.Level[n];
				bool landT = World.Water[t] == SimWorld.WaterLand, landN = World.Water[n] == SimWorld.WaterLand;
				// Deep sea never touches land: it becomes shallow.
				if (landT && World.Level[n] == LevelDeep)
				{
					if (SetTerrain(n, LevelShallow, World.Water[n], B("Water")))
						queue.Enqueue(n);
					continue;
				}
				if (landT != landN)
				{
					// The land at the water's edge is a plain: raising lifts the water into land,
					// lowering brings the bank down.
					int land = landT ? t : n, wet = landT ? n : t;
					if (World.Level[land] > LevelPlain)
					{
						if (raising ? StepTile(wet, LevelPlain - World.Level[wet]) : SetTerrain(land, LevelPlain, SimWorld.WaterLand, LandBiome(land, LevelPlain)))
						{
							queue.Enqueue(raising ? wet : land);
							queue.Enqueue(t);
						}
					}
					continue;
				}
				if (!landT)
					continue;
				if (raising && ln < lt - 1)
				{
					if (StepTile(n, lt - 1 - ln))
						queue.Enqueue(n);
				}
				else if (!raising && ln > lt + 1)
				{
					if (StepTile(n, lt + 1 - ln))
						queue.Enqueue(n);
				}
			}
		}
	}

	/// <summary>After the land changed: creatures on water drown, water sources and the lands
	/// where creatures are born are worked out again.</summary>
	private void AfterTerrain(int from)
	{
		if (_terrainChanged.Count == from)
			return;
		var touched = new HashSet<int>();
		for (int k = from; k < _terrainChanged.Count; k++)
			touched.Add(_terrainChanged[k]);
		for (int i = 0; i < Units.Capacity; i++)
		{
			if (!Units.Alive[i] || Units.Task[i] == (byte)Task.Sail)
				continue;
			int t = World.Index(Math.Clamp((int)Units.X[i], 0, World.Width - 1), Math.Clamp((int)Units.Y[i], 0, World.Height - 1));
			if (touched.Contains(t) && World.Water[t] != SimWorld.WaterLand && !Assets.Species[Units.Species[i]].IsLegend)
				KillUnit(i, Death.Disaster);
		}
		_nearestWater = World.NearestWater(24);
		_spawnTiles.Clear();
		for (int t = 0; t < World.Biome.Length; t++)
			if (World.Water[t] == SimWorld.WaterLand && _spawnTables[World.Biome[t]] != null)
				_spawnTiles.Add(t);
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);
		Zones.Rebuild(Units);
	}

	// ------------------------------------------------------------------ the powers

	/// <summary>Raises the land under the brush one level (water becomes plain, plains hills,
	/// hills mountains). Returns the tiles changed, those around included.</summary>
	public int PowerRaise(float x, float y, float radius) => Shape(x, y, radius, +1);

	/// <summary>Lowers the land under the brush one level, down into the water.</summary>
	public int PowerLower(float x, float y, float radius) => Shape(x, y, radius, -1);

	private int Shape(float x, float y, float radius, int by)
	{
		if (World == null)
			return 0;
		int from = _terrainChanged.Count;
		TilesWithin(x, y, radius, t => StepTile(t, by));
		SettleTerrain(from, by > 0);
		AfterTerrain(from);
		int changed = _terrainChanged.Count - from;
		if (changed > 0)
		{
			Grieve(World.Index(Math.Clamp((int)x, 0, World.Width - 1), Math.Clamp((int)y, 0, World.Height - 1)), changed * 0.1f, "struck");
			GodActs(by > 0 ? "earthquake" : "flood", x, y, radius, 1);
		}
		return changed;
	}

	/// <summary>Pours water under the brush (land becomes a lake, at the level of the plain), or,
	/// on water, dries it into plain land. Returns the tiles changed.</summary>
	public int PowerWater(float x, float y, float radius)
	{
		if (World == null || !World.InBounds((int)x, (int)y))
			return 0;
		bool dry = World.Water[World.Index((int)x, (int)y)] != SimWorld.WaterLand;
		int from = _terrainChanged.Count;
		TilesWithin(x, y, radius, t =>
		{
			if (dry)
			{
				if (World.Water[t] != SimWorld.WaterLand)
					SetTerrain(t, LevelPlain, SimWorld.WaterLand, LandBiome(t, LevelPlain));
			}
			else if (World.Water[t] == SimWorld.WaterLand)
				SetTerrain(t, LevelShallow, WaterKind(t), B("Water"));
		});
		SettleTerrain(from, !dry);
		// The land around fresh water is a plain: a lake does not hang on a hillside.
		if (!dry)
		{
			int mid = _terrainChanged.Count;
			for (int k = from; k < mid; k++)
			{
				int t = _terrainChanged[k];
				int tx = t % World.Width, ty = t / World.Width;
				for (int d = 0; d < 4; d++)
				{
					int nx = tx + (d == 0 ? 1 : d == 1 ? -1 : 0), ny = ty + (d == 2 ? 1 : d == 3 ? -1 : 0);
					if (World.InBounds(nx, ny) && World.Water[World.Index(nx, ny)] == SimWorld.WaterLand && World.Level[World.Index(nx, ny)] > LevelPlain)
						SetTerrain(World.Index(nx, ny), LevelPlain, SimWorld.WaterLand, LandBiome(World.Index(nx, ny), LevelPlain));
				}
			}
			SettleTerrain(mid, false);
		}
		AfterTerrain(from);
		int changed = _terrainChanged.Count - from;
		if (changed > 0)
			GodActs("flood", x, y, radius, 1);
		return changed;
	}

	// ------------------------------------------------------------------ stamps

	/// <summary>The stamps the player can paste: the built-in ones, then their own. id, name.</summary>
	public string[] StampIds()
	{
		EnsureBuiltinStamps();
		return _stampOrder.ToArray();
	}

	public string StampName(string id) => _stamps.TryGetValue(id, out var s) ? s.Name : "";

	private void EnsureBuiltinStamps()
	{
		if (_stamps.ContainsKey("volcano_small") || _biomeNames.Length == 0)
			return;
		foreach (var (id, name) in BuiltinStamps)
		{
			var s = MakeBuiltin(id);
			s.Id = id;
			s.Name = name;
			_stamps[id] = s;
			_stampOrder.Insert(Math.Min(_stampOrder.Count, Array.FindIndex(BuiltinStamps, b => b.id == id)), id);
		}
	}

	/// <summary>Draws a built-in stamp: rings around its middle, by distance.</summary>
	private Stamp MakeBuiltin(string id)
	{
		int r = id switch { "volcano_small" => 4, "volcano_big" => 7, "island" => 8, "crater" => 6, "oasis" => 5, "mountain" => 6, _ => 5 };
		int size = r * 2 + 1;
		var s = new Stamp { W = size, H = size, Level = new sbyte[size * size], Water = new byte[size * size], Biome = new byte[size * size] };
		Array.Fill(s.Level, (sbyte)-1);
		int lava = B("Lava"), rock = B("Volcanic rock"), mountain = B("Mountain"), hills = B("Hills"), grass = B("Grassland"),
			forest = B("Forest"), beach = B("Beach"), water = B("Water"), desert = B("Desert"), jungle = B("Jungle"), peak = B("Peak"), savanna = B("Savanna");
		for (int y = 0; y < size; y++)
			for (int x = 0; x < size; x++)
			{
				float d = MathF.Sqrt((x - r) * (x - r) + (y - r) * (y - r)) / (r + 0.5f);
				// Ragged edges: a little noise from the cell's place.
				float jag = ((x * 73856093 ^ y * 19349663) & 255) / 255f * 0.12f;
				d += jag - 0.06f;
				if (d > 1f)
					continue;
				int i = y * size + x;
				(int level, int w, int b) cell = id switch
				{
					"volcano_small" or "volcano_big" => d < 0.22f ? (LevelMountain, 0, lava) : d < 0.5f ? (LevelMountain, 0, rock)
						: d < 0.78f ? (LevelHill, 0, rock) : (LevelPlain, 0, -1),
					"island" => d < 0.25f ? (LevelHill, 0, forest) : d < 0.7f ? (LevelPlain, 0, d < 0.45f ? forest : grass) : d < 0.85f ? (LevelPlain, 0, beach) : (LevelShallow, WaterOcean, water),
					"crater" => d < 0.3f ? (LevelShallow, WaterLake, water) : d < 0.7f ? (LevelPlain, 0, rock) : (LevelHill, 0, rock),
					"oasis" => d < 0.3f ? (LevelShallow, WaterLake, water) : d < 0.55f ? (LevelPlain, 0, jungle) : d < 0.75f ? (LevelPlain, 0, savanna) : (LevelPlain, 0, desert),
					"mountain" => d < 0.2f ? (LevelMountain, 0, peak) : d < 0.55f ? (LevelMountain, 0, mountain) : d < 0.85f ? (LevelHill, 0, hills) : (LevelPlain, 0, -1),
					_ => d < 0.8f ? (LevelShallow, WaterLake, water) : (LevelPlain, 0, -1),
				};
				s.Level[i] = (sbyte)cell.level;
				s.Water[i] = (byte)cell.w;
				s.Biome[i] = (byte)Math.Max(0, cell.b < 0 ? 255 : cell.b);
			}
		return s;
	}

	/// <summary>Pastes stamp `id` centred on (x, y): each of its cells takes its level, water and
	/// biome (a cell with no biome keeps the land's own, or takes one of its level), then the
	/// terrain around is fixed. Returns the tiles changed, or -1 for an unknown stamp.</summary>
	public int PowerStamp(string id, float x, float y)
	{
		EnsureBuiltinStamps();
		if (World == null || !_stamps.TryGetValue(id ?? "", out var s))
			return -1;
		int from = _terrainChanged.Count;
		int x0 = (int)MathF.Floor(x) - s.W / 2, y0 = (int)MathF.Floor(y) - s.H / 2;
		bool raised = false;
		for (int cy = 0; cy < s.H; cy++)
			for (int cx = 0; cx < s.W; cx++)
			{
				int i = cy * s.W + cx;
				if (s.Level[i] < 0 || !World.InBounds(x0 + cx, y0 + cy))
					continue;
				int t = World.Index(x0 + cx, y0 + cy);
				byte level = (byte)s.Level[i];
				byte water = s.Water[i];
				// A shore of a stamp laid on land stays land.
				if (water == WaterOcean && World.Water[t] == SimWorld.WaterLand)
				{
					water = SimWorld.WaterLand;
					level = LevelPlain;
				}
				if (water != SimWorld.WaterLand && World.Water[t] == WaterOcean)
					water = WaterOcean;
				int biome = s.Biome[i] == 255 || s.Biome[i] >= _biomeNames.Length ? -1 : s.Biome[i];
				if (water == SimWorld.WaterLand && biome < 0)
					biome = LandBiome(t, level);
				raised |= level > World.Level[t];
				SetTerrain(t, level, water, biome);
				if (_biomeNames[World.Biome[t]] == "Lava")
				{
					foreach (int u in UnitsWithin(t % World.Width + 0.5f, t / World.Width + 0.5f, 0.8f).ToArray())
						KillUnit(u, Death.Fire);
				}
			}
		SettleTerrain(from, true);
		SettleTerrain(from, false);
		AfterTerrain(from);
		int changed = _terrainChanged.Count - from;
		if (changed > 0)
		{
			if (id.StartsWith("volcano"))
			{
				Ignite(x, y, s.W * 0.35f);
				LateSpirits();
			}
			LogEvent($"the land changes {PlaceNear(x, y)}: {(s.Mine ? "a piece of another world" : s.Name.ToLower())} rises by your hand.", "disasters");
			GodActs(raised ? "earthquake" : "flood", x, y, s.W / 2f, 1);
		}
		return changed;
	}

	/// <summary>Copies the square of `size` tiles centred on (x, y) as a stamp: JSON the game
	/// keeps on disk, and pastes back with AddStamp.</summary>
	public string CopyStamp(float x, float y, int size)
	{
		if (World == null)
			return "";
		size = Math.Clamp(size, 3, 48);
		int x0 = (int)MathF.Floor(x) - size / 2, y0 = (int)MathF.Floor(y) - size / 2;
		var levels = new int[size * size];
		var water = new int[size * size];
		var biomes = new string[size * size];
		for (int cy = 0; cy < size; cy++)
			for (int cx = 0; cx < size; cx++)
			{
				int i = cy * size + cx;
				if (!World.InBounds(x0 + cx, y0 + cy))
				{
					levels[i] = -1;
					biomes[i] = "";
					continue;
				}
				int t = World.Index(x0 + cx, y0 + cy);
				levels[i] = World.Level[t];
				water[i] = World.Water[t];
				biomes[i] = _biomeNames[World.Biome[t]];
			}
		return JsonSerializer.Serialize(new Dictionary<string, object>
		{
			["w"] = size, ["h"] = size, ["level"] = levels, ["water"] = water, ["biome"] = biomes,
		});
	}

	/// <summary>Adds a stamp the player saved (JSON of CopyStamp) under `id` and `name`. Biomes
	/// are kept by name, so a stamp works in any world. Returns "" or why it is refused.</summary>
	public string AddStamp(string id, string name, string json)
	{
		if (string.IsNullOrWhiteSpace(id) || Array.Exists(BuiltinStamps, b => b.id == id))
			return "bad id";
		try
		{
			using var doc = JsonDocument.Parse(json);
			var root = doc.RootElement;
			int w = root.GetProperty("w").GetInt32(), h = root.GetProperty("h").GetInt32();
			if (w < 1 || h < 1 || w > 64 || h > 64)
				return "bad size";
			var s = new Stamp { Id = id, Name = name, W = w, H = h, Level = new sbyte[w * h], Water = new byte[w * h], Biome = new byte[w * h], Mine = true };
			var levels = root.GetProperty("level");
			var waters = root.GetProperty("water");
			var biomes = root.GetProperty("biome");
			if (levels.GetArrayLength() != w * h || waters.GetArrayLength() != w * h || biomes.GetArrayLength() != w * h)
				return "bad cells";
			for (int i = 0; i < w * h; i++)
			{
				int level = levels[i].GetInt32(), water = waters[i].GetInt32();
				int b = Array.IndexOf(_biomeNames, biomes[i].GetString() ?? "");
				if (level < 0 || level > LevelMountain || b < 0 || water < 0 || water > WaterRiver)
				{
					s.Level[i] = -1;
					continue;
				}
				// Land and water must agree with the level.
				bool land = level >= LevelPlain;
				s.Level[i] = (sbyte)level;
				s.Water[i] = land ? SimWorld.WaterLand : (byte)Math.Max(1, water);
				s.Biome[i] = (byte)b;
			}
			EnsureBuiltinStamps();
			if (!_stamps.ContainsKey(id))
				_stampOrder.Add(id);
			_stamps[id] = s;
			return "";
		}
		catch (Exception e)
		{
			return "not a stamp: " + e.Message;
		}
	}

	public void RemoveStamp(string id)
	{
		if (_stamps.TryGetValue(id, out var s) && s.Mine)
		{
			_stamps.Remove(id);
			_stampOrder.Remove(id);
		}
	}

	// ------------------------------------------------------------------ the map's side

	/// <summary>Terrain changes since the last call, as quads (tile, level, water, biome).</summary>
	public int[] TakeTerrainChanges()
	{
		if (World == null || _terrainChanged.Count == 0)
			return Array.Empty<int>();
		var seen = new HashSet<int>();
		var list = new List<int>();
		foreach (int t in _terrainChanged)
			if (t < World.Level.Length && seen.Add(t))
			{
				list.Add(t);
				list.Add(World.Level[t]);
				list.Add(World.Water[t]);
				list.Add(World.Biome[t]);
			}
		_terrainChanged.Clear();
		return list.ToArray();
	}

	/// <summary>Level of tile (x, y) (tests).</summary>
	public int LevelAt(int x, int y) => World != null && World.InBounds(x, y) ? World.Level[World.Index(x, y)] : -1;

	/// <summary>Water of tile (x, y): 0 land, 1 sea, 2 lake, 3 river (tests).</summary>
	public int WaterAt(int x, int y) => World != null && World.InBounds(x, y) ? World.Water[World.Index(x, y)] : -1;


	/// <summary>Whether every pair of land neighbours differs by one level at most and no deep sea
	/// touches land (tests).</summary>
	public bool TerrainValid()
	{
		for (int y = 0; y < World.Height; y++)
			for (int x = 0; x < World.Width; x++)
			{
				int t = World.Index(x, y);
				foreach (var (nx, ny) in new[] { (x + 1, y), (x, y + 1) })
				{
					if (!World.InBounds(nx, ny))
						continue;
					int n = World.Index(nx, ny);
					bool lt = World.Water[t] == SimWorld.WaterLand, ln = World.Water[n] == SimWorld.WaterLand;
					if (lt && ln && Math.Abs(World.Level[t] - World.Level[n]) > 1)
						return false;
					if (lt && World.Level[n] == LevelDeep || ln && World.Level[t] == LevelDeep)
						return false;
					if (lt != (World.Level[t] >= LevelPlain))
						return false;
					// The land at the water's edge is a plain.
					if (lt != ln && World.Level[lt ? t : n] > LevelPlain)
						return false;
				}
			}
		return true;
	}
}
