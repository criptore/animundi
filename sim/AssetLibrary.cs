using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;
using Godot;

namespace Animundi.Sim;

/// <summary>A species as a data record (data/species.json).</summary>
public sealed class SpeciesRecord
{
	[JsonPropertyName("id")] public string Id { get; set; }
	[JsonPropertyName("name")] public string Name { get; set; }
	[JsonPropertyName("sprite")] public string Sprite { get; set; }
	/// <summary>Tiles per second.</summary>
	[JsonPropertyName("speed")] public float Speed { get; set; } = 1f;
	/// <summary>How far, in tiles, it wanders from where it stands.</summary>
	[JsonPropertyName("roam")] public float Roam { get; set; } = 6f;
	/// <summary>Biome name (scripts/world/biomes.gd) -> weight, where it is born on its own.
	/// Empty: it never appears by itself, only through the player or events.</summary>
	[JsonPropertyName("natural")] public Dictionary<string, float> Natural { get; set; } = new();

	public bool IsNatural => Natural.Count > 0;
}

/// <summary>
/// Content as data, the way WorldBox's AssetManager holds its libraries: adding a creature is
/// adding a record, not code. Later the AI minds will write records too (docs/GAME_DESIGN.md).
/// </summary>
public sealed class AssetLibrary
{
	private sealed class SpeciesFile
	{
		[JsonPropertyName("species")] public List<SpeciesRecord> Species { get; set; } = new();
	}

	public readonly List<SpeciesRecord> Species = new();
	private readonly Dictionary<string, int> _speciesIndex = new();

	public static AssetLibrary Load(string speciesPath = "res://data/species.json")
	{
		var lib = new AssetLibrary();
		var file = JsonSerializer.Deserialize<SpeciesFile>(FileAccess.GetFileAsString(speciesPath));
		foreach (var s in file.Species)
		{
			lib._speciesIndex[s.Id] = lib.Species.Count;
			lib.Species.Add(s);
		}
		return lib;
	}

	/// <summary>Index of a species, or -1.</summary>
	public int SpeciesIndex(string id) => _speciesIndex.TryGetValue(id, out int i) ? i : -1;
}
