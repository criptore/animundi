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

	/// <summary>Whether the point (in tiles) stands on land.</summary>
	public bool IsLandAt(float x, float y) => IsLand((int)Mathf.Floor(x), (int)Mathf.Floor(y));
}
