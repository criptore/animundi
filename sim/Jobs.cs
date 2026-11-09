using System;
using System.Collections.Generic;

namespace Animundi.Sim;

/// <summary>
/// Village jobs (docs/VILLAGES.md section 4), handed out every two seconds by what the village
/// lacks, with WorldBox's limits, and the work itself: walking to the spot, working there a few
/// seconds, bringing the goods home.
/// </summary>
public partial class Simulation
{
	public enum Job : byte
	{
		None, Gatherer, Woodcutter, Hunter, Builder, Farmer, Miner, Fisher, Blacksmith, Fireman, RoadBuilder, Soldier,
	}

	public static readonly string[] JobNames =
	{
		"idle", "gatherer", "woodcutter", "hunter", "builder", "farmer", "miner", "fisher", "blacksmith", "fireman",
		"road builder", "soldier",
	};

	public enum Goods : byte { None, Food, Wood, Stone, Metal, Gold }

	/// <summary>Goods are thrown into a stockpile or a town hall from this far (WorldBox: 7 tiles).</summary>
	private const float ThrowReach = 7f;

	/// <summary>Jobs by what the village lacks. Warriors are soldiers; chiefs, shamans and the young
	/// don't work. Each wanted job gets one worker first (most urgent first), then the rest fill up.</summary>
	private void HandOutWork(int v, List<int> people)
	{
		var village = Villages[v];
		int pop = people.Count;
		var adults = new List<int>();
		foreach (int i in people)
			if (IsAdult(i) && Units.Role[i] != (byte)Role.Chief && Units.Role[i] != (byte)Role.Shaman)
				adults.Add(i);
			else
				Units.Job[i] = (byte)Job.None;
		// Warriors: up to 35% of adults once the village has 15 people (more for warlike peoples).
		float aggression = Assets.Species[village.Species].Race?.Temper("aggression") ?? 0.5f;
		int warriors = 0;
		foreach (int i in adults)
			if (Units.Role[i] == (byte)Role.Warrior)
				warriors++;
		int wantWarriors = pop >= 15 ? (int)(adults.Count * (0.15f + 0.2f * aggression)) : 2;
		// The strong and the brave first, then anyone.
		for (int pass = 0; pass < 2 && warriors < wantWarriors; pass++)
			foreach (int i in adults)
			{
				if (warriors >= wantWarriors)
					break;
				bool fit = (Units.Traits[i] & ((int)Trait.Strong | (int)Trait.Brave)) != 0;
				if (Units.Role[i] == (byte)Role.Villager && (fit || pass == 1))
				{
					Units.Role[i] = (byte)Role.Warrior;
					warriors++;
				}
			}
		var workers = new List<int>();
		foreach (int i in adults)
		{
			if (Units.Role[i] == (byte)Role.Warrior)
				SetJob(i, Job.Soldier);
			else
				workers.Add(i);
		}
		if (workers.Count == 0)
			return;

		int fires = FiresIn(v);
		int fields = village.Fields.Count;
		float food = village.Food;
		// WorldBox's gatherer table, by food in store.
		int gatherers = food > 100 ? 1 : food > 60 ? 4 : food > 40 ? 5 : food > 20 ? 7 : 10;
		var want = new (Job job, int n)[]
		{
			(Job.Fireman, Math.Min(3, fires)),
			(Job.Builder, village.Site >= 0 ? 3 : 0),
			(Job.Gatherer, gatherers),
			(Job.Farmer, fields > 0 ? Math.Max(1, fields / 5) : 0),
			(Job.Woodcutter, village.Wood > 30 + pop ? 1 : 2 + pop / 10),
			(Job.Hunter, food < pop * 2f ? 2 : 1),
			(Job.Miner, village.ByType.TryGetValue(_tMine, out var mines) && mines.Count > 0 ? Math.Min(5, 1 + pop / 10) : 0),
			(Job.Fisher, village.ByType.TryGetValue(_tDock, out var docks) && docks.Count > 0 ? Math.Min(3, 1 + pop / 15) : 0),
			(Job.Blacksmith, pop >= 15 && village.Metal >= 1f ? 1 : 0),
			(Job.RoadBuilder, village.RoadPlan.Count > 0 ? 1 : 0),
		};
		var target = new int[JobNames.Length];
		int left = workers.Count;
		foreach (var (job, n) in want)
			if (n > 0 && left > 0)
			{
				target[(int)job] = 1;
				left--;
			}
		foreach (var (job, n) in want)
		{
			int more = Math.Min(n - target[(int)job], left);
			if (more > 0)
			{
				target[(int)job] += more;
				left -= more;
			}
		}
		target[(int)Job.Gatherer] += left;

		// People keep the job they have when it is still wanted; the others move.
		var have = new int[JobNames.Length];
		var free = new List<int>();
		foreach (int i in workers)
		{
			int j = Units.Job[i];
			if (j != 0 && j != (int)Job.Soldier && have[j] < target[j])
				have[j]++;
			else
				free.Add(i);
		}
		foreach (int i in free)
		{
			int best = (int)Job.Gatherer;
			for (int j = 1; j < JobNames.Length; j++)
				if (have[j] < target[j])
				{
					best = j;
					break;
				}
			SetJob(i, (Job)best);
			have[best]++;
		}
	}

	private void SetJob(int i, Job job)
	{
		if (Units.Job[i] == (byte)job)
			return;
		Units.Job[i] = (byte)job;
		Units.WorkTarget[i] = -1;
		if (Units.Task[i] == (byte)Task.Work)
			Units.Task[i] = (byte)Task.Wander;
	}

	/// <summary>Burning tiles and buildings in the village's land.</summary>
	private int FiresIn(int v)
	{
		int n = 0;
		foreach (int t in _burningTiles)
			if (Owns(v, t % World.Width, t / World.Width))
				n++;
		foreach (int b in Villages[v].Buildings)
			if (Buildings[b].Alive && Buildings[b].Burning > 0f)
				n += 2;
		return n;
	}

	/// <summary>Tools make work faster: up to a third less time when every worker has some.</summary>
	private float ToolSpeed(int v)
	{
		var village = Villages[v];
		return 1f + 0.5f * Math.Min(1f, village.Tools / Math.Max(1f, village.Population * 0.5f));
	}

	/// <summary>The store nearest to the person: a stockpile, the town hall or the bonfire.</summary>
	private int NearestStore(int i, int v)
	{
		int best = -1;
		float bestD = float.MaxValue;
		foreach (int type in _storeTypes)
		{
			if (!Villages[v].ByType.TryGetValue(type, out var list))
				continue;
			foreach (int b in list)
			{
				var bld = Buildings[b];
				if (!bld.Alive || !bld.Done)
					continue;
				float dx = bld.X + 0.5f - Units.X[i], dy = bld.Y + 1f - Units.Y[i];
				float d = dx * dx + dy * dy;
				if (d < bestD)
				{
					bestD = d;
					best = b;
				}
			}
		}
		return best;
	}

	private void Store(Village village, Goods goods, float amount)
	{
		switch (goods)
		{
			case Goods.Food: village.Food += amount; break;
			case Goods.Wood: village.Wood += amount; break;
			case Goods.Stone: village.Stone += amount; break;
			case Goods.Metal: village.Metal += amount; break;
			case Goods.Gold: village.Gold += amount; break;
		}
	}

	private void Deliver(int i, int v)
	{
		Store(Villages[v], (Goods)Units.Carry[i], Units.CarryAmount[i]);
		Units.Carry[i] = 0;
		Units.CarryAmount[i] = 0f;
	}

	/// <summary>Goes to work: first brings home what it carries (thrown in from 7 tiles of a
	/// stockpile or town hall), then walks to its job's spot.</summary>
	private void Work(int i, int v, SpeciesRecord sp)
	{
		var village = Villages[v];
		// On campaign, what a soldier takes goes to the army's supplies (the village's stores).
		if (Units.Carry[i] != 0 && Units.Army[i] >= 0)
			Deliver(i, v);
		if (Units.Carry[i] != 0)
		{
			int store = NearestStore(i, v);
			var bld = store >= 0 ? Buildings[store] : null;
			float sx = bld != null ? bld.X + 0.5f : village.X + 0.5f, sy = bld != null ? bld.Y + 1.1f : village.Y + 0.9f;
			float dx = sx - Units.X[i], dy = sy - Units.Y[i];
			if (bld != null && bld.Type != _tBonfire && dx * dx + dy * dy <= ThrowReach * ThrowReach)
				Deliver(i, v);
			else
			{
				GoTo(i, sx, sy, Task.Deliver);
				return;
			}
		}
		switch ((Job)Units.Job[i])
		{
			case Job.Gatherer:
			{
				// The best grass (wild grains, berries, herbs) near the village.
				float best = 0.45f;
				int bt = -1;
				int r = village.Food < village.Population * 2f ? 18 : 12;
				for (int k = 0; k < 12; k++)
				{
					int x = village.X + _rng.Next(-r, r + 1), y = village.Y + _rng.Next(-r, r + 1);
					if (!World.IsLand(x, y))
						continue;
					int t = World.Index(x, y);
					if (Grass[t] > best && _buildingAt[t] < 0 && _ground[t] == 0)
					{
						best = Grass[t];
						bt = t;
					}
				}
				if (bt >= 0)
					StartWork(i, v, bt, 2f, bt % World.Width + 0.5f, bt / World.Width + 0.6f);
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
					StartWork(i, v, tree, 3f, _pX[tree] - 0.4f, _pY[tree]);
				else
					WanderNear(i, v, 10f);
				break;
			}
			case Job.Hunter:
				if (!TryHunt(i, sp))
					WanderNear(i, v, 12f);
				break;
			case Job.Builder:
				if (village.Site >= 0 && Buildings[village.Site].Alive)
				{
					var site = Buildings[village.Site];
					StartWork(i, v, village.Site, 1f, site.X + 0.5f + ((float)_rng.NextDouble() - 0.5f) * 1.4f, site.Y + 1.15f);
				}
				else
					WanderNear(i, v, 4f);
				break;
			case Job.Farmer:
			{
				// Ripe wheat first; sowing bare fields when it is not winter.
				int field = -1;
				bool sow = Season() != 3;
				for (int k = 0; k < 8 && village.Fields.Count > 0; k++)
				{
					int t = village.Fields[_rng.Next(village.Fields.Count)];
					if (_wheat[t] >= 1f)
					{
						field = t;
						break;
					}
					if (field < 0 && sow && _wheat[t] <= 0f)
						field = t;
				}
				if (field >= 0)
					StartWork(i, v, field, 2f, field % World.Width + 0.5f, field / World.Width + 0.6f);
				else
					WanderNear(i, v, 5f);
				break;
			}
			case Job.Miner:
			case Job.Fisher:
			{
				int b = Nearest(v, Units.Job[i] == (byte)Job.Miner ? _tMine : _tDock, i);
				if (b >= 0)
					StartWork(i, v, b, Units.Job[i] == (byte)Job.Miner ? 6f : 5f, Buildings[b].X + 0.5f, Buildings[b].Y + 1.1f);
				else
					WanderNear(i, v, 5f);
				break;
			}
			case Job.Blacksmith:
			{
				int b = NearestStore(i, v);
				if (b >= 0 && village.Metal >= 1f)
					StartWork(i, v, b, 6f, Buildings[b].X + 1.1f, Buildings[b].Y + 1.1f);
				else
					WanderNear(i, v, 3f);
				break;
			}
			case Job.Fireman:
			{
				int fire = NearestFire(i, v);
				if (fire >= 0)
					StartWork(i, v, fire, 1f, fire % World.Width + 0.5f, fire / World.Width + 1.2f);
				else
					WanderNear(i, v, 4f);
				break;
			}
			case Job.RoadBuilder:
			{
				while (village.RoadPlan.Count > 0)
				{
					int t = village.RoadPlan[0];
					if (_buildingAt[t] < 0 && _ground[t] == 0 && Owns(v, t % World.Width, t / World.Width))
						break;
					village.RoadPlan.RemoveAt(0);
				}
				if (village.RoadPlan.Count > 0)
				{
					int t = village.RoadPlan[0];
					StartWork(i, v, t, 1.5f, t % World.Width + 0.5f, t / World.Width + 0.6f);
				}
				else
					WanderNear(i, v, 4f);
				break;
			}
			case Job.Soldier:
			{
				// At war: march with the army and fight. Then enemies and beasts in the village's
				// land; then training on the dummies; else the hunt.
				if (Units.Army[i] >= 0 && SoldierAtWar(i, v))
					break;
				if (GuardVillage(i, v))
					break;
				int dummy = Nearest(v, _tDummy, i);
				if (dummy >= 0 && Units.Training[i] < 1f)
					StartWork(i, v, dummy, 4f, Buildings[dummy].X + 1.1f, Buildings[dummy].Y + 0.9f);
				else if (!TryHunt(i, sp))
					WanderNear(i, v, 10f);
				break;
			}
		}
	}

	private void StartWork(int i, int v, int target, float seconds, float x, float y)
	{
		Units.WorkTarget[i] = target;
		Units.WorkTimer[i] = seconds / ToolSpeed(v);
		GoTo(i, x, y, Task.Work);
	}

	/// <summary>The built building of `type` of the village nearest to person i, or -1.</summary>
	private int Nearest(int v, int type, int i)
	{
		int best = -1;
		float bestD = float.MaxValue;
		if (!Villages[v].ByType.TryGetValue(type, out var list))
			return -1;
		foreach (int b in list)
		{
			var bld = Buildings[b];
			if (!bld.Alive || !bld.Done || bld.Type != type)
				continue;
			float dx = bld.X - Units.X[i], dy = bld.Y - Units.Y[i];
			if (dx * dx + dy * dy < bestD)
			{
				bestD = dx * dx + dy * dy;
				best = b;
			}
		}
		return best;
	}

	/// <summary>The burning tile of the village's land nearest to person i (a burning building's
	/// tile counts), or -1.</summary>
	private int NearestFire(int i, int v)
	{
		int best = -1;
		float bestD = float.MaxValue;
		void Try(int t)
		{
			float dx = t % World.Width - Units.X[i], dy = t / World.Width - Units.Y[i];
			if (dx * dx + dy * dy < bestD)
			{
				bestD = dx * dx + dy * dy;
				best = t;
			}
		}
		foreach (int b in Villages[v].Buildings)
			if (Buildings[b].Alive && Buildings[b].Burning > 0f)
				Try(World.Index(Buildings[b].X, Buildings[b].Y));
		foreach (int t in _burningTiles)
			if (Owns(v, t % World.Width, t / World.Width))
				Try(t);
		return best;
	}

	/// <summary>A soldier goes after a beast that hunts in the village's land.</summary>
	private bool GuardVillage(int i, int v)
	{
		var village = Villages[v];
		// Enemy soldiers in the village's land come first.
		if (EngageEnemy(i, 9f) && Owns(v, (int)Units.X[Units.Prey[i]], (int)Units.Y[Units.Prey[i]]))
			return true;
		Units.Prey[i] = -1;
		Units.Task[i] = (byte)Task.Wander;
		_found.Clear();
		Zones.Query(Units, village.X + 0.5f, village.Y + 0.5f, 14f, _found);
		foreach (int j in _found)
		{
			var sp = Assets.Species[Units.Species[j]];
			if (Units.Alive[j] && !sp.IsPeople && sp.Diet == "carnivore" && Owns(v, (int)Units.X[j], (int)Units.Y[j]))
			{
				Units.Task[i] = (byte)Task.Hunt;
				Units.Prey[i] = j;
				return true;
			}
		}
		return false;
	}

	/// <summary>How likely a person is to win against a beast that attacks them: warriors more
	/// (trained ones and those with weapons more still), the brave more than the others.</summary>
	private float DefendChance(int j)
	{
		int v = Units.Village[j];
		float weapons = v >= 0 ? Math.Min(1f, Villages[v].Weapons / Math.Max(1f, Villages[v].Population * 0.3f)) : 0f;
		if (Units.Role[j] == (byte)Role.Warrior)
			return Math.Min(0.97f, 0.8f + 0.1f * Units.Training[j] + 0.07f * weapons);
		return (Units.Traits[j] & (int)Trait.Brave) != 0 ? 0.65f : 0.5f;
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

	/// <summary>Working at the spot, a second at a time. Returns true when it did something.</summary>
	private bool DoWork(int i, int v, float dt)
	{
		Units.WorkTimer[i] -= dt;
		int target = Units.WorkTarget[i];
		var village = Villages[v];
		switch ((Job)Units.Job[i])
		{
			case Job.Gatherer:
				if (Units.WorkTimer[i] > 0f)
					return true;
				if (target >= 0 && Grass[target] > 0.2f)
				{
					Grass[target] -= 0.35f;
					Carry(i, Goods.Food, 3f);
				}
				break;
			case Job.Woodcutter:
				if (target < 0 || !_pAlive[target])
					break;
				if (Units.WorkTimer[i] > 0f)
					return true;
				RemovePlant(target);
				Carry(i, Goods.Wood, 4f);
				break;
			case Job.Builder:
				if (target < 0 || target != village.Site || !Buildings[target].Alive)
					break;
				if (!BuildSome(v, target, dt * ToolSpeed(v)))
					return true;
				break;
			case Job.Farmer:
				if (Units.WorkTimer[i] > 0f)
					return true;
				if (target >= 0 && _ground[target] == GroundField)
				{
					if (_wheat[target] >= 1f)
					{
						Carry(i, Goods.Food, 5f);
						_wheat[target] = 0f;
						_overlayChanged.Add(target);
					}
					else if (_wheat[target] <= 0f && Season() != 3)
					{
						_wheat[target] = 0.01f;
						_overlayChanged.Add(target);
					}
				}
				break;
			case Job.Miner:
				if (Units.WorkTimer[i] > 0f)
					return true;
				if (target >= 0 && Buildings[target].Alive && Buildings[target].Type == _tMine)
				{
					// Mostly stone, some metal; gold only in the hills and mountains.
					double roll = _rng.NextDouble();
					bool rock = NearRock(Buildings[target].X, Buildings[target].Y);
					if (rock && roll < 0.08)
						Carry(i, Goods.Gold, 1f);
					else if (roll < 0.35)
						Carry(i, Goods.Metal, 1f);
					else
						Carry(i, Goods.Stone, 3f);
				}
				break;
			case Job.Fisher:
				if (Units.WorkTimer[i] > 0f)
					return true;
				if (target >= 0 && Buildings[target].Alive && NextToWater(Buildings[target].X, Buildings[target].Y))
					Carry(i, Goods.Food, 4f);
				break;
			case Job.Blacksmith:
				if (Units.WorkTimer[i] > 0f)
					return true;
				if (village.Metal >= 1f)
				{
					village.Metal -= 1f;
					if (village.Tools < village.Population / 2)
						village.Tools++;
					else
						village.Weapons++;
				}
				break;
			case Job.Fireman:
			{
				if (target < 0)
					break;
				// Water on the fire: the tile and those around it, and the building there.
				int tx = target % World.Width, ty = target / World.Width;
				for (int dy = -1; dy <= 1; dy++)
					for (int dx = -1; dx <= 1; dx++)
						if (World.InBounds(tx + dx, ty + dy))
							PutOut(World.Index(tx + dx, ty + dy));
				break;
			}
			case Job.RoadBuilder:
				if (Units.WorkTimer[i] > 0f)
					return true;
				if (target >= 0 && _buildingAt[target] < 0 && _ground[target] == 0)
					SetGround(target, GroundRoad);
				village.RoadPlan.Remove(target);
				break;
			case Job.Soldier:
				if (Units.WorkTimer[i] > 0f)
					return true;
				Units.Training[i] = Math.Min(1f, Units.Training[i] + 0.05f);
				break;
		}
		Units.Task[i] = (byte)Task.Wander;
		Units.WorkTarget[i] = -1;
		return true;
	}

	private void Carry(int i, Goods goods, float amount)
	{
		Units.Carry[i] = (byte)goods;
		Units.CarryAmount[i] = amount;
	}

	/// <summary>Puts out the fire on tile t: the ground, its plants and the building on it.</summary>
	private void PutOut(int t)
	{
		if (TileBurn[t] > 0f)
		{
			TileBurn[t] = 0f;
			_burningTiles.Remove(t);
			Scorch[t] = Math.Max(Scorch[t], (byte)120);
			_scorchChanged.Add(t);
		}
		for (int p = _tileFirst[t]; p >= 0; p = _pNext[p])
			if (_pBurn[p] > 0f)
			{
				_pBurn[p] = 0f;
				_burning.Remove(p);
			}
		int b = _buildingAt[t];
		if (b >= 0 && Buildings[b].Burning > 0f)
		{
			Buildings[b].Burning = 0f;
			FiresPutOut++;
		}
	}

	public int FiresPutOut { get; private set; }
}
