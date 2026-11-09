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
	private float[] _dryness = Array.Empty<float>();
	private readonly List<int> _scorchChanged = new();
	private readonly List<string> _events = new();
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
	public int BurningCount() => _burning.Count;

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

	private void LogEvent(string text) => _events.Add($"Year {Year()}, {SeasonName().ToLower()}: {text}");

	/// <summary>Events since the last call (deaths of species, fires...).</summary>
	public string[] TakeEvents()
	{
		var e = _events.ToArray();
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
		_dryness = new float[_biomeNames.Length];
		for (int b = 0; b < _biomeNames.Length; b++)
		{
			_fertility[b] = Fertility(_biomeNames[b]);
			_dryness[b] = Dryness(_biomeNames[b]);
		}
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

	private static float Fertility(string biome) => biome switch
	{
		"Grassland" or "Flower meadow" => 1f,
		"Hills" or "Jungle" => 0.8f,
		"Forest" or "Swamp" => 0.7f,
		"Savanna" or "Mushroom land" => 0.6f,
		"Taiga" => 0.5f,
		"Tundra" => 0.35f,
		"Cursed land" => 0.2f,
		"Beach" => 0.15f,
		"Desert" or "Mountain" => 0.1f,
		"Snow" => 0.05f,
		_ => 0f,
	};

	/// <summary>How easily fire spreads in a biome.</summary>
	private static float Dryness(string biome) => biome switch
	{
		"Desert" or "Savanna" => 1.4f,
		"Grassland" or "Flower meadow" or "Hills" or "Forest" => 1f,
		"Taiga" or "Volcanic rock" or "Cursed land" => 0.9f,
		"Tundra" or "Mushroom land" => 0.6f,
		"Jungle" => 0.5f,
		"Swamp" or "Snow" => 0.3f,
		_ => 0.8f,
	};

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

	/// <summary>Sets fire to the plants within `radius` tiles of (x, y) (god power, lightning).
	/// Returns how many caught fire.</summary>
	public int Ignite(float x, float y, float radius)
	{
		int n = 0;
		for (int ty = (int)(y - radius); ty <= (int)(y + radius); ty++)
			for (int tx = (int)(x - radius); tx <= (int)(x + radius); tx++)
			{
				if (!World.InBounds(tx, ty))
					continue;
				for (int p = _tileFirst[World.Index(tx, ty)]; p >= 0; p = _pNext[p])
				{
					float dx = _pX[p] - x, dy = _pY[p] - y;
					if (dx * dx + dy * dy <= radius * radius && _pBurn[p] == 0f && _flammable[_pSprite[p]])
					{
						SetOnFire(p);
						n++;
					}
				}
			}
		return n;
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
		for (int p = _tileFirst[World.Index((int)x, (int)y)]; p >= 0; p = _pNext[p])
			if (_pBurn[p] > 0f)
				return true;
		return false;
	}

	/// <summary>Every step: fires burn, spread to nearby plants, kill what stands in them and
	/// leave ash. Lightning strikes now and then (world law "natural disasters").</summary>
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
		if (_burning.Count == 0)
			return;
		float damp = 1f - 0.6f * Coldness();
		int count = _burning.Count;
		for (int k = 0; k < count; k++)
		{
			int p = _burning[k];
			if (!_pAlive[p])
				continue;
			_pBurn[p] += dt;
			int tx = (int)_pX[p], ty = (int)_pY[p];
			int t = World.Index(tx, ty);
			// Spread to plants on the 3x3 tiles around.
			float chance = 0.035f * _dryness[World.Biome[t]] * damp;
			for (int dy = -1; dy <= 1; dy++)
				for (int dx = -1; dx <= 1; dx++)
				{
					if (!World.InBounds(tx + dx, ty + dy))
						continue;
					for (int q = _tileFirst[World.Index(tx + dx, ty + dy)]; q >= 0; q = _pNext[q])
						if (_pBurn[q] == 0f && _flammable[_pSprite[q]] && _rng.NextDouble() < chance)
							SetOnFire(q);
				}
			// Creatures caught in the flames.
			_found.Clear();
			Zones.Query(Units, _pX[p], _pY[p] - 0.3f, 0.8f, _found);
			foreach (int u in _found)
				if (Units.Alive[u] && _rng.NextDouble() < 0.15)
					KillUnit(u, Death.Fire);
			if (_pBurn[p] >= BurnSeconds)
			{
				RemovePlant(p);
				PlantsBurned++;
				Scorch[t] = 255;
				Grass[t] = 0f;
				_scorchChanged.Add(t);
			}
		}
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);
	}

	private void Lightning()
	{
		if (_plantCount == 0)
			return;
		for (int tries = 0; tries < 30; tries++)
		{
			int p = _rng.Next(_plantCap);
			if (!_pAlive[p] || _pBurn[p] > 0f || !_flammable[_pSprite[p]])
				continue;
			string biome = _biomeNames[World.Biome[World.Index((int)_pX[p], (int)_pY[p])]];
			if (_dryness[World.Biome[World.Index((int)_pX[p], (int)_pY[p])]] < 0.6f && tries < 25)
				continue;
			Ignite(_pX[p], _pY[p], 1.5f);
			LogEvent($"lightning sets the {biome.ToLower()} ablaze near ({(int)_pX[p]}, {(int)_pY[p]}).");
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
