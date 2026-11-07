## Headless tests for world generation.
##   godot --headless --path . --script res://tests/test_world.gd
## Exits with the number of failed checks (0 = all passed).
extends SceneTree

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")
const PriorityQueue = preload("res://scripts/core/priority_queue.gd")
const TerrainBuilder = preload("res://scripts/render3d/terrain_builder.gd")
const VegetationBuilder = preload("res://scripts/render3d/vegetation_builder.gd")

var _failures := 0


func _initialize() -> void:
	test_priority_queue()
	test_determinism()
	test_seeds_differ()
	test_water_ratio()
	test_biomes_valid()
	test_water_reaches_the_sea()
	test_rivers_exist()
	test_poles_are_colder()
	test_renderer()
	test_terrain_mesh()
	test_vegetation()
	test_levels()
	print("\n%s (%d failed)" % ["FAILED" if _failures else "ALL PASSED", _failures])
	quit(_failures)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1


func make(seed_text: String, size := 128) -> WorldData:
	var s := WorldSettings.new()
	s.seed_text = seed_text
	s.set_size(size)
	return WorldGenerator.generate(s)


func test_priority_queue() -> void:
	var q := PriorityQueue.new()
	for v in [5, 1, 9, 3, 7, 2, 8]:
		q.push(float(v), v)
	var out := []
	while q.size() > 0:
		out.append(q.pop())
	check(out == [1, 2, 3, 5, 7, 8, 9], "priority queue pops in ascending order")


func test_determinism() -> void:
	var a := make("alpha")
	var b := make("alpha")
	check(a.biome == b.biome and a.elevation == b.elevation and a.water == b.water,
			"same seed gives the same world")


func test_seeds_differ() -> void:
	check(make("alpha").biome != make("beta").biome, "different seeds give different worlds")


func test_water_ratio() -> void:
	var s := WorldSettings.new()
	s.seed_text = "ratio"
	s.set_size(128)
	s.water_ratio = 0.6
	var w := WorldGenerator.generate(s)
	var sea := 0
	for i in w.size():
		if w.water[i] == WorldData.Water.OCEAN:
			sea += 1
	var ratio := float(sea) / w.size()
	# Inland seas are turned into land, so the ocean can only be a bit smaller than asked.
	check(ratio > 0.45 and ratio <= 0.61, "ocean covers about the requested share (%.2f for 0.60)" % ratio)


func test_biomes_valid() -> void:
	var w := make("valid")
	var ok := true
	for i in w.size():
		if w.biome[i] >= Biomes.COUNT:
			ok = false
		if w.water[i] != WorldData.Water.LAND and not Biomes.is_water_biome(w.biome[i]):
			ok = false
	check(ok, "every tile has a valid biome, water tiles have water biomes")
	check(Biomes.NAMES.size() == Biomes.COUNT and Biomes.TILES.size() == Biomes.COUNT, "biome tables are complete")


func test_water_reaches_the_sea() -> void:
	var w := make("flow")
	var ok := true
	for i in w.size():
		if w.water[i] == WorldData.Water.OCEAN:
			continue
		var j := i
		var steps := 0
		while j >= 0 and w.water[j] != WorldData.Water.OCEAN and steps <= w.size():
			j = w.downstream[j]
			steps += 1
		# Map border tiles are outlets too (downstream -1).
		if steps > w.size():
			ok = false
			break
	check(ok, "water from every land tile reaches the sea or the map edge, without loops")


func test_rivers_exist() -> void:
	var w := make("rivers", 256)
	var rivers := 0
	for i in w.size():
		if w.water[i] == WorldData.Water.RIVER:
			rivers += 1
	check(rivers > 50, "a 256 world has rivers (%d river tiles)" % rivers)


func test_poles_are_colder() -> void:
	var w := make("climate")
	var pole := 0.0
	var equator := 0.0
	for x in w.width:
		pole += w.temperature[w.index(x, 2)]
		equator += w.temperature[w.index(x, w.height / 2)]
	check(pole < equator, "poles are colder than the equator")


func test_terrain_mesh() -> void:
	var w := make("mesh", 64)
	var h := TerrainBuilder.heights(w)
	var mesh := TerrainBuilder.build_terrain(w, h)
	var arrays := mesh.surface_get_arrays(0)
	check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() >= 64 * 64 * 6, "terrain has a flat top for every tile")
	var ok := true
	for i in w.size():
		var land := w.water[i] == WorldData.Water.LAND
		var sea_floor := w.water[i] == WorldData.Water.OCEAN and w.biome[i] != Biomes.ICE
		if land and h[i] <= 0.0 or sea_floor and h[i] >= 0.0:
			ok = false
	check(ok, "land is above the sea plane and sea floor below it (sea ice floats on it)")


func test_levels() -> void:
	var w := make("levels", 128)
	var ok := true
	var used := {}
	for y in w.height:
		for x in w.width:
			var i := w.index(x, y)
			used[w.level[i]] = true
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				if w.in_bounds(x + d.x, y + d.y) and absi(int(w.level[i]) - int(w.level[w.index(x + d.x, y + d.y)])) > 1:
					ok = false
			if w.is_water(i) != (w.level[i] <= WorldData.Level.SHALLOW):
				ok = false
	check(ok, "neighbouring tiles differ by at most one level, water sits on the two water levels")
	check(used.size() == 5, "all five levels are used (%d)" % used.size())


func test_vegetation() -> void:
	var w := make("trees", 128)
	var h := TerrainBuilder.heights(w)
	var a := VegetationBuilder.build(w, h)
	var b := VegetationBuilder.build(w, h)
	var total := 0
	var same := a.keys() == b.keys()
	for k in a:
		total += a[k].instance_count
		same = same and a[k].instance_count == b[k].instance_count \
				and a[k].get_instance_transform(0) == b[k].get_instance_transform(0)
	check(total > 500, "a 128 world has vegetation (%d plants)" % total)
	check(same, "vegetation is the same for the same world")


func test_renderer() -> void:
	var w := make("render", 64)
	var r := MapRenderer.new()
	var img := r.render_biomes(w)
	check(img.get_width() == 64 * MapRenderer.TILE and img.get_height() == 64 * MapRenderer.TILE,
			"biome map is 8 pixels per tile")
	for layer in MapRenderer.LAYERS:
		if layer != "Biomes":
			check(r.render_layer(w, layer).get_size() == Vector2i(64, 64), "%s layer renders" % layer)
