using System;
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
	[JsonPropertyName("color")] public string Color { get; set; } = "#ffffff";
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

	/// <summary>A people (data/races.json) rather than an animal: it lives in villages.</summary>
	public bool IsPeople { get; set; }
	/// <summary>For a people: its race record and this world's variation of it.</summary>
	public RaceRecord Race { get; set; }

	public bool Grazes => Diet == "herbivore" || Diet == "omnivore";
	public bool Hunts => Diet == "carnivore" || Diet == "omnivore";
	public bool Eats => Diet != "none";
}

/// <summary>One of the 12 peoples (data/races.json).</summary>
public sealed class RaceRecord
{
	[JsonPropertyName("id")] public string Id { get; set; }
	[JsonPropertyName("name")] public string Name { get; set; }
	[JsonPropertyName("color")] public string Color { get; set; } = "#ffffff";
	[JsonPropertyName("biomes")] public List<string> Biomes { get; set; } = new();
	[JsonPropertyName("size")] public int Size { get; set; } = 5;
	[JsonPropertyName("speed")] public float Speed { get; set; } = 1f;
	[JsonPropertyName("lifespan")] public float Lifespan { get; set; } = 70f;
	[JsonPropertyName("temperament")] public Dictionary<string, float> Temperament { get; set; } = new();
	[JsonPropertyName("stats")] public Dictionary<string, float> Stats { get; set; } = new();
	[JsonPropertyName("language")] public LanguageRecord Language { get; set; } = new();

	public float Temper(string key) => Temperament.TryGetValue(key, out float v) ? v : 0.5f;
	public float Stat(string key) => Stats.TryGetValue(key, out float v) ? v : 5f;

	/// <summary>This world's version of the race: stats, temperament and lifespan shifted by the
	/// world's seed (docs/GAME_DESIGN.md section 8.1).</summary>
	public RaceRecord Vary(Random rng)
	{
		float Shift(float v, float spread) => v * (1f + ((float)rng.NextDouble() * 2f - 1f) * spread);
		var r = (RaceRecord)MemberwiseClone();
		r.Speed = Shift(Speed, 0.1f);
		r.Lifespan = Shift(Lifespan, 0.15f);
		r.Temperament = new();
		foreach (var (k, v) in Temperament)
			r.Temperament[k] = Math.Clamp(v + ((float)rng.NextDouble() * 2f - 1f) * 0.2f, 0f, 1f);
		r.Stats = new();
		foreach (var (k, v) in Stats)
			r.Stats[k] = Math.Clamp(MathF.Round(Shift(v, 0.2f)), 1f, 10f);
		return r;
	}
}

/// <summary>The sounds a people's language draws from.</summary>
public sealed class LanguageRecord
{
	[JsonPropertyName("consonants")] public string Consonants { get; set; } = "";
	[JsonPropertyName("vowels")] public string Vowels { get; set; } = "";
	[JsonPropertyName("patterns")] public List<string> Patterns { get; set; } = new();
	[JsonPropertyName("endings")] public List<string> Endings { get; set; } = new();
}

/// <summary>A village building (data/buildings.json).</summary>
public sealed class BuildingRecord
{
	[JsonPropertyName("id")] public string Id { get; set; }
	[JsonPropertyName("name")] public string Name { get; set; }
	[JsonPropertyName("homes")] public int Homes { get; set; }
	[JsonPropertyName("cost")] public Dictionary<string, float> Cost { get; set; } = new();
	[JsonPropertyName("build")] public float Build { get; set; } = 10f;
	[JsonPropertyName("pop")] public int Pop { get; set; }
	[JsonPropertyName("requires")] public List<string> Requires { get; set; } = new();
	[JsonPropertyName("limit")] public int Limit { get; set; }
	[JsonPropertyName("per")] public int Per { get; set; }
	[JsonPropertyName("place")] public string Place { get; set; } = "cluster";
	[JsonPropertyName("near")] public string Near { get; set; } = "";
	[JsonPropertyName("material")] public string Material { get; set; } = "wood";
	[JsonPropertyName("upgrade")] public string Upgrade { get; set; } = "";
	[JsonPropertyName("job")] public string Job { get; set; } = "";

	public bool Wooden => Material == "wood";
	public float CostOf(string goods) => Cost.TryGetValue(goods, out float v) ? v : 0f;
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

	private sealed class BuildingsFile
	{
		[JsonPropertyName("buildings")] public List<BuildingRecord> Buildings { get; set; } = new();
	}

	private sealed class RacesFile
	{
		[JsonPropertyName("races")] public List<RaceRecord> Races { get; set; } = new();
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
	/// <summary>The 12 peoples, as written in data/races.json (unvaried).</summary>
	public List<RaceRecord> Races = new();
	/// <summary>Village buildings, in the order the building plan considers them.</summary>
	public List<BuildingRecord> Buildings = new();
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
		lib.Races = JsonSerializer.Deserialize<RacesFile>(FileAccess.GetFileAsString("res://data/races.json")).Races;
		lib.Buildings = JsonSerializer.Deserialize<BuildingsFile>(FileAccess.GetFileAsString("res://data/buildings.json")).Buildings;
		return lib;
	}

	/// <summary>Index of a building in data/buildings.json, or -1.</summary>
	public int BuildingIndex(string id) => Buildings.FindIndex(b => b.Id == id);

	/// <summary>Adds a species at run time (the peoples chosen for a world). Returns its index.</summary>
	public int AddSpecies(SpeciesRecord s)
	{
		_speciesIndex[s.Id] = Species.Count;
		Species.Add(s);
		return Species.Count - 1;
	}

	/// <summary>Removes the species added at run time (a new world starts).</summary>
	public void RemovePeoples()
	{
		Species.RemoveAll(s => s.IsPeople);
		_speciesIndex.Clear();
		for (int k = 0; k < Species.Count; k++)
			_speciesIndex[Species[k].Id] = k;
	}

	/// <summary>Index of a species, or -1.</summary>
	public int SpeciesIndex(string id) => _speciesIndex.TryGetValue(id, out int i) ? i : -1;
}
