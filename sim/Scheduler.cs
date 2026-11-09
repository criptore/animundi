using System;
using System.Collections.Generic;

namespace Animundi.Sim;

/// <summary>
/// Runs the simulation's systems at their own rates, in batches, the way WorldBox spreads its work
/// over frames (docs/WORLDBOX_ANALYSIS.md):
/// - a unit system runs over all units every `Interval` seconds, cut into `Batches` slices, one
///   slice at a time, so a heavy job (decisions) costs a fraction of it per step;
/// - a world process runs every `Interval` seconds over one horizontal slice of the map, so a
///   whole-map job (plant growth, fire, erosion) visits the map bit by bit.
/// Time is fixed-step: the same inputs always give the same world.
/// </summary>
public sealed class Scheduler
{
	public sealed class UnitSystem
	{
		public string Name;
		public float Interval;
		public int Batches;
		/// <summary>(first unit, end unit exclusive, seconds since this slice last ran).</summary>
		public Action<int, int, float> Run;
		internal float Clock;
		internal int Next;
	}

	public sealed class WorldProcess
	{
		public string Name;
		public float Interval;
		public int Slices;
		/// <summary>(first row, end row exclusive).</summary>
		public Action<int, int> Run;
		internal float Clock;
		internal int Next;
	}

	/// <summary>Length of one simulation step in seconds.</summary>
	public const float Step = 1f / 30f;

	public readonly List<UnitSystem> UnitSystems = new();
	public readonly List<WorldProcess> WorldProcesses = new();
	/// <summary>Simulated seconds since the start.</summary>
	public double Time;

	/// <summary>Runs one fixed step of every system and process that is due.</summary>
	public void DoStep(int unitCapacity, int mapHeight)
	{
		Time += Step;
		foreach (var s in UnitSystems)
		{
			s.Clock += Step;
			float slice = s.Interval / s.Batches;
			while (s.Clock >= slice)
			{
				s.Clock -= slice;
				int per = (unitCapacity + s.Batches - 1) / Math.Max(s.Batches, 1);
				int a = s.Next * per;
				int b = Math.Min(unitCapacity, a + per);
				if (a < b)
					s.Run(a, b, s.Interval);
				s.Next = (s.Next + 1) % s.Batches;
			}
		}
		foreach (var p in WorldProcesses)
		{
			p.Clock += Step;
			if (p.Clock < p.Interval)
				continue;
			p.Clock -= p.Interval;
			int rows = (mapHeight + p.Slices - 1) / p.Slices;
			int a = p.Next * rows;
			int b = Math.Min(mapHeight, a + rows);
			if (a < b)
				p.Run(a, b);
			p.Next = (p.Next + 1) % p.Slices;
		}
	}
}
