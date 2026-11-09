using Godot;

namespace Animundi.Sim;

/// <summary>
/// The tile grid as the simulation sees it: one byte per tile and per layer, in flat arrays
/// (index = y * Width + x), copied from the GDScript world (scripts/world/world_data.gd).
/// </summary>
public sealed class SimWorld
{
	public const byte WaterLand = 0;

	public readonly int Width;
	public readonly int Height;
	public readonly byte[] Biome;
	public readonly byte[] Level;
	public readonly byte[] Water;

	public SimWorld(int width, int height)
	{
		Width = width;
		Height = height;
		Biome = new byte[width * height];
		Level = new byte[width * height];
		Water = new byte[width * height];
	}

	/// <summary>Copies the tile layers of a GDScript WorldData.</summary>
	public static SimWorld FromWorldData(GodotObject data)
	{
		var w = new SimWorld(data.Get("width").AsInt32(), data.Get("height").AsInt32());
		data.Get("biome").AsByteArray().CopyTo(w.Biome, 0);
		data.Get("level").AsByteArray().CopyTo(w.Level, 0);
		data.Get("water").AsByteArray().CopyTo(w.Water, 0);
		return w;
	}

	public int Index(int x, int y) => y * Width + x;

	public bool InBounds(int x, int y) => x >= 0 && y >= 0 && x < Width && y < Height;

	public bool IsLand(int x, int y) => InBounds(x, y) && Water[Index(x, y)] == WaterLand;

	/// <summary>For each land tile, the nearest water tile (sea, lake or river) within
	/// `maxDistance` steps, or -1 (breadth-first from every water tile).</summary>
	public int[] NearestWater(int maxDistance)
	{
		int n = Width * Height;
		var nearest = new int[n];
		var dist = new int[n];
		var queue = new int[n];
		int head = 0, tail = 0;
		for (int i = 0; i < n; i++)
		{
			nearest[i] = -1;
			dist[i] = int.MaxValue;
			if (Water[i] != WaterLand)
			{
				nearest[i] = i;
				dist[i] = 0;
				queue[tail++] = i;
			}
		}
		while (head < tail)
		{
			int i = queue[head++];
			if (dist[i] >= maxDistance)
				continue;
			int x = i % Width, y = i / Width;
			for (int k = 0; k < 4; k++)
			{
				int nx = x + (k == 0 ? 1 : k == 1 ? -1 : 0);
				int ny = y + (k == 2 ? 1 : k == 3 ? -1 : 0);
				if (!InBounds(nx, ny))
					continue;
				int j = ny * Width + nx;
				if (dist[j] != int.MaxValue)
					continue;
				dist[j] = dist[i] + 1;
				nearest[j] = nearest[i];
				queue[tail++] = j;
			}
		}
		return nearest;
	}

	/// <summary>Whether the point (in tiles) stands on land.</summary>
	public bool IsLandAt(float x, float y) => IsLand((int)Mathf.Floor(x), (int)Mathf.Floor(y));
}
