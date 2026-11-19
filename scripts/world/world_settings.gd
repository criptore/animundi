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


func set_size(tiles: int) -> void:
	width = tiles
	height = tiles


## The settings as a short code to share (0.9): the same code gives the same world anywhere.
## "AM1:" and the settings in base 64.
func to_code() -> String:
	var data := [seed_text, width, continents, roundi(water_ratio * 100), roundi(temperature_offset * 100),
			roundi(humidity_offset * 100), roundi(rivers * 100)]
	return "AM1:" + Marshalls.utf8_to_base64(JSON.stringify(data)).replace("=", "")


## Reads a code of to_code into these settings. False (nothing changed) if it is not one.
func from_code(code: String) -> bool:
	code = code.strip_edges()
	if not code.begins_with("AM1:"):
		return false
	var body := code.substr(4)
	var b64 := RegEx.create_from_string("^[A-Za-z0-9+/]+$")
	if b64.search(body) == null:
		return false
	while body.length() % 4 != 0:
		body += "="
	var text := Marshalls.base64_to_utf8(body)
	if text == "" or not text.begins_with("["):
		return false
	var data = JSON.parse_string(text)
	if not (data is Array) or data.size() != 7 or not (data[0] is String) or not SIZES.values().has(int(data[1])):
		return false
	seed_text = data[0]
	set_size(int(data[1]))
	continents = clampi(int(data[2]), 1, 8)
	water_ratio = clampf(float(data[3]) / 100.0, 0.2, 0.85)
	temperature_offset = clampf(float(data[4]) / 100.0, -0.3, 0.3)
	humidity_offset = clampf(float(data[5]) / 100.0, -0.3, 0.3)
	rivers = clampf(float(data[6]) / 100.0, 0.0, 1.0)
	return true


func duplicate_settings() -> RefCounted:
	var copy = get_script().new()
	for p in ["seed_text", "width", "height", "continents", "water_ratio", "temperature_offset",
			"humidity_offset", "rivers"]:
		copy.set(p, get(p))
	return copy
