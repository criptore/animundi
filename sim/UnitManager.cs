using System;

namespace Animundi.Sim;

/// <summary>
/// Every moving creature, stored as parallel arrays (structure of arrays) so batched updates walk
/// memory in order. A unit is an index; dead slots are reused through a free list.
/// Positions are in tiles (tile (x, y) covers x..x+1, y..y+1), at the unit's feet.
/// </summary>
public sealed class UnitManager
{
	public int Capacity { get; private set; }
	public int Count { get; private set; }

	public bool[] Alive = Array.Empty<bool>();
	public float[] X = Array.Empty<float>();
	public float[] Y = Array.Empty<float>();
	public float[] TargetX = Array.Empty<float>();
	public float[] TargetY = Array.Empty<float>();
	/// <summary>Index of the unit's species in the AssetLibrary.</summary>
	public int[] Species = Array.Empty<int>();
	/// <summary>Seconds left before the unit picks a new target when idle.</summary>
	public float[] Wait = Array.Empty<float>();
	/// <summary>1 when the unit last walked left (its sprite is mirrored).</summary>
	public bool[] FacingLeft = Array.Empty<bool>();

	// Life (0.2). Needs go from 0 (satisfied) to 1 (desperate).
	/// <summary>Age in years.</summary>
	public float[] Age = Array.Empty<float>();
	public float[] Hunger = Array.Empty<float>();
	public float[] Thirst = Array.Empty<float>();
	/// <summary>1 = rested, 0 = exhausted.</summary>
	public float[] Energy = Array.Empty<float>();
	/// <summary>Seconds before the unit can breed again.</summary>
	public float[] BreedWait = Array.Empty<float>();
	/// <summary>Seconds spent starving or dying of thirst (dies past a limit).</summary>
	public float[] Suffering = Array.Empty<float>();
	/// <summary>What the unit is doing: one of the Simulation.Task values.</summary>
	public byte[] Task = Array.Empty<byte>();
	/// <summary>Unit being hunted, or -1.</summary>
	public int[] Prey = Array.Empty<int>();

	// People (0.3). Animals keep the defaults (-1, 0, false).
	/// <summary>Village the person belongs to, or -1.</summary>
	public int[] Village = Array.Empty<int>();
	/// <summary>Villager, warrior, chief or shaman (Simulation.Role).</summary>
	public byte[] Role = Array.Empty<byte>();
	/// <summary>The village's work for this person (Simulation.Job).</summary>
	public byte[] Job = Array.Empty<byte>();
	public bool[] Female = Array.Empty<bool>();
	/// <summary>Partner, mother and father (unit indices), or -1.</summary>
	public int[] Partner = Array.Empty<int>();
	public int[] Mother = Array.Empty<int>();
	public int[] Father = Array.Empty<int>();
	/// <summary>Index of the person's name in Simulation's name list, or -1.</summary>
	public int[] Name = Array.Empty<int>();
	/// <summary>What the person carries home (Simulation.Goods) and how much.</summary>
	public byte[] Carry = Array.Empty<byte>();
	public float[] CarryAmount = Array.Empty<float>();
	/// <summary>Seconds of work left on the current task (chopping, harvesting, building).</summary>
	public float[] WorkTimer = Array.Empty<float>();
	/// <summary>What the work is aimed at (a plant, a tile or a building), or -1.</summary>
	public int[] WorkTarget = Array.Empty<int>();
	/// <summary>Personal traits, one bit each (Simulation.Trait).</summary>
	public int[] Traits = Array.Empty<int>();
	/// <summary>The building the person lives in, or -1.</summary>
	public int[] Home = Array.Empty<int>();
	/// <summary>A warrior's training on the dummies, 0..1.</summary>
	public float[] Training = Array.Empty<float>();

	private int[] _free = Array.Empty<int>();
	private int _freeCount;

	public int Spawn(int species, float x, float y)
	{
		int i;
		if (_freeCount > 0)
			i = _free[--_freeCount];
		else
		{
			if (Capacity == Alive.Length)
				Grow(Math.Max(256, Capacity * 2));
			i = Capacity++;
		}
		Alive[i] = true;
		X[i] = TargetX[i] = x;
		Y[i] = TargetY[i] = y;
		Species[i] = species;
		Wait[i] = 0f;
		FacingLeft[i] = false;
		Age[i] = 0f;
		Hunger[i] = 0f;
		Thirst[i] = 0f;
		Energy[i] = 1f;
		BreedWait[i] = 0f;
		Suffering[i] = 0f;
		Task[i] = 0;
		Prey[i] = -1;
		Village[i] = -1;
		Role[i] = 0;
		Job[i] = 0;
		Female[i] = false;
		Partner[i] = -1;
		Mother[i] = -1;
		Father[i] = -1;
		Name[i] = -1;
		Carry[i] = 0;
		CarryAmount[i] = 0f;
		WorkTimer[i] = 0f;
		WorkTarget[i] = -1;
		Traits[i] = 0;
		Home[i] = -1;
		Training[i] = 0f;
		Count++;
		return i;
	}

	public void Kill(int i)
	{
		if (!Alive[i])
			return;
		Alive[i] = false;
		_free[_freeCount++] = i;
		Count--;
	}

	public void Clear()
	{
		Array.Clear(Alive);
		Capacity = 0;
		Count = 0;
		_freeCount = 0;
	}

	private void Grow(int size)
	{
		Array.Resize(ref Alive, size);
		Array.Resize(ref X, size);
		Array.Resize(ref Y, size);
		Array.Resize(ref TargetX, size);
		Array.Resize(ref TargetY, size);
		Array.Resize(ref Species, size);
		Array.Resize(ref Wait, size);
		Array.Resize(ref FacingLeft, size);
		Array.Resize(ref Age, size);
		Array.Resize(ref Hunger, size);
		Array.Resize(ref Thirst, size);
		Array.Resize(ref Energy, size);
		Array.Resize(ref BreedWait, size);
		Array.Resize(ref Suffering, size);
		Array.Resize(ref Task, size);
		Array.Resize(ref Prey, size);
		Array.Resize(ref Village, size);
		Array.Resize(ref Role, size);
		Array.Resize(ref Job, size);
		Array.Resize(ref Female, size);
		Array.Resize(ref Partner, size);
		Array.Resize(ref Mother, size);
		Array.Resize(ref Father, size);
		Array.Resize(ref Name, size);
		Array.Resize(ref Carry, size);
		Array.Resize(ref CarryAmount, size);
		Array.Resize(ref WorkTimer, size);
		Array.Resize(ref WorkTarget, size);
		Array.Resize(ref Traits, size);
		Array.Resize(ref Home, size);
		Array.Resize(ref Training, size);
		Array.Resize(ref _free, size);
	}
}
