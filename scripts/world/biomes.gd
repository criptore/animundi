## Biome ids, their display names, the terrain tile each one uses, and the climate classification.
extends RefCounted

enum {
	DEEP_WATER, WATER, ICE, BEACH, DESERT, SAVANNA, GRASSLAND, MEADOW, FOREST, JUNGLE,
	SWAMP, TAIGA, TUNDRA, SNOW, HILLS, MOUNTAIN, PEAK, VOLCANIC, LAVA, MUSHROOM, CURSED,
}

const COUNT := 21

const NAMES := [
	"Deep water", "Water", "Ice", "Beach", "Desert", "Savanna", "Grassland", "Flower meadow",
	"Forest", "Jungle", "Swamp", "Taiga", "Tundra", "Snow", "Hills", "Mountain", "Peak",
	"Volcanic rock", "Lava", "Mushroom land", "Cursed land",
]

## Tile name in the terrain atlas (scripts/generated/terrain_atlas.gd) for each biome.
const TILES := [
	"Deep water", "Water", "Ice", "Sand", "Desert", "Savanna", "Grass", "Flower meadow",
	"Forest", "Jungle", "Swamp", "Taiga", "Tundra", "Snow", "Hills", "Mountain", "Peak",
	"Volcanic rock", "Lava", "Mushroom land", "Cursed soil",
]

## Ground colour of each biome in the 3D view, taken from the biome reference sheet
## (art/reference/biomes.png; water from art/reference/water.png).
const COLORS := [
	Color("#1b4479"), Color("#49ccdf"), Color("#a8dcf2"), Color("#f4e6a0"), Color("#f2c86c"),
	Color("#d8b460"), Color("#66b043"), Color("#6cb24a"), Color("#4a8a3a"), Color("#357a3a"),
	Color("#62744a"), Color("#4f7048"), Color("#b8d8d8"), Color("#e2f2f8"), Color("#72b046"),
	Color("#7e808a"), Color("#e4ecf2"), Color("#3a3238"), Color("#e8501c"), Color("#7a5a94"),
	Color("#45305c"),
]

# Land height bands (0 = shore, 1 = highest point). Land height is rank-based and squared, so
# a band above h holds about (1 - sqrt(h)) of the land: hills ~23%, mountains ~10%, peaks ~3%.
const PEAK_HEIGHT := 0.94
const MOUNTAIN_HEIGHT := 0.8
const HILLS_HEIGHT := 0.6
# Sea depth below which water turns deep (0 = shore, 1 = deepest point).
const DEEP_WATER_DEPTH := 0.14
# Temperature under which water freezes.
const ICE_TEMPERATURE := 0.04


## Land biome from climate alone (Whittaker-style table), before height and special overrides.
static func classify_climate(temperature: float, humidity: float, lowland: bool) -> int:
	if temperature < 0.15:
		return SNOW
	if temperature < 0.3:
		return TUNDRA if humidity < 0.45 else TAIGA
	if temperature < 0.62:
		if humidity < 0.52:
			return GRASSLAND
		if humidity < 0.8 or not lowland:
			return FOREST
		return SWAMP
	if humidity < 0.25:
		return DESERT
	if humidity < 0.45:
		return SAVANNA
	if humidity < 0.82 or not lowland:
		return JUNGLE
	return SWAMP


static func is_water_biome(b: int) -> bool:
	return b == DEEP_WATER or b == WATER or b == ICE
