using System;
using System.Collections.Generic;
using Godot;

namespace Animundi.Sim;

/// <summary>
/// Villages (docs/VILLAGES.md): territory, buildings and the building plan, stores, fields,
/// roads, fire in buildings, watch towers and settlers, following WorldBox's rules.
///
/// - A village owns zones of 8x8 tiles: 3x3 when it is founded, one more next to its land every
///   month while it grows. It builds only on its own land; its borders are drawn on the map.
/// - Buildings come from data/buildings.json. Once a month a village may start one building or
///   one upgrade: homes first when people run short of them, else the first building of the list
///   it has the people, buildings, goods and a place for.
/// - Stores: food, wood, stone, metal and gold, plus tools and weapons made by the blacksmith.
/// - Jobs are handed out every two seconds by what the village lacks (Jobs.cs does the work).
/// </summary>
public partial class Simulation
{
	public const int ZoneSize = 8;
	/// <summary>Seconds between two building plans: a month.</summary>
	public const float PlanSeconds = YearSeconds / 12f;

	public sealed class Village
	{
		public string Name;
		public int Species;
		public int X, Y;
		public float Food, Wood, Stone, Metal, Gold;
		public int Tools, Weapons;
		public int Population, Houses;
		public bool Alive = true;
		public int Founded;
		/// <summary>The building being built or upgraded, or -1 (one at a time).</summary>
		public int Site = -1;
		public double NextPlan;
		public double NextSettlers;
		/// <summary>Territory colour: the people's colour, a shade per village.</summary>
		public Color Color;
		public readonly List<int> Zones = new();
		public readonly List<int> Buildings = new();
		public readonly List<int> Fields = new();
		/// <summary>Tiles where road builders still have to lay a road.</summary>
		public readonly List<int> RoadPlan = new();
		/// <summary>Village it was founded from, or -1.</summary>
		public int Mother = -1;
	}

	public sealed class Building
	{
		/// <summary>Index in data/buildings.json (AssetLibrary.Buildings).</summary>
		public int Type;
		public int X, Y;
		public int Village;
		/// <summary>0..1 while it is built or upgraded; 1 when it stands.</summary>
		public float Progress = 1f;
		/// <summary>The building it is being upgraded to, or -1.</summary>
		public int UpgradeTo = -1;
		/// <summary>Seconds it has been burning (0 = not on fire) and how much of it is left.</summary>
		public float Burning;
		public float Health = 1f;
		/// <summary>Ruins crumble away at this time.</summary>
		public double CrumbleAt;
		public bool Alive = true;
		public bool Done => Progress >= 1f;
	}

	public readonly List<Village> Villages = new();
	public readonly List<Building> Buildings = new();
	// Building on each tile, or -1.
	private int[] _buildingAt = Array.Empty<int>();
	// Territory: owner village of each zone, or -1.
	private int _zw, _zh;
	private int[] _zoneOwner = Array.Empty<int>();
	// Ground made by people on each tile: 0 nothing, 1 road, 2 field; and the wheat on fields
	// (0 = bare soil, up to 1 = ripe).
	private byte[] _ground = Array.Empty<byte>();
	private float[] _wheat = Array.Empty<float>();
	public const byte GroundRoad = 1, GroundField = 2;
	private readonly HashSet<int> _overlayChanged = new();
	// Building types used by the rules below.
	private int _tBonfire, _tHut, _tStockpile, _tWell, _tWindmill, _tMine, _tDock, _tTownHall, _tBarracks,
		_tTower, _tDummy, _tRuin;
	private readonly HashSet<int> _houseTypes = new();
	private readonly HashSet<int> _storeTypes = new();

	public int TowerKills { get; private set; }
	public int BuildingsBurned { get; private set; }
	public int SettlersSent { get; private set; }

	private void SetupVillages()
	{
		Villages.Clear();
		Buildings.Clear();
		_buildingAt = new int[World.Width * World.Height];
		Array.Fill(_buildingAt, -1);
		_zw = (World.Width + ZoneSize - 1) / ZoneSize;
		_zh = (World.Height + ZoneSize - 1) / ZoneSize;
		_zoneOwner = new int[_zw * _zh];
		Array.Fill(_zoneOwner, -1);
		_ground = new byte[World.Width * World.Height];
		_wheat = new float[World.Width * World.Height];
		_overlayChanged.Clear();
		TowerKills = BuildingsBurned = SettlersSent = 0;
		int T(string id) => Assets.BuildingIndex(id);
		_tBonfire = T("bonfire");
		_tHut = T("hut");
		_tStockpile = T("stockpile");
		_tWell = T("well");
		_tWindmill = T("windmill");
		_tMine = T("mine");
		_tDock = T("dock");
		_tTownHall = T("town_hall");
		_tBarracks = T("barracks");
		_tTower = T("watch_tower");
		_tDummy = T("dummy");
		_tRuin = T("ruin");
		_houseTypes.Clear();
		foreach (var id in new[] { "hut", "house", "stone_house", "big_house" })
			_houseTypes.Add(T(id));
		_storeTypes.Clear();
		foreach (var id in new[] { "bonfire", "stockpile", "town_hall" })
			_storeTypes.Add(T(id));
	}

	private BuildingRecord Rec(int b) => Assets.Buildings[Buildings[b].Type];

	// ------------------------------------------------------------------ territory

	private int ZoneOf(int x, int y) => y / ZoneSize * _zw + x / ZoneSize;

	/// <summary>The village that owns tile (x, y), or -1.</summary>
	public int OwnerAt(int x, int y) => World.InBounds(x, y) ? _zoneOwner[ZoneOf(x, y)] : -1;

	private bool Owns(int v, int x, int y) => OwnerAt(x, y) == v;

	private void ClaimZone(int v, int z)
	{
		_zoneOwner[z] = v;
		Villages[v].Zones.Add(z);
		MarkZone(z);
	}

	private void MarkZone(int z)
	{
		int x0 = z % _zw * ZoneSize, y0 = z / _zw * ZoneSize;
		for (int y = y0; y < y0 + ZoneSize; y++)
			for (int x = x0; x < x0 + ZoneSize; x++)
				if (World.InBounds(x, y))
					_overlayChanged.Add(World.Index(x, y));
	}

	private int ZoneLand(int z)
	{
		int x0 = z % _zw * ZoneSize, y0 = z / _zw * ZoneSize, n = 0;
		for (int y = y0; y < y0 + ZoneSize; y++)
			for (int x = x0; x < x0 + ZoneSize; x++)
				if (World.IsLand(x, y))
					n++;
		return n;
	}

	/// <summary>A growing village claims the free zone next to its land nearest to its heart.</summary>
	private bool Expand(int v)
	{
		var village = Villages[v];
		int best = -1;
		float bestD = float.MaxValue;
		foreach (int z in village.Zones)
		{
			int zx = z % _zw, zy = z / _zw;
			for (int d = 0; d < 4; d++)
			{
				int nx = zx + (d == 0 ? 1 : d == 1 ? -1 : 0), ny = zy + (d == 2 ? 1 : d == 3 ? -1 : 0);
				if (nx < 0 || ny < 0 || nx >= _zw || ny >= _zh)
					continue;
				int nz = ny * _zw + nx;
				if (_zoneOwner[nz] >= 0)
					continue;
				float cx = (nx + 0.5f) * ZoneSize - village.X, cy = (ny + 0.5f) * ZoneSize - village.Y;
				float dist = cx * cx + cy * cy;
				if (dist < bestD && ZoneLand(nz) >= ZoneSize * ZoneSize / 4)
				{
					bestD = dist;
					best = nz;
				}
			}
		}
		if (best < 0)
			return false;
		ClaimZone(v, best);
		return true;
	}

	// ------------------------------------------------------------------ founding

	private int FoundVillage(int species, int x, int y, int mother = -1)
	{
		var race = Assets.Species[species].Race;
		int shade = Villages.FindAll(o => o.Species == species).Count;
		var c = new Color(race?.Color ?? "#ffffff");
		// Each village of a people a shade of its colour: lighter, darker, lighter...
		c = shade == 0 ? c : shade % 2 == 1 ? c.Lightened(0.12f * ((shade + 1) / 2)) : c.Darkened(0.12f * (shade / 2));
		var v = new Village
		{
			Name = _languages[species].PlaceName(), Species = species, X = x, Y = y,
			Food = 30f, Wood = 12f, Founded = Year(), Color = c, Mother = mother,
			NextPlan = Scheduler.Time + PlanSeconds * 0.5, NextSettlers = Scheduler.Time + YearSeconds * 4,
		};
		Villages.Add(v);
		int id = Villages.Count - 1;
		int cz = ZoneOf(x, y);
		int czx = cz % _zw, czy = cz / _zw;
		for (int dy = -1; dy <= 1; dy++)
			for (int dx = -1; dx <= 1; dx++)
			{
				int zx = czx + dx, zy = czy + dy;
				if (zx >= 0 && zy >= 0 && zx < _zw && zy < _zh && _zoneOwner[zy * _zw + zx] < 0)
					ClaimZone(id, zy * _zw + zx);
			}
		AddBuilding(_tBonfire, x, y, id, 1f);
		return id;
	}

	private int AddBuilding(int type, int x, int y, int village, float progress)
	{
		Buildings.Add(new Building { Type = type, X = x, Y = y, Village = village, Progress = progress });
		int b = Buildings.Count - 1;
		int t = World.Index(x, y);
		_buildingAt[t] = b;
		Villages[village].Buildings.Add(b);
		// No trees, fields or roads where people build.
		for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
			RemovePlant(p);
		SetGround(t, 0);
		return b;
	}

	private void SetGround(int t, byte g)
	{
		if (_ground[t] == g)
			return;
		_ground[t] = g;
		_wheat[t] = 0f;
		_overlayChanged.Add(t);
	}

	// ------------------------------------------------------------------ the village, every 2 s

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
		GrowWheat(dt);
		CrumbleRuins();
		// Villages founded by settlers during this step start working at the next one.
		int count = Villages.Count;
		for (int v = 0; v < count; v++)
		{
			var village = Villages[v];
			if (!village.Alive)
				continue;
			var people = members[v];
			village.Population = people.Count;
			if (people.Count == 0)
			{
				Abandon(v);
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
			// The bonfire gives a little food of the land (berries, roots) every time.
			village.Food += 0.4f * dt / 2f;
			AssignHomes(v, people);
			if (Scheduler.Time >= village.NextPlan)
			{
				village.NextPlan = Scheduler.Time + PlanSeconds;
				if (village.Zones.Count < Math.Min(9 + people.Count / 3, 90))
					Expand(v);
				Plan(v, people.Count);
			}
			HandOutWork(v, people);
			TowersShoot(v);
			if (Scheduler.Time >= village.NextSettlers)
				SendSettlers(v, people);
		}
	}

	/// <summary>Homes the village's buildings offer (built ones only).</summary>
	public int Homes(int v)
	{
		int n = 0;
		foreach (int b in Villages[v].Buildings)
			if (Buildings[b].Alive && (Buildings[b].Done || Buildings[b].UpgradeTo >= 0))
				n += Rec(b).Homes;
		return n;
	}

	/// <summary>Everyone gets a home: the people already living somewhere stay, the homeless move
	/// into a building with room left; with none free, they sleep by the bonfire.</summary>
	private void AssignHomes(int v, List<int> people)
	{
		var village = Villages[v];
		var room = new Dictionary<int, int>();
		int bonfire = -1;
		foreach (int b in village.Buildings)
		{
			if (!Buildings[b].Alive || !(Buildings[b].Done || Buildings[b].UpgradeTo >= 0))
				continue;
			room[b] = Rec(b).Homes;
			if (Buildings[b].Type == _tBonfire)
				bonfire = b;
		}
		var homeless = new List<int>();
		foreach (int i in people)
		{
			int h = Units.Home[i];
			if (h >= 0 && room.TryGetValue(h, out int left) && left > 0)
				room[h] = left - 1;
			else
				homeless.Add(i);
		}
		foreach (int i in homeless)
		{
			int home = bonfire;
			foreach (var (b, left) in room)
				if (left > 0 && b != bonfire)
				{
					home = b;
					break;
				}
			if (home >= 0 && room.TryGetValue(home, out int l) && l > 0)
				room[home] = l - 1;
			Units.Home[i] = home;
		}
		int houses = 0;
		foreach (int b in village.Buildings)
			if (Buildings[b].Alive && _houseTypes.Contains(Buildings[b].Type) && (Buildings[b].Done || Buildings[b].UpgradeTo >= 0))
				houses++;
		village.Houses = houses;
	}

	// ------------------------------------------------------------------ the building plan

	/// <summary>How many buildings of `type` the village has or is making.</summary>
	private int CountOf(int v, int type, bool doneOnly = false)
	{
		int n = 0;
		foreach (int b in Villages[v].Buildings)
		{
			var bld = Buildings[b];
			if (!bld.Alive)
				continue;
			if (bld.Type == type && (!doneOnly || bld.Done) || (!doneOnly && bld.UpgradeTo == type))
				n++;
		}
		return n;
	}

	public bool HasBuilding(int v, string id) => CountOf(v, Assets.BuildingIndex(id), true) > 0;

	private bool CanAfford(Village village, BuildingRecord rec) =>
		village.Wood >= rec.CostOf("wood") && village.Stone >= rec.CostOf("stone")
		&& village.Metal >= rec.CostOf("metal") && village.Gold >= rec.CostOf("gold");

	private void Pay(Village village, BuildingRecord rec)
	{
		village.Wood -= rec.CostOf("wood");
		village.Stone -= rec.CostOf("stone");
		village.Metal -= rec.CostOf("metal");
		village.Gold -= rec.CostOf("gold");
	}

	/// <summary>Whether the village may start building `type` now (people, prerequisites, limit;
	/// not goods nor place).</summary>
	private bool Allowed(int v, int type, int pop)
	{
		var rec = Assets.Buildings[type];
		if (pop < rec.Pop || type == _tRuin || type == _tBonfire)
			return false;
		foreach (var req in rec.Requires)
			if (CountOf(v, Assets.BuildingIndex(req), true) == 0)
				return false;
		int limit = rec.Limit + (rec.Per > 0 ? pop / rec.Per : 0);
		return limit == 0 || CountOf(v, type) < limit;
	}

	/// <summary>Once a month: one new building or one upgrade, WorldBox's way. Homes come first
	/// when people are short of them (an upgrade, or a new hut); else the first building of
	/// data/buildings.json the village may make; else an upgrade of a house.</summary>
	private void Plan(int v, int pop)
	{
		var village = Villages[v];
		if (village.Site >= 0 && Buildings[village.Site].Alive && (Buildings[village.Site].Progress < 1f))
			return;
		village.Site = -1;
		bool crowded = pop + 3 > Homes(v);
		if (crowded)
		{
			if (_rng.NextDouble() < 0.5 && TryUpgrade(v, pop))
				return;
			if (TryStart(v, _tHut) || TryUpgrade(v, pop))
				return;
		}
		for (int t = 0; t < Assets.Buildings.Count; t++)
		{
			var rec = Assets.Buildings[t];
			if (t == _tHut || rec.Upgrade != "" || !Allowed(v, t, pop) || !CanAfford(village, rec))
				continue;
			if (TryStart(v, t))
				return;
		}
		TryUpgrade(v, pop);
	}

	private bool TryStart(int v, int type)
	{
		var village = Villages[v];
		var rec = Assets.Buildings[type];
		if (!CanAfford(village, rec))
			return false;
		int spot = FindSpot(v, rec);
		if (spot < 0)
			return false;
		Pay(village, rec);
		village.Site = AddBuilding(type, spot % World.Width, spot / World.Width, v, 0f);
		return true;
	}

	/// <summary>Upgrades one building whose next tier the village may make and afford: a hut
	/// into a house, a house into a stone house...</summary>
	private bool TryUpgrade(int v, int pop)
	{
		var village = Villages[v];
		for (int t = 0; t < Assets.Buildings.Count; t++)
		{
			var rec = Assets.Buildings[t];
			if (rec.Upgrade == "" || !Allowed(v, t, pop) || !CanAfford(village, rec))
				continue;
			int from = Assets.BuildingIndex(rec.Upgrade);
			foreach (int b in village.Buildings)
			{
				var bld = Buildings[b];
				if (bld.Alive && bld.Done && bld.Type == from && bld.Burning == 0f)
				{
					Pay(village, rec);
					bld.UpgradeTo = t;
					bld.Progress = 0f;
					village.Site = b;
					return true;
				}
			}
		}
		return false;
	}

	/// <summary>A free tile of the territory where `rec` may stand, by its place rule, or -1.
	/// A building keeps a free tile around it.</summary>
	private int FindSpot(int v, BuildingRecord rec)
	{
		var village = Villages[v];
		if (village.Zones.Count == 0)
			return -1;
		int near = rec.Near != "" ? Assets.BuildingIndex(rec.Near) : -1;
		int best = -1;
		float bestScore = float.MaxValue;
		for (int tries = 0; tries < 120; tries++)
		{
			int z = village.Zones[_rng.Next(village.Zones.Count)];
			int x = z % _zw * ZoneSize + _rng.Next(ZoneSize), y = z / _zw * ZoneSize + _rng.Next(ZoneSize);
			if (x < 1 || y < 1 || x >= World.Width - 1 || y >= World.Height - 1 || !World.IsLand(x, y))
				continue;
			int t = World.Index(x, y);
			if (_buildingAt[t] >= 0 || _ground[t] == GroundField || TileBurn[t] > 0f || _biomeNames[World.Biome[t]] == "Lava")
				continue;
			if (BuildingWithin(x, y, 1) >= 0)
				continue;
			float dx = x - village.X, dy = y - village.Y;
			float dist = MathF.Sqrt(dx * dx + dy * dy);
			float score;
			switch (rec.Place)
			{
				case "apart":
					if (BuildingWithin(x, y, 2) >= 0 || dist < 4f)
						continue;
					score = dist;
					break;
				case "border":
				{
					bool edge = false;
					for (int k = 0; k < 8 && !edge; k++)
						edge = !Owns(v, x + (k % 3 - 1) * 3, y + (k / 3 - 1) * 3);
					if (!edge)
						continue;
					score = -dist;
					break;
				}
				case "shore":
					if (!NextToWater(x, y))
						continue;
					score = dist;
					break;
				case "mine":
					score = dist + (NearRock(x, y) ? 0f : 40f);
					if (BuildingWithin(x, y, 2) >= 0)
						continue;
					break;
				case "near":
				{
					int b = BuildingWithin(x, y, 3, near);
					if (b < 0 || Buildings[b].Village != v)
						continue;
					score = dist;
					break;
				}
				default:  // cluster: next to the others, as close to the heart as it can
					if (BuildingWithin(x, y, 3) < 0)
						continue;
					score = dist;
					break;
			}
			if (_ground[t] == GroundRoad)
				score += 3f;
			if (score < bestScore)
			{
				bestScore = score;
				best = t;
			}
		}
		return best;
	}

	/// <summary>A building within `r` tiles (Chebyshev) of (x, y), of `type` if it is not -1.</summary>
	private int BuildingWithin(int x, int y, int r, int type = -1)
	{
		for (int dy = -r; dy <= r; dy++)
			for (int dx = -r; dx <= r; dx++)
			{
				if (!World.InBounds(x + dx, y + dy))
					continue;
				int b = _buildingAt[World.Index(x + dx, y + dy)];
				if (b >= 0 && (type < 0 || Buildings[b].Type == type))
					return b;
			}
		return -1;
	}

	private bool NextToWater(int x, int y)
	{
		for (int d = 0; d < 4; d++)
		{
			int nx = x + (d == 0 ? 1 : d == 1 ? -1 : 0), ny = y + (d == 2 ? 1 : d == 3 ? -1 : 0);
			if (World.InBounds(nx, ny) && World.Water[World.Index(nx, ny)] != SimWorld.WaterLand)
				return true;
		}
		return false;
	}

	/// <summary>Whether hills, mountains or rock are within two tiles (mines dig there, and only
	/// there find gold).</summary>
	private bool NearRock(int x, int y)
	{
		for (int dy = -2; dy <= 2; dy++)
			for (int dx = -2; dx <= 2; dx++)
				if (World.InBounds(x + dx, y + dy))
				{
					string b = _biomeNames[World.Biome[World.Index(x + dx, y + dy)]];
					if (b == "Hills" || b == "Mountain" || b == "Peak" || b == "Volcanic rock")
						return true;
				}
		return false;
	}

	/// <summary>A builder's second of work on the village's site. Returns true when it is done.</summary>
	private bool BuildSome(int v, int b, float work)
	{
		var bld = Buildings[b];
		var rec = Assets.Buildings[bld.UpgradeTo >= 0 ? bld.UpgradeTo : bld.Type];
		bld.Progress = Math.Min(1f, bld.Progress + work / Math.Max(rec.Build, 0.5f));
		if (bld.Progress < 1f)
			return false;
		if (bld.UpgradeTo >= 0)
		{
			bld.Type = bld.UpgradeTo;
			bld.UpgradeTo = -1;
		}
		Villages[v].Site = -1;
		Built(v, b);
		return true;
	}

	/// <summary>A building is finished: windmills get fields, every building a road to the heart
	/// of the village; the great buildings are news.</summary>
	private void Built(int v, int b)
	{
		var village = Villages[v];
		var bld = Buildings[b];
		var rec = Assets.Buildings[bld.Type];
		if (bld.Type == _tWindmill)
			MakeFields(v, bld.X, bld.Y);
		PlanRoad(v, bld.X, bld.Y + 1, village.X, village.Y + 1);
		if (!_houseTypes.Contains(bld.Type) && bld.Type != _tDummy)
			LogEvent($"{village.Name} builds a {rec.Name.ToLower()}.");
	}

	// ------------------------------------------------------------------ fields and roads

	/// <summary>Fields around a windmill: free land of the territory within three tiles.</summary>
	private void MakeFields(int v, int cx, int cy)
	{
		for (int y = cy - 3; y <= cy + 3; y++)
			for (int x = cx - 3; x <= cx + 3; x++)
			{
				if (Math.Abs(x - cx) <= 1 && Math.Abs(y - cy) <= 1)
					continue;
				if (!World.IsLand(x, y) || !Owns(v, x, y))
					continue;
				int t = World.Index(x, y);
				if (_buildingAt[t] >= 0 || _ground[t] != 0 || BuildingWithin(x, y, 1) >= 0 && BuildingWithin(x, y, 1) != _buildingAt[World.Index(cx, cy)])
					continue;
				for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
					RemovePlant(p);
				SetGround(t, GroundField);
				Villages[v].Fields.Add(t);
			}
	}

	/// <summary>Wheat grows on sown fields in spring and summer, slower in autumn, not in winter.</summary>
	private void GrowWheat(float dt)
	{
		float rate = Season() switch { 0 => 1f / 18f, 1 => 1f / 14f, 2 => 1f / 30f, _ => 0f };
		if (rate == 0f)
			return;
		foreach (var village in Villages)
		{
			if (!village.Alive)
				continue;
			foreach (int t in village.Fields)
			{
				float w = _wheat[t];
				if (w <= 0f || w >= 1f)
					continue;
				int before = GroundCode(t);
				_wheat[t] = Math.Min(1f, w + rate * dt);
				if (GroundCode(t) != before)
					_overlayChanged.Add(t);
			}
		}
	}

	/// <summary>An L-shaped road from (x0, y0) to (x1, y1), over land without buildings: tiles for
	/// the road builders.</summary>
	private void PlanRoad(int v, int x0, int y0, int x1, int y1)
	{
		var plan = Villages[v].RoadPlan;
		int x = x0, y = y0;
		for (int steps = 0; steps < 64 && (x != x1 || y != y1); steps++)
		{
			if (x != x1)
				x += Math.Sign(x1 - x);
			else
				y += Math.Sign(y1 - y);
			if (!World.IsLand(x, y))
				return;
			int t = World.Index(x, y);
			if (_buildingAt[t] < 0 && _ground[t] == 0 && !plan.Contains(t))
				plan.Add(t);
		}
	}

	/// <summary>Walking is half again as fast on roads.</summary>
	private float GroundSpeed(float x, float y)
	{
		int tx = (int)x, ty = (int)y;
		return World.InBounds(tx, ty) && _ground[World.Index(tx, ty)] == GroundRoad ? 1.5f : 1f;
	}

	// ------------------------------------------------------------------ fire in buildings

	/// <summary>Wooden buildings next to burning tiles may catch fire (called by FireStep for each
	/// burning tile).</summary>
	private void HeatBuildings(int x, int y, float dt)
	{
		for (int dy = -1; dy <= 1; dy++)
			for (int dx = -1; dx <= 1; dx++)
			{
				if (!World.InBounds(x + dx, y + dy))
					continue;
				int b = _buildingAt[World.Index(x + dx, y + dy)];
				if (b >= 0 && Buildings[b].Burning == 0f && Rec(b).Wooden && Buildings[b].Type != _tRuin && _rng.NextDouble() < 0.8 * dt)
					Buildings[b].Burning = 0.001f;
			}
	}

	/// <summary>Burning buildings: they lose a little every step, set the land around alight and
	/// fall to ruins when nothing is left (firemen put them out first, if they can).</summary>
	private void BuildingFire(float dt)
	{
		for (int b = 0; b < Buildings.Count; b++)
		{
			var bld = Buildings[b];
			if (!bld.Alive || bld.Burning == 0f)
				continue;
			bld.Burning += dt;
			bld.Health -= dt / 14f;
			if (_rng.NextDouble() < 0.6 * dt)
			{
				int nx = bld.X + _rng.Next(-1, 2), ny = bld.Y + _rng.Next(-1, 2);
				if (World.InBounds(nx, ny))
					IgniteTile(World.Index(nx, ny));
			}
			// The people inside run for it; those who stay burn.
			if (bld.Health <= 0f)
			{
				BuildingsBurned++;
				if (Rec(b).Homes > 1 || bld.Type == _tWindmill)
					LogEvent($"a {Rec(b).Name.ToLower()} of {Villages[bld.Village].Name} burns down.");
				ToRuin(b);
			}
		}
	}

	public bool BuildingBurning(int b) => Buildings[b].Alive && Buildings[b].Burning > 0f;

	/// <summary>A building becomes a ruin, which crumbles away after two years.</summary>
	private void ToRuin(int b)
	{
		var bld = Buildings[b];
		var village = Villages[bld.Village];
		if (village.Site == b)
			village.Site = -1;
		if (bld.Type == _tWindmill)
		{
			// Its fields go back to the wild.
			foreach (int t in village.Fields)
				SetGround(t, 0);
			village.Fields.Clear();
			foreach (int o in village.Buildings)
				if (o != b && Buildings[o].Alive && Buildings[o].Type == _tWindmill && Buildings[o].Done)
					MakeFields(bld.Village, Buildings[o].X, Buildings[o].Y);
		}
		bld.Type = _tRuin;
		bld.UpgradeTo = -1;
		bld.Progress = 1f;
		bld.Burning = 0f;
		bld.Health = 1f;
		bld.CrumbleAt = Scheduler.Time + YearSeconds * 2;
	}

	private void CrumbleRuins()
	{
		for (int b = 0; b < Buildings.Count; b++)
		{
			var bld = Buildings[b];
			if (bld.Alive && bld.Type == _tRuin && Scheduler.Time >= bld.CrumbleAt)
			{
				bld.Alive = false;
				_buildingAt[World.Index(bld.X, bld.Y)] = -1;
				Villages[bld.Village].Buildings.Remove(b);
			}
		}
	}

	/// <summary>No one lives in the village any more: its buildings fall to ruins, its land is free.</summary>
	private void Abandon(int v)
	{
		var village = Villages[v];
		village.Alive = false;
		foreach (int b in village.Buildings.ToArray())
			if (Buildings[b].Alive && Buildings[b].Type != _tRuin)
				ToRuin(b);
		foreach (int t in village.Fields)
			SetGround(t, 0);
		village.Fields.Clear();
		foreach (int z in village.Zones)
		{
			_zoneOwner[z] = -1;
			MarkZone(z);
		}
		village.Zones.Clear();
		LogEvent($"{village.Name} is abandoned: no one lives there any more.");
	}

	// ------------------------------------------------------------------ watch towers

	/// <summary>Watch towers shoot arrows at beasts that hunt in the village's land.</summary>
	private void TowersShoot(int v)
	{
		foreach (int b in Villages[v].Buildings)
		{
			var bld = Buildings[b];
			if (!bld.Alive || bld.Type != _tTower || !bld.Done)
				continue;
			_found.Clear();
			Zones.Query(Units, bld.X + 0.5f, bld.Y + 0.5f, 8f, _found);
			foreach (int u in _found)
			{
				var sp = Assets.Species[Units.Species[u]];
				if (Units.Alive[u] && !sp.IsPeople && sp.Diet == "carnivore")
				{
					if (_rng.NextDouble() < 0.5)
					{
						KillUnit(u, Death.Other);
						TowerKills++;
					}
					break;
				}
			}
		}
	}

	// ------------------------------------------------------------------ settlers

	/// <summary>A big, crowded village sends settlers away, 6 to 12 adults with their families, to
	/// found a new village of its people nearby, in a land they like.</summary>
	private void SendSettlers(int v, List<int> people)
	{
		var village = Villages[v];
		village.NextSettlers = Scheduler.Time + YearSeconds * (2 + _rng.NextDouble() * 2);
		int homes = Homes(v);
		if (people.Count < 30 || (people.Count < homes * 0.85f && people.Count < 60))
			return;
		if (Villages.FindAll(o => o.Alive && o.Species == village.Species).Count >= 12)
			return;
		var race = Assets.Species[village.Species].Race;
		int site = FindSettlement(race, village.X, village.Y);
		if (site < 0)
			return;
		var leaving = new List<int>();
		int want = 6 + _rng.Next(7);
		foreach (int i in people)
		{
			if (leaving.Count >= want)
				break;
			if (want - leaving.Count < 2 && Units.Partner[i] >= 0)
				continue;
			if (!IsAdult(i) || Units.Role[i] == (byte)Role.Chief || leaving.Contains(i))
				continue;
			leaving.Add(i);
			int p = Units.Partner[i];
			if (p >= 0 && Units.Alive[p] && Units.Village[p] == v && !leaving.Contains(p) && Units.Role[p] != (byte)Role.Chief)
				leaving.Add(p);
		}
		// Their young children follow them (a party of 18 at most).
		foreach (int i in people)
			if (leaving.Count < 18 && !IsAdult(i) && !leaving.Contains(i) && (leaving.Contains(Units.Mother[i]) || leaving.Contains(Units.Father[i])))
				leaving.Add(i);
		if (leaving.Count < 6)
			return;
		int nv = FoundVillage(village.Species, site % World.Width, site / World.Width, v);
		var colony = Villages[nv];
		float food = Math.Min(village.Food * 0.3f, 25f), wood = Math.Min(village.Wood * 0.3f, 12f);
		village.Food -= food;
		village.Wood -= wood;
		colony.Food = food + 10f;
		colony.Wood = wood + 4f;
		bool chief = false;
		foreach (int i in leaving)
		{
			Units.Village[i] = nv;
			Units.Home[i] = -1;
			Units.Job[i] = (byte)Job.None;
			Units.Carry[i] = 0;
			if (!chief && IsAdult(i))
			{
				Units.Role[i] = (byte)Role.Chief;
				chief = true;
			}
			GoTo(i, colony.X + 0.5f + ((float)_rng.NextDouble() - 0.5f) * 3f, colony.Y + 1f + ((float)_rng.NextDouble() - 0.5f) * 3f, Task.Wander);
		}
		village.Population -= leaving.Count;
		colony.Population = leaving.Count;
		SettlersSent += leaving.Count;
		LogEvent($"{leaving.Count} settlers leave {village.Name} and found {colony.Name}.");
	}

	/// <summary>A place for a new village 18 to 45 tiles away: free land in a liked biome, near
	/// fresh water, far enough from other villages. -1 if none.</summary>
	private int FindSettlement(RaceRecord race, int cx, int cy)
	{
		var liked = new HashSet<int>();
		foreach (var name in race.Biomes)
		{
			int b = Array.IndexOf(_biomeNames, name);
			if (b >= 0)
				liked.Add(b);
		}
		int fallback = -1;
		for (int tries = 0; tries < 400; tries++)
		{
			double a = _rng.NextDouble() * Math.Tau;
			double r = 18 + _rng.NextDouble() * 27;
			int x = cx + (int)(Math.Cos(a) * r), y = cy + (int)(Math.Sin(a) * r);
			if (x < 4 || y < 4 || x >= World.Width - 4 || y >= World.Height - 4)
				continue;
			int t = World.Index(x, y);
			if (World.Water[t] != SimWorld.WaterLand || _buildingAt[t] >= 0 || _zoneOwner[ZoneOf(x, y)] >= 0)
				continue;
			bool far = true;
			foreach (var o in Villages)
				far &= !o.Alive || Math.Abs(o.X - x) + Math.Abs(o.Y - y) > 22;
			if (!far)
				continue;
			int w = _nearestWater[t];
			bool water = w >= 0 && Math.Abs(w % World.Width - x) + Math.Abs(w / World.Width - y) <= 8;
			bool likes = liked.Contains(World.Biome[t]);
			if (likes && water)
				return t;
			if (fallback < 0 && (likes || water) && _biomeNames[World.Biome[t]] != "Lava")
				fallback = t;
		}
		return fallback;
	}

	// ------------------------------------------------------------------ the map overlay

	/// <summary>What the map draws on a tile: 0 nothing, 1 road, 2 bare field, 3 young wheat,
	/// 4 growing wheat, 5 ripe wheat.</summary>
	private int GroundCode(int t)
	{
		if (_ground[t] == GroundRoad)
			return 1;
		if (_ground[t] != GroundField)
			return 0;
		float w = _wheat[t];
		return w <= 0f ? 2 : w < 0.5f ? 3 : w < 1f ? 4 : 5;
	}

	/// <summary>Map changes since the last call, as triples (tile, ground code, territory) where
	/// territory is the owner's colour packed as 0xRRGGBBAA, AA telling villages apart (0 = no one's).</summary>
	public int[] TakeOverlayChanges()
	{
		if (_overlayChanged.Count == 0)
			return Array.Empty<int>();
		var list = new int[_overlayChanged.Count * 3];
		int k = 0;
		foreach (int t in _overlayChanged)
		{
			list[k++] = t;
			list[k++] = GroundCode(t);
			int o = _zoneOwner[ZoneOf(t % World.Width, t / World.Width)];
			if (o < 0)
				list[k++] = 0;
			else
			{
				var c = Villages[o].Color;
				list[k++] = (int)(((uint)(c.R * 255f) << 24) | ((uint)(c.G * 255f) << 16) | ((uint)(c.B * 255f) << 8) | (uint)(o % 250 + 1));
			}
		}
		_overlayChanged.Clear();
		return list;
	}

	/// <summary>Ground made by people on tile (x, y): 0 nothing, 1 road, 2 field (tests, HUD).</summary>
	public int GroundAt(int x, int y) => World.InBounds(x, y) ? _ground[World.Index(x, y)] : 0;

	public int TerritoryTiles(int v)
	{
		int n = 0;
		foreach (int z in Villages[v].Zones)
			n += ZoneSize * ZoneSize;
		return n;
	}

	/// <summary>Every building standing: kind, village, position, done (tests, inspector).</summary>
	public Godot.Collections.Array BuildingTable()
	{
		var list = new Godot.Collections.Array();
		for (int b = 0; b < Buildings.Count; b++)
		{
			var bld = Buildings[b];
			if (!bld.Alive)
				continue;
			list.Add(new Godot.Collections.Dictionary
			{
				["id"] = Assets.Buildings[bld.Type].Id, ["village"] = bld.Village, ["x"] = bld.X, ["y"] = bld.Y,
				["done"] = bld.Done, ["burning"] = bld.Burning > 0f, ["owner_ok"] = Owns(bld.Village, bld.X, bld.Y),
			});
		}
		return list;
	}

	/// <summary>Sets a building on fire (tests; god powers later).</summary>
	public bool IgniteBuilding(int x, int y)
	{
		if (!World.InBounds(x, y))
			return false;
		int b = _buildingAt[World.Index(x, y)];
		if (b < 0 || !Rec(b).Wooden)
			return false;
		Buildings[b].Burning = 0.001f;
		return true;
	}

	private string BuildingSummary(int v)
	{
		var counts = new SortedDictionary<string, int>();
		foreach (int b in Villages[v].Buildings)
		{
			var bld = Buildings[b];
			if (!bld.Alive || !bld.Done || bld.Type == _tBonfire)
				continue;
			string n = Assets.Buildings[bld.Type].Name.ToLower();
			counts[n] = counts.TryGetValue(n, out int c) ? c + 1 : 1;
		}
		var parts = new List<string>();
		foreach (var (n, c) in counts)
			parts.Add(c > 1 ? $"{c} {n}s" : $"1 {n}");
		return string.Join(", ", parts);
	}
}
