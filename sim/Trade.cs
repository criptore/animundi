using System;
using System.Collections.Generic;

namespace Animundi.Sim;

/// <summary>
/// Trade (0.4): villages with a market or a stockpile open routes to friendly villages nearby
/// (same kingdom or allies, never an enemy). Every month a route carries what one village has
/// too much of to the other (food, wood, stone), and a market earns gold on each trade. Goods
/// travel visibly: carts along land paths, boats between docks along water paths (paths found
/// once per route, breadth-first on the tile grid).
/// </summary>
public partial class Simulation
{
	public sealed class TradeRoute
	{
		public int A, B;
		public bool Sea;
		/// <summary>Tiles from A to B.</summary>
		public int[] Path;
		public double Next;
		public int Trips;
		public bool Alive = true;
	}

	/// <summary>A cart or a boat on its way (drawn only: the goods are already traded).</summary>
	public sealed class Vehicle
	{
		public bool Boat;
		public int[] Path;
		public bool Back;
		public float At;
		public int Village;
	}

	private readonly List<TradeRoute> _trade = new();
	private readonly List<Vehicle> _vehicles = new();
	public int Trades { get; private set; }
	private const int MaxRouteTiles = 110;
	private const float CartSpeed = 1.6f, BoatSpeed = 2.4f;

	private bool Friendly(int a, int b) => a == b || a >= 0 && b >= 0 && Kingdoms[a].Allies.Contains(b);

	/// <summary>Every 2 s: new routes now and then; due routes trade; broken routes close.</summary>
	private void TradeStep(float dt)
	{
		foreach (var r in _trade)
			if (r.Alive && (!Villages[r.A].Alive || !Villages[r.B].Alive || !Friendly(Villages[r.A].Kingdom, Villages[r.B].Kingdom)))
				r.Alive = false;
		_trade.RemoveAll(r => !r.Alive);
		if (_rng.NextDouble() < 0.15)
			OpenRoute();
		foreach (var r in _trade)
			if (Scheduler.Time >= r.Next)
			{
				r.Next = Scheduler.Time + PlanSeconds;
				Exchange(r);
			}
	}

	private bool Trading(int v) => CountOf(v, Assets.BuildingIndex("market"), true) > 0 || CountOf(v, _tStockpile, true) > 0;

	/// <summary>A village that trades and has fewer than two routes looks for a friendly partner
	/// within reach, by sea if both have docks on the same water, else by land.</summary>
	private void OpenRoute()
	{
		if (Villages.Count < 2)
			return;
		int a = _rng.Next(Villages.Count);
		var va = Villages[a];
		if (!va.Alive || va.Population < 15 || !Trading(a) || _trade.FindAll(r => r.A == a || r.B == a).Count >= 2)
			return;
		int best = -1;
		float bestD = float.MaxValue;
		for (int b = 0; b < Villages.Count; b++)
		{
			var vb = Villages[b];
			if (b == a || !vb.Alive || vb.Population < 10 || !Friendly(va.Kingdom, vb.Kingdom) || !Trading(b)
				|| _trade.Exists(r => r.A == a && r.B == b || r.A == b && r.B == a))
				continue;
			float d = Math.Abs(va.X - vb.X) + Math.Abs(va.Y - vb.Y);
			if (d < bestD && d < MaxRouteTiles * 0.8f)
			{
				bestD = d;
				best = b;
			}
		}
		if (best < 0)
			return;
		int[] path = null;
		bool sea = false;
		int da = Nearest(a, _tDock), db = Nearest(best, _tDock);
		if (da >= 0 && db >= 0)
		{
			path = FindPath(WaterNextTo(Buildings[da]), WaterNextTo(Buildings[db]), water: true);
			sea = path != null;
		}
		path ??= FindPath(World.Index(va.X, va.Y + 1), World.Index(Villages[best].X, Villages[best].Y + 1), water: false);
		if (path == null)
			return;
		_trade.Add(new TradeRoute { A = a, B = best, Sea = sea, Path = path, Next = Scheduler.Time + PlanSeconds * _rng.NextDouble() });
		LogEvent($"a trade route {(sea ? "by sea" : "by road")} opens between {va.Name} and {Villages[best].Name}.", "cities");
	}

	private int Nearest(int v, int type)
	{
		if (!Villages[v].ByType.TryGetValue(type, out var list))
			return -1;
		foreach (int b in list)
			if (Buildings[b].Alive && Buildings[b].Done)
				return b;
		return -1;
	}

	private int WaterNextTo(Building b)
	{
		for (int dy = -1; dy <= 2; dy++)
			for (int dx = -1; dx <= 1; dx++)
				if (World.InBounds(b.X + dx, b.Y + dy) && World.Water[World.Index(b.X + dx, b.Y + dy)] != SimWorld.WaterLand)
					return World.Index(b.X + dx, b.Y + dy);
		return -1;
	}

	/// <summary>Shortest 8-way path between two tiles over water or over land, at most
	/// MaxRouteTiles long, or null.</summary>
	private int[] FindPath(int from, int to, bool water)
	{
		if (from < 0 || to < 0)
			return null;
		bool Ok(int t) => (World.Water[t] != SimWorld.WaterLand) == water && (water || _biomeNames[World.Biome[t]] != "Lava");
		if (!Ok(from) || !Ok(to))
			return null;
		var prev = new Dictionary<int, int> { [from] = -1 };
		var queue = new Queue<(int t, int d)>();
		queue.Enqueue((from, 0));
		while (queue.Count > 0)
		{
			var (t, d) = queue.Dequeue();
			if (t == to)
			{
				var path = new List<int>();
				for (int c = to; c >= 0; c = prev[c])
					path.Add(c);
				path.Reverse();
				return path.ToArray();
			}
			if (d >= MaxRouteTiles)
				continue;
			int x = t % World.Width, y = t / World.Width;
			for (int k = 0; k < 8; k++)
			{
				int nx = x + (k % 3) - 1, ny = y + (k / 3) - 1;
				if (k == 4 || nx == x && ny == y || !World.InBounds(nx, ny))
					continue;
				int n = World.Index(nx, ny);
				if (prev.ContainsKey(n) || !Ok(n))
					continue;
				// No cutting corners: a diagonal step needs both tiles beside it to be passable
				// (a walker going straight from tile to tile never touches the water).
				if (nx != x && ny != y && (!Ok(World.Index(nx, y)) || !Ok(World.Index(x, ny))))
					continue;
				prev[n] = t;
				queue.Enqueue((n, d + 1));
			}
		}
		return null;
	}

	/// <summary>A month of trade on a route: up to 10 of each good one village has to spare and
	/// the other lacks; a market earns gold on each trade. A cart or a boat makes the trip.</summary>
	private void Exchange(TradeRoute r)
	{
		var a = Villages[r.A];
		var b = Villages[r.B];
		bool moved = false;
		moved |= Swap(ref a.Food, ref b.Food, a.Population * 6f, b.Population * 6f);
		moved |= Swap(ref a.Wood, ref b.Wood, 40f, 40f);
		moved |= Swap(ref a.Stone, ref b.Stone, 30f, 30f);
		int market = Assets.BuildingIndex("market");
		if (CountOf(r.A, market, true) > 0)
			a.Gold += 1f;
		if (CountOf(r.B, market, true) > 0)
			b.Gold += 1f;
		r.Trips++;
		Trades++;
		if (moved || r.Trips % 3 == 1)
			_vehicles.Add(new Vehicle { Boat = r.Sea, Path = r.Path, Back = r.Trips % 2 == 0, Village = r.A });
	}

	/// <summary>Moves up to 10 from the side that has more than it needs to the side that needs it.</summary>
	private static bool Swap(ref float a, ref float b, float needA, float needB)
	{
		if (a > needA && b < needB)
		{
			float n = Math.Min(10f, Math.Min(a - needA, needB - b));
			a -= n;
			b += n;
			return n > 0f;
		}
		if (b > needB && a < needA)
		{
			float n = Math.Min(10f, Math.Min(b - needB, needA - a));
			b -= n;
			a += n;
			return n > 0f;
		}
		return false;
	}

	/// <summary>Every step: carts and boats move along their paths; they leave at the end.</summary>
	private void MoveVehicles(int a, int b, float dt)
	{
		foreach (var v in _vehicles)
			v.At += dt * (v.Boat ? BoatSpeed : CartSpeed);
		_vehicles.RemoveAll(v => v.At >= v.Path.Length - 1);
	}

	/// <summary>Where a vehicle is, in tiles, and whether it goes left.</summary>
	private (float x, float y, bool left) VehiclePos(Vehicle v)
	{
		int n = v.Path.Length;
		float at = Math.Clamp(v.At, 0f, n - 1.001f);
		int k = (int)at;
		float f = at - k;
		int t0 = v.Path[v.Back ? n - 1 - k : k], t1 = v.Path[v.Back ? n - 2 - k : k + 1];
		float x0 = t0 % World.Width + 0.5f, y0 = t0 / World.Width + 0.7f;
		float x1 = t1 % World.Width + 0.5f, y1 = t1 / World.Width + 0.7f;
		return (x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, x1 < x0);
	}

	/// <summary>Trade routes: villages, by sea or road, trips (HUD, tests).</summary>
	public Godot.Collections.Array TradeTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var r in _trade)
			list.Add(new Godot.Collections.Dictionary
			{
				["a"] = Villages[r.A].Name, ["b"] = Villages[r.B].Name, ["sea"] = r.Sea, ["trips"] = r.Trips, ["length"] = r.Path.Length,
			});
		return list;
	}

	public int VehicleCount() => _vehicles.Count;
}
