using System;
using System.Collections.Generic;

namespace Animundi.Sim;

/// <summary>
/// The map cut into square zones (ZoneSize tiles across) holding the units inside them, for spatial
/// queries ("who is near here?") without scanning every unit. Rebuilt in one pass (a counting
/// sort) whenever units have moved: cheap, and no per-unit bookkeeping.
/// </summary>
public sealed class ZoneGrid
{
	public const int ZoneSize = 8;

	public readonly int ZonesX;
	public readonly int ZonesY;
	// Units of zone z are Members[Start[z] .. Start[z + 1]).
	private readonly int[] _start;
	private int[] _members = Array.Empty<int>();
	private int[] _zoneOf = Array.Empty<int>();

	public ZoneGrid(int widthTiles, int heightTiles)
	{
		ZonesX = (widthTiles + ZoneSize - 1) / ZoneSize;
		ZonesY = (heightTiles + ZoneSize - 1) / ZoneSize;
		_start = new int[ZonesX * ZonesY + 1];
	}

	public int ZoneAt(float x, float y)
	{
		int zx = Math.Clamp((int)(x / ZoneSize), 0, ZonesX - 1);
		int zy = Math.Clamp((int)(y / ZoneSize), 0, ZonesY - 1);
		return zy * ZonesX + zx;
	}

	/// <summary>Puts every living unit in its zone.</summary>
	public void Rebuild(UnitManager units)
	{
		int n = units.Capacity;
		if (_zoneOf.Length < n)
		{
			_zoneOf = new int[n];
			_members = new int[n];
		}
		Array.Clear(_start);
		for (int i = 0; i < n; i++)
		{
			if (!units.Alive[i])
			{
				_zoneOf[i] = -1;
				continue;
			}
			int z = ZoneAt(units.X[i], units.Y[i]);
			_zoneOf[i] = z;
			_start[z + 1]++;
		}
		for (int z = 0; z < ZonesX * ZonesY; z++)
			_start[z + 1] += _start[z];
		var fill = (int[])_start.Clone();
		for (int i = 0; i < n; i++)
			if (_zoneOf[i] >= 0)
				_members[fill[_zoneOf[i]]++] = i;
	}

	/// <summary>Adds to `result` the living units within `radius` tiles of (x, y).</summary>
	public void Query(UnitManager units, float x, float y, float radius, List<int> result)
	{
		int x0 = Math.Max(0, (int)((x - radius) / ZoneSize));
		int x1 = Math.Min(ZonesX - 1, (int)((x + radius) / ZoneSize));
		int y0 = Math.Max(0, (int)((y - radius) / ZoneSize));
		int y1 = Math.Min(ZonesY - 1, (int)((y + radius) / ZoneSize));
		float r2 = radius * radius;
		for (int zy = y0; zy <= y1; zy++)
			for (int zx = x0; zx <= x1; zx++)
			{
				int z = zy * ZonesX + zx;
				for (int k = _start[z]; k < _start[z + 1]; k++)
				{
					int i = _members[k];
					float dx = units.X[i] - x, dy = units.Y[i] - y;
					if (dx * dx + dy * dy <= r2)
						result.Add(i);
				}
			}
	}

	/// <summary>Number of units in zone z (for map layers and statistics).</summary>
	public int CountIn(int z) => _start[z + 1] - _start[z];
}
