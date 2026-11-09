using System;
using System.Collections.Generic;

namespace Animundi.Sim;

/// <summary>
/// War between kingdoms (0.4): when a war is declared, each side sends an army of its warriors
/// against the enemy village nearest to it. Soldiers fight the enemy's people they meet (blows
/// with health, strength, training and weapons), defenders guard their land. A village whose
/// defenders are all gone while enemy soldiers stand in it is besieged, and taken when the siege
/// is complete: it joins the conqueror, a little disloyal. Wars end in peace (plans in
/// Kingdoms.cs), or when a kingdom has fallen.
/// </summary>
public partial class Simulation
{
	public sealed class War
	{
		public int A, B;
		public double Started;
		public int DeadA, DeadB;
		/// <summary>Village each side's army marches on, or -1.</summary>
		public int TargetA = -1, TargetB = -1;
	}

	public readonly List<War> Wars = new();
	// The road each kingdom's army takes to its target village (a land path), or null when the
	// target cannot be reached on foot (across the sea: boats of war come later).
	private readonly Dictionary<(int kingdom, int target), int[]> _armyPaths = new();
	public int WarDeaths { get; private set; }
	public int Conquests { get; private set; }
	/// <summary>Seconds of siege before a village with no defenders falls.</summary>
	public const float SiegeSeconds = 20f;

	public bool AtWar(int a, int b) => a >= 0 && b >= 0 && a != b && WarBetween(a, b) != null;

	public War WarBetween(int a, int b) => Wars.Find(w => w.A == a && w.B == b || w.A == b && w.B == a);

	/// <summary>Whether persons i and j belong to kingdoms at war.</summary>
	private bool Enemies(int i, int j)
	{
		int a = KingdomOfUnit(i), b = KingdomOfUnit(j);
		return a >= 0 && b >= 0 && AtWar(a, b);
	}

	private void DeclareWar(int a, int b, bool announce = true)
	{
		if (AtWar(a, b))
			return;
		Wars.Add(new War { A = a, B = b, Started = Scheduler.Time });
		Kingdoms[a].Allies.Remove(b);
		Kingdoms[b].Allies.Remove(a);
		if (announce)
			LogEvent($"{Kingdoms[a].Name} declares war on {Kingdoms[b].Name}!", "wars");
		// Allies of the attacked join in.
		foreach (int al in Kingdoms[b].Allies)
			if (al != a && Kingdoms[al].Alive && !AtWar(al, a))
			{
				Wars.Add(new War { A = al, B = a, Started = Scheduler.Time });
				LogEvent($"{Kingdoms[al].Name} stands by its ally {Kingdoms[b].Name} and goes to war.", "wars");
			}
	}

	private void MakePeace(int a, int b)
	{
		var war = WarBetween(a, b);
		if (war == null)
			return;
		Wars.Remove(war);
		// Lasting bitterness on both sides.
		Kingdoms[a].Memory[b] = (Kingdoms[a].Memory.TryGetValue(b, out float ma) ? ma : 0f) - 15f;
		Kingdoms[b].Memory[a] = (Kingdoms[b].Memory.TryGetValue(a, out float mb) ? mb : 0f) - 15f;
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Army[i] >= 0)
			{
				int k = KingdomOfUnit(i);
				if (k == a || k == b)
					Units.Army[i] = -1;
			}
		LogEvent($"peace between {Kingdoms[a].Name} and {Kingdoms[b].Name} after {(int)((Scheduler.Time - war.Started) / YearSeconds)} years of war"
			+ $" ({war.DeadA + war.DeadB} dead).", "wars");
	}

	// ------------------------------------------------------------------ armies and sieges

	/// <summary>Every 2 s: armies get targets and soldiers, besieged villages fall.</summary>
	private void WarStep(float dt)
	{
		foreach (var war in Wars.ToArray())
		{
			if (!Kingdoms[war.A].Alive || !Kingdoms[war.B].Alive)
			{
				Wars.Remove(war);
				continue;
			}
			war.TargetA = Muster(war.A, war.B, war.TargetA);
			war.TargetB = Muster(war.B, war.A, war.TargetB);
		}
		Sieges(dt);
	}

	/// <summary>Keeps kingdom k's army marching on a village of `enemy`: the nearest one to k's
	/// villages; two thirds of k's warriors join it, the rest guard home.</summary>
	private int Muster(int k, int enemy, int target)
	{
		if (target < 0 || !Villages[target].Alive || Villages[target].Kingdom != enemy)
		{
			target = -1;
			float best = float.MaxValue;
			for (int v = 0; v < Villages.Count; v++)
			{
				var ev = Villages[v];
				if (!ev.Alive || ev.Kingdom != enemy)
					continue;
				foreach (var own in Villages)
				{
					if (!own.Alive || own.Kingdom != k)
						continue;
					float d = Math.Abs(own.X - ev.X) + Math.Abs(own.Y - ev.Y);
					if (d < best)
					{
						best = d;
						target = v;
					}
				}
			}
			if (target >= 0)
			{
				_armyPaths[(k, target)] = ArmyPath(k, target);
				if (_armyPaths[(k, target)] != null)
					LogEvent($"the army of {Kingdoms[k].Name} marches on {Villages[target].Name}.", "wars");
			}
		}
		if (target < 0)
			return -1;
		int warriors = 0, marching = 0;
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Role[i] == (byte)Role.Warrior && IsAdult(i) && KingdomOfUnit(i) == k)
			{
				warriors++;
				if (Units.Army[i] >= 0)
					marching++;
			}
		int want = warriors * 2 / 3;
		for (int i = 0; i < Units.Capacity && marching < want; i++)
			if (Units.Alive[i] && Units.Role[i] == (byte)Role.Warrior && IsAdult(i) && KingdomOfUnit(i) == k && Units.Army[i] < 0)
			{
				Units.Army[i] = target;
				Units.ArmyStep[i] = -1;
				marching++;
			}
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Army[i] >= 0 && Units.Army[i] != target && KingdomOfUnit(i) == k)
			{
				Units.Army[i] = target;
				Units.ArmyStep[i] = -1;
			}
		return target;
	}

	/// <summary>A land road from the kingdom's village nearest to `target` to it, or null.</summary>
	private int[] ArmyPath(int k, int target)
	{
		var t = Villages[target];
		int from = -1;
		float best = float.MaxValue;
		foreach (var own in Villages)
			if (own.Alive && own.Kingdom == k)
			{
				float d = Math.Abs(own.X - t.X) + Math.Abs(own.Y - t.Y);
				if (d < best)
				{
					best = d;
					from = World.Index(own.X, own.Y + 1);
				}
			}
		return from < 0 ? null : FindPath(from, World.Index(t.X, t.Y + 1), water: false);
	}

	/// <summary>A village of a kingdom at war with enemy soldiers in it and no defender left is
	/// besieged; when the siege is complete it is taken.</summary>
	private void Sieges(float dt)
	{
		for (int v = 0; v < Villages.Count; v++)
		{
			var village = Villages[v];
			if (!village.Alive || village.Kingdom < 0)
				continue;
			int attackers = 0, defenders = 0, by = -1;
			_found.Clear();
			Zones.Query(Units, village.X + 0.5f, village.Y + 0.5f, 8f, _found);
			foreach (int i in _found)
			{
				if (!Units.Alive[i] || !Assets.Species[Units.Species[i]].IsPeople || !IsAdult(i))
					continue;
				int k = KingdomOfUnit(i);
				if (k == village.Kingdom && Units.Role[i] == (byte)Role.Warrior)
					defenders++;
				else if (k >= 0 && AtWar(k, village.Kingdom) && Units.Army[i] == v)
				{
					attackers++;
					by = k;
				}
			}
			if (attackers >= 2 && defenders == 0)
			{
				village.Siege += dt / SiegeSeconds;
				village.SiegeBy = by;
				// Besiegers set wooden buildings alight now and then.
				if (_rng.NextDouble() < 0.05 * dt && village.Buildings.Count > 0)
				{
					int b = village.Buildings[_rng.Next(village.Buildings.Count)];
					if (Buildings[b].Alive && Rec(b).Wooden && Buildings[b].Burning == 0f && Buildings[b].Type != _tRuin)
						SetBuildingOnFire(b);
				}
				if (village.Siege >= 1f)
					Conquer(v, by);
			}
			else
				village.Siege = Math.Max(0f, village.Siege - dt / SiegeSeconds);
		}
	}

	/// <summary>Village v is taken by kingdom k: it joins k, disloyal for a while.</summary>
	private void Conquer(int v, int k)
	{
		var village = Villages[v];
		int old = village.Kingdom;
		bool capital = Kingdoms[old].Capital == v;
		village.Siege = 0f;
		village.Conquered = 1f;
		village.CalmUntil = Scheduler.Time + YearSeconds * 5;
		village.Loyalty = -10f;
		JoinKingdom(v, k);
		Conquests++;
		LogEvent($"{Kingdoms[k].Name} takes {village.Name} from {Kingdoms[old].Name}{(capital ? ", its capital" : "")}!", "wars");
		if (capital)
			Kingdoms[old].Capital = -1;
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Army[i] == v)
				Units.Army[i] = -1;
	}

	// ------------------------------------------------------------------ soldiers and fights

	/// <summary>A soldier at war: fights the enemy near it, else marches on its army's target.
	/// True when it has something to do.</summary>
	private bool SoldierAtWar(int i, int v)
	{
		int target = Units.Army[i];
		if (EngageEnemy(i, 7f))
			return true;
		if (target < 0 || !Villages[target].Alive)
		{
			Units.Army[i] = -1;
			return false;
		}
		// Along the army's road, step by step: first to the start of the road (its nearest point
		// on this side), then from point to point, a couple of tiles ahead at a time.
		int k = KingdomOfUnit(i);
		if (!_armyPaths.TryGetValue((k, target), out var path) || path == null)
			return false;
		float Dist(int p)
		{
			float dx = path[p] % World.Width + 0.5f - Units.X[i], dy = path[p] / World.Width + 0.5f - Units.Y[i];
			return dx * dx + dy * dy;
		}
		int step = Units.ArmyStep[i];
		if (step < 0 || step >= path.Length)
		{
			step = 0;
			for (int p = 1; p < path.Length; p++)
				if (Dist(p) < Dist(step))
					step = p;
		}
		while (step < path.Length - 1 && Dist(step) < 2.5f)
			step++;
		Units.ArmyStep[i] = step;
		int next = path[Math.Min(path.Length - 1, step + 1)];
		float j = step >= path.Length - 2 ? 2.5f : 0.4f;
		GoTo(i, next % World.Width + 0.5f + ((float)_rng.NextDouble() - 0.5f) * j, next / World.Width + 0.6f + ((float)_rng.NextDouble() - 0.5f) * j, Task.Wander);
		return true;
	}

	/// <summary>Attacks the nearest enemy person within r tiles, soldiers first. True if found.</summary>
	private bool EngageEnemy(int i, float r)
	{
		_found.Clear();
		Zones.Query(Units, Units.X[i], Units.Y[i], r, _found);
		int best = -1;
		float bestScore = float.MaxValue;
		foreach (int j in _found)
		{
			if (j == i || !Units.Alive[j] || !Assets.Species[Units.Species[j]].IsPeople || !Enemies(i, j))
				continue;
			float dx = Units.X[j] - Units.X[i], dy = Units.Y[j] - Units.Y[i];
			float score = dx * dx + dy * dy - (Units.Role[j] == (byte)Role.Warrior ? 30f : 0f);
			if (score < bestScore)
			{
				bestScore = score;
				best = j;
			}
		}
		if (best < 0)
			return false;
		Units.Task[i] = (byte)Task.Hunt;
		Units.Prey[i] = best;
		return true;
	}

	/// <summary>Most health a person has: stronger peoples have more.</summary>
	private float MaxHealth(int i)
	{
		var race = Assets.Species[Units.Species[i]].Race;
		return 60f + 8f * (race?.Stat("strength") ?? 5f);
	}

	/// <summary>Damage of one blow: strength, a warrior's training, the village's weapons.</summary>
	private float BlowDamage(int i)
	{
		var race = Assets.Species[Units.Species[i]].Race;
		float d = 8f + 2.4f * (race?.Stat("strength") ?? 5f);
		if (Units.Role[i] == (byte)Role.Warrior)
		{
			int v = Units.Village[i];
			float weapons = v >= 0 ? Math.Min(1f, Villages[v].Weapons / Math.Max(1f, Villages[v].Population * 0.3f)) : 0f;
			d *= 1.3f + 0.5f * Units.Training[i] + 0.5f * weapons;
		}
		return d * (0.7f + 0.6f * (float)_rng.NextDouble());
	}

	/// <summary>Two people of kingdoms at war in reach: blows are exchanged, a second apart.
	/// Returns true while the fight goes on (the attacker stays on its target).</summary>
	private bool Fight(int i, int j, float dt)
	{
		Units.Wait[i] -= dt;
		if (Units.Wait[i] > 0f)
			return true;
		Units.Wait[i] = 0.8f + 0.4f * (float)_rng.NextDouble();
		Units.Health[j] -= BlowDamage(i);
		if (Units.Health[j] <= 0f)
		{
			WarDied(j);
			KillUnit(j, Death.War);
			Units.Prey[i] = -1;
			Units.Task[i] = (byte)Task.Wander;
			return false;
		}
		// The other strikes back.
		Units.Health[i] -= BlowDamage(j) * (Units.Role[j] == (byte)Role.Warrior ? 1f : 0.5f);
		if (Units.Health[i] <= 0f)
		{
			WarDied(i);
			KillUnit(i, Death.War);
			return false;
		}
		return true;
	}

	private void WarDied(int i)
	{
		WarDeaths++;
		int k = KingdomOfUnit(i);
		if (k < 0)
			return;
		Kingdoms[k].Weariness = Math.Min(1f, Kingdoms[k].Weariness + 0.02f);
		foreach (var w in Wars)
		{
			if (w.A == k)
				w.DeadA++;
			else if (w.B == k)
				w.DeadB++;
		}
	}

	/// <summary>Soldiers marching with an army and their mean distance to its target (tools, tests).</summary>
	public Godot.Collections.Dictionary ArmyInfo()
	{
		int n = 0;
		float dist = 0f;
		var jobs = new Dictionary<string, int>();
		for (int i = 0; i < Units.Capacity; i++)
			if (Units.Alive[i] && Units.Army[i] >= 0)
			{
				n++;
				var t = Villages[Units.Army[i]];
				dist += MathF.Abs(t.X - Units.X[i]) + MathF.Abs(t.Y - Units.Y[i]);
				string key = $"{JobNames[Units.Job[i]]}/{(Task)Units.Task[i]}";
				jobs[key] = jobs.TryGetValue(key, out int c) ? c + 1 : 1;
			}
		var d = new Godot.Collections.Dictionary { ["marching"] = n, ["distance"] = n > 0 ? dist / n : 0f };
		foreach (var (k, c) in jobs)
			d[k] = c;
		return d;
	}

	/// <summary>Whether a village is under siege, 0..1 (HUD).</summary>
	public float SiegeOf(int v) => Villages[v].Siege;

	/// <summary>Wars under way: sides, years, dead, targets (HUD, tests).</summary>
	public Godot.Collections.Array WarTable()
	{
		var list = new Godot.Collections.Array();
		foreach (var w in Wars)
			list.Add(new Godot.Collections.Dictionary
			{
				["a"] = Kingdoms[w.A].Name, ["b"] = Kingdoms[w.B].Name, ["years"] = (Scheduler.Time - w.Started) / YearSeconds,
				["dead"] = w.DeadA + w.DeadB, ["target_a"] = w.TargetA >= 0 ? Villages[w.TargetA].Name : "",
				["target_b"] = w.TargetB >= 0 ? Villages[w.TargetB].Name : "",
			});
		return list;
	}
}
