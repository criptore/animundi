using System;
using System.Collections.Generic;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Living nature (0.2): seasons, the grass that grazers eat, plants that grow, spread, burn and
/// grow back, wildfires (lightning or the player) and the scorched ground they leave.
///
/// Plants live in parallel arrays like units, with a linked list per tile for "what grows here".
/// A world process visits the map one slice at a time: grass grows back, ash fades, saplings
/// grow, adult plants seed their neighbourhood, empty ground is recolonised.
/// </summary>
public partial class Simulation
{
	/// <summary>Seconds in a year; a season is a quarter of it.</summary>
	public const float YearSeconds = 60f;
	public static readonly string[] SeasonNames = { "Spring", "Summer", "Autumn", "Winter" };
	/// <summary>Seconds a plant burns before it is gone.</summary>
	public const float BurnSeconds = 2.5f;

	/// <summary>Grass on each tile, 0..fertility of its biome: what grazers eat.</summary>
	public float[] Grass = Array.Empty<float>();
	/// <summary>Ash on each tile, 0..255, left by fire; fades over most of a year.</summary>
	public byte[] Scorch = Array.Empty<byte>();
	private float[] _fertility = Array.Empty<float>();
	// Per biome, from data/biomes.json: chance per second that a burning neighbour lights a tile,
	// and how long a tile burns.
	private float[] _burnChance = Array.Empty<float>();
	private float[] _burnTime = Array.Empty<float>();
	/// <summary>Seconds each tile has been burning, 0 when not on fire.</summary>
	public float[] TileBurn = Array.Empty<float>();
	private readonly List<int> _burningTiles = new();
	private readonly List<int> _scorchChanged = new();
	private readonly List<(string cat, string text)> _events = new();
	private float _lightningIn;

	// Plants, as parallel arrays (index = plant).
	private readonly List<string> _plantSprites = new();
	// Per plant sprite: whether it burns (rocks and boulders don't).
	private readonly List<bool> _flammable = new();
	private readonly Dictionary<string, int> _plantSpriteIndex = new();
	private int _plantCap;
	private int _plantCount;
	private int[] _pSprite = Array.Empty<int>();
	private float[] _pX = Array.Empty<float>();
	private float[] _pY = Array.Empty<float>();
	private bool[] _pFlip = Array.Empty<bool>();
	private float[] _pScale = Array.Empty<float>();
	/// <summary>0.3 = sapling .. 1 = grown.</summary>
	private float[] _pGrowth = Array.Empty<float>();
	private bool[] _pAlive = Array.Empty<bool>();
	/// <summary>Seconds burning, 0 when not on fire.</summary>
	private float[] _pBurn = Array.Empty<float>();
	private int[] _pNext = Array.Empty<int>();
	private int[] _pFree = Array.Empty<int>();
	private int _pFreeCount;
	private int[] _tileFirst = Array.Empty<int>();
	private byte[] _tileCount = Array.Empty<byte>();
	private readonly List<int> _burning = new();
	// Per biome: plant sprites that grow there with their density, and the total density.
	private List<(int sprite, float perTile)>[] _biomePlants = Array.Empty<List<(int, float)>>();
	private float[] _biomeDensity = Array.Empty<float>();

	public int PlantCount() => _plantCount;

	/// <summary>Plants burned down since the world started.</summary>
	public int PlantsBurned { get; private set; }

	/// <summary>Whether plants with this sprite burn.</summary>
	public bool IsFlammable(string sprite) => _flammable[PlantSprite(sprite)];
	public int BurningCount() => _burning.Count + _burningTiles.Count;

	// ------------------------------------------------------------------ seasons

	/// <summary>0 at the start of spring, 1 at the end of winter.</summary>
	public float YearProgress() => (float)(Scheduler.Time / YearSeconds % 1.0);
	public int Year() => 1 + (int)(Scheduler.Time / YearSeconds);
	public int Season() => (int)(YearProgress() * 4f) % 4;
	public string SeasonName() => SeasonNames[Season()];

	/// <summary>How cold the season is: 0 in summer, 1 in midwinter.</summary>
	public float Coldness() => Math.Max(0f, MathF.Cos(MathF.Tau * (YearProgress() - 0.875f)));

	/// <summary>How fast things grow this season: fast in spring, none in midwinter.</summary>
	private float GrowthFactor()
	{
		float p = YearProgress();
		return p < 0.25f ? 1.4f : p < 0.5f ? 1f : p < 0.75f ? 0.6f : 0.15f * (1f - Coldness());
	}

	// ------------------------------------------------------------------ events

	/// <summary>Event categories for the log's filters: kings, wars, cities, disasters, life.</summary>
	public static readonly string[] EventCategories = { "kings", "wars", "cities", "disasters", "life" };

	private void LogEvent(string text, string cat = "life")
	{
		_events.Add((cat, $"Year {Year()}, {SeasonName().ToLower()}: {text}"));
		if (_events.Count > 2000)
			_events.RemoveRange(0, 1000);
	}

	/// <summary>Events since the last call (deaths of species, fires...).</summary>
	public string[] TakeEvents()
	{
		var e = new string[_events.Count];
		for (int k = 0; k < e.Length; k++)
			e[k] = _events[k].text;
		_events.Clear();
		return e;
	}

	/// <summary>Events since the last call with their category: [category, text, category, text...].</summary>
	public string[] TakeTaggedEvents()
	{
		var e = new string[_events.Count * 2];
		for (int k = 0; k < _events.Count; k++)
		{
			e[k * 2] = _events[k].cat;
			e[k * 2 + 1] = _events[k].text;
		}
		_events.Clear();
		return e;
	}

	// ------------------------------------------------------------------ setup

	private void SetupNature()
	{
		int n = World.Width * World.Height;
		Grass = new float[n];
		Scorch = new byte[n];
		_fertility = new float[_biomeNames.Length];
		_burnChance = new float[_biomeNames.Length];
		_burnTime = new float[_biomeNames.Length];
		for (int b = 0; b < _biomeNames.Length; b++)
			if (Assets.Biomes.TryGetValue(_biomeNames[b], out var rec))
			{
				_fertility[b] = rec.Fertility;
				_burnChance[b] = rec.BurnChance;
				_burnTime[b] = rec.BurnTime;
			}
		TileBurn = new float[n];
		_burningTiles.Clear();
		for (int i = 0; i < n; i++)
			Grass[i] = World.Water[i] == SimWorld.WaterLand ? _fertility[World.Biome[i]] : 0f;
		_scorchChanged.Clear();
		_events.Clear();
		_lightningIn = 40f + (float)_rng.NextDouble() * 60f;

		_tileFirst = new int[n];
		Array.Fill(_tileFirst, -1);
		_tileCount = new byte[n];
		_plantCount = 0;
		_plantCap = 0;
		_pFreeCount = 0;
		_burning.Clear();
		PlantsBurned = 0;
		_biomePlants = new List<(int, float)>[_biomeNames.Length];
		_biomeDensity = new float[_biomeNames.Length];
		foreach (var (name, list) in Assets.Plants)
		{
			int b = Array.IndexOf(_biomeNames, name);
			if (b < 0)
				continue;
			_biomePlants[b] = new();
			foreach (var e in list)
			{
				_biomePlants[b].Add((PlantSprite(e.Sprite), e.PerTile));
				_biomeDensity[b] += e.PerTile;
			}
		}
		_stripDirty = Array.Empty<bool>();
	}

	private int PlantSprite(string id)
	{
		if (!_plantSpriteIndex.TryGetValue(id, out int s))
		{
			s = _plantSprites.Count;
			_plantSprites.Add(id);
			_flammable.Add(!(id.Contains("Rock") || id.Contains("Boulder")));
			_plantSpriteIndex[id] = s;
		}
		return s;
	}

	// ------------------------------------------------------------------ plants

	/// <summary>Takes the world's plants as placed by scripts/world/flora.gd: sprite ids, feet
	/// positions in tiles, mirrored (1) or not, size factor.</summary>
	public void LoadPlants(string[] ids, Vector2[] positions, byte[] flips, float[] scales)
	{
		for (int k = 0; k < ids.Length; k++)
		{
			int p = AddPlant(PlantSprite(ids[k]), positions[k].X, positions[k].Y, flips[k] == 1, scales[k]);
			if (p >= 0)
				_pGrowth[p] = 1f;
		}
	}

	private int AddPlant(int sprite, float x, float y, bool flip, float scale)
	{
		int tx = (int)x, ty = (int)y;
		if (!World.IsLand(tx, ty))
			return -1;
		int t = World.Index(tx, ty);
		if (_tileCount[t] == 255)
			return -1;
		int p;
		if (_pFreeCount > 0)
			p = _pFree[--_pFreeCount];
		else
		{
			if (_plantCap == _pAlive.Length)
				GrowPlants(Math.Max(1024, _plantCap * 2));
			p = _plantCap++;
		}
		_pSprite[p] = sprite;
		_pX[p] = x;
		_pY[p] = y;
		_pFlip[p] = flip;
		_pScale[p] = scale;
		_pGrowth[p] = 0.3f;
		_pAlive[p] = true;
		_pBurn[p] = 0f;
		_pNext[p] = _tileFirst[t];
		_tileFirst[t] = p;
		_tileCount[t]++;
		_plantCount++;
		MarkStrip(ty);
		return p;
	}

	private void RemovePlant(int p)
	{
		if (!_pAlive[p])
			return;
		int tx = (int)_pX[p], ty = (int)_pY[p];
		int t = World.Index(tx, ty);
		if (_tileFirst[t] == p)
			_tileFirst[t] = _pNext[p];
		else
			for (int q = _tileFirst[t]; q >= 0; q = _pNext[q])
				if (_pNext[q] == p)
				{
					_pNext[q] = _pNext[p];
					break;
				}
		_tileCount[t]--;
		_pAlive[p] = false;
		_pFree[_pFreeCount++] = p;
		_plantCount--;
		MarkStrip(ty);
	}

	private void GrowPlants(int size)
	{
		Array.Resize(ref _pSprite, size);
		Array.Resize(ref _pX, size);
		Array.Resize(ref _pY, size);
		Array.Resize(ref _pFlip, size);
		Array.Resize(ref _pScale, size);
		Array.Resize(ref _pGrowth, size);
		Array.Resize(ref _pAlive, size);
		Array.Resize(ref _pBurn, size);
		Array.Resize(ref _pNext, size);
		Array.Resize(ref _pFree, size);
	}

	/// <summary>Plants on the 3x3 tiles around (x, y).</summary>
	private int PlantsAround(int x, int y)
	{
		int n = 0;
		for (int dy = -1; dy <= 1; dy++)
			for (int dx = -1; dx <= 1; dx++)
				if (World.InBounds(x + dx, y + dy))
					n += _tileCount[World.Index(x + dx, y + dy)];
		return n;
	}

	/// <summary>Whether `sprite` grows in the biome of tile t, and room is left around it.</summary>
	private bool RoomFor(int sprite, int x, int y)
	{
		if (!World.IsLand(x, y))
			return false;
		int t = World.Index(x, y);
		if (Scorch[t] > 64)
			return false;
		var list = _biomePlants[World.Biome[t]];
		if (list == null)
			return false;
		bool grows = false;
		foreach (var (s, _) in list)
			grows |= s == sprite;
		return grows && PlantsAround(x, y) < _biomeDensity[World.Biome[t]] * 9f + 0.5f;
	}

	/// <summary>The world process for nature: one slice of rows every call.</summary>
	private void NatureSlice(int y0, int y1)
	{
		// Each row is visited once every Slices * Interval seconds.
		float elapsed = NatureInterval * NatureSlices;
		float growth = GrowthFactor();
		bool treesGrow = Law("trees_growth");
		int ashFade = (int)MathF.Ceiling(255f * elapsed / (YearSeconds * 0.75f));
		for (int y = y0; y < y1; y++)
			for (int x = 0; x < World.Width; x++)
			{
				int t = World.Index(x, y);
				if (World.Water[t] != SimWorld.WaterLand)
					continue;
				int b = World.Biome[t];
				if (Scorch[t] > 0)
				{
					Scorch[t] = (byte)Math.Max(0, Scorch[t] - ashFade);
					_scorchChanged.Add(t);
				}
				if (Scorch[t] < 128)
					Grass[t] = Math.Min(_fertility[b], Grass[t] + 0.04f * _fertility[b] * growth * elapsed);
				if (!treesGrow)
					continue;
				for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
				{
					if (_pBurn[p] > 0f)
						continue;
					if (_pGrowth[p] < 1f)
					{
						// Redraw only when the sapling has visibly grown (every tenth of its size).
						float before = _pGrowth[p];
						_pGrowth[p] = Math.Min(1f, before + elapsed * growth / (YearSeconds * 0.5f));
						if ((int)(before * 10f) != (int)(_pGrowth[p] * 10f))
							MarkStrip(y);
					}
					else if (_rng.NextDouble() < 0.04 * growth)
					{
						// A grown plant seeds a spot nearby.
						float sx = _pX[p] + ((float)_rng.NextDouble() * 2f - 1f) * 2.5f;
						float sy = _pY[p] + ((float)_rng.NextDouble() * 2f - 1f) * 2.5f;
						if (RoomFor(_pSprite[p], (int)sx, (int)sy) && OnLandFootprint(_pSprite[p], sx, sy))
							AddPlant(_pSprite[p], sx, sy, _rng.Next(2) == 0, 0.85f + (float)_rng.NextDouble() * 0.3f);
					}
				}
				// Bare ground slowly gets plants of its biome back (after fires, or new biomes).
				var list = _biomePlants[b];
				if (list != null && _tileCount[t] == 0 && Scorch[t] < 64 && _rng.NextDouble() < _biomeDensity[b] * 0.05 * growth)
				{
					float r = (float)_rng.NextDouble() * _biomeDensity[b];
					foreach (var (s, perTile) in list)
					{
						r -= perTile;
						if (r > 0f)
							continue;
						float px = x + 0.1f + (float)_rng.NextDouble() * 0.8f;
						float py = y + 0.2f + (float)_rng.NextDouble() * 0.75f;
						if (RoomFor(s, x, y) && OnLandFootprint(s, px, py))
							AddPlant(s, px, py, _rng.Next(2) == 0, 0.85f + (float)_rng.NextDouble() * 0.3f);
						break;
					}
				}
			}
	}

	private const float NatureInterval = 0.25f;
	private const int NatureSlices = 32;

	/// <summary>Like scripts/world/flora.gd on_land: the whole sprite stands over land.</summary>
	private bool OnLandFootprint(int sprite, float fx, float fy)
	{
		Vector2 size = PlantSize(sprite) / Tile;
		float half = size.X * 0.4f;
		for (int ty = (int)MathF.Floor(fy - size.Y * 0.9f); ty <= (int)MathF.Floor(fy); ty++)
			for (int tx = (int)MathF.Floor(fx - half); tx <= (int)MathF.Floor(fx + half); tx++)
				if (!World.IsLand(tx, ty))
					return false;
		return true;
	}

	// ------------------------------------------------------------------ fire

	// Fire works like WorldBox's: it lives on tiles. Each biome has a burn chance (data/biomes.json):
	// every second, a burning tile may set each neighbour on fire, if that neighbour still has fuel
	// (grass or plants). Plants on a burning tile catch fire too, and burning plants light the
	// ground under them. A tile burns for its biome's burn time, then turns to ash.

	/// <summary>Sets fire to the tiles (and their plants) within `radius` tiles of (x, y): lightning
	/// now, god powers later. Returns how many tiles caught fire.</summary>
	public int Ignite(float x, float y, float radius)
	{
		int n = 0;
		for (int ty = (int)(y - radius); ty <= (int)(y + radius); ty++)
			for (int tx = (int)(x - radius); tx <= (int)(x + radius); tx++)
			{
				float dx = tx + 0.5f - x, dy = ty + 0.5f - y;
				if (World.InBounds(tx, ty) && dx * dx + dy * dy <= radius * radius && IgniteTile(World.Index(tx, ty)))
					n++;
			}
		return n;
	}

	/// <summary>Whether tile t has something to burn: grass, or a plant that burns.</summary>
	private bool HasFuel(int t)
	{
		if (Grass[t] > 0.1f)
			return true;
		for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
			if (_flammable[_pSprite[p]])
				return true;
		return false;
	}

	private bool IgniteTile(int t)
	{
		if (World.Water[t] != SimWorld.WaterLand || TileBurn[t] > 0f || Scorch[t] > 64)
			return false;
		if (_burnChance[World.Biome[t]] <= 0f || !HasFuel(t))
			return false;
		TileBurn[t] = 0.001f;
		_burningTiles.Add(t);
		return true;
	}

	private void SetOnFire(int p)
	{
		_pBurn[p] = 0.001f;
		_burning.Add(p);
		MarkStrip((int)_pY[p]);
	}

	public bool OnFire(float x, float y)
	{
		if (!World.InBounds((int)x, (int)y))
			return false;
		int t = World.Index((int)x, (int)y);
		if (TileBurn[t] > 0f)
			return true;
		for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
			if (_pBurn[p] > 0f)
				return true;
		return false;
	}

	public bool TileOnFire(int x, int y) => World.InBounds(x, y) && TileBurn[World.Index(x, y)] > 0f;

	/// <summary>Every step: burning tiles spread to their neighbours by burn chance, set their
	/// plants alight and kill what stands in them; burning plants light the ground under them;
	/// burnt-out tiles turn to ash. Lightning strikes now and then (world law "natural disasters").</summary>
	private void FireStep(int a, int b, float dt)
	{
		if (Law("natural_disasters"))
		{
			_lightningIn -= dt;
			if (_lightningIn <= 0f)
			{
				_lightningIn = 40f + (float)_rng.NextDouble() * 80f;
				Lightning();
			}
		}
		BuildingFire(dt);
		if (_burningTiles.Count == 0 && _burning.Count == 0)
			return;
		// Fire spreads less in the cold.
		float damp = 1f - 0.6f * Coldness();

		int plantCount = _burning.Count;
		for (int k = 0; k < plantCount; k++)
		{
			int p = _burning[k];
			if (!_pAlive[p])
				continue;
			_pBurn[p] += dt;
			int t = World.Index((int)_pX[p], (int)_pY[p]);
			if (TileBurn[t] == 0f && _rng.NextDouble() < 2.0 * dt)
				IgniteTile(t);
			if (_pBurn[p] >= BurnSeconds)
			{
				RemovePlant(p);
				PlantsBurned++;
			}
		}
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);

		int tileCount = _burningTiles.Count;
		for (int k = 0; k < tileCount; k++)
		{
			int t = _burningTiles[k];
			TileBurn[t] += dt;
			int x = t % World.Width, y = t / World.Width;
			for (int d = 0; d < 4; d++)
			{
				int nx = x + (d == 0 ? 1 : d == 1 ? -1 : 0), ny = y + (d == 2 ? 1 : d == 3 ? -1 : 0);
				if (!World.InBounds(nx, ny))
					continue;
				int nt = World.Index(nx, ny);
				if (TileBurn[nt] == 0f && _rng.NextDouble() < _burnChance[World.Biome[nt]] * damp * dt)
					IgniteTile(nt);
			}
			for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
				if (_pBurn[p] == 0f && _flammable[_pSprite[p]] && _rng.NextDouble() < 1.5 * dt)
					SetOnFire(p);
			// Wooden buildings next to the flames.
			HeatBuildings(x, y, dt);
			// Creatures caught in the flames.
			_found.Clear();
			Zones.Query(Units, x + 0.5f, y + 0.5f, 0.75f, _found);
			foreach (int u in _found)
				if (Units.Alive[u] && _rng.NextDouble() < 4.0 * dt)
					KillUnit(u, Death.Fire);
			if (TileBurn[t] >= _burnTime[World.Biome[t]])
			{
				TileBurn[t] = 0f;
				Scorch[t] = 255;
				Grass[t] = 0f;
				_scorchChanged.Add(t);
			}
		}
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
	}

	private void Lightning()
	{
		// Strike a random land tile with fuel, preferring biomes that burn well.
		for (int tries = 0; tries < 40; tries++)
		{
			int t = _rng.Next(World.Width * World.Height);
			if (World.Water[t] != SimWorld.WaterLand || !HasFuel(t))
				continue;
			int b = World.Biome[t];
			if (_burnChance[b] < 0.3f && tries < 35)
				continue;
			int x = t % World.Width, y = t / World.Width;
			if (Ignite(x + 0.5f, y + 0.5f, 1.2f) > 0)
				LogEvent($"lightning sets the {_biomeNames[b].ToLower()} ablaze near ({x}, {y}).", "disasters");
			return;
		}
	}

	/// <summary>Ash changes since the last call, as pairs (tile, ash 0..255) for the map.</summary>
	public int[] TakeScorchChanges()
	{
		var seen = new HashSet<int>();
		var pairs = new List<int>();
		foreach (int t in _scorchChanged)
			if (seen.Add(t))
			{
				pairs.Add(t);
				pairs.Add(Scorch[t]);
			}
		_scorchChanged.Clear();
		return pairs.ToArray();
	}
}
