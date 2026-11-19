using System;
using System.Collections.Generic;

namespace Animundi.Sim;

/// <summary>
/// Disasters (0.7, docs/NATURE.md): earthquakes, eruptions, floods, tornadoes, droughts and
/// wildfires. Each is one action with three triggers, as in WorldBox: nature itself (the laws
/// "natural disasters" and "eruptions"), an angry spirit (Spirits.cs) and the player's hand
/// (the powers of the Nature tab).
///
/// - Earthquake: buildings fall to ruins, people are crushed, lairs cave in.
/// - Eruption: lava bursts out and flows downhill for a while, burning and burying what it
///   meets; years later it cools into volcanic rock. Demons may crawl out of the fire.
/// - Flood: the low land around the water goes under for a while: creatures drown, wheat is
///   lost, wooden buildings are swept away; the silt it leaves is green the next spring.
/// - Tornado: a whirlwind that wanders, throws creatures, uproots plants and tears buildings.
/// - Drought: for a year or more the grass withers, nothing grows, wheat fails, fire runs.
/// - Wildfire: a great fire breaks out in dry woods or grass.
///
/// The kingdoms that live through one remember it, and make myths and gods of it (Religion.cs).
/// </summary>
public partial class Simulation
{
	public static readonly string[] DisasterKinds = { "earthquake", "eruption", "flood", "tornado", "drought", "wildfire" };

	public sealed class Disaster
	{
		public string Kind = "", Cause = "nature", Place = "";
		public float X, Y, Radius, VX, VY;
		public double Start, Until, NextTick;
		public int Year, Killed, Ruined;
		/// <summary>Flooded or parched tiles; for an eruption, the lava it has poured.</summary>
		public readonly List<int> Tiles = new();
		/// <summary>Tiles of lava an eruption can still pour.</summary>
		public int Budget;
		public bool Over;
	}

	/// <summary>Disasters underway, and the last ones that ended (for the Nature book).</summary>
	public readonly List<Disaster> Disasters = new();
	public readonly List<Disaster> PastDisasters = new();
	/// <summary>How many disasters cover each tile: water over the land, and drought.</summary>
	public byte[] Flooded = Array.Empty<byte>();
	public byte[] Parched = Array.Empty<byte>();
	private Random _disasterRng = new(1);
	private double _nextDisaster;
	// Lava poured by eruptions, and when each tile cools into volcanic rock.
	private readonly List<(int tile, double at)> _cooling = new();
	private int _bLava = -1, _bVolcanic = -1;
	/// <summary>Disasters since the world started, by kind.</summary>
	public readonly Dictionary<string, int> DisasterCounts = new();

	private void SetupDisasters(int seed)
	{
		Disasters.Clear();
		PastDisasters.Clear();
		DisasterCounts.Clear();
		_cooling.Clear();
		int n = World.Width * World.Height;
		Flooded = new byte[n];
		Parched = new byte[n];
		_disasterRng = new Random(seed ^ 0xd15a);
		_nextDisaster = YearSeconds * (3.0 + 3.0 * _disasterRng.NextDouble());
		_bLava = Array.IndexOf(_biomeNames, "Lava");
		_bVolcanic = Array.IndexOf(_biomeNames, "Volcanic rock");
	}

	// ------------------------------------------------------------------ every half second

	private void DisasterStep(float dt)
	{
		if (World == null)
			return;
		for (int k = Disasters.Count - 1; k >= 0; k--)
		{
			var d = Disasters[k];
			switch (d.Kind)
			{
				case "eruption":
					LavaFlows(d);
					break;
				case "flood":
					FloodDrowns(d, dt);
					break;
				case "tornado":
					TornadoMoves(d, dt);
					break;
				case "drought":
					// Dry land catches fire by itself in the hot months.
					if (Season() == 1 && d.Tiles.Count > 0 && _disasterRng.NextDouble() < 0.02 * dt)
						IgniteTile(d.Tiles[_disasterRng.Next(d.Tiles.Count)]);
					break;
			}
			if (d.Over || Scheduler.Time >= d.Until)
			{
				EndDisaster(d);
				Disasters.RemoveAt(k);
			}
		}
		// Lava cools into rock.
		for (int k = _cooling.Count - 1; k >= 0; k--)
			if (Scheduler.Time >= _cooling[k].at)
			{
				int t = _cooling[k].tile;
				if (World.Biome[t] == _bLava && _bVolcanic >= 0)
					SetBiome(t, _bVolcanic);
				_cooling.RemoveAt(k);
			}
		if (Scheduler.Time >= _nextDisaster)
		{
			_nextDisaster = Scheduler.Time + YearSeconds * (1.5 + 3.0 * _disasterRng.NextDouble());
			NaturalDisaster();
		}
		PlagueWatch(dt);
	}

	/// <summary>Nature strikes on its own: a kind drawn by the season and the laws, somewhere
	/// that suits it (half the time near a village: the world tells stories about people).</summary>
	private void NaturalDisaster()
	{
		bool weather = Law("natural_disasters"), deep = Law("eruptions");
		int season = Season();
		var kinds = new List<(string kind, float weight)>();
		if (weather)
		{
			kinds.Add(("tornado", season <= 1 ? 1.4f : 0.5f));
			kinds.Add(("flood", season == 0 || season == 2 ? 1.4f : 0.5f));
			kinds.Add(("drought", season <= 1 ? 1f : 0f));
			kinds.Add(("wildfire", season == 1 || season == 2 ? 1.2f : 0.2f));
		}
		if (deep)
		{
			kinds.Add(("earthquake", 1f));
			kinds.Add(("eruption", 1.5f));
		}
		float total = 0f;
		foreach (var (_, w) in kinds)
			total += w;
		if (total <= 0f)
			return;
		// A kind with nowhere to happen (no volcano, no shore) gives way to another draw.
		for (int tries = 0; tries < 4; tries++)
		{
			float r = (float)_disasterRng.NextDouble() * total;
			string kind = kinds[^1].kind;
			foreach (var (name, w) in kinds)
			{
				r -= w;
				if (r <= 0f)
				{
					kind = name;
					break;
				}
			}
			int t = DisasterSpot(kind);
			if (t < 0)
				continue;
			float radius = kind switch
			{
				"earthquake" => 5f + 4f * (float)_disasterRng.NextDouble(), "flood" => 6f + 4f * (float)_disasterRng.NextDouble(),
				"drought" => 10f + 6f * (float)_disasterRng.NextDouble(), "eruption" => 1f + 2f * (float)_disasterRng.NextDouble(),
				"wildfire" => 2.5f, _ => 1.8f,
			};
			if (StartDisaster(kind, t % World.Width + 0.5f, t / World.Width + 0.5f, radius, "nature") != null)
				return;
		}
	}

	/// <summary>Whether a disaster of this kind can start on land tile t.</summary>
	private bool DisasterFits(string kind, int t)
	{
		if (World.Water[t] != SimWorld.WaterLand)
			return false;
		int b = World.Biome[t];
		string biome = _biomeNames[b];
		switch (kind)
		{
			case "eruption":
				return b == _bLava || b == _bVolcanic;
			case "flood":
			{
				int w = _nearestWater[t];
				return w >= 0 && Math.Abs(w % World.Width - t % World.Width) + Math.Abs(w / World.Width - t / World.Width) <= 3;
			}
			case "tornado":
				return biome is "Grassland" or "Flower meadow" or "Savanna" or "Desert" or "Hills" or "Tundra" or "Beach";
			case "drought":
				return _fertility[b] >= 0.3f && Parched[t] == 0;
			case "wildfire":
				return _burnChance[b] >= 0.1f && HasFuel(t) && Scorch[t] == 0;
			default:
				return true;
		}
	}

	/// <summary>A land tile where a disaster of this kind can start, or -1.</summary>
	private int DisasterSpot(string kind)
	{
		var alive = Villages.FindAll(v => v.Alive);
		for (int tries = 0; tries < 60; tries++)
		{
			int x, y;
			if (tries < 30 && alive.Count > 0 && kind != "eruption")
			{
				var v = alive[_disasterRng.Next(alive.Count)];
				x = v.X + _disasterRng.Next(-12, 13);
				y = v.Y + _disasterRng.Next(-12, 13);
			}
			else
			{
				x = _disasterRng.Next(World.Width);
				y = _disasterRng.Next(World.Height);
			}
			if (World.InBounds(x, y) && DisasterFits(kind, World.Index(x, y)))
				return World.Index(x, y);
		}
		if (kind == "eruption")
		{
			// Volcanoes are rare (only the player and the mountains' wrath make them): look for one.
			var tiles = new List<int>();
			for (int t = 0; t < World.Biome.Length; t++)
				if (World.Water[t] == SimWorld.WaterLand && (World.Biome[t] == _bLava || World.Biome[t] == _bVolcanic))
					tiles.Add(t);
			if (tiles.Count > 0)
				return tiles[_disasterRng.Next(tiles.Count)];
		}
		return -1;
	}

	// ------------------------------------------------------------------ starting one

	private static string DisasterPast(string kind) => kind switch
	{
		"earthquake" => "the earth shook", "eruption" => "the ground burst open in fire", "flood" => "the waters rose",
		"tornado" => "a whirlwind came down", "drought" => "a drought withered the land", _ => "a wildfire raged",
	};

	/// <summary>What a kingdom remembers of a disaster, by kind (Religion.cs MemoryDomains).</summary>
	private static string DisasterMemory(string kind) => kind switch
	{
		"earthquake" => "quake", "eruption" => "eruption", "flood" => "flood", "tornado" => "whirlwind", "drought" => "drought", _ => "fire",
	};

	/// <summary>A disaster of `kind` starts at (x, y), in tiles. `cause` is "nature", "player" or
	/// the full name of the spirit that sends it. Returns it, or null when it cannot happen
	/// there (the sea, nothing to burn).</summary>
	private Disaster StartDisaster(string kind, float x, float y, float radius, string cause)
	{
		if (World == null || !World.IsLandAt(x, y) || Array.IndexOf(DisasterKinds, kind) < 0)
			return null;
		var d = new Disaster
		{
			Kind = kind, Cause = cause, X = x, Y = y, Radius = radius, Start = Scheduler.Time, Until = Scheduler.Time + 3.0,
			Year = Year(), Place = PlaceNear(x, y),
		};
		string sent = cause == "nature" || cause == "player" ? "" : $"{cause}, is angry: ";
		string text;
		switch (kind)
		{
			case "earthquake":
				Quake(d);
				text = $"{sent}the earth shakes {d.Place}: {d.Ruined} buildings fall, {d.Killed} are crushed.";
				break;
			case "eruption":
				Erupt(d);
				text = $"{sent}the ground bursts open in fire {d.Place}: lava pours out.";
				break;
			case "flood":
				if (!Flood(d))
					return null;
				text = $"{sent}the waters rise {d.Place}: {d.Tiles.Count} tiles of land go under.";
				break;
			case "tornado":
			{
				double a = _disasterRng.NextDouble() * Math.PI * 2;
				d.VX = (float)Math.Cos(a) * 1.3f;
				d.VY = (float)Math.Sin(a) * 1.3f;
				d.Until = Scheduler.Time + 18.0 + 12.0 * _disasterRng.NextDouble();
				text = $"{sent}a whirlwind comes down {d.Place}.";
				break;
			}
			case "drought":
				Parch(d);
				d.Until = Scheduler.Time + YearSeconds * (1.0 + 0.6 * _disasterRng.NextDouble());
				text = $"{sent}a drought sets in {d.Place}: the grass withers and the wheat fails.";
				break;
			default:
			{
				int lit = Ignite(x, y, radius);
				if (lit == 0)
					return null;
				string biome = _biomeNames[World.Biome[World.Index((int)x, (int)y)]].ToLower();
				text = $"{sent}a wildfire breaks out in the {biome} {d.Place}.";
				break;
			}
		}
		DisasterCounts[kind] = (DisasterCounts.TryGetValue(kind, out int c) ? c : 0) + 1;
		LogEvent(text, "disasters");
		// The kingdoms that see it remember it; the spirit's own deeds are remembered as its own.
		if (cause == "nature" || cause == "player")
			RememberDisaster(d, $"{DisasterPast(kind)} {d.Place}");
		if (kind == "earthquake" || kind == "wildfire")
		{
			d.Over = true;
			Keep(d);
		}
		else
			Disasters.Add(d);
		return d;
	}

	private void RememberDisaster(Disaster d, string text)
	{
		float reach = d.Radius + 12f;
		var seen = new HashSet<int>();
		foreach (var v in Villages)
			if (v.Alive && v.Kingdom >= 0 && (v.X - d.X) * (v.X - d.X) + (v.Y - d.Y) * (v.Y - d.Y) <= reach * reach && seen.Add(v.Kingdom))
				Remember(v.Kingdom, DisasterMemory(d.Kind), text, d.Kind == "wildfire" ? 1.5f : 2.5f);
	}

	private void Keep(Disaster d)
	{
		PastDisasters.Add(d);
		if (PastDisasters.Count > 12)
			PastDisasters.RemoveAt(0);
	}

	private void EndDisaster(Disaster d)
	{
		d.Over = true;
		switch (d.Kind)
		{
			case "eruption":
				foreach (int t in d.Tiles)
					_cooling.Add((t, Scheduler.Time + YearSeconds * (1.5 + 1.5 * _disasterRng.NextDouble())));
				LogEvent($"the fire {d.Place} grows quiet: {d.Tiles.Count} tiles lie under lava, {d.Killed} dead, {d.Ruined} buildings lost.", "disasters");
				break;
			case "flood":
				foreach (int t in d.Tiles)
				{
					if (Flooded[t] > 0)
						Flooded[t]--;
					_overlayChanged.Add(t);
					// The silt it leaves: ash washed away, green grass.
					if (Scorch[t] > 0)
					{
						Scorch[t] = 0;
						_scorchChanged.Add(t);
					}
					Grass[t] = _fertility[World.Biome[t]];
				}
				LogEvent($"the waters draw back {d.Place}: {d.Killed} drowned, {d.Ruined} buildings swept away.", "disasters");
				break;
			case "tornado":
				LogEvent($"the whirlwind dies out {PlaceNear(d.X, d.Y)}: {d.Killed} dead, {d.Ruined} buildings torn down.", "disasters");
				break;
			case "drought":
				foreach (int t in d.Tiles)
				{
					if (Parched[t] > 0)
						Parched[t]--;
					_overlayChanged.Add(t);
				}
				LogEvent($"the rains return {d.Place}: the drought is over.", "disasters");
				break;
		}
		Keep(d);
	}

	// ------------------------------------------------------------------ what each one does

	/// <summary>Kills a creature in a disaster (legends shrug them off). True when it died.</summary>
	private bool DisasterKills(Disaster d, int i)
	{
		if (!Units.Alive[i] || Assets.Species[Units.Species[i]].IsLegend)
			return false;
		KillUnit(i, Death.Disaster);
		d.Killed++;
		return true;
	}

	private bool Ruin(Disaster d, int b)
	{
		var bld = Buildings[b];
		if (!bld.Alive || bld.Type == _tRuin)
			return false;
		ToRuin(b);
		d.Ruined++;
		return true;
	}

	private void Quake(Disaster d)
	{
		float r = d.Radius;
		for (int b = 0; b < Buildings.Count; b++)
		{
			var bld = Buildings[b];
			if (!bld.Alive || bld.Type == _tRuin)
				continue;
			float dist = MathF.Sqrt((bld.X + 0.5f - d.X) * (bld.X + 0.5f - d.X) + (bld.Y + 0.5f - d.Y) * (bld.Y + 0.5f - d.Y));
			// Timber bends where stone breaks.
			if (dist <= r && _disasterRng.NextDouble() < (Rec(b).Wooden ? 0.5 : 0.7) * (1f - dist / r * 0.7f))
				Ruin(d, b);
		}
		foreach (int i in UnitsWithin(d.X, d.Y, r).ToArray())
		{
			float dist = MathF.Sqrt((Units.X[i] - d.X) * (Units.X[i] - d.X) + (Units.Y[i] - d.Y) * (Units.Y[i] - d.Y));
			if (_disasterRng.NextDouble() < 0.14 * (1f - dist / r * 0.7f))
				DisasterKills(d, i);
		}
		DamageLairs(d.X, d.Y, r * 0.6f, 1f, "caves in");
	}

	/// <summary>Changes the biome of a land tile: its plants go, fire dies, the map is told
	/// (the biome brush and eruptions).</summary>
	private void SetBiome(int t, int b)
	{
		World.Biome[t] = (byte)b;
		while (_tileFirst[t] >= 0)
		{
			MarkStrip((int)_pY[_tileFirst[t]]);
			RemovePlant(_tileFirst[t]);
		}
		TileBurn[t] = 0f;
		Grass[t] = Math.Min(Grass[t], _fertility[b]);
		_biomeChanged.Add(t);
	}

	/// <summary>Lava takes a tile: what stands there dies (but creatures of the fire), the
	/// building on it is lost, fields and roads are buried, the land around catches fire.</summary>
	private void Lava(Disaster d, int t)
	{
		if (World.Water[t] != SimWorld.WaterLand || World.Biome[t] == _bLava || _bLava < 0)
			return;
		SetBiome(t, _bLava);
		d.Tiles.Add(t);
		int x = t % World.Width, y = t / World.Width;
		int b = _buildingAt[t];
		if (b >= 0)
			Ruin(d, b);
		if (_ground[t] != 0)
			BuryField(t);
		_found.Clear();
		Zones.Query(Units, x + 0.5f, y + 0.5f, 0.8f, _found);
		foreach (int i in _found.ToArray())
			if (Units.Alive[i] && !Assets.Species[Units.Species[i]].Natural.ContainsKey("Lava"))
				DisasterKills(d, i);
		for (int k = 0; k < 4; k++)
		{
			int nx = x + (k == 0 ? 1 : k == 1 ? -1 : 0), ny = y + (k == 2 ? 1 : k == 3 ? -1 : 0);
			if (World.InBounds(nx, ny))
				IgniteTile(World.Index(nx, ny));
		}
		DamageLairs(x + 0.5f, y + 0.5f, 0.8f, 1f, "is buried in lava");
	}

	/// <summary>A field or a road is lost: the ground goes back to the wild.</summary>
	private void BuryField(int t)
	{
		if (_ground[t] == GroundField)
			foreach (var village in Villages)
				village.Fields.Remove(t);
		SetGround(t, 0);
		_wheat[t] = 0f;
	}

	private void Erupt(Disaster d)
	{
		d.Until = Scheduler.Time + 26.0 + 8.0 * _disasterRng.NextDouble();
		d.Budget = (int)(16 + 12 * d.Radius);
		// The mouth: lava in the middle, a ring of black rock, ash all around.
		TilesWithin(d.X, d.Y, Math.Max(1.1f, d.Radius * 0.6f), t => Lava(d, t));
		if (_bVolcanic >= 0)
			TilesWithin(d.X, d.Y, d.Radius * 0.6f + 1.6f, t =>
			{
				if (World.Water[t] == SimWorld.WaterLand && World.Biome[t] != _bLava && World.Biome[t] != _bVolcanic && _buildingAt[t] < 0)
					SetBiome(t, _bVolcanic);
			});
		TilesWithin(d.X, d.Y, d.Radius + 5f, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand || World.Biome[t] == _bLava || _disasterRng.NextDouble() > 0.6)
				return;
			Scorch[t] = (byte)Math.Max(Scorch[t], (byte)200);
			Grass[t] = 0f;
			_scorchChanged.Add(t);
		});
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);
		// What lives in the fire comes out with it.
		int demon = Assets.SpeciesIndex("demon");
		if (demon >= 0 && Law("monsters") && _disasterRng.NextDouble() < 0.5 && d.Tiles.Count > 0)
		{
			int n = 2 + _disasterRng.Next(2);
			for (int k = 0; k < n; k++)
			{
				int t = d.Tiles[_disasterRng.Next(d.Tiles.Count)];
				SpawnUnit(demon, t % World.Width + 0.5f, t / World.Width + 0.5f, false);
			}
			LogEvent($"demons crawl out of the fire {d.Place}.", "nature");
		}
	}

	/// <summary>Lava flows: now and then a tile of the flow spills onto a neighbour that is not
	/// higher (downhill first), until the eruption has poured what it had.</summary>
	private void LavaFlows(Disaster d)
	{
		if (d.Budget <= 0 || d.Tiles.Count == 0)
		{
			d.Over = d.Budget <= 0;
			return;
		}
		if (Scheduler.Time < d.NextTick)
			return;
		d.NextTick = Scheduler.Time + 0.45;
		for (int tries = 0; tries < 6; tries++)
		{
			// The newest lava flows most.
			int from = d.Tiles[d.Tiles.Count - 1 - _disasterRng.Next(Math.Min(d.Tiles.Count, 12))];
			int x = from % World.Width, y = from / World.Width;
			int best = -1, bestLevel = World.Level[from] + 1;
			int first = _disasterRng.Next(4);
			for (int k = 0; k < 4; k++)
			{
				int dir = (first + k) % 4;
				int nx = x + (dir == 0 ? 1 : dir == 1 ? -1 : 0), ny = y + (dir == 2 ? 1 : dir == 3 ? -1 : 0);
				if (!World.IsLand(nx, ny))
					continue;
				int nt = World.Index(nx, ny);
				if (World.Biome[nt] != _bLava && World.Level[nt] < bestLevel)
				{
					bestLevel = World.Level[nt];
					best = nt;
				}
			}
			if (best < 0)
				continue;
			Lava(d, best);
			d.Budget--;
			_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
			return;
		}
	}

	/// <summary>The water spreads from the shore over the lowest land around, a few tiles deep;
	/// with no water near, a cloudburst floods the hollow where it falls. False when nothing
	/// goes under.</summary>
	private bool Flood(Disaster d)
	{
		float r = d.Radius;
		int low = int.MaxValue;
		var seeds = new List<int>();
		TilesWithin(d.X, d.Y, r, t =>
		{
			if (World.Water[t] == SimWorld.WaterLand)
				low = Math.Min(low, World.Level[t]);
		});
		TilesWithin(d.X, d.Y, r, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand || World.Level[t] != low || World.Biome[t] == _bLava)
				return;
			int x = t % World.Width, y = t / World.Width;
			for (int k = 0; k < 4; k++)
			{
				int nx = x + (k == 0 ? 1 : k == 1 ? -1 : 0), ny = y + (k == 2 ? 1 : k == 3 ? -1 : 0);
				if (World.InBounds(nx, ny) && World.Water[World.Index(nx, ny)] != SimWorld.WaterLand)
				{
					seeds.Add(t);
					return;
				}
			}
		});
		int reach = (int)Math.Max(2f, r * 0.55f);
		if (seeds.Count == 0)
		{
			int here = World.Index((int)d.X, (int)d.Y);
			if (World.Level[here] != low)
				return false;
			seeds.Add(here);
			reach = (int)Math.Max(2f, r * 0.8f);
		}
		// Breadth-first from the shore, over land of the same low level.
		var depth = new Dictionary<int, int>();
		var queue = new Queue<int>();
		foreach (int s in seeds)
			if (depth.TryAdd(s, 0))
				queue.Enqueue(s);
		while (queue.Count > 0)
		{
			int t = queue.Dequeue();
			d.Tiles.Add(t);
			if (depth[t] >= reach)
				continue;
			int x = t % World.Width, y = t / World.Width;
			for (int k = 0; k < 4; k++)
			{
				int nx = x + (k == 0 ? 1 : k == 1 ? -1 : 0), ny = y + (k == 2 ? 1 : k == 3 ? -1 : 0);
				if (!World.IsLand(nx, ny))
					continue;
				int nt = World.Index(nx, ny);
				float dx = nx + 0.5f - d.X, dy = ny + 0.5f - d.Y;
				if (World.Level[nt] == low && World.Biome[nt] != _bLava && dx * dx + dy * dy <= r * r && depth.TryAdd(nt, depth[t] + 1))
					queue.Enqueue(nt);
			}
		}
		if (d.Tiles.Count == 0)
			return false;
		d.Until = Scheduler.Time + 16.0 + d.Radius;
		foreach (int t in d.Tiles)
		{
			if (Flooded[t] < 255)
				Flooded[t]++;
			_overlayChanged.Add(t);
			// Water puts fires out, drowns the wheat and sweeps wooden walls away.
			TileBurn[t] = 0f;
			for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
				if (_pBurn[p] > 0f)
				{
					_pBurn[p] = 0f;
					MarkStrip((int)_pY[p]);
				}
			if (_ground[t] == GroundField)
				_wheat[t] = 0f;
			int b = _buildingAt[t];
			if (b >= 0 && Buildings[b].Alive)
			{
				Buildings[b].Burning = 0f;
				if (Rec(b).Wooden && _disasterRng.NextDouble() < 0.3)
					Ruin(d, b);
			}
		}
		_burningTiles.RemoveAll(t => TileBurn[t] == 0f);
		_burning.RemoveAll(p => !_pAlive[p] || _pBurn[p] == 0f);
		return true;
	}

	private void FloodDrowns(Disaster d, float dt)
	{
		foreach (int i in UnitsWithin(d.X, d.Y, d.Radius + 1f).ToArray())
		{
			int t = World.Index((int)Units.X[i], (int)Units.Y[i]);
			if (Flooded[t] > 0 && _disasterRng.NextDouble() < 0.025 * dt)
				DisasterKills(d, i);
		}
	}

	/// <summary>The whirlwind wanders over the land, turning as it goes; what it passes over is
	/// thrown, uprooted or torn down.</summary>
	private void TornadoMoves(Disaster d, float dt)
	{
		double turn = (_disasterRng.NextDouble() - 0.5) * 1.6 * dt;
		float cos = (float)Math.Cos(turn), sin = (float)Math.Sin(turn);
		(d.VX, d.VY) = (d.VX * cos - d.VY * sin, d.VX * sin + d.VY * cos);
		float nx = d.X + d.VX * dt, ny = d.Y + d.VY * dt;
		if (World.IsLandAt(nx, ny))
		{
			d.X = nx;
			d.Y = ny;
		}
		else
		{
			// The sea turns it back.
			d.VX = -d.VX;
			d.VY = -d.VY;
		}
		float r = d.Radius;
		foreach (int i in UnitsWithin(d.X, d.Y, r).ToArray())
		{
			if (Assets.Species[Units.Species[i]].IsLegend || _disasterRng.NextDouble() > 0.5 * dt)
				continue;
			if (_disasterRng.NextDouble() < 0.15)
			{
				DisasterKills(d, i);
				continue;
			}
			// Thrown a few tiles away.
			double a = _disasterRng.NextDouble() * Math.PI * 2;
			float far = 2f + 3f * (float)_disasterRng.NextDouble();
			float tx = Units.X[i] + (float)Math.Cos(a) * far, ty = Units.Y[i] + (float)Math.Sin(a) * far;
			if (World.IsLandAt(tx, ty))
			{
				Units.X[i] = Units.TargetX[i] = tx;
				Units.Y[i] = Units.TargetY[i] = ty;
			}
		}
		TilesWithin(d.X, d.Y, r, t =>
		{
			for (int p = _tileFirst[t]; p >= 0;)
			{
				int next = _pNext[p];
				if (_disasterRng.NextDouble() < 0.8 * dt)
					RemovePlant(p);
				p = next;
			}
			if (_ground[t] == GroundField)
				_wheat[t] = 0f;
			int b = _buildingAt[t];
			if (b >= 0 && Buildings[b].Alive && _disasterRng.NextDouble() < (Rec(b).Wooden ? 0.6 : 0.15) * dt)
				Ruin(d, b);
		});
		DamageLairs(d.X, d.Y, r, 0.3f * dt, "is torn apart by the wind");
	}

	private void Parch(Disaster d)
	{
		TilesWithin(d.X, d.Y, d.Radius, t =>
		{
			if (World.Water[t] != SimWorld.WaterLand)
				return;
			d.Tiles.Add(t);
			if (Parched[t] < 255)
				Parched[t]++;
			Grass[t] *= 0.35f;
			_overlayChanged.Add(t);
		});
	}

	/// <summary>Ends the droughts whose land comes within `radius` of (x, y) (a negative radius:
	/// (x, y) must be that deep inside): rain, a spirit's gift or the player's.</summary>
	private int EndDroughts(float x, float y, float radius)
	{
		int ended = 0;
		foreach (var d in Disasters)
		{
			float reach = Math.Max(0f, d.Radius + radius);
			if (d.Kind == "drought" && !d.Over && (d.X - x) * (d.X - x) + (d.Y - y) * (d.Y - y) <= reach * reach)
			{
				d.Over = true;
				ended++;
			}
		}
		return ended;
	}

	// ------------------------------------------------------------------ the player

	/// <summary>The player's disasters (Nature tab): `kind` is one of DisasterKinds, the brush
	/// gives its size. Returns 1 when it happened, 0 when it cannot there.</summary>
	public int PowerDisaster(string kind, float x, float y, float radius)
	{
		float size = kind switch
		{
			"earthquake" => 4f + radius * 1.2f, "flood" => 4f + radius * 1.2f, "drought" => 6f + radius * 2f,
			"eruption" => Math.Clamp(radius * 0.6f, 1f, 4f), "wildfire" => Math.Max(2f, radius), _ => 1.8f,
		};
		var d = StartDisaster(kind, x, y, size, "player");
		if (d == null)
			return 0;
		// The spirit of that land feels the hand that struck it.
		Grieve(World.Index((int)x, (int)y), 4f, "struck");
		GodActs(kind, x, y, size, 1);
		return 1;
	}

	// ------------------------------------------------------------------ queries (HUD, tests)

	/// <summary>Disasters underway, then the last that ended: kind, place, cause, year, killed,
	/// ruined, tiles, underway, x, y, radius.</summary>
	public Godot.Collections.Array DisasterTable()
	{
		var list = new Godot.Collections.Array();
		void Row(Disaster d, bool underway) => list.Add(new Godot.Collections.Dictionary
		{
			["kind"] = d.Kind, ["place"] = d.Place, ["cause"] = d.Cause, ["year"] = d.Year, ["killed"] = d.Killed, ["ruined"] = d.Ruined,
			["tiles"] = d.Tiles.Count, ["underway"] = underway, ["x"] = d.X, ["y"] = d.Y, ["radius"] = d.Radius,
			["left"] = underway ? (float)Math.Max(0.0, d.Until - Scheduler.Time) : 0f,
		});
		foreach (var d in Disasters)
			Row(d, true);
		for (int k = PastDisasters.Count - 1; k >= 0; k--)
			Row(PastDisasters[k], false);
		return list;
	}

	/// <summary>Name of the biome of tile (x, y), as the simulation has it now.</summary>
	public string BiomeAt(int x, int y) => World.InBounds(x, y) ? _biomeNames[World.Biome[World.Index(x, y)]] : "";

	public bool TileFlooded(int x, int y) => World.InBounds(x, y) && Flooded[World.Index(x, y)] > 0;
	public bool TileParched(int x, int y) => World.InBounds(x, y) && Parched[World.Index(x, y)] > 0;

	/// <summary>Makes nature strike now (tests and tools): one natural disaster, by the laws.</summary>
	public void NaturalDisasterNow() => NaturalDisaster();

	/// <summary>Seconds of simulated time left for every disaster underway (tests): ends them.</summary>
	public void EndDisastersNow()
	{
		foreach (var d in Disasters)
			d.Until = Scheduler.Time;
	}

	/// <summary>Makes poured lava cool now (tests).</summary>
	public void CoolLavaNow()
	{
		for (int k = 0; k < _cooling.Count; k++)
			_cooling[k] = (_cooling[k].tile, Scheduler.Time);
	}
}
