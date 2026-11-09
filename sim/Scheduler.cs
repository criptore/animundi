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
		/// <summary>A system that is not about units (fire, births over time): it runs at its rate
		/// even when there are no units, with an empty range.</summary>
		public bool Global;
		/// <summary>Interval in coarse steps (ultra-fast mode), when longer than Interval:
		/// decisions are taken less often there. 0 = same as Interval.</summary>
		public float CoarseInterval;
		internal float Clock;
		internal int Next;
		/// <summary>Real milliseconds spent in this system since the last TakeTimes.</summary>
		public double Ms;
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
	/// <summary>Coarse steps for the ultra-fast speed: one step covers this many fixed steps.
	/// Systems that run every step (walking, fire) then run once with the longer time, so a
	/// century costs a fraction of what it does at normal speed. 1 = normal.</summary>
	public int StepScale = 1;

	/// <summary>Runs one fixed step of every system and process that is due.</summary>
	public void DoStep(int unitCapacity, int mapHeight)
	{
		float dt = Step * StepScale;
		Time += dt;
		foreach (var s in UnitSystems)
		{
			s.Clock += dt;
			float interval = StepScale > 1 && s.CoarseInterval > 0f ? s.CoarseInterval : s.Interval;
			float slice = interval / s.Batches;
			if (s.Batches == 1 && s.Clock >= slice * 2f)
			{
				// Several runs due at once (coarse steps): one run over the whole time.
				int due = (int)(s.Clock / slice);
				s.Clock -= due * slice;
				long t0 = System.Diagnostics.Stopwatch.GetTimestamp();
				if (s.Global)
					s.Run(0, 0, interval * due);
				else if (unitCapacity > 0)
					s.Run(0, unitCapacity, interval * due);
				s.Ms += System.Diagnostics.Stopwatch.GetElapsedTime(t0).TotalMilliseconds;
				continue;
			}
			while (s.Clock >= slice)
			{
				s.Clock -= slice;
				int per = (unitCapacity + s.Batches - 1) / Math.Max(s.Batches, 1);
				int a = s.Next * per;
				int b = Math.Min(unitCapacity, a + per);
				long t1 = System.Diagnostics.Stopwatch.GetTimestamp();
				if (s.Global)
					s.Run(0, 0, interval);
				else if (a < b)
					s.Run(a, b, interval);
				s.Ms += System.Diagnostics.Stopwatch.GetElapsedTime(t1).TotalMilliseconds;
				s.Next = (s.Next + 1) % s.Batches;
			}
		}
		foreach (var p in WorldProcesses)
		{
			p.Clock += dt;
			while (p.Clock >= p.Interval)
			{
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
}
