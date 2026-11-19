## Saved worlds (1.0, docs/POLISH.md): a slot is one file in user://saves/ holding the land (the
## generated world as the terrain tools left it), the settings it came from, a few words to show
## in the list, and the whole simulation (sim/SaveState.cs). The autosave has its own slot.
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")
const DIR := "user://saves"
const SLOTS := 6
const AUTO := "autosave"
const VERSION := 1
## The arrays of a WorldData that make the land.
const ARRAYS := ["elevation", "temperature", "humidity", "flow", "downstream", "water", "biome", "level", "volcanoes"]


static func path_of(slot: String, dir := DIR) -> String:
	return dir.path_join(slot + ".save")


## Writes a world to a slot ("slot_1".."slot_6" or "autosave"). `about` is what the list shows:
## year, people, kingdoms, era... Returns "" or why it failed.
static func save(slot: String, world: WorldData, settings, sim_blob: PackedByteArray, about: Dictionary, dir := DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var land := {"width": world.width, "height": world.height, "seed_value": world.seed_value, "sea_level": world.sea_level}
	for a in ARRAYS:
		land[a] = world.get(a)
	var data := {
		"version": VERSION, "saved": Time.get_datetime_string_from_system(false, true), "unix": Time.get_unix_time_from_system(),
		"about": about, "code": settings.to_code(), "land": land, "sim": sim_blob,
	}
	var f := FileAccess.open_compressed(path_of(slot, dir), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return "cannot write %s" % path_of(slot, dir)
	f.store_var(data)
	f.close()
	return ""


## Reads a slot: {about, code, world (a WorldData), sim (the simulation's blob), saved}, or {}.
static func read(slot: String, dir := DIR) -> Dictionary:
	if not FileAccess.file_exists(path_of(slot, dir)):
		return {}
	var f := FileAccess.open_compressed(path_of(slot, dir), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var data = f.get_var()
	f.close()
	if not (data is Dictionary) or int(data.get("version", 0)) > VERSION or not data.has("land"):
		return {}
	var land: Dictionary = data.land
	var world := WorldData.new(int(land.width), int(land.height), int(land.seed_value))
	world.sea_level = float(land.sea_level)
	for a in ARRAYS:
		if land.has(a):
			world.set(a, land[a])
	return {"about": data.get("about", {}), "code": data.get("code", ""), "world": world, "sim": data.get("sim", PackedByteArray()),
			"saved": data.get("saved", ""), "unix": data.get("unix", 0.0)}


## What each slot holds, for the list: [{slot, empty, saved, about}], the autosave first.
static func list(dir := DIR) -> Array:
	var out := []
	for slot in [AUTO] + range(1, SLOTS + 1).map(func(n): return "slot_%d" % n):
		var entry := {"slot": slot, "empty": true, "saved": "", "about": {}, "unix": 0.0}
		if FileAccess.file_exists(path_of(slot, dir)):
			var f := FileAccess.open_compressed(path_of(slot, dir), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
			if f != null:
				var data = f.get_var()
				f.close()
				if data is Dictionary:
					entry = {"slot": slot, "empty": false, "saved": data.get("saved", ""), "about": data.get("about", {}), "unix": data.get("unix", 0.0)}
		out.append(entry)
	return out


## The slot saved last, or "".
static func latest(dir := DIR) -> String:
	var best := ""
	var when := -1.0
	for e in list(dir):
		if not e.empty and float(e.unix) > when:
			when = float(e.unix)
			best = e.slot
	return best


static func remove(slot: String, dir := DIR) -> void:
	DirAccess.remove_absolute(path_of(slot, dir))
