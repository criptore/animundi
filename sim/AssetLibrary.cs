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

	/// <summary>herbivore, carnivore, omnivore or none.</summary>
	[JsonPropertyName("diet")] public string Diet { get; set; } = "herbivore";
	/// <summary>0-12: a hunter only catches prey of its size or smaller.</summary>
	[JsonPropertyName("size")] public int Size { get; set; } = 5;
	/// <summary>Years (a year lasts Simulation.YearSeconds).</summary>
	[JsonPropertyName("lifespan")] public float Lifespan { get; set; } = 10f;
	/// <summary>Young per birth; 0 for creatures that do not breed.</summary>
	[JsonPropertyName("litter")] public int Litter { get; set; } = 1;
	/// <summary>Moves towards the equator in winter.</summary>
	[JsonPropertyName("migrates")] public bool Migrates { get; set; }

	public bool Grazes => Diet == "herbivore" || Diet == "omnivore";
	public bool Hunts => Diet == "carnivore" || Diet == "omnivore";
	public bool Eats => Diet != "none";
}

/// <summary>Properties of a biome (data/biomes.json).</summary>
public sealed class BiomeRecord
{
	/// <summary>How much grass grows, 0..1.</summary>
	[JsonPropertyName("fertility")] public float Fertility { get; set; }
	/// <summary>Per second, the chance a burning neighbour sets this tile on fire.</summary>
	[JsonPropertyName("burn_chance")] public float BurnChance { get; set; }
	/// <summary>Seconds a tile burns before turning to ash.</summary>
	[JsonPropertyName("burn_time")] public float BurnTime { get; set; } = 2.5f;
}

/// <summary>A plant that grows in a biome (data/plants.json).</summary>
public sealed class PlantEntry
{
	[JsonPropertyName("sprite")] public string Sprite { get; set; }
	[JsonPropertyName("per_tile")] public float PerTile { get; set; }
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

	private sealed class BiomesFile
	{
		[JsonPropertyName("biomes")] public Dictionary<string, BiomeRecord> Biomes { get; set; } = new();
	}

	private sealed class PlantsFile
	{
		[JsonPropertyName("biomes")] public Dictionary<string, List<PlantEntry>> Biomes { get; set; } = new();
	}

	public readonly List<SpeciesRecord> Species = new();
	private readonly Dictionary<string, int> _speciesIndex = new();
	/// <summary>Biome name -> plants that grow there.</summary>
	public Dictionary<string, List<PlantEntry>> Plants = new();
	/// <summary>Biome name -> its properties.</summary>
	public Dictionary<string, BiomeRecord> Biomes = new();

	public static AssetLibrary Load(string speciesPath = "res://data/species.json",
		string plantsPath = "res://data/plants.json", string biomesPath = "res://data/biomes.json")
	{
		var lib = new AssetLibrary();
		var file = JsonSerializer.Deserialize<SpeciesFile>(FileAccess.GetFileAsString(speciesPath));
		foreach (var s in file.Species)
		{
			lib._speciesIndex[s.Id] = lib.Species.Count;
			lib.Species.Add(s);
		}
		lib.Plants = JsonSerializer.Deserialize<PlantsFile>(FileAccess.GetFileAsString(plantsPath)).Biomes;
		lib.Biomes = JsonSerializer.Deserialize<BiomesFile>(FileAccess.GetFileAsString(biomesPath)).Biomes;
		return lib;
	}

	/// <summary>Index of a species, or -1.</summary>
	public int SpeciesIndex(string id) => _speciesIndex.TryGetValue(id, out int i) ? i : -1;
}
