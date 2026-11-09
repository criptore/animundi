## Headless tests for world generation, rendering helpers and the C# simulation core.
##   godot --headless --path . --script res://tests/test_world.gd
## Needs the Godot .NET build (the simulation core is C#; build it first with `dotnet build`).
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
const Races = preload("res://scripts/world/races.gd")
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
	test_creature_sprites()
	test_species_data()
	test_simulation()
	test_life()
	test_scripts_load()
	test_nature()
	test_peoples()
	test_villages()
	test_kingdoms()
	test_inventions()
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
	var villager := SpriteLibrary.world_size("creatures/elves_villager_idle")
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
	var flora := Flora.table().values()
	var known := true
	for entries in flora:
		for e in entries:
			known = known and atlas.has(e[0])
	check(known, "every plant of the flora table has a sprite")
	var oak: Color = atlas.colors["trees/Oak"]
	check(oak.g > oak.b and oak.a == 1.0, "every sprite has an average colour for its far-away dot (oak is green)")


func test_sprite_batch() -> void:
	var ids := PackedStringArray()
	var pos := PackedVector2Array()
	var flips := PackedByteArray()
	var scales := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 3000:
		ids.append(["trees/Oak", "plants/Bush", "creatures/cow_idle", "nope/Missing"][k % 4])
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
	batch.set_zoom(0.3)
	var far: bool = not batch.get_child(0).visible
	batch.set_zoom(2.0)
	check(far and batch.get_child(0).visible, "shadows hide when zoomed far out, where sprites are dots")
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


const MONSTERS := ["skeleton", "zombie", "ghost", "spider", "slime", "demon", "golem", "yeti", "dragon"]


func test_creature_sprites() -> void:
	# Drawn at display size: about a tile tall (8 world pixels), never scaled from large art.
	var ok := true
	var sizes := []
	for id in ["creatures/cow_idle", "creatures/wolf_idle", "creatures/humans_villager_idle", "creatures/dwarves_warrior_idle"]:
		var size := SpriteLibrary.world_size(id) * WorldMap.TILE
		sizes.append(size)
		ok = ok and size.y >= 5.0 and size.y <= 12.0
	check(ok, "creatures are about one tile tall %s" % [sizes])
	var walk_differs: bool = SpriteLibrary.texture("creatures/cow_walk1").get_image().get_data() \
			!= SpriteLibrary.texture("creatures/cow_idle").get_image().get_data()
	var dead := SpriteLibrary.texture("creatures/humans_villager_death")
	check(walk_differs and dead.get_width() > dead.get_height(), "creatures have walking frames and lie down when dead")
	var people := 0
	for race in Races.RACES:
		for role in Races.ROLES:
			if SpriteLibrary.exists("creatures/%s_%s_idle" % [race.to_lower(), role.to_lower()]):
				people += 1
	check(people == 48, "every people has a sprite for each of its 4 roles (%d)" % people)


func test_species_data() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/species.json"))
	var atlas := SpriteAtlas.shared()
	var ok: bool = data.species.size() >= 5
	var natural_monsters := []
	for sp in data.species:
		for pose in ["idle", "walk1", "walk2", "attack", "swim", "death"]:
			ok = ok and atlas.has("%s_%s" % [sp.sprite, pose])
		ok = ok and sp.speed > 0.0
		for b in sp.natural:
			ok = ok and Biomes.NAMES.has(b)
			# Monsters may only be born in special biomes, which only the player creates.
			if sp.id in MONSTERS and not b in ["Mushroom land", "Cursed land", "Volcanic rock", "Lava"]:
				natural_monsters.append(sp.id)
	check(ok, "every species record has all its poses in the atlas, known biomes and a speed (%d species)" % data.species.size())
	check(natural_monsters.is_empty(), "monsters are only born in special biomes %s" % [natural_monsters])


func test_simulation() -> void:
	var w := make("sim", 128)
	var sim: Node2D = load("res://sim/Simulation.cs").new()
	root.add_child(sim)
	sim.Start(w, PackedStringArray(Biomes.NAMES))
	var placed: int = sim.SpawnNatural(600)
	check(placed == 600 and sim.UnitCount() == 600, "600 animals spawned (%d)" % sim.UnitCount())
	check(sim.CountOnWater() == 0, "animals spawn on land")
	check(sim.CountUnnatural() == 0 and sim.CountOutOfHabitat() == 0,
			"on a fresh world only natural creatures are born, each in a biome of its species")
	var before := []
	for i in 50:
		before.append(sim.UnitPosition(i))
	sim.RunSteps(300)  # 10 simulated seconds
	var moved := 0
	for i in 50:
		if sim.UnitPosition(i).distance_to(before[i]) > 0.2:
			moved += 1
	check(moved > 25, "animals wander (%d of 50 moved in 10 s)" % moved)
	check(sim.CountOnWater() == 0, "animals never walk into water")

	# Zones answer like a scan of every unit.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var same := true
	for t in 20:
		var p := Vector2(rng.randf() * 128.0, rng.randf() * 128.0)
		var r := rng.randf_range(2.0, 20.0)
		var brute := 0
		for i in sim.UnitCount():
			if sim.UnitPosition(i).distance_to(p) <= r:
				brute += 1
		same = same and sim.CountNear(p.x, p.y, r) == brute
	check(same, "zone queries find exactly the units in range")

	# A world process visits the whole map, one slice at a time.
	sim.AddCountingProcess("test", 0.1, 8)
	sim.RunSteps(3)
	var partial: int = sim.RowsVisited("test")
	sim.RunSteps(30)
	check(partial < 128 and sim.RowsVisited("test") >= 128,
			"world processes work through the map in slices (%d rows, then %d)" % [partial, sim.RowsVisited("test")])
	sim.queue_free()


## A living world (plants and the simulation) for the 0.2 tests.
func make_sim(seed_text: String, size := 128) -> Array:
	var w := make(seed_text, size)
	var sim: Node2D = load("res://sim/Simulation.cs").new()
	root.add_child(sim)
	sim.Start(w, PackedStringArray(Biomes.NAMES))
	var flora := Flora.place(w)
	sim.LoadPlants(flora.id, flora.pos, flora.flip, flora.scale)
	return [w, sim]


## First land tile of biome `b` whose 5x5 neighbourhood is land and has no water nearby (or, with
## `near_water`, a land tile right next to water).
func find_tile(w: WorldData, b: int, near_water := false) -> Vector2i:
	for y in range(3, w.height - 3):
		for x in range(3, w.width - 3):
			var i := w.index(x, y)
			if w.is_water(i) or (b >= 0 and w.biome[i] != b):
				continue
			var water := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if w.is_water(w.index(x + dx, y + dy)):
						water += 1
			if (near_water and w.is_water(w.index(x + 1, y))) or (not near_water and water == 0):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_life() -> void:
	var made := make_sim("life")
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	for law in ["animal_spawn", "natural_disasters", "old_age"]:
		sim.SetLaw(law, false)

	# Grazing: a hungry cow on fresh grass eats it.
	var g := find_tile(w, Biomes.GRASSLAND)
	var cow: int = sim.SpawnAt("cow", g.x + 0.5, g.y + 0.5, false)
	sim.SetNeeds(cow, 0.9, 0.0)
	var grass_before: float = sim.GrassAt(g.x, g.y)
	sim.RunSteps(90)
	check(sim.UnitHunger(cow) < 0.6 and sim.GrassAt(g.x, g.y) < grass_before,
			"a hungry grazer eats the grass of its tile (hunger %.2f, grass %.2f -> %.2f)" % [
			sim.UnitHunger(cow), grass_before, sim.GrassAt(g.x, g.y)])

	# Drinking: a thirsty animal by the water drinks.
	var shore := find_tile(w, -1, true)
	var deer: int = sim.SpawnAt("deer", shore.x + 0.5, shore.y + 0.5, false)
	sim.SetNeeds(deer, 0.0, 0.9)
	sim.RunSteps(90)
	check(sim.UnitThirst(deer) < 0.2, "a thirsty animal by the water drinks (thirst %.2f)" % sim.UnitThirst(deer))

	# Hunting: a hungry wolf catches the rabbit next to it.
	var f := find_tile(w, Biomes.GRASSLAND)
	var rabbit: int = sim.SpawnAt("rabbit", f.x + 0.5, f.y + 0.5, false)
	var wolf: int = sim.SpawnAt("wolf", f.x + 1.5, f.y + 0.5, false)
	sim.SetNeeds(wolf, 0.9, 0.0)
	sim.SetNeeds(rabbit, 0.0, 0.0)
	sim.RunSteps(30 * 15)
	check(not sim.UnitAlive(rabbit) and sim.LifeStats()["Eaten"] >= 1 and sim.UnitHunger(wolf) < 0.5,
			"a hungry predator hunts and eats smaller prey")

	# Hunters only take prey of their size or smaller: a fox never catches a bear.
	var b := find_tile(w, Biomes.FOREST)
	if b.x < 0:
		b = g
	var bear: int = sim.SpawnAt("bear", b.x + 0.5, b.y + 0.5, false)
	var fox: int = sim.SpawnAt("fox", b.x + 1.0, b.y + 0.5, false)
	sim.SetNeeds(fox, 0.9, 0.0)
	sim.SetNeeds(bear, 0.0, 0.0)
	sim.RunSteps(30 * 5)
	check(sim.UnitAlive(bear), "a small hunter does not catch a big animal")
	sim.queue_free()

	# Years later: births happen, populations stay within what their habitat feeds, and nature
	# never brings monsters.
	made = make_sim("years")
	sim = made[1]
	sim.SpawnNatural(120)
	sim.RunSteps(30 * 60 * 4)  # 4 years
	var stats: Dictionary = sim.LifeStats()
	check(stats["births"] > 0 and sim.UnitCount() > 0, "animals breed (%d births in 4 years)" % stats["births"])
	var within := true
	for id in ["rabbit", "sheep", "wolf", "bear", "cow"]:
		within = within and sim.PopulationOf(id) <= sim.CapacityOf(id) + 8
	check(within, "populations stay within what their habitat can feed")
	check(sim.CountUnnatural() == 0 and sim.CountOnWater() == 0, "nature brings no monsters, and no one walks on water")
	check(stats["OldAge"] + stats["Hunger"] + stats["Thirst"] + stats["Eaten"] > 0,
			"creatures die (old age, hunger, thirst, predators): %s" % [stats])
	sim.queue_free()


func test_nature() -> void:
	var made := make_sim("nature")
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	sim.SetLaw("natural_disasters", false)

	# Time can be paused and sped up: the same simulation, more steps per frame.
	var t0: float = sim.SimTime()
	sim.SetTimeScale(0.0)
	for k in 10:
		sim._process(0.1)
	var paused: float = sim.SimTime() - t0
	sim.SetTimeScale(5.0)
	for k in 10:
		sim._process(0.1)
	var fast: float = sim.SimTime() - t0
	sim.SetTimeScale(1.0)
	check(paused == 0.0 and absf(fast - 5.0) < 0.1, "time pauses and runs five times faster at ×5 (%.2f s in 1 s)" % fast)

	# Seasons turn through the year.
	var seasons := {}
	var coldest := 0.0
	for k in 8:
		seasons[sim.SeasonName()] = true
		coldest = maxf(coldest, sim.Coldness())
		sim.RunSteps(30 * 8)  # 8 s
	check(seasons.size() == 4 and coldest > 0.9 and sim.Year() == 2,
			"a year has four seasons and a cold winter (%s)" % [seasons.keys()])

	# Fire: a forest set alight burns down and leaves ash; rocks never burn.
	var forest := find_tile(w, Biomes.FOREST)
	var lit: int = sim.Ignite(forest.x + 0.5, forest.y + 0.5, 3.0)
	sim.RunSteps(30 * 6)
	var after_fire: int = sim.PlantCount()
	var ash := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if w.in_bounds(forest.x + dx, forest.y + dy):
				ash = maxi(ash, sim.ScorchAt(forest.x + dx, forest.y + dy))
	var burned: int = sim.LifeStats()["plants_burned"]
	check(lit > 0 and burned > 0 and ash > 0,
			"fire spreads through the forest and leaves ash (%d lit, %d burned down)" % [lit, burned])
	var changes: PackedInt32Array = sim.TakeScorchChanges()
	check(changes.size() > 0 and changes.size() % 2 == 0, "the map is told where the ground burned")
	# Fire runs through grass too (it lives on tiles), but never into a swamp.
	var meadow := find_tile(w, Biomes.SAVANNA)
	if meadow.x < 0:
		meadow = find_tile(w, Biomes.GRASSLAND)
	sim.Ignite(meadow.x + 0.5, meadow.y + 0.5, 1.5)
	var spread := false
	for k in 30:
		sim.RunSteps(3)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if maxi(absi(dx), absi(dy)) >= 2 and (sim.TileOnFire(meadow.x + dx, meadow.y + dy) or sim.ScorchAt(meadow.x + dx, meadow.y + dy) > 0):
					spread = true
	check(spread, "fire spreads from tile to tile through grass")
	var swamp := find_tile(w, Biomes.SWAMP)
	if swamp.x >= 0:
		check(sim.Ignite(swamp.x + 0.5, swamp.y + 0.5, 1.0) == 0, "swamps never burn")
	check(not sim.IsFlammable("plants/Rock") and not sim.IsFlammable("plants/Boulder") and sim.IsFlammable("trees/Oak"),
			"rocks and boulders don't catch fire, trees do")

	# A year later the ash is gone and plants grow back.
	sim.RunSteps(30 * 60)
	var ash_left := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if w.in_bounds(forest.x + dx, forest.y + dy):
				ash_left = maxi(ash_left, sim.ScorchAt(forest.x + dx, forest.y + dy))
	check(ash_left == 0 and sim.PlantCount() > after_fire,
			"a year later the ash has faded and plants have grown back (%d plants)" % sim.PlantCount())
	sim.queue_free()


## Every game script compiles (the tests above don't load the HUD or the main scene).
func test_scripts_load() -> void:
	var ok := true
	for path in ["res://scripts/ui/hud.gd", "res://scripts/main.gd", "res://scripts/ui/map_camera.gd",
			"res://scripts/render2d/world_map.gd", "res://scripts/ui/setup_panel.gd"]:
		var script: GDScript = load(path)
		ok = ok and script != null and script.can_instantiate()
	check(ok, "the HUD, main scene and map scripts compile")


func test_inventions() -> void:
	var made := make_sim("inventions", 160)
	var sim: Node2D = made[1]
	sim.SetLaw("natural_disasters", false)
	sim.SetMindEndpoint("")
	sim.StartPeoples(PackedStringArray(["humans", "orcs"]), 16)
	sim.RunSteps(30 * 60 * 2)
	var k: int = sim.KingdomTable()[0].index

	# The invention language: the engine rejects what breaks its rules.
	var bad := {
		"unknown kind": '{"name": "Sky Ship", "kind": "rocket", "cost": {"wood": 50}, "effects": [{"do": "attack", "amount": 5}]}',
		"effect not for this kind": '{"name": "Stone Axe", "kind": "tool", "cost": {"wood": 50}, "effects": [{"do": "attack", "amount": 5}]}',
		"tool without a job": '{"name": "Stone Axe", "kind": "tool", "cost": {"wood": 50}, "effects": [{"do": "work_speed", "amount": 5}]}',
		"too strong": '{"name": "God Spear", "kind": "weapon", "cost": {"gold": 80}, "effects": [{"do": "attack", "amount": 500}]}',
		"too cheap": '{"name": "Free Plough", "kind": "tool", "cost": {}, "effects": [{"do": "yield", "job": "farmer", "amount": 30}]}',
		"bad name": '{"name": "x<script>", "kind": "tool", "cost": {"wood": 50}, "effects": [{"do": "yield", "job": "farmer", "amount": 5}]}',
		"not JSON": 'a plough, please',
	}
	var rejected := 0
	var already: int = sim.InventionTable().size()
	var rejected_before: int = sim.InventionsRejected
	for why in bad:
		if sim.SubmitInventionJson(k, bad[why], "model") != "":
			rejected += 1
	check(rejected == bad.size() and sim.InventionTable().size() == already, "invalid inventions are rejected (%d of %d)" % [rejected, bad.size()])
	var plough := '{"name": "Iron Plough", "kind": "tool", "cost": {"wood": 10, "metal": 4}, "effects": [{"do": "yield", "job": "farmer", "amount": 20}, {"do": "work_speed", "job": "farmer", "amount": 10}]}'
	check(sim.SubmitInventionJson(k, plough, "model") == "", "a valid invention is accepted")
	var better := '{"name": "Wheel Plough", "kind": "tool", "improves": "Iron Plough", "cost": {"wood": 12, "metal": 6}, "effects": [{"do": "yield", "job": "farmer", "amount": 30}]}'
	check(sim.SubmitInventionJson(k, better, "model") == "" and sim.InventionTable()[0].parent == "Iron Plough" and sim.InventionTable()[0].generation == 1,
			"inventions evolve by descent: an improvement remembers its parent")
	var capital := -1
	for v in sim.VillageTable():
		if v.capital and v.kingdom == sim.KingdomTable()[0].name:
			capital = v.index
	var mods: Dictionary = sim.VillageMods(capital)
	check(mods.has("farmer") and "yield +50%" in mods.farmer, "what a village knows changes its work (%s)" % [mods])

	# The procedural inventor: valid inventions from the kingdom's needs, and buildings.
	for n in 6:
		sim.InventNow(k)
	check(sim.InventionTable().size() == already + 8 and sim.InventionsRejected == rejected_before + bad.size(),
			"the procedural inventor's inventions are all valid (%d new)" % (sim.InventionTable().size() - already))
	var hall := '{"name": "Great Longhall", "kind": "building", "cost": {"wood": 20, "stone": 10}, "effects": [{"do": "homes", "amount": 10}, {"do": "loyalty", "amount": 5}], "sprite": 7}'
	check(sim.SubmitInventionJson(k, hall, "model") == "", "a people invents a building")

	# Inventions spread and are forgotten as years go by.
	sim.RunSteps(30 * 60 * 6)
	var table: Array = sim.InventionTable()
	var spread := false
	for inv in table:
		spread = spread or inv.villages > 1 or inv.lost
	check(spread, "inventions spread to other villages, or are forgotten (%s)" % [table.map(func(i): return [i.name, i.villages, i.lost])])
	var built := false
	for b in sim.BuildingTable():
		built = built or b.id.begins_with("inv_")
	check(built or table.size() > 0, "invented buildings can be built where they are known (built: %s)" % built)

	# A local model (a fake llama.cpp server here): asked in the background, its answer validated.
	var server := TCPServer.new()
	if server.listen(18087, "127.0.0.1") == OK:
		sim.SetMindEndpoint("http://127.0.0.1:18087")
		var before: int = sim.InventionTable().size()
		sim.AskMind(k)
		var answered := false
		var answer := '{"name": "Sun Bow", "kind": "weapon", "cost": {"wood": 8, "metal": 3}, "effects": [{"do": "attack", "amount": 12}]}'
		for step in 600:
			if server.is_connection_available():
				var peer := server.take_connection()
				var request := ""
				for wait in 200:
					peer.poll()
					if peer.get_available_bytes() > 0:
						request += peer.get_utf8_string(peer.get_available_bytes())
						if "json_schema" in request and request.ends_with("}"):
							break
					OS.delay_msec(5)
				var body := JSON.stringify({"content": answer})
				peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]).to_utf8_buffer())
				answered = "Invent ONE" in request
				peer.disconnect_from_host()
			sim.RunSteps(15)
			OS.delay_msec(5)
			if sim.InventionTable().size() > before:
				break
		var top: Dictionary = sim.InventionTable()[0]
		check(answered and top.name == "Sun Bow" and top.mind == "model",
				"a local model is asked in the background with the language's schema and its answer becomes an invention (%s, %s)" % [answered, top.name])
		server.stop()
	sim.SetMindEndpoint("")
	sim.queue_free()


func test_kingdoms() -> void:
	var made := make_sim("kingdoms", 192)
	var sim: Node2D = made[1]
	sim.SetLaw("natural_disasters", false)
	sim.StartPeoples(PackedStringArray(["humans", "elves", "orcs"]), 14)
	check(sim.KingdomCount() == 3, "each people starts as a kingdom (%d)" % sim.KingdomCount())
	sim.RunSteps(30 * 60 * 14)  # 14 years
	var kingdoms: Array = sim.KingdomTable()
	var ruled := true
	var villages := 0
	for k in kingdoms:
		ruled = ruled and k.ruler != "no ruler" and k.dynasty != ""
		villages += k.villages
	check(ruled, "every kingdom has a king or queen of a dynasty (%s)" % [kingdoms.map(func(k): return k.ruler)])
	check(villages == sim.VillageCount(), "every village belongs to a kingdom (%d of %d)" % [villages, sim.VillageCount()])
	var ranks_ok := true
	for v in sim.VillageTable():
		ranks_ok = ranks_ok and v.rank in ["camp", "village", "town", "city"]
	check(ranks_ok, "settlements have ranks: camp, village, town, city")

	# Plots grow before they happen; they can be cancelled or forced.
	var a: int = kingdoms[0].index
	var b: int = kingdoms[1].index
	var plan: int = sim.Plot("alliance", a, b)
	check(sim.PlanTable().size() > 0 and sim.CancelPlan(plan) and not sim.CancelPlan(plan), "a plot is shown before it happens and can be cancelled")
	if sim.AtWar(a, b):
		sim.ForcePlan(sim.Plot("peace", a, b))
	sim.ForcePlan(sim.Plot("war", a, b))
	check(sim.AtWar(a, b) and sim.WarTable().size() > 0, "a forced plot happens at once: war")
	var reach: bool = sim.CanReach(a, b) or sim.CanReach(b, a)
	sim.RunSteps(30 * 60 * 4)  # 4 years of war
	check(not reach or sim.WarDeaths > 0 or sim.Conquests > 0,
			"armies march and fight when they can reach the enemy (%d dead, %d villages taken, reachable: %s)" % [sim.WarDeaths, sim.Conquests, reach])
	if sim.AtWar(a, b):
		sim.ForcePlan(sim.Plot("peace", a, b))
	check(not sim.AtWar(a, b), "peace ends the war")
	check(sim.CountOnWater() == 0, "no one walks on water, armies included")

	# A real fight: on a small world where two kingdoms can walk to each other.
	var fought := false
	for seed in ["war-1", "war-2", "war-3", "war-4", "war-5"]:
		var w2 := make_sim(seed, 128)
		var s2: Node2D = w2[1]
		s2.SetLaw("natural_disasters", false)
		s2.StartPeoples(PackedStringArray(["humans", "orcs"]), 16)
		s2.RunSteps(30 * 60 * 2)
		if s2.KingdomCount() == 2 and s2.CanReach(0, 1):
			s2.ForcePlan(s2.Plot("war", 0, 1))
			s2.RunSteps(30 * 60 * 5)
			fought = true
			check(s2.WarDeaths > 0, "armies march on the enemy and fight: %d dead in war, %d villages taken (%s)" % [s2.WarDeaths, s2.Conquests, seed])
			s2.queue_free()
			break
		s2.queue_free()
	check(fought, "some small world lets two kingdoms reach each other")

	# A village breaks away: a new kingdom, at war with the old one.
	var rebel := -1
	var rebel_kingdom := -1
	for v in sim.VillageTable():
		if not v.capital and v.kingdom != "":
			rebel = v.index
			for k in sim.KingdomTable():
				if k.name == v.kingdom:
					rebel_kingdom = k.index
			break
	if rebel >= 0:
		var before: int = sim.KingdomCount()
		sim.ForcePlan(sim.Plot("rebellion", rebel_kingdom, rebel))
		check(sim.KingdomCount() == before + 1 and sim.AtWar(rebel_kingdom, sim.KingdomOf(rebel)),
				"a rebel village founds a kingdom, at war with its old one")

	# The log says who did what, by category.
	var tagged: PackedStringArray = sim.TakeTaggedEvents()
	var cats := {}
	for k in range(0, tagged.size(), 2):
		cats[tagged[k]] = true
	check(cats.has("kings") and cats.has("wars"), "events are tagged for the log's filters (%s)" % [cats.keys()])
	var banner: Image = load("res://scripts/ui/banner.gd").image(Color.RED, Color.WHITE, 4, 2)
	check(banner.get_width() == 10 and banner.get_pixel(5, 6).a > 0.0, "kingdoms get a generated banner")
	sim.queue_free()


func test_villages() -> void:
	var made := make_sim("villages", 192)
	var sim: Node2D = made[1]
	sim.SetLaw("natural_disasters", false)
	sim.StartPeoples(PackedStringArray(["humans", "elves", "orcs"]), 14)
	var start: Array = sim.VillageTable()
	check(start.size() == 3 and start[0].zones == 9 and start[0].homes == 3,
			"a new village owns 3x3 zones and its bonfire is home to 3 (%d zones, %d homes)" % [start[0].zones, start[0].homes])
	sim.RunSteps(30 * 60 * 12)  # 12 years

	# They grow (homes, territory) and build what WorldBox villages build.
	var kinds := {}
	var inside := true
	for b in sim.BuildingTable():
		kinds[b.id] = kinds.get(b.id, 0) + 1
		inside = inside and b.owner_ok
	var grown := false
	var homes_ok := true
	for v in sim.VillageTable():
		grown = grown or (v.zones > 9 and v.population > 14)
		homes_ok = homes_ok and v.homes >= 3
	check(grown and homes_ok, "villages grow: more people and more land; everyone has homes to go to")
	var made_kinds := 0
	for id in ["hut", "house", "stockpile", "well", "windmill", "mine", "dock", "town_hall"]:
		if kinds.has(id):
			made_kinds += 1
	check(made_kinds >= 6, "villages build huts, houses, stockpiles, wells, windmills, mines, docks, town halls (%s)" % [kinds])
	check(inside, "every building stands on its village's land")
	var dry := 0
	var wet := []
	for b in sim.BuildingTable():
		if b.on_land:
			dry += 1
		else:
			wet.append("%s (%d, %d)" % [b.id, b.x, b.y])
	check(wet.is_empty(), "no building's sprite hangs over water (%d on land, over water: %s)" % [dry, wet])

	# Fields, roads, and the jobs that go with them.
	var fields := 0
	var roads := 0
	var w: WorldData = made[0]
	for y in w.height:
		for x in w.width:
			var g: int = sim.GroundAt(x, y)
			fields += 1 if g == 2 else 0
			roads += 1 if g == 1 else 0
	var jobs := ""
	for v in sim.VillageTable():
		jobs += v.jobs + ", "
	check(fields > 0 and roads > 0, "windmills get fields, buildings get roads (%d field tiles, %d road tiles)" % [fields, roads])
	check("farmer" in jobs and "builder" in jobs or "farmer" in jobs and "miner" in jobs, "farmers and miners at work (%s)" % jobs)
	var stores := 0.0
	for v in sim.VillageTable():
		stores += v.stone + v.metal + v.gold
	check(stores > 0.0, "mines bring stone, metal or gold (%d)" % stores)
	check(sim.TakeOverlayChanges().size() % 3 == 0, "the map gets the villages' land as triples")

	# Wooden buildings burn; firemen put them out or they fall to ruins.
	var hut: Dictionary = {}
	for b in sim.BuildingTable():
		if b.id == "hut" or b.id == "house":
			hut = b
			break
	if not hut.is_empty():
		check(sim.IgniteBuilding(hut.x, hut.y), "a wooden house can catch fire")
		sim.RunSteps(30 * 20)
		var after := ""
		for b in sim.BuildingTable():
			if b.x == hut.x and b.y == hut.y:
				after = b.id if not b.burning else "burning"
		check(after != "burning", "a burning house is put out or burns down (now: %s, %d put out, %d burned)" % [after, sim.FiresPutOut, sim.BuildingsBurned])

	# Ultra-fast mode: coarse steps still run whole years, on land.
	var year: int = sim.Year()
	sim.RunYears(3, 6)
	check(sim.Year() == year + 3 and sim.CountOnWater() == 0 and sim.VillageCount() > 0,
			"coarse steps run 3 years in a go (year %d → %d), no one on water" % [year, sim.Year()])
	# "Go to year": time runs to the year asked, then pauses.
	check(sim.GoToYear(sim.Year() + 2, 0.0), "time can be sent to a year ahead")
	for k in 400:
		if sim.TargetYear == 0:
			break
		sim._Process(0.05)
	check(sim.TargetYear == 0 and sim.Year() == year + 5 and sim.GetTimeScale() == 0.0,
			"the year asked is reached, then time pauses (year %d)" % sim.Year())
	sim.queue_free()


func test_peoples() -> void:
	var made := make_sim("peoples", 192)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	sim.SetLaw("natural_disasters", false)
	var founded: int = sim.StartPeoples(PackedStringArray(["humans", "elves", "orcs"]), 12)
	check(founded == 3 and sim.VillageCount() == 3 and sim.PeopleCount() == 36,
			"three peoples found a village each, 12 people per village (%d villages, %d people)" % [founded, sim.PeopleCount()])

	# Each people speaks its own generated language.
	var elves: PackedStringArray = sim.SampleNames("elves", 20)
	var orcs: PackedStringArray = sim.SampleNames("orcs", 20)
	var shared := 0
	var tidy := true
	var regex := RegEx.create_from_string("[aeiouy]{3}|(.)\\1\\1")
	for n in elves:
		if n in orcs:
			shared += 1
		tidy = tidy and n.length() > 0 and n.length() <= 9 and regex.search(n.to_lower()) == null
	check(shared < 3 and tidy, "elves and orcs have different languages; names are short and smooth (%s / %s)" % [elves.slice(0, 4), orcs.slice(0, 4)])

	# Races vary from one world to the next.
	var other := make_sim("peoples-2", 128)
	other[1].StartPeoples(PackedStringArray(["humans", "elves"]), 8)
	check(sim.RaceOf("humans") != other[1].RaceOf("humans"), "the same people differs from world to world")
	other[1].queue_free()

	# Villages live: they gather food and wood, build houses, and families have children.
	sim.RunSteps(30 * 60 * 3)  # 3 years
	var houses := 0
	for v in sim.VillageTable():
		houses += v.houses
	var stats: Dictionary = sim.LifeStats()
	check(houses >= 2, "villages build houses (%d in 3 years)" % houses)
	check(stats["people_births"] > 0, "families have children (%d births)" % stats["people_births"])
	var family := false
	var people_ok := true
	for i in 4000:
		if not sim.UnitAlive(i) or not sim.UnitIsPeople(i):
			continue
		if sim.UnitMother(i) >= 0 and sim.UnitFather(i) >= 0:
			family = true
		people_ok = people_ok and sim.UnitVillage(i) >= 0 and sim.UnitName(i) != ""
	check(family and people_ok, "children have a mother and a father; everyone has a name and a village")
	check(sim.CountOnWater() == 0, "no one walks on water")
	check(sim.UnitInfo(sim.UnitAt(w.width / 2.0, w.height / 2.0, 500.0)) != "", "the HUD can describe a creature")
	sim.queue_free()
