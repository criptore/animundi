## Everything the player chooses before a world is generated.
## Same settings (seed included) always give the same world.
extends RefCounted

const SIZES := {"Tiny": 128, "Small": 256, "Medium": 384, "Large": 512}

var seed_text := "animundi"
var width := 256
var height := 256
## Number of large land masses.
var continents := 3
## Share of the map under the sea, 0..1.
var water_ratio := 0.55
## Shifts the whole climate: -0.3 is an ice age, +0.3 a hot world.
var temperature_offset := 0.0
## Shifts rainfall: -0.3 is a dry world, +0.3 a wet one.
var humidity_offset := 0.0
## 0 = few, short rivers; 1 = many long rivers.
var rivers := 0.5
var volcanoes := 2
## 0 = no magical biomes, 1 = many.
var magic := 0.5


func set_size(tiles: int) -> void:
	width = tiles
	height = tiles


func duplicate_settings() -> RefCounted:
	var copy = get_script().new()
	for p in ["seed_text", "width", "height", "continents", "water_ratio", "temperature_offset",
			"humidity_offset", "rivers", "volcanoes", "magic"]:
		copy.set(p, get(p))
	return copy
