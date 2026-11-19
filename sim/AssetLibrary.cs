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
	/// <summary>A legendary monster (data/legends.json): unique, with a mind (Legends.cs).</summary>
	public bool IsLegend { get; set; }
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

/// <summary>A legendary monster (data/legends.json): unique in a world, with a mind.</summary>
public sealed class LegendRecord
{
	[JsonPropertyName("id")] public string Id { get; set; }
	[JsonPropertyName("title")] public string Title { get; set; }
	[JsonPropertyName("sprite")] public string Sprite { get; set; }
	/// <summary>Biomes where it sleeps and wakes.</summary>
	[JsonPropertyName("lair")] public List<string> Lair { get; set; } = new();
	/// <summary>Odds that a world holds it.</summary>
	[JsonPropertyName("chance")] public float Chance { get; set; } = 0.5f;
	/// <summary>The years between which it wakes: [from, to].</summary>
	[JsonPropertyName("wake")] public List<int> Wake { get; set; } = new() { 5, 30 };
	[JsonPropertyName("health")] public float Health { get; set; } = 3000f;
	/// <summary>How many it can strike down at once.</summary>
	[JsonPropertyName("strength")] public int Strength { get; set; } = 3;
	[JsonPropertyName("speed")] public float Speed { get; set; } = 1f;
	[JsonPropertyName("roam")] public float Roam { get; set; } = 20f;
	/// <summary>What its strikes do: fire, stomp, roots, raise_dead, quake, lightning.</summary>
	[JsonPropertyName("power")] public string Power { get; set; } = "stomp";
	/// <summary>The domain of the god its deeds give a people, and the myth's deed.</summary>
	[JsonPropertyName("domain")] public string Domain { get; set; } = "the beasts";
	[JsonPropertyName("deed")] public string Deed { get; set; } = "Loosed the Beast";
	/// <summary>wrath, greed, cunning, pride, 0..1.</summary>
	[JsonPropertyName("temper")] public Dictionary<string, float> Temper { get; set; } = new();
	/// <summary>Syllables of its name: one from the first half, one from the second.</summary>
	[JsonPropertyName("names")] public List<string> Names { get; set; } = new();
	[JsonPropertyName("lore")] public string Lore { get; set; } = "";

	public float T(string key) => Temper.TryGetValue(key, out float v) ? v : 0.5f;
}

/// <summary>A kind of nature spirit (data/spirits.json): the lands it can be the spirit of.</summary>
public sealed class SpiritRecord
{
	[JsonPropertyName("kind")] public string Kind { get; set; }
	/// <summary>What its lands are called: "the Northern Woods".</summary>
	[JsonPropertyName("places")] public List<string> Places { get; set; } = new();
	[JsonPropertyName("biomes")] public List<string> Biomes { get; set; } = new();
	/// <summary>The domain of the god a people makes of it.</summary>
	[JsonPropertyName("domain")] public string Domain { get; set; } = "the wild";
	[JsonPropertyName("deed")] public string Deed { get; set; } = "Spoke from the Wild";
	/// <summary>What it does in anger (Spirits.cs), and its gift when content.</summary>
	[JsonPropertyName("wrath")] public List<string> Wrath { get; set; } = new();
	[JsonPropertyName("gift")] public string Gift { get; set; } = "bloom";
	/// <summary>Syllables of its name: one from the first half, one from the second.</summary>
	[JsonPropertyName("names")] public List<string> Names { get; set; } = new();
	[JsonPropertyName("lore")] public string Lore { get; set; } = "";
	/// <summary>Only born of land the world did not have at first (volcanoes).</summary>
	[JsonPropertyName("late")] public bool Late { get; set; }
}

/// <summary>An age of a people (data/ages.json, Ages.cs).</summary>
public sealed class AgeRecord
{
	[JsonPropertyName("id")] public string Id { get; set; }
	[JsonPropertyName("name")] public string Name { get; set; }
	/// <summary>Knowledge it takes to leave this age for the next.</summary>
	[JsonPropertyName("knowledge")] public float Knowledge { get; set; } = 100f;
	[JsonPropertyName("strength")] public float Strength { get; set; } = 1f;
	[JsonPropertyName("work")] public float Work { get; set; } = 1f;
	/// <summary>What each person gives to the air in a year.</summary>
	[JsonPropertyName("pollution")] public float Pollution { get; set; }
	/// <summary>Effects of the invention language this age unlocks.</summary>
	[JsonPropertyName("blocks")] public List<string> Blocks { get; set; } = new();
	/// <summary>vehicle, ship, home, weapon: the age's designs before a people renames them.</summary>
	[JsonPropertyName("designs")] public Dictionary<string, string> Designs { get; set; } = new();
	[JsonPropertyName("lore")] public string Lore { get; set; } = "";
}

/// <summary>What the ages past the future are made of (data/ages.json "beyond").</summary>
public sealed class BeyondRecord
{
	[JsonPropertyName("first")] public List<string> First { get; set; } = new();
	[JsonPropertyName("second")] public List<string> Second { get; set; } = new();
	[JsonPropertyName("growth")] public float Growth { get; set; } = 1.33f;
	[JsonPropertyName("vehicle")] public List<string> Vehicle { get; set; } = new();
	[JsonPropertyName("home")] public List<string> Home { get; set; } = new();
	[JsonPropertyName("weapon")] public List<string> Weapon { get; set; } = new();
}

/// <summary>A mood of the world (data/eras.json, Eras.cs).</summary>
public sealed class EraRecord
{
	[JsonPropertyName("id")] public string Id { get; set; }
	[JsonPropertyName("name")] public string Name { get; set; }
	[JsonPropertyName("weight")] public float Weight { get; set; } = 1f;
	[JsonPropertyName("growth")] public float Growth { get; set; } = 1f;
	[JsonPropertyName("cold")] public float Cold { get; set; }
	[JsonPropertyName("fire")] public float Fire { get; set; } = 1f;
	[JsonPropertyName("monsters")] public float Monsters { get; set; } = 1f;
	[JsonPropertyName("spirits")] public float Spirits { get; set; } = 1f;
	[JsonPropertyName("knowledge")] public float Knowledge { get; set; } = 1f;
	[JsonPropertyName("harvest")] public float Harvest { get; set; } = 1f;
	/// <summary>Kind of disaster -> how much likelier (1 = as usual).</summary>
	[JsonPropertyName("disasters")] public Dictionary<string, float> Disasters { get; set; } = new();
	[JsonPropertyName("tint")] public List<float> Tint { get; set; } = new() { 1f, 1f, 1f };
	[JsonPropertyName("lore")] public string Lore { get; set; } = "";

	public float DisasterWeight(string kind) => Disasters.TryGetValue(kind, out float w) ? w : 1f;
}

/// <summary>A symptom diseases are generated from (data/diseases.json).</summary>
public sealed class SymptomRecord
{
	[JsonPropertyName("id")] public string Id { get; set; }
	[JsonPropertyName("nouns")] public List<string> Nouns { get; set; } = new();
	[JsonPropertyName("text")] public string Text { get; set; } = "";
	/// <summary>Chance per second to pass it to someone close: [from, to].</summary>
	[JsonPropertyName("contagion")] public List<float> Contagion { get; set; } = new() { 0.05f, 0.1f };
	/// <summary>Share of the sick who die of it: [from, to].</summary>
	[JsonPropertyName("lethality")] public List<float> Lethality { get; set; } = new() { 0.1f, 0.3f };
	/// <summary>Seconds it lasts: [from, to].</summary>
	[JsonPropertyName("seconds")] public List<float> Seconds { get; set; } = new() { 25f, 45f };
}

/// <summary>A change a monster species can go through (data/monsters.json).</summary>
public sealed class MutationRecord
{
	[JsonPropertyName("id")] public string Id { get; set; }
	[JsonPropertyName("adjective")] public string Adjective { get; set; } = "";
	[JsonPropertyName("text")] public string Text { get; set; } = "";
	[JsonPropertyName("speed")] public float Speed { get; set; } = 1f;
	[JsonPropertyName("roam")] public float Roam { get; set; } = 1f;
	[JsonPropertyName("size")] public int Size { get; set; }
	[JsonPropertyName("litter")] public int Litter { get; set; }
	[JsonPropertyName("lifespan")] public float Lifespan { get; set; } = 1f;
	/// <summary>Multiplies the chance people have to fight it off.</summary>
	[JsonPropertyName("defend")] public float Defend { get; set; } = 1f;
	/// <summary>Multiplies how fast its lairs bring new ones.</summary>
	[JsonPropertyName("spawn")] public float Spawn { get; set; } = 1f;
	/// <summary>fire (what it kills burns), plague (it carries a sickness), or "".</summary>
	[JsonPropertyName("ability")] public string Ability { get; set; } = "";
}

/// <summary>A common monster (data/monsters.json): its lair and the changes it can go through.</summary>
public sealed class MonsterRecord
{
	[JsonPropertyName("id")] public string Id { get; set; }
	/// <summary>nest, crypt, pit, cave, pool or cairn (the lair's sprite), and what it is called.</summary>
	[JsonPropertyName("lair")] public string Lair { get; set; } = "cave";
	[JsonPropertyName("lair_name")] public string LairName { get; set; } = "lair";
	[JsonPropertyName("pool")] public List<string> Pool { get; set; } = new();
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
	/// <summary>The age (index in data/ages.json) its kingdom must have reached to build it (Ages.cs).</summary>
	[JsonPropertyName("age")] public int Age { get; set; }
	/// <summary>Sprite name for buildings invented in the game (buildings/inv_N), else "".</summary>
	public string Sprite { get; set; } = "";
	/// <summary>The invention this building comes from (Inventions.cs), or -1.</summary>
	public int Invention { get; set; } = -1;

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

	private sealed class LegendsFile
	{
		[JsonPropertyName("legends")] public List<LegendRecord> Legends { get; set; } = new();
	}

	private sealed class SpiritsFile
	{
		[JsonPropertyName("spirits")] public List<SpiritRecord> Spirits { get; set; } = new();
	}

	private sealed class DiseasesFile
	{
		[JsonPropertyName("adjectives")] public List<string> Adjectives { get; set; } = new();
		[JsonPropertyName("symptoms")] public List<SymptomRecord> Symptoms { get; set; } = new();
	}

	private sealed class MonstersFile
	{
		[JsonPropertyName("monsters")] public List<MonsterRecord> Monsters { get; set; } = new();
		[JsonPropertyName("mutations")] public List<MutationRecord> Mutations { get; set; } = new();
	}

	private sealed class AgesFile
	{
		[JsonPropertyName("ages")] public List<AgeRecord> Ages { get; set; } = new();
		[JsonPropertyName("beyond")] public BeyondRecord Beyond { get; set; } = new();
	}

	private sealed class ErasFile
	{
		[JsonPropertyName("eras")] public List<EraRecord> Eras { get; set; } = new();
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
	/// <summary>The legendary monsters (data/legends.json); each is also a species.</summary>
	public List<LegendRecord> Legends = new();
	/// <summary>Kinds of nature spirits (data/spirits.json).</summary>
	public List<SpiritRecord> Spirits = new();
	/// <summary>What diseases are generated from (data/diseases.json).</summary>
	public List<string> DiseaseAdjectives = new();
	public List<SymptomRecord> Symptoms = new();
	/// <summary>Common monsters and the changes they can go through (data/monsters.json).</summary>
	public List<MonsterRecord> Monsters = new();
	public List<MutationRecord> Mutations = new();
	/// <summary>The ages of the peoples and the ages beyond (data/ages.json).</summary>
	public List<AgeRecord> Ages = new();
	public BeyondRecord Beyond = new();
	/// <summary>Moods of the world (data/eras.json).</summary>
	public List<EraRecord> Eras = new();
	/// <summary>The mods loaded (docs/MODS.md): folder names of ModsDir.</summary>
	public List<string> Mods = new();
	/// <summary>What each mod brought, or why it was refused: name → text.</summary>
	public Dictionary<string, string> ModNotes = new();
	/// <summary>Where mods are looked for: each folder in it is a mod.</summary>
	public static string ModsDir = "user://mods";

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
		if (FileAccess.FileExists("res://data/legends.json"))
			lib.Legends = JsonSerializer.Deserialize<LegendsFile>(FileAccess.GetFileAsString("res://data/legends.json")).Legends;
		// Each legend is a species too (drawn, moved, inspected like any creature), born of no
		// biome: nature never spawns it; Legends.cs wakes it.
		foreach (var l in lib.Legends)
		{
			lib._speciesIndex[l.Id] = lib.Species.Count;
			lib.Species.Add(new SpeciesRecord
			{
				Id = l.Id, Name = l.Title, Sprite = l.Sprite, Speed = l.Speed, Roam = l.Roam, Diet = "none",
				Size = 14, Lifespan = 100000f, Litter = 0, IsLegend = true,
			});
		}
		if (FileAccess.FileExists("res://data/spirits.json"))
			lib.Spirits = JsonSerializer.Deserialize<SpiritsFile>(FileAccess.GetFileAsString("res://data/spirits.json")).Spirits;
		if (FileAccess.FileExists("res://data/diseases.json"))
		{
			var diseases = JsonSerializer.Deserialize<DiseasesFile>(FileAccess.GetFileAsString("res://data/diseases.json"));
			lib.DiseaseAdjectives = diseases.Adjectives;
			lib.Symptoms = diseases.Symptoms;
		}
		if (FileAccess.FileExists("res://data/monsters.json"))
		{
			var monsters = JsonSerializer.Deserialize<MonstersFile>(FileAccess.GetFileAsString("res://data/monsters.json"));
			lib.Monsters = monsters.Monsters;
			lib.Mutations = monsters.Mutations;
		}
		if (FileAccess.FileExists("res://data/ages.json"))
		{
			var ages = JsonSerializer.Deserialize<AgesFile>(FileAccess.GetFileAsString("res://data/ages.json"));
			lib.Ages = ages.Ages;
			lib.Beyond = ages.Beyond ?? new BeyondRecord();
		}
		if (FileAccess.FileExists("res://data/eras.json"))
			lib.Eras = JsonSerializer.Deserialize<ErasFile>(FileAccess.GetFileAsString("res://data/eras.json")).Eras;
		lib.LoadMods();
		return lib;
	}

	// ------------------------------------------------------------------ mods

	/// <summary>Every folder of ModsDir is a mod: its species.json, buildings.json, eras.json and
	/// ages.json ("beyond" words) add records, or replace those with the same id. A file that does
	/// not read is skipped and said in ModNotes; the game goes on without it.</summary>
	private void LoadMods()
	{
		Mods.Clear();
		ModNotes.Clear();
		using var dir = DirAccess.Open(ModsDir);
		if (dir == null)
			return;
		var names = new List<string>(dir.GetDirectories());
		names.Sort(StringComparer.Ordinal);
		foreach (var name in names)
		{
			string root = ModsDir.TrimEnd('/') + "/" + name;
			var done = new List<string>();
			try
			{
				string path = root + "/species.json";
				if (FileAccess.FileExists(path))
				{
					int n = 0;
					foreach (var s in JsonSerializer.Deserialize<SpeciesFile>(FileAccess.GetFileAsString(path)).Species)
					{
						if (string.IsNullOrEmpty(s.Id))
							continue;
						if (_speciesIndex.TryGetValue(s.Id, out int at))
							Species[at] = s;
						else
						{
							_speciesIndex[s.Id] = Species.Count;
							Species.Add(s);
						}
						n++;
					}
					done.Add($"{n} species");
				}
				path = root + "/buildings.json";
				if (FileAccess.FileExists(path))
				{
					int n = 0;
					foreach (var b in JsonSerializer.Deserialize<BuildingsFile>(FileAccess.GetFileAsString(path)).Buildings)
					{
						if (string.IsNullOrEmpty(b.Id) || b.Id == "ruin")
							continue;
						int at = BuildingIndex(b.Id);
						if (at >= 0)
							Buildings[at] = b;
						else
						{
							// Before the ruin, which stays last.
							int ruin = BuildingIndex("ruin");
							Buildings.Insert(ruin >= 0 ? ruin : Buildings.Count, b);
						}
						n++;
					}
					done.Add($"{n} buildings");
				}
				path = root + "/eras.json";
				if (FileAccess.FileExists(path))
				{
					int n = 0;
					foreach (var e in JsonSerializer.Deserialize<ErasFile>(FileAccess.GetFileAsString(path)).Eras)
					{
						if (string.IsNullOrEmpty(e.Id))
							continue;
						int at = Eras.FindIndex(o => o.Id == e.Id);
						if (at >= 0)
							Eras[at] = e;
						else
							Eras.Add(e);
						n++;
					}
					done.Add($"{n} moods of the world");
				}
				path = root + "/ages.json";
				if (FileAccess.FileExists(path))
				{
					var ages = JsonSerializer.Deserialize<AgesFile>(FileAccess.GetFileAsString(path));
					if (ages.Beyond != null)
					{
						Beyond.First.AddRange(ages.Beyond.First);
						Beyond.Second.AddRange(ages.Beyond.Second);
						Beyond.Vehicle.AddRange(ages.Beyond.Vehicle);
						Beyond.Home.AddRange(ages.Beyond.Home);
						Beyond.Weapon.AddRange(ages.Beyond.Weapon);
						done.Add("words for the ages beyond");
					}
				}
				Mods.Add(name);
				ModNotes[name] = done.Count > 0 ? string.Join(", ", done) : "nothing the game reads (scenarios, stamps and sprites are read by the interface)";
			}
			catch (Exception e)
			{
				ModNotes[name] = "refused: " + e.Message;
			}
		}
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
