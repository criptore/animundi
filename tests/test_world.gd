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
const WorldMap = preload("res://scripts/render2d/world_map.gd")
const MapCamera = preload("res://scripts/ui/map_camera.gd")
const Flora = preload("res://scripts/world/flora.gd")
const SpriteAtlas = preload("res://scripts/render2d/sprite_atlas.gd")
const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")
const SpriteBatch = preload("res://scripts/render2d/sprite_batch.gd")

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
	test_world_map()
	test_map_camera()
	test_trackpad()
	test_flora()
	test_sprite_atlas()
	test_sprite_batch()
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


func test_world_map() -> void:
	var w := make("map", 64)
	var map := WorldMap.new()
	map.set_world(w)
	check(map.texture.get_size() == Vector2(64, 64), "the map is one texture, one texel per tile")
	check(map.pixel_size() == Vector2(64, 64) * WorldMap.TILE, "a tile is %d world pixels" % WorldMap.TILE)
	check(map.tile_at(Vector2(3.5, 10.2) * WorldMap.TILE) == Vector2i(3, 10)
			and map.tile_at(Vector2(-1, 5)) == Vector2i(-1, -1)
			and map.tile_at(Vector2(64, 5) * WorldMap.TILE) == Vector2i(-1, -1),
			"points map to the tile under them, outside the map to (-1, -1)")
	var ok := true
	for b in Biomes.COUNT:
		ok = ok and WorldMap.pattern(b) >= 0 and WorldMap.pattern(b) < WorldMap.Pattern.size()
	check(ok, "every biome has a ground pattern")
	var a := map.color_image().duplicate() as Image
	var again := WorldMap.new()
	again.set_world(make("map", 64))
	check(a.get_data() == again.color_image().get_data(), "the same world gives the same map")

	# Changing a tile redraws that texel only.
	var i := w.index(20, 30)
	var before := a.get_pixel(20, 30)
	w.biome[i] = Biomes.LAVA if w.biome[i] != Biomes.LAVA else Biomes.SNOW
	map.update_tiles(PackedInt32Array([i]))
	var img := map.color_image().duplicate() as Image
	check(img.get_pixel(20, 30) != before and img.get_pixel(21, 30) == a.get_pixel(21, 30),
			"updating a tile changes its texel and leaves its neighbours")

	map.show_layer("Height")
	check(map.color_image().get_data() != img.get_data(), "data layers recolour the map")
	map.free()
	again.free()


func test_map_camera() -> void:
	var cam := MapCamera.new()
	cam.bounds = Vector2(2048, 2048)
	cam.frame_all()
	check(cam.position == Vector2(1024, 1024) and cam.zoom.x <= 720.0 / 2048.0,
			"framing shows the whole map")
	var screen := Vector2(900, 200)
	var under := cam.screen_to_world(screen)
	cam.zoom_at(2.0, screen)
	check(cam.screen_to_world(screen).distance_to(under) < 0.01, "zooming keeps the point under the mouse")
	cam.zoom_at(1000.0, screen)
	check(cam.zoom.x == MapCamera.MAX_ZOOM, "zoom stops at the closest level")
	cam.pan_screen(Vector2(1e6, 1e6))
	check(cam.position == Vector2.ZERO, "the view stays on the map")
	cam.free()


func test_flora() -> void:
	var w := make("flora", 128)
	var a := Flora.place(w)
	var b := Flora.place(w)
	check(a.id == b.id and a.pos == b.pos and a.flip == b.flip and a.scale == b.scale, "same world, same plants")
	check(a.id.size() > 500, "a 128 world has plants (%d)" % a.id.size())
	var ok := true
	for k in a.id.size():
		if not Flora.on_land(w, a.pos[k], SpriteLibrary.world_size(a.id[k]) * a.scale[k]):
			ok = false
	check(ok, "every plant's sprite stands over land, never over water")
	var mushroom := SpriteLibrary.world_size("plants/Red_mushroom")
	var villager := SpriteLibrary.world_size("peoples/Elves_Villager")
	check(mushroom.y < villager.y * 0.6, "mushrooms are smaller than the peoples")

	# Changing a tile only changes the plants on and right around it.
	var before := {}
	for k in a.id.size():
		before["%s@%s" % [a.id[k], a.pos[k]]] = true
	var i := -1
	for k in w.size():
		if w.biome[k] == Biomes.FOREST:
			i = k
			break
	w.biome[i] = Biomes.DESERT
	var c := Flora.place(w)
	var moved := 0
	for k in c.id.size():
		if not before.has("%s@%s" % [c.id[k], c.pos[k]]):
			moved += 1
	check(moved <= 2, "editing one tile leaves the other plants in place (%d new)" % moved)

	var specials := 0
	for seed_text in ["s1", "s2", "s3"]:
		var sw := make(seed_text, 128)
		for k in sw.size():
			if sw.biome[k] in [Biomes.MUSHROOM, Biomes.CURSED, Biomes.VOLCANIC, Biomes.LAVA]:
				specials += 1
	check(specials == 0, "no special biome is generated at random")


func test_sprite_atlas() -> void:
	var atlas := SpriteAtlas.shared()
	var ok := true
	for group in SpriteAtlas.GROUPS:
		for id in SpriteLibrary.list(group):
			ok = ok and atlas.has(id)
	check(ok and atlas.regions.size() > 90, "every sprite is in the atlas (%d)" % atlas.regions.size())
	var rects: Array = atlas.regions.values()
	var inside := true
	var apart := true
	for n in rects.size():
		var r: Rect2 = rects[n]
		inside = inside and r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= 1.0 and r.end.y <= 1.0
		for m in range(n + 1, rects.size()):
			apart = apart and not r.intersects(rects[m])
	check(inside and apart, "atlas regions fit in the texture and never overlap")
	var flora := Flora.FLORA.values()
	var known := true
	for entries in flora:
		for e in entries:
			known = known and atlas.has(e[0])
	check(known, "every plant of the flora table has a sprite")


func test_sprite_batch() -> void:
	var ids := PackedStringArray()
	var pos := PackedVector2Array()
	var flips := PackedByteArray()
	var scales := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 3000:
		ids.append(["trees/Oak", "plants/Bush", "animals/Cow", "nope/Missing"][k % 4])
		pos.append(Vector2(rng.randf_range(0, 2048), rng.randf_range(0, 2048)))
		flips.append(k % 2)
		scales.append(1.0)
	var batch := SpriteBatch.new()
	batch.set_sprites(ids, pos, flips, scales)
	check(batch.count == 2250, "unknown sprites are skipped (%d drawn)" % batch.count)
	# Sprites layer: strips in order, and sprites sorted by feet height inside each strip.
	var layer: Node = batch.get_child(1)
	var last := -INF
	var total := 0
	var sorted := true
	for strip in layer.get_children():
		var mm: MultiMesh = (strip as MultiMeshInstance2D).multimesh
		total += mm.instance_count
		for n in mm.instance_count:
			var y := mm.get_instance_transform_2d(n).origin.y
			sorted = sorted and y >= last
			last = y
	check(sorted and total == 2250, "sprites are drawn top to bottom, nearest last")
	check(layer.get_child_count() == 16 and batch.get_child(0).get_child_count() == 16,
			"one strip of sprites and one of shadows per 16 rows of tiles")
	batch.free()


func test_trackpad() -> void:
	var cam := MapCamera.new()
	cam.bounds = Vector2(2048, 2048)
	cam.look_at_point(Vector2(1024, 1024), 2.0)

	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.5
	pinch.position = Vector2(640, 360)
	check(cam.handle_input(pinch) and is_equal_approx(cam.zoom.x, 3.0), "pinching zooms")

	var start := cam.position
	var swipe := InputEventPanGesture.new()
	swipe.delta = Vector2(2, 0)
	cam.handle_input(swipe)
	check(cam.position.x > start.x and is_equal_approx(cam.position.y, start.y), "two-finger scroll pans")

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 0.5
	wheel.position = Vector2(640, 360)
	var before := cam.zoom.x
	cam.handle_input(wheel)
	check(is_equal_approx(cam.zoom.x, before * pow(MapCamera.ZOOM_STEP, 0.5)), "a fraction of a wheel notch zooms a fraction of a step")

	start = cam.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	cam.handle_input(press)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(30, 0)
	cam.handle_input(move)
	press.pressed = false
	cam.handle_input(press)
	check(cam.position.x < start.x, "click and drag pans")
	start = cam.position
	cam.handle_input(move)
	check(cam.position == start, "moving without a button pressed does not pan")

	var plus := InputEventKey.new()
	plus.keycode = KEY_EQUAL
	plus.pressed = true
	before = cam.zoom.x
	cam.handle_input(plus)
	check(cam.zoom.x > before, "the + key zooms in")
	cam.free()
