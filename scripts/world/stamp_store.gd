## The player's own stamps (0.9 terrain tools, docs/POWERS.md): areas of a map saved with the
## "Copy the land" power, kept as JSON files in user://stamps/ so they can be pasted in any world.
## The simulation makes and reads the JSON (sim/Terrain.cs CopyStamp, AddStamp); this only keeps
## the files.
extends RefCounted

const DIR := "user://stamps"


## Every saved stamp: [[id, name, json], ...], oldest first.
static func load_all(dir := DIR) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files := Array(d.get_files())
	files.sort()
	for f in files:
		if not String(f).ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(f))
		var data = JSON.parse_string(text)
		if not (data is Dictionary) or not data.has("stamp"):
			continue
		out.append([String(f).get_basename(), String(data.get("name", f)), JSON.stringify(data.stamp)])
	return out


## Saves a stamp (CopyStamp's JSON) under the next free number. Returns [id, name].
static func save(json: String, dir := DIR) -> Array:
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 1
	while FileAccess.file_exists(dir.path_join("my_stamp_%03d.json" % n)):
		n += 1
	var id := "my_stamp_%03d" % n
	var name := "My stamp %d" % n
	var f := FileAccess.open(dir.path_join(id + ".json"), FileAccess.WRITE)
	if f == null:
		return []
	f.store_string(JSON.stringify({"name": name, "stamp": JSON.parse_string(json)}))
	f.close()
	return [id, name]


static func remove(id: String, dir := DIR) -> void:
	DirAccess.remove_absolute(dir.path_join(id + ".json"))
