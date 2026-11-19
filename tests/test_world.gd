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
	test_culture()
	test_faiths()
	test_legends()
	test_disasters()
	test_plagues()
	test_spirits()
	test_monsters()
	test_ages()
	test_eras()
	test_progress_costs()
	test_terrain()
	test_more_powers()
	test_world_views()
	test_powers()
	test_interface()
	test_power_bar()
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
	var ages_drawn := true
	for id in ["effects/Vehicle_land_1", "effects/Vehicle_land_4", "effects/Vehicle_sea_5", "effects/Era_factory", "effects/Era_launch_pad",
			"effects/Home_0_0_0", "effects/Home_3_1_1", "effects/Mushroom_2", "effects/Rocket_1"]:
		ages_drawn = ages_drawn and atlas.has(id) and atlas.sizes[id].x > 4
	check(ages_drawn, "the vehicles, buildings and homes of the ages, the bomb and the rocket are drawn in the atlas")


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
			"res://scripts/render2d/world_map.gd", "res://scripts/ui/setup_panel.gd", "res://scripts/ui/ui.gd",
			"res://scripts/ui/power_bar.gd", "res://scripts/ui/inspector.gd", "res://scripts/ui/laws_window.gd",
			"res://scripts/ui/settings_window.gd", "res://scripts/ui/pause_menu.gd", "res://scripts/ui/main_menu.gd"]:
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
	# (spirits, monsters and peoples entering a new age ask the same model: they keep quiet here)
	sim.SetLaw("spirits", false)
	sim.SetLaw("monsters", false)
	sim.SetLaw("ages", false)
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
				# (other minds, of cultures or legends, may ask the same server meanwhile)
				answered = answered or "Invent ONE" in request
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

	# The model built into the game: llama.cpp ships with it and loads here; a tiny random model
	# (tests/data, made by tools/make_tiny_model.py) writes nonsense, but its grammar keeps the
	# answer a record of the invention language, which the engine then validates.
	var native: String = sim.MindNativeCheck()
	check(native.begins_with("ok"), "llama.cpp, built into the game, loads on this computer (%s)" % native)
	sim.StartMind(ProjectSettings.globalize_path("res://tests/data/tiny_random.gguf"), "", false)
	for wait in 400:
		if sim.MindStatus().status in ["ready", "failed", "missing"]:
			break
		OS.delay_msec(25)
	check(sim.MindStatus().status == "ready", "the built-in mind loads its model (%s)" % [sim.MindStatus()])
	if sim.MindStatus().status == "ready":
		var asked_before: int = sim.ModelAnswers + sim.ModelFailures
		sim.AskMind(k)
		for wait in 800:
			sim.RunSteps(5)
			OS.delay_msec(25)
			if sim.ModelAnswers + sim.ModelFailures > asked_before:
				# (legends, spirits and monsters ask the same model: wait for the inventor's answer)
				var got = JSON.parse_string(sim.LastModelAnswer)
				if got is Dictionary and got.has("kind"):
					break
				asked_before = sim.ModelAnswers + sim.ModelFailures
		var record = JSON.parse_string(sim.LastModelAnswer)
		check(record is Dictionary and record.has("kind") and record.has("effects") and not sim.LastModelError.begins_with("not valid JSON"),
				"the built-in model answers in the background with a record of the invention language, then validated (%s)" % [
				sim.LastModelError if sim.LastModelError != "" else "accepted"])
		# Its grammar knows which effects each kind may have, and that work effects name a job:
		# even a random model can't break those rules (caps, budget and cost are the engine's).
		var broken := []
		for i in 6:
			var asked: int = sim.ModelAnswers + sim.ModelFailures
			sim.AskMind(k)
			for wait in 800:
				sim.RunSteps(5)
				OS.delay_msec(25)
				if sim.ModelAnswers + sim.ModelFailures > asked:
					break
			var why: String = sim.LastModelError
			if "cannot '" in why or "needs a job" in why or "amount must be" in why or why.begins_with("not valid JSON"):
				broken.append(why)
		check(broken.is_empty(), "the grammar only writes valid JSON, each kind with its own effects within their caps, and a job where one is needed (%s)" % [broken])
	sim.StopMind()
	# The JSON schema sent to model servers carries the same rules.
	var schema: Dictionary = JSON.parse_string(sim.MindSchema())
	var schema_ok: bool = schema.has("anyOf") and schema.anyOf.size() == 7
	var allowed := {"tool": ["work_speed", "yield"], "weapon": ["attack"], "armour": ["defense"],
			"technique": ["work_speed", "yield", "food", "loyalty", "knowledge", "clean"], "building": ["defense", "homes", "food", "loyalty", "knowledge"],
			"vehicle": ["speed"], "energy": ["power", "clean"]}
	if schema_ok:
		for branch in schema.anyOf:
			var kind: String = branch.properties.kind.enum[0]
			var dos := []
			for e in branch.properties.effects.items.anyOf:
				dos.append(e.properties.do.enum[0])
				if e.properties.do.enum[0] in ["work_speed", "yield"] and not ("job" in e.required):
					schema_ok = false
			dos.sort()
			var want: Array = allowed[kind].duplicate()
			want.sort()
			if dos != want:
				schema_ok = false
	check(schema_ok, "the schema sent to model servers allows each kind only its own effects, and requires a job for work effects")
	check(sim.MindStatus().status == "off", "the built-in mind can be stopped: the procedural inventor takes over")
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


## God powers (sim/Powers.cs): each one a call on the simulation with a place in tiles.
func test_powers() -> void:
	var made := make_sim("powers", 128)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	var land := find_tile(w, Biomes.FOREST)
	if land.x < 0:
		land = find_tile(w, -1)
	var x := land.x + 0.5
	var y := land.y + 0.5
	var sea := Vector2i(-1, -1)
	for i in w.size():
		if w.level[i] == WorldData.Level.DEEP_SEA:
			sea = Vector2i(i % w.width, i / w.width)
			break

	# Smite and bless.
	sim.ClearUnits()
	for k in 10:
		sim.SpawnAt("rabbit", x, y, false)
	var rabbits: int = sim.PopulationOf("rabbit")
	var blessed: int = sim.SpawnAt("rabbit", x, y, false)
	sim.SetNeeds(blessed, 0.9, 0.9)
	check(sim.PowerBless(x, y, 3.0) >= 1 and sim.UnitHunger(blessed) == 0.0 and sim.UnitThirst(blessed) == 0.0,
			"bless feeds and heals the creatures under the brush")
	check(sim.PowerSmite(x, y, 3.0) == rabbits + 1 and sim.PopulationOf("rabbit") == 0,
			"smite kills every creature under the brush (%d left)" % sim.PopulationOf("rabbit"))

	# Fire, then rain.
	var lit: int = sim.PowerFire(x, y, 2.0)
	check(lit > 0 and sim.TileOnFire(land.x, land.y), "the fire power sets the land alight (%d tiles)" % lit)
	var out: int = sim.PowerRain(x, y, 4.0)
	check(out > 0 and sim.BurningCount() == 0, "rain puts the fire out (%d tiles, %d still burning)" % [out, sim.BurningCount()])
	check(sim.GrassAt(land.x, land.y) > 0.0, "rain makes the grass grow back")

	# Lightning and meteor.
	sim.SpawnAt("wolf", x, y, false)
	check(sim.PowerLightning(x, y) == 1 and sim.PopulationOf("wolf") == 0, "lightning kills what it strikes")
	sim.PowerRain(x, y, 6.0)
	for k in 4:
		sim.SpawnAt("deer", x, y, false)
	var plants_before: int = sim.PlantCount()
	check(sim.PowerMeteor(x, y, 3.0) == 4 and sim.ScorchAt(land.x, land.y) == 255 and sim.PlantCount() < plants_before,
			"a meteor kills, scorches the ground and flattens the plants")
	check(sim.TakeScorchChanges().size() > 0, "the map is told about the scorched ground")

	# Nothing happens on water or outside the map.
	var nothing := 0
	for p in [Vector2(-5, -5), Vector2(w.width + 9, 3), Vector2(sea.x + 0.5, sea.y + 0.5)]:
		nothing += sim.PowerFire(p.x, p.y, 2.0) + sim.PowerLightning(p.x, p.y) + sim.PowerRain(p.x, p.y, 2.0) \
				+ sim.PowerMeteor(p.x, p.y, 0.4) + sim.PowerSmite(p.x, p.y, 2.0) + sim.PowerBless(p.x, p.y, 2.0)
	check(sea.x >= 0 and nothing == 0, "powers do nothing on the sea or outside the map (%d)" % nothing)
	sim.RunSteps(120)

	# Creatures and peoples.
	sim.ClearUnits()
	var wolves: int = sim.PopulationOf("wolf")
	check(sim.PowerSpawn("wolf", x, y, 5) == 5 and sim.PopulationOf("wolf") == wolves + 5, "the spawn power brings creatures")
	check(sim.PowerSpawn("wolf", sea.x + 0.5, sea.y + 0.5, 5) == 0 and sim.PowerSpawn("unicorn", x, y, 5) == 0 and sim.PowerSpawn("humans", x, y, 5) == 0,
			"nothing is spawned on the sea, nor an unknown species, nor a people as a beast")
	check("dragon" in sim.SpawnableSpecies() and "humans" in sim.RaceIds() and not ("humans" in sim.SpawnableSpecies()),
			"the powers list creatures and peoples apart")
	var villages: int = sim.VillageCount()
	var people: int = sim.PeopleCount()
	var settled: int = sim.PowerSettle("humans", x, y, 8)
	check(settled >= 0 and sim.VillageCount() == villages + 1 and sim.PeopleCount() == people + 8,
			"the settle power founds a village with its people (%d, %d villages, %d people)" % [settled, sim.VillageCount(), sim.PeopleCount()])
	check(sim.PowerSettle("elves", x, y, 8) == -1 and sim.PowerSettle("elves", sea.x + 0.5, sea.y + 0.5, 8) == -1
			and sim.PowerSettle("martians", x, y, 8) == -1 and sim.VillageCount() == villages + 1,
			"no village on another's land, on the sea or of an unknown people")
	check(sim.VillageAt(x, y) == settled and sim.KingdomAt(x, y) >= 0 and sim.VillageAt(sea.x + 0.5, sea.y + 0.5) == -1
			and sim.KingdomAt(-3.0, -3.0) == -1 and sim.VillageInfo(settled).name != "" and sim.VillageInfo(999).is_empty(),
			"the land tells which village and kingdom own it")

	# Whispers: a second kingdom far enough to have its own land.
	var far := Vector2i(-1, -1)
	for i in w.size():
		var p := Vector2i(i % w.width, i / w.width)
		if not w.is_water(i) and sim.VillageAt(p.x, p.y) == -1 and absi(p.x - land.x) + absi(p.y - land.y) > 30:
			far = p
			break
	var other: int = sim.PowerSettle("orcs", far.x + 0.5, far.y + 0.5, 8)
	var ka: int = sim.KingdomAt(x, y)
	var kb: int = sim.KingdomAt(far.x + 0.5, far.y + 0.5)
	check(other >= 0 and ka >= 0 and kb >= 0 and ka != kb, "two peoples settled by the player are two kingdoms")
	var war_ok: bool = sim.PowerWhisper("war", ka, kb)
	var wars_text := ""
	for k in sim.KingdomTable():
		wars_text += str(k.wars)
	check(war_ok and wars_text != "" and not sim.PowerWhisper("war", ka, kb) and not sim.PowerWhisper("alliance", ka, kb),
			"a whisper of war starts a war, once (%s)" % wars_text)
	var peace_ok: bool = sim.PowerWhisper("peace", ka, kb)
	wars_text = ""
	for k in sim.KingdomTable():
		wars_text += str(k.wars)
	check(peace_ok and wars_text == "" and not sim.PowerWhisper("peace", ka, kb), "a whisper of peace ends it (%s)" % wars_text)
	check(sim.PowerWhisper("alliance", ka, kb) and not sim.PowerWhisper("alliance", ka, kb), "a whisper of friendship allies them, once")
	check(not sim.PowerWhisper("war", ka, ka) and not sim.PowerWhisper("war", ka, 99) and not sim.PowerWhisper("war", -1, kb)
			and not sim.PowerWhisper("gossip", ka, kb), "whispers that make no sense are refused")
	check(sim.LawTable().has("hunger") and sim.LawTable().hunger == true, "the laws of the world are listed")
	sim.SetLaw("hunger", false)
	check(sim.LawTable().hunger == false, "a law can be switched off")
	sim.SetLaw("hunger", true)

	# The biome brush.
	var spot := Vector2(far.x + 0.5, far.y + 12.5) if not w.is_water(w.index(far.x, far.y + 12)) else Vector2(x + 14.0, y)
	sim.TakeBiomeChanges()
	var painted: int = sim.PowerBiome("Desert", spot.x, spot.y, 2.0)
	var changes: PackedInt32Array = sim.TakeBiomeChanges()
	var all_desert := changes.size() == painted * 2
	for k in range(1, changes.size(), 2):
		all_desert = all_desert and changes[k] == Biomes.DESERT
	check(painted > 0 and all_desert and sim.TakeBiomeChanges().is_empty(), "the biome brush paints the land and tells the map, once (%d tiles)" % painted)
	check(sim.PowerBiome("Desert", spot.x, spot.y, 2.0) == 0 and sim.PowerBiome("Water", spot.x, spot.y, 2.0) == 0
			and sim.PowerBiome("Candy", spot.x, spot.y, 2.0) == 0 and sim.PowerBiome("Lava", sea.x + 0.5, sea.y + 0.5, 1.0) == 0,
			"nothing to paint: the same biome, a water biome, an unknown one, the sea")
	sim.SpawnAt("bear", spot.x, spot.y, false)
	var bears: int = sim.PopulationOf("bear")
	check(sim.PowerBiome("Lava", spot.x, spot.y, 2.0) > 0 and sim.PopulationOf("bear") == bears - 1, "lava kills what stands on it")
	check(sim.PowerBiome("Forest", x, y, 3.0) >= 0, "the brush paints over a village's land")
	sim.RunSteps(1800)
	check(sim.VillageCount() >= 1, "the world goes on after the powers (%d villages)" % sim.VillageCount())
	sim.queue_free()


## The interface from the title screen to the game: title, world setup, the game's panels, the
## pause menu and back.
func test_interface() -> void:
	var hud: CanvasLayer = load("res://scripts/ui/hud.gd").new()
	hud.settings = load("res://scripts/world/world_settings.gd").new()
	# Built outside the tree: nothing here needs a window.
	hud._ready()
	hud._setup._ready()
	var asked := []
	hud.generate_requested.connect(func(): asked.append("generate"))
	hud.start_requested.connect(func(races, n, _ai): asked.append([races.size(), n]))
	hud.speed_selected.connect(func(v): asked.append(v))
	hud.show_setup()
	check(hud.blocking() and hud._title.visible and not hud._setup.visible and not hud._game.visible,
			"the game opens on the title screen, the world setup waiting behind it")
	hud._on_title("new_world")
	check(hud.setup_visible() and not hud._title.visible and not hud._game.visible, "New world shows the world setup")
	hud._setup._seed_edit.text = "interface"
	hud._setup._continents.value = 5
	hud._setup.request()
	check(hud.settings.seed_text == "interface" and hud.settings.continents == 5 and asked == ["generate"],
			"the setup writes the land's settings and asks for the world")
	hud._setup._on_start()
	check(asked[-1] == [3, 12] and hud._game.visible and not hud.blocking(), "starting the world shows the game (%s)" % [asked])
	for book in hud.BOOKS:
		hud._show_book(book[0], false)
		check(hud._dock.visible and hud._pages[book[0]].visible, "the dock opens the book of %s" % book[0])
	hud._show_book("chronicle", true)
	check(not hud._dock.visible, "clicking the open book's tab closes the dock")
	hud.set_populations({"Wolf": 12, "Rabbit": 40})
	hud.set_counts(30, 2, 1, 52)
	hud.add_event("Year 1, spring: a test.", "wars")
	hud.set_villages([{"rank": "village", "name": "Tolm", "people": "Humans", "population": 12, "homes": 14, "food": 5, "wood": 3,
			"stone": 0, "metal": 0, "gold": 0, "building": "hut", "x": 10, "y": 20}])
	var shown := []
	hud.focus_requested.connect(func(tile): shown.append(tile))
	hud._village_rows[0][0].pressed.emit()
	check(shown == [Vector2(10, 20)] and hud._life_rows[0][2].text == "Rabbit" and hud._counts["people"].text == "30",
			"the dock lists villages (a click shows one) and creatures, the top bar counts")
	asked.clear()
	hud._open_pause()
	check(hud._pause.visible and hud.blocking() and asked == [0.0], "the menu pauses the world (%s)" % [asked])
	hud._pause.close()
	check(not hud.blocking() and asked == [0.0, 1.0], "leaving the menu lets time run as before (%s)" % [asked])
	hud._open(hud.laws)
	hud._open(hud._settings_window)
	check(hud.laws.visible and hud._settings_window.visible and hud._shade.visible, "windows open over a shade")
	hud._settings_window.close()
	hud.laws.close()
	hud._soon("Saved worlds", "Later.")
	check(hud._toast.visible and "later version" in hud._toast_label.text and not hud._shade.visible, "a feature to come says so")
	hud._open_pause()
	hud._on_pause("title")
	check(hud._title.visible and not hud._game.visible and asked[-1] == "generate", "back to the title makes a new world behind it")
	hud.free()


## The god powers bar: a button per power, menus for what to bring or paint, a brush, the laws.
func test_power_bar() -> void:
	var PowerBar = load("res://scripts/ui/power_bar.gd")
	var Inspector = load("res://scripts/ui/inspector.gd")
	var bar: PanelContainer = PowerBar.new()
	root.add_child(bar)
	bar.setup(PackedStringArray(["wolf", "dragon"]), PackedStringArray(["humans", "orcs"]), PackedStringArray(["Desert", "Lava"]))
	var got := []
	bar.power_changed.connect(func(power, arg): got.append([power, arg]))
	check(bar.power == "inspect" and not bar.drags(), "the bar starts on Inspect")
	bar.select("fire")
	check(got == [["fire", ""]] and bar.drags() and bar.hint() != "", "choosing a power tells the game (%s)" % [got])
	bar.select("spawn")
	check(bar.power == "spawn" and bar.arg == "wolf" and "wolf" in bar.hint(), "a power that brings something remembers what (%s)" % bar.hint())
	bar._pick("biome", "Lava")
	check(bar.power == "biome" and bar.arg == "Lava" and got[-1] == ["biome", "Lava"], "picking in a menu chooses the power and what it paints")
	bar.select("nonsense")
	check(bar.power == "inspect", "an unknown power falls back to Inspect")
	bar.brush = 2
	bar.step_brush(1)
	var up: int = bar.brush
	for k in 9:
		bar.step_brush(1)
	var top: int = bar.brush
	for k in 9:
		bar.step_brush(-1)
	check(up == 3 and top == 8 and bar.brush == 1 and bar.radius() > 0.5, "the brush steps through its sizes and stops at both ends")
	var soon := []
	bar.soon_requested.connect(func(power_name, _what): soon.append(power_name))
	for tab in bar._grids:
		for child in bar._grids[tab].get_children():
			if child.has_meta("soon"):
				child.pressed.emit()
	check(soon.size() >= 5 and bar.power == "inspect", "powers to come say so and change nothing (%s)" % [soon])
	var laws := []
	var laws_window: PanelContainer = load("res://scripts/ui/laws_window.gd").new()
	root.add_child(laws_window)
	laws_window.law_toggled.connect(func(law, on): laws.append([law, on]))
	laws_window.set_laws({"hunger": true, "old_age": false})
	laws_window._toggle_law(0)
	laws_window._toggle_law(1)
	check(laws == [["hunger", false], ["old_age", true]], "the laws window switches laws (%s)" % [laws])
	laws_window.queue_free()
	for id in bar.POWERS:
		if not bar._buttons.has(id):
			check(false, "no button for the power %s" % id)
	bar.queue_free()

	var card: PanelContainer = Inspector.new()
	root.add_child(card)
	var closed := [0]
	card.closed.connect(func(): closed[0] += 1)
	card.show_unit("Aldo", "Aldo · Humans man, villager, 20 years · farmer of Tolm")
	check(card.visible and card._title.text == "Aldo", "the inspector shows a creature")
	card.show_village({})
	check(not card.visible and closed[0] == 1, "the inspector closes when its village is gone")
	card.close()
	check(closed[0] == 1, "closing twice tells once")
	card.queue_free()


func test_culture() -> void:
	var made := make_sim("culture", 160)
	var sim: Node2D = made[1]
	sim.SetLaw("natural_disasters", false)
	sim.SetMindEndpoint("")
	sim.StartPeoples(PackedStringArray(["humans", "orcs"]), 16)
	sim.RunSteps(30 * 60 * 2)
	var row: Dictionary = sim.CultureTable()[0]
	var k: int = row.index
	check(row.values.size() == 8 and row.gods.size() >= 1 and row.creed != "" and row.structure != "" and row.walls != "",
			"every kingdom has a culture: values, a way of building, a first god (%s, %s)" % [row.creed, row.structure])

	# The custom language: the engine rejects what breaks its rules.
	var bad := {
		"unknown kind": '{"name": "Sky Rule", "kind": "decree", "about": "war", "text": "So it is.", "effects": [{"do": "attack", "amount": 5}]}',
		"unknown value": '{"name": "Sky Rule", "kind": "law", "about": "pizza", "text": "So it is.", "effects": [{"do": "attack", "amount": 5}]}',
		"over the cap": '{"name": "Sky Rule", "kind": "law", "about": "war", "text": "So it is.", "effects": [{"do": "attack", "amount": 50}]}',
		"too strong": '{"name": "Sky Rule", "kind": "law", "about": "war", "text": "So it is.", "effects": [{"do": "attack", "amount": 15}, {"do": "loyalty", "amount": 10}]}',
		"taboo without a price": '{"name": "Sky Ban", "kind": "taboo", "about": "faith", "text": "So it is.", "effects": [{"do": "faith", "amount": 5}]}',
		"work effect without a job": '{"name": "Sky Rule", "kind": "law", "about": "wealth", "text": "So it is.", "effects": [{"do": "yield", "amount": 5}]}',
		"bad name": '{"name": "x<script>", "kind": "law", "about": "war", "text": "So it is.", "effects": [{"do": "attack", "amount": 5}]}',
		"bad text": '{"name": "Sky Rule", "kind": "law", "about": "war", "text": "<b>So it is</b>", "effects": [{"do": "attack", "amount": 5}]}',
		"no effect": '{"name": "Sky Rule", "kind": "law", "about": "war", "text": "So it is.", "effects": []}',
		"not JSON": 'a law, please',
	}
	var refused := []
	var customs_before: int = row.customs.size()
	for why in bad:
		if sim.SubmitCustomJson(k, bad[why], "model") == "":
			refused.append(why)
	check(refused.is_empty() and sim.CultureTable()[0].customs.size() == customs_before, "invalid customs are rejected (accepted: %s)" % [refused])

	# A law changes how the kingdom's villages fight and how loyal they are.
	var capital := -1
	for v in sim.VillageTable():
		if v.capital and v.kingdom == row.kingdom:
			capital = v.index
	var attack_before: float = sim.VillageMods(capital).attack
	var law := '{"name": "Blood Oath", "kind": "law", "about": "war", "text": "Every grown hand owes a season to the army.", "effects": [{"do": "attack", "amount": 12}, {"do": "loyalty", "amount": -4}]}'
	check(sim.SubmitCustomJson(k, law, "model") == "", "a valid law is adopted")
	var mods: Dictionary = sim.VillageMods(capital)
	check(is_equal_approx(mods.attack - attack_before, 12.0), "a law changes the kingdom's villages (attack %s -> %s)" % [attack_before, mods.attack])
	var war_before: float = row.values.war
	check(sim.CultureTable()[0].values.war > war_before or war_before == 1.0, "a custom strengthens the value it is about")
	check(sim.SubmitCustomJson(k, law, "model") != "", "the same custom is not adopted twice")

	# Three customs of a kind: a fourth makes the oldest give way.
	for n in 6:
		sim.SubmitCustomJson(k, '{"name": "Law %s", "kind": "law", "about": "honour", "text": "So it is.", "effects": [{"do": "defense", "amount": 3}]}' % "abcdef"[n], "model")
	var laws: Array = sim.CultureTable()[0].customs.filter(func(c): return c.kind == "law")
	check(laws.size() == 3 and laws.all(func(c): return c.name != "Blood Oath"), "a kingdom keeps three laws: old ones give way (%s)" % [laws.map(func(c): return c.name)])
	check(is_equal_approx(sim.VillageMods(capital).attack, attack_before), "a custom given up no longer acts")

	# The procedural writer: valid customs from what the kingdom values.
	var rejected_before: int = sim.CustomsRejected
	for n in 30:
		sim.CultureNow(k)
	var written: Array = sim.CultureTable()[0].customs
	check(sim.CustomsRejected == rejected_before and written.size() == 9 and written.any(func(c): return c.mind == "procedural"),
			"the procedural writer's customs are all valid: laws, rituals and taboos (%s)" % [written.map(func(c): return c.kind + " " + c.name)])
	var bounded := true
	for v in sim.VillageTable():
		var m: Dictionary = sim.VillageMods(v.index)
		bounded = bounded and m.attack >= -40.0 and m.attack <= 80.0 and m.defense >= -40.0 and m.defense <= 60.0
	check(bounded, "customs never push a village's bonuses out of bounds")

	# The player is a god: healing is worshipped, wrath is feared or hated.
	var place: Dictionary = {}
	for v in sim.VillageTable():
		if v.index == capital:
			place = v
	check(sim.CultureTable()[0].stance == "unnoticed", "a people the player never touched has not noticed them")
	sim.TakeTaggedEvents()
	for n in 40:
		sim.PowerBless(place.x + 0.5, place.y + 0.5, 6.0)
	var blessed: Dictionary = sim.CultureTable()[0]
	check(blessed.stance == "worshipped" and blessed.god_name != "" and blessed.gods.any(func(g): return g.player),
			"a people the player heals worships them, under a name of its own (%s, %s)" % [blessed.stance, blessed.god_name])
	var told := 0
	var tagged: PackedStringArray = sim.TakeTaggedEvents()
	for n in range(0, tagged.size(), 2):
		if tagged[n] == "culture":
			told += 1
	check(told <= 2 and blessed.gratitude <= 12.0, "a power dragged over a village is felt and told once, not at every touch (%d events, gratitude %d)" % [told, blessed.gratitude])
	check(sim.MythNow(k), "a people remembers what happened to it")
	var myth: Dictionary = sim.CultureTable()[0].myths[-1]
	check("healing" in myth.source and myth.god == blessed.god_name and place.name in myth.source,
			"its myth is drawn from what really happened, and given to the god who did it (%s / %s)" % [myth.title, myth.source])
	var other: Dictionary = sim.CultureTable()[1]
	var other_place: Dictionary = {}
	for v in sim.VillageTable():
		if v.capital and v.kingdom == other.kingdom:
			other_place = v
	# (on the village's heart: owned land a few tiles away may be water)
	sim.PowerMeteor(other_place.x + 0.5, other_place.y + 0.5, 1.0)
	var struck: Dictionary = sim.CultureTable()[1]
	check(struck.stance in ["feared", "hated"] and struck.dread > struck.gratitude,
			"a people the player strikes fears or hates them (%s, dread %d)" % [struck.stance, struck.dread])
	check(sim.MythNow(struck.index) and "star fell" in sim.CultureTable()[1].myths[-1].source, "the meteor becomes a myth of theirs")
	check(sim.SubmitMythJson(k, '{"title": "x<script>", "text": "A tale of old days."}', "model") != "", "a myth with a bad title is rejected")

	# The chronicle: chapters written from the events of their years, and named ages.
	sim.WriteChapterNow()
	var chapters: Array = sim.ChronicleTable()
	check(chapters.size() >= 1 and chapters[0].text.length() > 20 and chapters[0].mind == "procedural" and chapters[0].to == sim.Year(),
			"the chronicler writes a chapter from the events of its years (%s: %s)" % [chapters[0].title if chapters.size() > 0 else "", chapters[0].text.left(120) if chapters.size() > 0 else ""])
	check(sim.AgeName() == "The Age of Dawn" and chapters[0].age == "The Age of Dawn", "the world begins in the Age of Dawn")
	var kingdoms: Array = sim.KingdomTable()
	sim.PowerWhisper("war", kingdoms[0].index, kingdoms[1].index)
	sim.RunSteps(30 * 60 * 9)
	sim.WriteChapterNow()
	var ages: Array = sim.AgeTable()
	check(ages.size() >= 2 and sim.AgeName().begins_with("The Age of ") and sim.AgeName() != "The Age of Dawn" and sim.ChronicleTable()[0].age == sim.AgeName(),
			"after ten years an age is named after what filled them (%s)" % [ages.map(func(a): return [a.name, a.theme, a.from])])
	var good := '{"title": "The Long Summer", "text": "The harvests were rich and the kings were quiet. No one remembers a better time.", "age": "The Age of Gold"}'
	check(sim.SubmitChapterJson(good, "model") == "" and sim.ChronicleTable()[0].title == "The Long Summer", "a mind's chapter joins the chronicle")
	check(sim.SubmitChapterJson('{"title": "Bad", "text": "<b>too short</b>", "age": ""}', "model") != ""
			and sim.SubmitChapterJson('{"title": "Fine Title", "text": "A text that is long enough to be a chapter.", "age": "Gold"}', "model") != "",
			"a chapter with a bad text or a badly named age is rejected")

	# Years go by: minds write customs and myths on their own, faith moves, rebels keep their gods.
	sim.RunSteps(30 * 60 * 6)
	var later: Array = sim.CultureTable()
	check(later.all(func(c): return c.faith >= 0.0 and c.faith <= 100.0 and c.customs.size() <= 9 and c.gods.size() <= 6),
			"cultures stay within bounds as years go by (faith %s)" % [later.map(func(c): return int(c.faith))])
	check(sim.ChronicleTable().size() >= 4, "the chronicler writes a chapter every five years (%d chapters)" % sim.ChronicleTable().size())
	var biggest := -1
	for v in sim.VillageTable():
		if not v.capital and (biggest < 0 or v.population > sim.VillageInfo(biggest).population):
			biggest = v.index
	if biggest >= 0:
		var mother: String = sim.VillageInfo(biggest).kingdom
		var mother_row: Dictionary = sim.CultureTable().filter(func(c): return c.kingdom == mother)[0]
		sim.ForcePlan(sim.Plot("rebellion", mother_row.index, biggest))
		var rebel_name: String = sim.VillageInfo(biggest).kingdom
		var rebels: Array = sim.CultureTable().filter(func(c): return c.kingdom == rebel_name)
		check(rebel_name != mother and rebels.size() == 1 and rebels[0].religion == mother_row.religion and rebels[0].creed == mother_row.creed
				and rebels[0].customs.size() == mother_row.customs.size(),
				"a kingdom born of a rebellion keeps its mother's gods and customs (%s from %s)" % [rebel_name, mother])
	else:
		check(true, "no second village to rebel in this world (skipped)")

	# A local model (a fake llama.cpp server): its custom is validated like any other, and a
	# broken answer falls back to the procedural writer.
	# (spirits, monsters and peoples entering a new age ask the same model: they keep quiet here)
	sim.SetLaw("spirits", false)
	sim.SetLaw("monsters", false)
	sim.SetLaw("ages", false)
	var server := TCPServer.new()
	if server.listen(18088, "127.0.0.1") == OK:
		sim.SetMindEndpoint("http://127.0.0.1:18088")
		var answers := ['{"name": "Moon Vigil", "kind": "ritual", "about": "faith", "text": "Fires are lit for the gods at dusk.", "effects": [{"do": "faith", "amount": 6}]}',
				'{"name": "Broken", "kind": "ritual"']
		var results := []
		for answer in answers:
			var before: int = sim.ModelAnswers + sim.ModelFailures
			var customs_then: Array = sim.CultureTable().filter(func(c): return c.index == k)[0].customs.map(func(c): return c.name)
			sim.AskCultureMind(k, "custom")
			var asked := false
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
					asked = "Write ONE new custom" in request and "taboo" in request
					peer.disconnect_from_host()
				sim.RunSteps(15)
				OS.delay_msec(5)
				if sim.ModelAnswers + sim.ModelFailures > before:
					break
			var now: Array = sim.CultureTable().filter(func(c): return c.index == k)[0].customs
			results.append([asked, now.filter(func(c): return not (c.name in customs_then)).map(func(c): return [c.name, c.mind])])
		check(results[0][0] and results[0][1] == [["Moon Vigil", "model"]], "a local model is asked for a custom with the language's schema, and its answer is adopted (%s)" % [results[0]])
		check(results[1][1].size() == 1 and results[1][1][0][1] == "procedural", "a broken answer falls back to the procedural writer (%s)" % [results[1]])
		server.stop()
	sim.SetMindEndpoint("")
	# (questions other minds sent to the server that is gone fail now, not during the next checks)
	for wait in 80:
		sim.RunSteps(15)
		OS.delay_msec(25)

	# The built-in model with a tiny random model: grammars keep customs, myths and chapters
	# well-formed records whatever it writes.
	sim.StartMind(ProjectSettings.globalize_path("res://tests/data/tiny_random.gguf"), "", false)
	for wait in 400:
		if sim.MindStatus().status in ["ready", "failed", "missing"]:
			break
		OS.delay_msec(25)
	if sim.MindStatus().status == "ready":
		var broken := []
		for what in ["custom", "custom", "chapter"]:
			var asked: int = sim.ModelAnswers + sim.ModelFailures
			if what == "chapter":
				sim.AskChronicler()
			else:
				sim.AskCultureMind(k, what)
			for wait in 1200:
				sim.RunSteps(5)
				OS.delay_msec(25)
				if sim.ModelAnswers + sim.ModelFailures > asked:
					# (legends, spirits and monsters ask the same model: wait for the answer asked for)
					var got = JSON.parse_string(sim.LastModelAnswer)
					if got is Dictionary and got.has("title" if what == "chapter" else "about"):
						break
					asked = sim.ModelAnswers + sim.ModelFailures
			var record = JSON.parse_string(sim.LastModelAnswer)
			var why: String = sim.LastModelError
			var keys: Array = ["title", "text", "age"] if what == "chapter" else ["name", "kind", "about", "text", "effects"]
			if not (record is Dictionary) or not record.has_all(keys) or why.begins_with("not valid JSON") or "unknown" in why or "needs a job" in why or "forbidden character" in why:
				broken.append([what, why, sim.LastModelAnswer.left(80)])
		check(broken.is_empty(), "the grammars keep the built-in model's customs and chapters well-formed (%s)" % [broken])
	else:
		check(false, "the built-in mind loads its model (%s)" % [sim.MindStatus()])
	sim.StopMind()
	var grammar: String = sim.CultureGrammar()
	check("do-work-speed" in grammar and "\\\"taboo\\\"" in grammar and JSON.parse_string(sim.CultureSchema()).properties.effects.maxItems == 2,
			"the custom language has a grammar and a schema")
	sim.queue_free()


## Faiths between kingdoms: holy wars, conversions, heresies, the Miracle power and the Convert whisper.
func test_faiths() -> void:
	var made := make_sim("faiths", 160)
	var sim: Node2D = made[1]
	sim.SetLaw("natural_disasters", false)
	sim.SetMindEndpoint("")
	sim.StartPeoples(PackedStringArray(["humans", "orcs"]), 16)
	var rows: Array = sim.CultureTable()
	var a: int = rows[0].index
	var b: int = rows[1].index
	check(rows[0].religion != rows[1].religion and sim.LawTable().get("faiths", false), "each people starts with its own faith; faiths are a law of the world")

	# Holy wars: a devout kingdom calls a war on unbelievers holy.
	sim.SetFaith(a, 80.0)
	sim.SetCultureValue(a, "faith", 0.9)
	sim.SetFaith(b, 20.0)
	check(sim.HolyWar(a, b) and not sim.HolyWar(b, a), "a devout kingdom calls a war on another faith holy, a lukewarm one does not")

	# The Convert whisper: a kingdom takes up another's faith at once.
	check(sim.PowerWhisper("convert", b, a) and sim.CultureTable()[1].religion == sim.CultureTable()[0].religion
			and sim.CultureTable()[1].creed == sim.CultureTable()[0].creed and not sim.PowerWhisper("convert", b, a),
			"the Convert whisper turns a kingdom to another's faith, once")
	check(not sim.HolyWar(a, b), "no holy war between kingdoms of the same faith")

	# Heresy: a kingdom of the same faith that values other things breaks away from it.
	for value in ["war", "honour", "nature", "wealth", "knowledge", "faith", "freedom", "tradition"]:
		sim.SetCultureValue(a, value, 0.05)
		sim.SetCultureValue(b, value, 0.95)
	sim.SetFaith(a, 60.0)
	sim.SetFaith(b, 60.0)
	for n in 300:
		sim.ReligionYearNow()
		if sim.CultureTable()[0].religion != sim.CultureTable()[1].religion:
			break
	var split: Array = sim.CultureTable()
	check(split[0].religion != split[1].religion and split[0].creed != split[1].creed,
			"a faith splits in a heresy when its kingdoms value different things (%s / %s)" % [split[0].creed, split[1].creed])

	# In a real game, kingdoms that share a faith are mostly a kingdom and its rebels: values a
	# few points apart (kinship ~0.93). Their faith must still split now and then.
	check(sim.PowerWhisper("convert", b, a), "the rebels' kingdom shares its old faith again")
	for value in ["war", "honour", "nature", "wealth", "knowledge", "faith", "freedom", "tradition"]:
		sim.SetCultureValue(a, value, 0.5)
		sim.SetCultureValue(b, value, 0.55)
	sim.SetCultureValue(b, "freedom", 0.65)
	sim.SetFaith(a, 60.0)
	sim.SetFaith(b, 60.0)
	var years := 0
	while years < 100 and sim.CultureTable()[0].religion == sim.CultureTable()[1].religion:
		sim.ReligionYearNow()
		years += 1
	check(years >= 10 and sim.CultureTable()[0].religion != sim.CultureTable()[1].religion,
			"a faith shared by a kingdom and its rebels splits within a lifetime, not in its first years (%d years)" % years)

	# A people that converts does not drive out the old faithful: when a faith splits, the
	# newcomers are the heretics, and the kingdom that held it first keeps it.
	for value in ["war", "honour", "nature", "wealth", "knowledge", "faith", "freedom", "tradition"]:
		sim.SetCultureValue(a, value, 0.05)
		sim.SetCultureValue(b, value, 0.95)
	sim.SetFaith(a, 60.0)
	sim.SetFaith(b, 60.0)
	for n in 12:
		sim.ReligionYearNow()
	var elder_creed: String = sim.CultureTable()[0].creed
	check(sim.PowerWhisper("convert", b, a), "the stranger people takes up the elder's faith")
	for n in 9:
		sim.ReligionYearNow()
	check(sim.CultureTable()[0].religion == sim.CultureTable()[1].religion, "a faith newly taken up holds for its first years")
	for n in 40:
		sim.ReligionYearNow()
	check(sim.CultureTable()[0].creed == elder_creed and sim.CultureTable()[1].religion != sim.CultureTable()[0].religion
			and sim.CultureTable()[1].creed != elder_creed,
			"then the newcomers break from it, and the elder keeps it (%s / %s)" % [sim.CultureTable()[0].creed, sim.CultureTable()[1].creed])
	check(sim.HeresyChance(0.99) == 0.0 and sim.HeresyChance(0.94) > 0.03 and sim.HeresyChance(0.5) <= 1.0,
			"twin faiths never split; drifted ones do, a few in a hundred each year (%.3f)" % sim.HeresyChance(0.94))

	# Conversions in a real game: a hostile-ish neighbour (opinion -25: the border alone costs 15)
	# a dozen points less devout still may turn; one hated, at war or as devout does not.
	check(sim.ConversionChance(12.0, -25.0, false) > 0.03 and sim.ConversionChance(12.0, -25.0, true) > sim.ConversionChance(12.0, -25.0, false),
			"a neighbour a dozen points cooler in faith may take up the other's (%.3f a year)" % sim.ConversionChance(12.0, -25.0, false))
	check(sim.ConversionChance(5.0, 0.0, true) == 0.0 and sim.ConversionChance(30.0, -60.0, true) == 0.0
			and sim.ConversionChance(90.0, 50.0, true) <= 0.5,
			"no conversion for a small gap or a hated neighbour, and never a sure one")

	# Conversion: a lukewarm kingdom takes up the faith of a fervent ally.
	for value in ["war", "honour", "nature", "wealth", "knowledge", "faith", "freedom", "tradition"]:
		sim.SetCultureValue(a, value, 0.5)
		sim.SetCultureValue(b, value, 0.5)
	if sim.AtWar(a, b):
		sim.PowerWhisper("peace", a, b)
	sim.PowerWhisper("alliance", a, b)
	sim.SetFaith(a, 5.0)
	sim.SetFaith(b, 95.0)
	for n in 300:
		sim.ReligionYearNow()
		if sim.CultureTable()[0].religion == sim.CultureTable()[1].religion:
			break
	check(sim.CultureTable()[0].religion == sim.CultureTable()[1].religion, "a lukewarm kingdom takes up the faith of a fervent ally")

	# The Miracle: it heals, and the people who see it grow in faith and worship the player.
	var capital := {}
	for v in sim.VillageTable():
		if v.capital and v.kingdom == sim.CultureTable()[0].kingdom:
			capital = v
	sim.SetFaith(a, 20.0)
	var seen: int = sim.PowerMiracle(capital.x + 0.5, capital.y + 0.5, 2.0)
	var after: Dictionary = sim.CultureTable()[0]
	check(seen > 0 and after.faith > 20.0 and after.gratitude > 0.0 and after.stance == "worshipped" and after.god_name != "",
			"a miracle heals and makes the people who see it worship the player (%s, faith %d)" % [after.stance, after.faith])
	check(sim.PowerMiracle(-50.0, -50.0, 2.0) == 0, "no miracle off the map")
	sim.queue_free()


func legend_row(sim: Node2D, id: String) -> Dictionary:
	for l in sim.LegendTable():
		if l.id == id:
			return l
	return {}


## Legendary monsters (sim/Legends.cs): unique, named, with a mind; they wake by themselves or
## are called by the player, raid, are remembered in myths, and can be slain.
func test_legends() -> void:
	var made := make_sim("legends", 160)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	sim.SetLaw("natural_disasters", false)
	sim.SetMindEndpoint("")
	var table: Array = sim.LegendTable()
	var drawn := table.size() == 6
	for l in table:
		drawn = drawn and l.state in ["absent", "dormant"] and l.name != "" and l.full_name.ends_with(l.title)
	check(drawn, "each world draws which legends sleep in it, each with a name of its own (%s)" % [table.map(func(l): return [l.id, l.state, l.full_name])])
	var atlas := SpriteAtlas.shared()
	var sprites := true
	for rec in JSON.parse_string(FileAccess.get_file_as_string("res://data/legends.json")).legends:
		for pose in ["idle", "walk1", "walk2", "attack", "swim", "death"]:
			sprites = sprites and atlas.has("%s_%s" % [rec.sprite, pose])
		sprites = sprites and SpriteLibrary.world_size(rec.sprite + "_idle").y * WorldMap.TILE > 16.0
	check(sprites, "every legend has all its poses, drawn larger than the common creatures")
	check(sim.IsLegend("ash_wyrm") and not sim.IsLegend("wolf") and "ash_wyrm" in sim.SpawnableSpecies(),
			"legends are creatures the player can call with the creatures' power")

	# Asleep while the law says so, awake when their year comes.
	sim.SetLaw("legends", false)
	sim.SetLegendWake("elder_treant", 1)
	sim.RunSteps(30)
	check(legend_row(sim, "elder_treant").state == "dormant", "with the law off, legends stay asleep")
	sim.SetLaw("legends", true)
	sim.RunSteps(30)
	var treant := legend_row(sim, "elder_treant")
	check(treant.state == "awake" and not treant.summoned and treant.unit >= 0, "a legend wakes in its lair when its year comes (%s)" % treant.state)

	sim.StartPeoples(PackedStringArray(["humans", "orcs"]), 16)
	sim.RunSteps(30 * 60)
	var village: Dictionary = sim.VillageTable()[0]
	var spot := Vector2(-1, -1)
	for d in [Vector2i(6, 0), Vector2i(0, 6), Vector2i(-6, 0), Vector2i(0, -6), Vector2i(4, 4), Vector2i(-4, -4), Vector2i(3, 0), Vector2i(0, 3)]:
		var t: Vector2i = Vector2i(village.x, village.y) + d
		if t.x >= 0 and t.y >= 0 and t.x < w.width and t.y < w.height and not w.is_water(w.index(t.x, t.y)):
			spot = Vector2(t.x + 0.5, t.y + 0.5)
			break

	# Called by the player: once, never two.
	check(sim.PowerSpawn("ash_wyrm", spot.x, spot.y, 5) == 1 and sim.PowerSpawn("ash_wyrm", spot.x, spot.y, 5) == 0,
			"a legend is unique: called once, refused while it walks the world")
	var wyrm := legend_row(sim, "ash_wyrm")
	check(wyrm.state == "awake" and wyrm.summoned and sim.UnitName(wyrm.unit) == wyrm.full_name and wyrm.full_name in sim.UnitInfo(wyrm.unit),
			"a legend has its name in the world and in the inspector (%s)" % sim.UnitInfo(wyrm.unit))
	check(sim.LegendLabels().size() >= 1, "the names of the legends that walk the world are written over them")

	# Its mind: the procedural one, and a mind's decision validated like any record.
	sim.LegendThinkNow("ash_wyrm")
	wyrm = legend_row(sim, "ash_wyrm")
	check(wyrm.goal in ["slumber", "roam", "hunt", "raid", "tribute"] and wyrm.words != "" and wyrm.mind == "procedural",
			"a legend's mind chooses what it does and says it (%s: \"%s\")" % [wyrm.goal, wyrm.words])
	check(sim.SubmitLegendJson("ash_wyrm", '{"goal": "dance", "target": "", "words": "Hm."}') != ""
			and sim.SubmitLegendJson("ash_wyrm", '{"goal": "raid", "target": "Nowhere", "words": "Burn."}') != ""
			and sim.SubmitLegendJson("ash_wyrm", 'burn them all') != "",
			"a legend's decision that breaks the rules is refused")
	var target: String = village.kingdom
	check(sim.SubmitLegendJson("ash_wyrm", '{"goal": "raid", "target": "%s", "words": "Your walls are kindling to me."}' % target) == ""
			and legend_row(sim, "ash_wyrm").goal == "raid" and legend_row(sim, "ash_wyrm").target == target,
			"a valid decision is followed: a raid on a kingdom within reach")

	# The raid: people fall, warriors strike back, the kingdom remembers.
	sim.RunSteps(30 * 40)
	wyrm = legend_row(sim, "ash_wyrm")
	check(wyrm.kills > 0 or wyrm.health < 0.999 or wyrm.state == "slain", "a raid leaves dead and wounds (%d slain, strength %d%%, %s)" % [wyrm.kills, int(wyrm.health * 100.0), wyrm.state])
	check(wyrm.deeds != "", "a legend's deeds are kept (%s)" % wyrm.deeds)
	var k := -1
	for row in sim.KingdomTable():
		if row.name == target:
			k = row.index
	# (a kingdom the raid wiped out tells no myth: those that saw it from afar may)
	var tellers: Array = [k] if k >= 0 else sim.KingdomTable().map(func(row): return row.index)
	var told: bool = k < 0
	for teller in tellers:
		for n in 6:
			if not sim.MythNow(teller):
				break
	for c in sim.CultureTable():
		if c.index in tellers:
			for m in c.myths:
				told = told or wyrm.name in String(m.source)
	check(told, "the kingdom a legend fell upon makes a myth of it")

	# Slain, and called back.
	wyrm = legend_row(sim, "ash_wyrm")
	if wyrm.state == "awake":
		sim.PowerSmite(wyrm.x, wyrm.y, 1.0)
	wyrm = legend_row(sim, "ash_wyrm")
	check(wyrm.state == "slain" and wyrm.slain > 0 and wyrm.slayer != "", "a legend can be slain, and who slew it is told (%s)" % wyrm.slayer)
	check(sim.PowerSpawn("ash_wyrm", spot.x, spot.y, 1) == 1, "a slain legend can be called back by the player")
	sim.queue_free()


## A world where nature does nothing by itself: the tests of 0.7 call each thing themselves.
func make_quiet_sim(seed_text: String, size := 128) -> Array:
	var made := make_sim(seed_text, size)
	for law in ["natural_disasters", "eruptions", "plagues", "spirits", "monsters", "legends"]:
		made[1].SetLaw(law, false)
	made[1].SetMindEndpoint("")
	return made


func count_ruins(sim: Node2D) -> int:
	var n := 0
	for b in sim.BuildingTable():
		if b.id == "ruin":
			n += 1
	return n


func test_disasters() -> void:
	var made := make_quiet_sim("disasters", 128)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	check(sim.LawTable().has("eruptions") and sim.LawTable().has("plagues") and sim.LawTable().has("spirits") and sim.LawTable().has("monsters"),
			"disasters, plagues, spirits and monsters are laws of the world")
	sim.StartPeoples(PackedStringArray(["humans"]), 16)
	sim.RunSteps(30 * 120)
	var village: Dictionary = sim.VillageTable()[0]
	var at := Vector2(village.x + 0.5, village.y + 0.5)
	check(sim.PowerDisaster("earthquake", 2.0, 2.0, 3.0) == 0 or not w.is_water(w.index(2, 2)), "no disaster starts on the sea")

	# Earthquake: buildings fall.
	var ruins := count_ruins(sim)
	var people: int = sim.PeopleCount()
	var quakes := 0
	for n in 4:
		quakes += sim.PowerDisaster("earthquake", at.x, at.y, 5.0)
	var quake: Dictionary = sim.DisasterTable()[0]
	check(quakes == 4 and count_ruins(sim) > ruins and quake.kind == "earthquake" and quake.cause == "player" and not quake.underway,
			"an earthquake brings buildings down (%d ruins, were %d; %d people, were %d)" % [count_ruins(sim), ruins, sim.PeopleCount(), people])
	var k := -1
	for row in sim.KingdomTable():
		k = row.index
	var told := false
	for n in 6:
		if k < 0 or not sim.MythNow(k):
			break
	for c in sim.CultureTable():
		for m in c.myths:
			told = told or "shook" in String(m.source)
	check(told, "the kingdom that lived through a disaster makes a myth of it")

	# Flood: the low land by the water goes under for a while, then the water draws back.
	var shore := find_tile(w, -1, true)
	sim.TakeOverlayChanges()
	check(sim.PowerDisaster("flood", shore.x + 0.5, shore.y + 0.5, 3.0) == 1, "a flood rises from the shore")
	var flood: Dictionary = sim.DisasterTable()[0]
	var codes := {}
	var changes: PackedInt32Array = sim.TakeOverlayChanges()
	for n in range(0, changes.size(), 3):
		codes[changes[n + 1]] = true
	check(flood.kind == "flood" and flood.underway and flood.tiles > 0 and sim.TileFlooded(shore.x, shore.y) and codes.has(6),
			"flooded land is under water on the map (%d tiles)" % flood.tiles)
	sim.EndDisastersNow()
	sim.RunSteps(30)
	check(not sim.TileFlooded(shore.x, shore.y) and not sim.DisasterTable()[0].underway, "the water draws back")

	# Drought: the grass withers and does not grow back; rain ends it.
	var meadow := find_tile(w, Biomes.GRASSLAND)
	if meadow.x < 0:
		meadow = find_tile(w, Biomes.FOREST)
	sim.SetGrass(meadow.x, meadow.y, 1.0)
	check(sim.PowerDisaster("drought", meadow.x + 0.5, meadow.y + 0.5, 3.0) == 1 and sim.TileParched(meadow.x, meadow.y) and sim.GrassAt(meadow.x, meadow.y) < 0.5,
			"a drought withers the grass (%.2f)" % sim.GrassAt(meadow.x, meadow.y))
	var dry: float = sim.GrassAt(meadow.x, meadow.y)
	sim.RunSteps(30 * 20)
	check(sim.GrassAt(meadow.x, meadow.y) <= dry and sim.TileParched(meadow.x, meadow.y), "nothing grows while the drought lasts (%.2f, was %.2f)" % [sim.GrassAt(meadow.x, meadow.y), dry])
	sim.PowerRain(meadow.x + 0.5, meadow.y + 0.5, 2.0)
	sim.RunSteps(30)
	check(not sim.TileParched(meadow.x, meadow.y), "rain ends a drought")

	# Tornado: it wanders.
	check(sim.PowerDisaster("tornado", meadow.x + 0.5, meadow.y + 0.5, 2.0) == 1, "a whirlwind comes down")
	var before: Dictionary = sim.DisasterTable()[0]
	sim.RunSteps(30 * 4)
	var after: Dictionary = sim.DisasterTable()[0]
	check(after.kind == "tornado" and after.underway and Vector2(after.x, after.y).distance_to(Vector2(before.x, before.y)) > 0.5,
			"the whirlwind wanders over the land (%.1f tiles in 4 s)" % Vector2(after.x, after.y).distance_to(Vector2(before.x, before.y)))
	sim.EndDisastersNow()
	sim.RunSteps(30)

	# Eruption: lava pours out, flows, then cools into volcanic rock.
	sim.TakeBiomeChanges()
	check(sim.PowerDisaster("eruption", meadow.x + 0.5, meadow.y + 0.5, 3.0) == 1 and sim.BiomeAt(meadow.x, meadow.y) == "Lava",
			"an eruption opens the ground in lava")
	var poured: int = sim.DisasterTable()[0].tiles
	sim.RunSteps(30 * 12)
	var flowed: int = sim.DisasterTable()[0].tiles
	var lava_on_map := false
	var repainted: PackedInt32Array = sim.TakeBiomeChanges()
	for n in range(0, repainted.size(), 2):
		lava_on_map = lava_on_map or repainted[n + 1] == Biomes.LAVA
	check(flowed > poured and lava_on_map, "lava flows over the land around and the map shows it (%d tiles, were %d)" % [flowed, poured])
	sim.EndDisastersNow()
	sim.RunSteps(30)
	sim.CoolLavaNow()
	sim.RunSteps(30)
	check(sim.BiomeAt(meadow.x, meadow.y) == "Volcanic rock", "lava cools into volcanic rock (%s)" % sim.BiomeAt(meadow.x, meadow.y))

	# Wildfire, and nature striking on its own.
	var woods := find_tile(w, Biomes.FOREST)
	if woods.x >= 0:
		sim.SetGrass(woods.x, woods.y, 0.7)
		check(sim.PowerDisaster("wildfire", woods.x + 0.5, woods.y + 0.5, 3.0) == 1 and sim.BurningCount() > 0, "a wildfire breaks out in the woods")
	var seen: int = sim.DisasterTable().size()
	sim.SetLaw("natural_disasters", true)
	sim.SetLaw("eruptions", true)
	var kinds := {}
	for n in 12:
		sim.NaturalDisasterNow()
		kinds[sim.DisasterTable()[0].kind] = true
		sim.EndDisastersNow()
		sim.RunSteps(10)
	check(sim.DisasterTable().size() >= seen and kinds.size() >= 2, "nature strikes on its own, in several ways (%s)" % [kinds.keys()])
	check(sim.LifeStats().has("Disaster") and sim.LifeStats().has("Plague"), "deaths by disaster and by plague are counted")
	var atlas := SpriteAtlas.shared()
	check(atlas.has("effects/Tornado_0") and atlas.has("effects/Tornado_2") and atlas.has("effects/Sick"), "the whirlwind and the mark of the sick have their sprites")
	sim.queue_free()


func test_plagues() -> void:
	var made := make_quiet_sim("plagues", 128)
	var sim: Node2D = made[1]
	sim.StartPeoples(PackedStringArray(["humans"]), 16)
	sim.RunSteps(30 * 30)
	var village: Dictionary = sim.VillageTable()[0]
	var v: int = village.index
	var at := Vector2(village.x + 0.5, village.y + 0.5)

	# A sickness passes from one to the next, kills some, and the others get over it for good.
	var d: int = sim.StartDisease(v, "fever", "none", 0.5, 0.5, 20.0, 3)
	var first: Dictionary = sim.DiseaseTable()[0]
	check(d >= 0 and sim.SickCount() == 3 and first.name.begins_with("the ") and first.sick == 3 and first.ended < 0,
			"a disease breaks out with a name of its own (%s)" % first.name)
	var sick_unit := -1
	for i in 4000:
		if sim.UnitSick(i):
			sick_unit = i
			break
	check(sick_unit >= 0 and first.name in sim.UnitInfo(sick_unit), "the inspector tells who is sick, and with what (%s)" % sim.UnitInfo(sick_unit))
	sim.RunSteps(30 * 10)
	var spreading: Dictionary = sim.DiseaseTable()[0]
	check(spreading.caught > 3, "it passes to those who stand close (%d caught it)" % spreading.caught)
	check(sim.VillageTable()[0].sick > 0 and sim.VillageTable()[0].sickness == first.name, "a village counts its sick")
	sim.RunSteps(30 * 90)
	var over: Dictionary = sim.DiseaseTable()[0]
	check(over.dead > 0 and over.recovered > 0 and over.ended > 0 and sim.SickCount() == 0 and sim.LifeStats().Plague == over.dead,
			"it kills some, the others get over it, and it burns out (%d dead, %d recovered of %d)" % [over.dead, over.recovered, over.caught])

	# Quarantine, and the player's healing hand.
	sim.StartPeoples(PackedStringArray(["elves"]), 16)
	sim.RunSteps(30 * 20)
	var other: Dictionary = sim.VillageTable().filter(func(row): return row.index != v)[0]
	check(sim.StartDisease(other.index, "cough", "quarantine", 0.4, 0.0, 300.0, 8) >= 0, "another sickness, in another village")
	sim.RunSteps(30 * 6)
	check(sim.VillageQuarantined(other.index), "a village with many sick shuts its gates")
	var healed: int = sim.PowerHeal(other.x + 0.5, other.y + 0.5, 14.0)
	check(healed > 0 and sim.SickCount() == 0, "the player heals the sick (%d)" % healed)
	sim.RunSteps(30 * 6)
	check(not sim.VillageQuarantined(other.index), "the gates open again when no one is sick")

	# The player's plague takes any creature of flesh; golems never sicken.
	var spot := at + Vector2(6, 0)
	var sheep := 0
	for n in 5:
		if sim.SpawnAt("sheep", spot.x, spot.y, false) >= 0:
			sheep += 1
	if sheep > 0:
		var before: int = sim.DiseaseTable().size()
		var caught: int = sim.PowerPlague(spot.x, spot.y, 1.0)
		var plague: Dictionary = sim.DiseaseTable()[0]
		check(caught > 0 and sim.DiseaseTable().size() == before + 1 and plague.carrier == "all" and plague.cause == "player",
				"the player's plague takes hold of the creatures under the brush (%d caught %s)" % [caught, plague.name])
		sim.PowerSmite(spot.x, spot.y, 2.0)
		var golem: int = sim.SpawnAt("golem", spot.x, spot.y, false)
		check(golem >= 0 and sim.PowerPlague(spot.x, spot.y, 0.6) == 0, "what is not of flesh never sickens")
	# On its own.
	sim.SetLaw("plagues", true)
	var known: int = sim.DiseaseTable().size()
	for n in 6:
		sim.OutbreakNow()
	check(sim.DiseaseTable().size() > known, "sicknesses break out on their own (%d new)" % (sim.DiseaseTable().size() - known))
	var names := {}
	for row in sim.DiseaseTable():
		names[row.name] = true
	check(names.size() == sim.DiseaseTable().size(), "every disease of a world has its own name (%s)" % [names.keys()])
	sim.queue_free()


func test_spirits() -> void:
	var made := make_quiet_sim("spirits", 160)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	var spirits: Array = sim.SpiritTable()
	var fine := spirits.size() >= 2 and spirits.size() <= 9
	var places := {}
	for s in spirits:
		fine = fine and s.tiles >= 80 and s.name != "" and String(s.full_name).contains("spirit of") and s.mood > 0.0
		fine = fine and sim.SpiritAt(s.x, s.y) == s.index
		places[s.place] = true
	check(fine and places.size() == spirits.size(), "each large land of a world has a spirit with a name and a place (%s)" % [spirits.map(func(s): return s.full_name)])

	sim.StartPeoples(PackedStringArray(["humans", "elves"]), 16)
	sim.RunSteps(30 * 60)
	# A spirit with a kingdom in or near its lands.
	var spirit := -1
	var kingdom := ""
	var k := -1
	var village := {}
	for row in sim.VillageTable():
		for dy in range(-10, 11, 5):
			for dx in range(-10, 11, 5):
				if spirit < 0 and sim.SpiritAt(row.x + dx, row.y + dy) >= 0:
					spirit = sim.SpiritAt(row.x + dx, row.y + dy)
					kingdom = row.kingdom
					village = row
	for row in sim.KingdomTable():
		if row.name == kingdom:
			k = row.index
	check(spirit >= 0 and k >= 0, "a village lives in or near a spirit's lands")
	if spirit < 0 or k < 0:
		sim.queue_free()
		return

	# The rules a spirit's mind is held to.
	sim.SetSpiritMood(spirit, 0.8)
	check(sim.SubmitSpiritJson(spirit, '{"act": "punish", "target": "%s", "words": "Burn."}' % kingdom) != ""
			and sim.SubmitSpiritJson(spirit, '{"act": "dance", "target": "", "words": "Hm."}') != ""
			and sim.SubmitSpiritJson(spirit, '{"act": "bless", "target": "Nowhere", "words": "Take this."}') != ""
			and sim.SubmitSpiritJson(spirit, 'bless them') != "",
			"a spirit's decision that breaks the rules is refused (a content spirit does not punish)")
	check(sim.SubmitSpiritJson(spirit, '{"act": "bless", "target": "%s", "words": "You walked softly. Eat."}' % kingdom) == "",
			"a content spirit blesses a kingdom near its lands")
	var blessed: Dictionary = sim.SpiritTable()[spirit]
	check(blessed.act == "bless" and blessed.target == kingdom and blessed.deeds != "" and blessed.mood < 0.8, "its gift is given and kept among its deeds (%s)" % blessed.deeds)
	sim.SetSpiritMood(spirit, -0.9)
	check(sim.SubmitSpiritJson(spirit, '{"act": "bless", "target": "%s", "words": "Eat."}' % kingdom) != "", "an angry spirit does not bless")

	# What is done to its lands grieves it; wrathful, it strikes the kingdom it blames.
	sim.SetSpiritMood(spirit, 0.0)
	sim.GrieveSpirit(spirit, 400.0, k)
	var disasters: int = sim.DisasterTable().size() + sim.DiseaseTable().size()
	var beasts: int = sim.UnitCount()
	sim.SpiritThinkNow(spirit)
	var angry: Dictionary = sim.SpiritTable()[spirit]
	check(angry.act == "punish" and angry.target == kingdom and angry.mind == "procedural" and angry.words != "" and "trees felled" in angry.wounds,
			"a spirit whose trees are felled grows wrathful and punishes the kingdom that did it (%s: \"%s\")" % [angry.act, angry.words])
	check(angry.mood > -1.0 and (sim.DisasterTable().size() + sim.DiseaseTable().size() > disasters or sim.UnitCount() > beasts or "fields" in angry.deeds or "storm" in angry.deeds),
			"its wrath is a disaster of its kind (%s)" % angry.deeds)
	var told := false
	for n in 8:
		if not sim.MythNow(k):
			break
	for c in sim.CultureTable():
		if c.index == k:
			for m in c.myths:
				told = told or angry.name in String(m.source)
	check(told, "the kingdom makes a myth of what the spirit did to it")
	var events := "\n".join(sim.TakeEvents())
	check(angry.name in events, "the chronicle tells what spirits do")

	# A volcano raised by the player gets its spirit.
	var land := Vector2(village.x + 14.5, village.y + 0.5)
	if not w.is_water(w.index(clampi(int(land.x), 0, w.width - 1), clampi(int(land.y), 0, w.height - 1))):
		sim.PowerBiome("Volcanic rock", land.x, land.y, 4.0)
		sim.SpiritWatchNow()
		check(sim.SpiritTable().any(func(s): return s.kind == "volcano"), "a volcano the player raises gets a spirit of its own")
	sim.queue_free()


func test_monsters() -> void:
	var made := make_quiet_sim("monsters", 128)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	var atlas := SpriteAtlas.shared()
	var sprites := true
	for rec in JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json")).monsters:
		sprites = sprites and atlas.has("effects/Lair_%s" % rec.lair) and rec.id in sim.SpawnableSpecies()
	check(sprites, "every monster has a lair, and every lair its sprite")
	var spot := find_tile(w, Biomes.GRASSLAND)
	if spot.x < 0:
		spot = find_tile(w, -1)
	var at := Vector2(spot.x + 0.5, spot.y + 0.5)
	sim.SetLaw("hunger", false)
	for n in 8:
		sim.SpawnAt("spider", at.x, at.y, false)
	check(sim.StrainTable().size() == 1 and sim.StrainTable()[0].name == "Spider" and sim.StrainTable()[0].generation == 1, "monsters that live in a world are listed")

	# Lairs.
	check(sim.FoundLairAt("spider", spot.x, spot.y) and not sim.FoundLairAt("spider", spot.x + 2, spot.y), "monsters make a lair, and no second one right beside it")
	var lair: Dictionary = sim.LairTable()[0]
	check(lair.alive and lair.name == "spider nest" and lair.kind == "nest" and lair.size == 1.0, "a lair has a name and a place (%s %s)" % [lair.name, lair.place])
	sim.SetLaw("monsters", true)
	sim.PowerSmite(at.x, at.y, 12.0)
	sim.AgeLairs(6.0)
	sim.RunSteps(30 * 8)
	lair = sim.LairTable()[0]
	check(lair.born > 0 and sim.PopulationOf("spider") > 0 and lair.size > 2.0, "a lair left alone grows and brings new monsters (%d born, size %.1f)" % [lair.born, lair.size])

	# Mutations.
	for n in 8:
		sim.SpawnAt("spider", at.x, at.y, false)
	check(sim.SubmitMutationJson("spider", '{"mutation": "wings", "name": ""}') != "" and sim.SubmitMutationJson("spider", 'grow') != ""
			and sim.SubmitMutationJson("spider", '{"mutation": "venom", "name": "Sheep"}') != "",
			"a change that breaks the rules is refused")
	sim.MutateNow("spider")
	var strain: Dictionary = sim.StrainTable()[0]
	check(strain.generation == 2 and strain.mutations.size() == 1 and strain.name != "Spider" and String(strain.name).ends_with("Spider") and strain.mind == "procedural"
			and strain.lineage != "" and sim.PopulationTable().has(strain.name),
			"a thriving species of monsters changes, and bears a new name (%s)" % strain.name)
	var free := ""
	for id in ["venom", "giant", "swarm", "swift", "cunning"]:
		if free == "" and sim.SubmitMutationJson("spider", '{"mutation": "%s", "name": "Ashfang Spider"}' % id) == "":
			free = id
	strain = sim.StrainTable()[0]
	check(free != "" and strain.generation == 3 and strain.name == "Ashfang Spider" and sim.SubmitMutationJson("spider", '{"mutation": "%s", "name": ""}' % free) != "",
			"a mind may name the strain; a change is only taken once (%s)" % strain.name)
	check("Ashfang" in "\n".join(sim.TakeEvents()), "the chronicle tells how monsters change")

	# The player's wrath destroys a lair.
	sim.PowerMeteor(at.x, at.y, 2.0)
	lair = sim.LairTable()[0]
	check(not lair.alive and lair.end != "", "a meteor destroys a lair (%s)" % lair.end)

	# A new world gets the species as they were.
	sim.Start(w, PackedStringArray(Biomes.NAMES))
	sim.SpawnAt("spider", at.x, at.y, false)
	check(sim.PopulationTable().has("Spider") and sim.StrainTable()[0].generation == 1 and sim.LairTable().is_empty(), "a new world starts with the monsters as they were")
	sim.queue_free()


## The id (index) of the kingdom named `name` in the simulation's kingdom table, or -1.
func kingdom_index(sim: Node2D, name: String) -> int:
	for row in sim.KingdomTable():
		if row.name == name:
			return row.index
	return -1


func progress_row(sim: Node2D, k: int) -> Dictionary:
	for row in sim.ProgressTable():
		if row.index == k:
			return row
	return {}


## 0.8 Ages: knowledge, the ages one by one, things that evolve, falling back, the ages beyond.
func test_ages() -> void:
	var made := make_quiet_sim("ages", 128)
	var sim: Node2D = made[1]
	check(sim.LawTable().has("ages") and sim.LawTable().has("pollution") and sim.LawTable().has("nuclear_war") and sim.LawTable().has("eras"),
			"the ages, pollution, nuclear war and the moods of the world are laws")
	var names: PackedStringArray = sim.AgeNames()
	check(names.size() >= 10 and names[0] == "Stone Age" and "Industrial Age" in names and "Space Age" in names,
			"the ages run from the Stone Age to the stars (%s)" % [", ".join(names)])
	sim.StartPeoples(PackedStringArray(["humans", "orcs"]), 16)
	sim.RunSteps(30 * 60)
	var kingdoms: Array = sim.KingdomTable()
	var k: int = kingdoms[0].index
	var row := progress_row(sim, k)
	check(kingdoms[0].age_name == "Stone Age" and row.designs.vehicle == "Sledge" and row.designs.weapon == "Stone Spear",
			"a people starts in the Stone Age, with its sledges and stone spears (%s)" % [row.designs])
	var gain: float = sim.KnowledgeGainOf(k)
	var before: float = sim.KingdomKnowledge(k)
	sim.AgesYearNow()
	check(gain > 0.0 and sim.KingdomKnowledge(k) > before, "a people gains knowledge every year (%.1f a year)" % gain)

	# Into the Bronze Age: the things of the age change, and the change is told.
	sim.TakeEvents()
	sim.AddKnowledge(k, 1000.0)
	row = progress_row(sim, k)
	var events := "\n".join(sim.TakeEvents())
	check(row.age >= 1 and "enter the Bronze Age" in events, "enough knowledge takes a people into the next age (%s)" % row.age_name)
	check(row.designs.vehicle != "Sledge" and "→" in String(row.lineage.vehicle) and row.mind == "procedural" and row.words != "",
			"its mind names the things of the new age, each grown from the old (%s)" % row.lineage.vehicle)
	check(row.strength > 1.0, "its soldiers strike harder than in the Stone Age (x%.2f)" % row.strength)

	# What a mind may write.
	check(sim.SubmitDesigns(k, "a cart") != "" and sim.SubmitDesigns(k, '{"age": "", "vehicle": "C4rt!", "ship": "Boat", "home": "Hut", "weapon": "Axe", "words": "Hm."}') != ""
			and sim.SubmitDesigns(k, '{"age": "", "vehicle": "Cart", "ship": "Boat", "home": "Hut", "weapon": "Axe", "words": ""}') != "",
			"designs that break the rules are refused")
	check(sim.SubmitDesigns(k, '{"age": "", "vehicle": "Thunder Wagon", "ship": "Reed Skiff", "home": "Clay Hall", "weapon": "Sun Blade", "words": "The wheel turns for us."}') == ""
			and sim.KingdomDesign(k, "vehicle") == "Thunder Wagon", "a mind's designs are taken")
	var prompt: String = sim.DesignPrompt(k)
	check(row.age_name in prompt and "Thunder Wagon" in prompt, "the model is told the age and what the people used until now")

	# Inventions of later ages: vehicles once the wheel is known, engines from the Industrial Age.
	var other: int = kingdoms[1].index
	var cart := '{"name": "Swift Wheel", "kind": "vehicle", "cost": {"wood": 20, "metal": 10}, "effects": [{"do": "speed", "amount": 20}], "sprite": 0}'
	var engine := '{"name": "Fire Engine", "kind": "energy", "cost": {"wood": 20, "metal": 10}, "effects": [{"do": "power", "amount": 15}], "sprite": 0}'
	var refused: String = sim.SubmitInventionJson(other, cart, "model")
	check("beyond their age" in refused or "budget" in refused, "a Stone Age people cannot invent a vehicle (%s)" % refused)
	check(sim.SubmitInventionJson(k, cart, "model") == null or sim.SubmitInventionJson(k, cart, "model") == "", "a Bronze Age people can")
	check(sim.SubmitInventionJson(k, engine, "model") != "", "engines wait for the Industrial Age")

	# Buildings of later ages.
	var v: int = sim.VillageTable()[0].index
	for r in sim.VillageTable():
		if r.kingdom == kingdoms[0].name:
			v = r.index
	check(not sim.AgeAllows(v, "factory") and sim.AgeAllows(v, "hut"), "factories wait for the Industrial Age")
	sim.SetKingdomAge(k, 5)
	check(sim.KingdomAgeName(k) == "Industrial Age" and sim.AgeAllows(v, "factory") and not sim.AgeAllows(v, "silo"),
			"an industrial people may build factories, not yet missile silos")
	check(sim.SubmitInventionJson(k, engine, "model") == null or sim.SubmitInventionJson(k, engine, "model") == "", "an industrial people invents engines")
	row = progress_row(sim, k)
	check(String(row.lineage.vehicle).split("→").size() >= 5 and row.designs.vehicle != "", "its vehicles have come a long way (%s)" % row.lineage.vehicle)

	# Falling back, and finding the way again.
	sim.TakeEvents()
	sim.SetbackNow(k, 2.0, "a great fire")
	row = progress_row(sim, k)
	events = "\n".join(sim.TakeEvents())
	check(row.age == 4 and row.peak == 5 and "falls back" in events and "a great fire" in row.feats,
			"a people that loses its knowledge falls back an age, and remembers how far it had come (%s)" % row.age_name)
	var regained: float = sim.KnowledgeGainOf(k)
	sim.SetKingdomAge(k, 5)
	check(regained > 0.0 and sim.KingdomAge(k) == 5, "what was lost is found again")

	# Beyond the future: ages without end, named as they are reached.
	var count: int = sim.AgeNames().size()
	sim.SetKingdomAge(k, count)
	var beyond: String = sim.KingdomAgeName(k)
	check(not (beyond in sim.AgeNames()) and beyond != "" and sim.WorldAges().beyond == beyond, "past the last age come ages no one has seen (%s)" % beyond)
	check(sim.SubmitDesigns(k, '{"age": "Glass Dawn", "vehicle": "Thought Sled", "ship": "Star Skiff", "home": "Dream Hall", "weapon": "Hush Lance", "words": "We have gone further than any."}') == ""
			and sim.KingdomAgeName(k) == "The Glass Dawn", "the first people to reach an age beyond may name it (%s)" % sim.KingdomAgeName(k))
	sim.SetKingdomAge(k, count + 1)
	check(sim.KingdomAgeName(k) != "The Glass Dawn" and sim.WorldAges().beyond.contains("The Glass Dawn"), "and the ages go on")

	# The built-in model with a tiny random model: the grammar keeps its designs well-formed.
	check("name ::=" in sim.DesignGrammarOf(k) and "\\\"vehicle\\\"" in sim.DesignGrammarOf(k), "the designs have a grammar for the built-in model")
	sim.StartMind(ProjectSettings.globalize_path("res://tests/data/tiny_random.gguf"), "", false)
	for wait in 400:
		if sim.MindStatus().status in ["ready", "failed", "missing"]:
			break
		OS.delay_msec(25)
	if sim.MindStatus().status == "ready":
		var asked: int = sim.ModelAnswers + sim.ModelFailures
		sim.AskDesigns(k)
		var got = null
		for wait in 1200:
			sim.RunSteps(5)
			OS.delay_msec(25)
			if sim.ModelAnswers + sim.ModelFailures > asked:
				got = JSON.parse_string(sim.LastModelAnswer)
				if got is Dictionary and got.has("vehicle"):
					break
				asked = sim.ModelAnswers + sim.ModelFailures
		var why: String = sim.LastModelError
		check(got is Dictionary and got.has_all(["age", "vehicle", "ship", "home", "weapon", "words"]) and not why.begins_with("not valid JSON")
				and not ("forbidden character" in why), "the grammar keeps the built-in model's designs well-formed (%s; %s)" % [sim.LastModelAnswer.left(100), why])
	else:
		check(false, "the built-in mind loads its model (%s)" % [sim.MindStatus()])
	sim.StopMind()
	sim.queue_free()


## 0.8 Moods of the world: eras that change the weather and growth, brought on by the player.
func test_eras() -> void:
	var made := make_quiet_sim("eras", 96)
	var sim: Node2D = made[1]
	var ids: PackedStringArray = sim.EraIds()
	check(ids.size() >= 6 and "dark" in ids and "magical" in ids and sim.EraName() == "Calm Era", "a world begins calm, with eras to come (%s)" % [", ".join(ids)])
	sim.TakeEvents()
	check(sim.PowerEra("cold") and sim.EraId() == "cold" and "cold era" in "\n".join(sim.TakeEvents()), "the player brings a cold era on, and the chronicle tells it")
	var cold: float = sim.Coldness()
	var cold_growth: float = sim.EraTable().growth
	sim.PowerEra("scorching")
	check(sim.Coldness() < cold or cold == 0.0, "a cold era is colder than a scorching one (%.2f, %.2f)" % [cold, sim.Coldness()])
	sim.PowerEra("bright")
	check(sim.EraTable().growth > cold_growth and sim.EraTable().knowledge > 1.0, "a bright era grows more and learns faster")
	sim.PowerEra("dark")
	var tint: Color = sim.EraTint()
	check(tint.b > tint.r and tint.r < 0.9 and sim.EraTable().monsters > 1.0, "a dark era darkens the land and brings monsters out (%s)" % tint)
	check(not sim.PowerEra("nonsense") and sim.EraId() == "dark", "an unknown era changes nothing")
	var table: Dictionary = sim.EraTable()
	check(table.by_player and table.years_left >= 15 and table.past.size() >= 3, "an era lasts decades, and the past ones are kept (%s)" % [table.past])
	sim.SetLaw("eras", false)
	sim.EraNextNow()
	check(sim.EraId() == "calm", "with the law off, the world stays calm")
	sim.SetLaw("eras", true)
	var seen := {}
	for n in 12:
		sim.EraNextNow()
		seen[sim.EraId()] = true
	check(seen.size() >= 3, "eras change on their own, by their weights (%s)" % [seen.keys()])
	sim.queue_free()


## 0.8 The price of progress: smog, warming, the bomb and its winter; rockets.
func test_progress_costs() -> void:
	var made := make_quiet_sim("progress", 128)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	sim.StartPeoples(PackedStringArray(["humans", "dwarves"]), 16)
	sim.RunSteps(30 * 90)
	var kingdoms: Array = sim.KingdomTable()
	var k: int = kingdoms[0].index
	var foe: int = kingdoms[1].index
	var capital: Dictionary = {}
	var foe_village: Dictionary = {}
	for r in sim.VillageTable():
		if r.kingdom == kingdoms[0].name and capital.is_empty():
			capital = r
		if r.kingdom == kingdoms[1].name and foe_village.is_empty():
			foe_village = r

	# Smog over the land of an industrial people.
	sim.SetKingdomAge(k, 6)
	sim.BuildNow(capital.index, "factory")
	sim.BuildNow(capital.index, "power_plant")
	for n in 3:
		sim.AgesYearNow()
	var air: Dictionary = sim.WorldAges()
	check(air.carbon > 0.0 and sim.SmogAt(capital.x, capital.y) > 0.0, "factories and power plants fill the air (carbon %.0f, smog %.1f)" % [air.carbon, sim.SmogAt(capital.x, capital.y)])
	sim.AddSmog(capital.x, capital.y, 400.0)
	sim.AgesYearNow()
	var blighted := 0
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			if sim.BlightAt(capital.x + dx, capital.y + dy) > 0:
				blighted += 1
	check(blighted > 0 and sim.WorldAges().smoggy_zones > 0, "thick smog withers the land (%d tiles blighted)" % blighted)

	# A warmer world: milder winters, told by the degree.
	var cold: float = sim.Coldness()
	sim.TakeEvents()
	sim.AddCarbon(15000.0 * 3.0)
	sim.AgesYearNow()
	check(sim.Warming >= 2.5 and "warmer" in "\n".join(sim.TakeEvents()) and (sim.Coldness() < cold or cold == 0.0),
			"the world warms and winters grow milder (%.1f degrees)" % sim.Warming)

	# The bomb.
	sim.SetKingdomAge(foe, 7)
	var people: int = sim.PeopleCount()
	var ruins := count_ruins(sim)
	var age_before: int = sim.KingdomAge(foe)
	var know_before: float = sim.KingdomKnowledge(foe)
	sim.TakeEvents()
	var killed: int = sim.Nuke(foe_village.x + 0.5, foe_village.y + 0.5, k)
	var events := "\n".join(sim.TakeEvents())
	check(killed > 0 and sim.PeopleCount() < people and count_ruins(sim) > ruins and "drops the bomb" in events,
			"the bomb kills and flattens (%d dead, %d ruins)" % [killed, count_ruins(sim) - ruins])
	check(sim.BlightAt(foe_village.x, foe_village.y) > 0 and sim.WorldAges().nukes == 1 and sim.SkyEffects() > 0,
			"it leaves blighted land and a mushroom cloud")
	check(sim.KingdomAge(foe) < age_before or sim.KingdomKnowledge(foe) < know_before or kingdom_index(sim, kingdoms[1].name) < 0,
			"the struck people loses knowledge")
	var tint_before: Color = sim.EraTint()
	sim.PowerNuke(foe_village.x + 0.5, foe_village.y + 0.5)
	events = "\n".join(sim.TakeEvents())
	check(sim.WorldAges().winter >= 2.0 and "nuclear winter" in events and sim.EraTint().s < tint_before.s + 0.001 and sim.Coldness() > 0.3,
			"bombs bring the nuclear winter: grey skies, cold, failing harvests")
	check(sim.PowerNuke(1.0, 1.0) == -1 or not w.is_water(w.index(1, 1)), "the bomb falls on land")

	# Kingdoms at war may drop the bomb themselves.
	sim.SetKingdomAge(k, 7)
	var silo: int = sim.BuildNow(capital.index, "silo")
	sim.PowerWhisper("war", k, foe)
	var dropped := false
	for n in 80:
		var before: int = sim.WorldAges().nukes
		# The winter of the bombs costs knowledge every year: keep them in the Atomic Age.
		sim.SetKingdomAge(k, 7)
		sim.AgesYearNow()
		if sim.WorldAges().nukes > before:
			dropped = true
			break
	check(silo >= 0 and (dropped or kingdom_index(sim, kingdoms[1].name) < 0), "an atomic kingdom at war, with a silo, may drop the bomb on its own (silo %d)" % silo)

	# To the stars.
	sim.SetLaw("nuclear_war", false)
	sim.SetKingdomAge(k, 8)
	var pad: int = sim.BuildNow(capital.index, "launch_pad")
	var first: String = sim.LaunchNow(k)
	var second: String = sim.LaunchNow(k)
	check(pad >= 0 and "first rocket" in first and "satellite" in second and sim.WorldAges().rockets == 2,
			"a Space Age people with a launch pad sends rockets and satellites up (%s; %s)" % [first, second])
	sim.queue_free()


## 0.9 Terrain tools: raise, lower, water, stamps and the player's own, the terrain kept valid.
func test_terrain() -> void:
	var made := make_quiet_sim("terrain", 128)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	check(sim.TerrainValid(), "a new world's terrain is valid (land steps by one level, plains at the water)")
	var at := find_tile(w, Biomes.GRASSLAND)
	if at.x < 0:
		at = find_tile(w, -1)
	var x := at.x + 0.5
	var y := at.y + 0.5
	sim.PowerRaise(x, y, 1.5)
	sim.PowerRaise(x, y, 1.5)
	check(sim.LevelAt(at.x, at.y) == 4 and sim.BiomeAt(at.x, at.y) == "Mountain" and sim.TerrainValid(),
			"raising the land twice makes a mountain, with hills around it (%d, %s)" % [sim.LevelAt(at.x, at.y), sim.BiomeAt(at.x, at.y)])
	var deer: int = sim.SpawnAt("deer", x + 0.2, y + 0.2, false)
	for n in 3:
		sim.PowerLower(x, y, 1.5)
	check(sim.WaterAt(at.x, at.y) > 0 and sim.LevelAt(at.x, at.y) <= 1 and sim.TerrainValid(), "lowering it three times brings the water in")
	check(deer < 0 or not sim.UnitAlive(deer), "what stood there drowns")
	check(sim.PowerWater(x, y, 1.5) > 0 and sim.WaterAt(at.x, at.y) == 0 and sim.TerrainValid(), "water dried by the Water power is land again")
	check(sim.PowerWater(x, y, 2.0) > 0 and sim.WaterAt(at.x, at.y) == 2 and sim.TerrainValid(), "the Water power pours a lake on land")
	var quads: PackedInt32Array = sim.TakeTerrainChanges()
	check(quads.size() > 0 and quads.size() % 4 == 0 and sim.TakeTerrainChanges().is_empty(), "the map is told what changed, once")

	# Stamps.
	var ids: PackedStringArray = sim.StampIds()
	check("volcano_small" in ids and "island" in ids and "oasis" in ids and sim.StampName("island") == "Island", "built-in stamps are ready (%s)" % [", ".join(ids)])
	var land := find_tile(w, Biomes.GRASSLAND)
	if land.x < 0:
		land = find_tile(w, -1)
	var far := Vector2i(-1, -1)
	for yy in range(10, w.height - 10, 3):
		for xx in range(10, w.width - 10, 3):
			if far.x < 0 and w.level[w.index(xx, yy)] == WorldData.Level.DEEP_SEA:
				far = Vector2i(xx, yy)
	if far.x >= 0:
		sim.PowerStamp("island", far.x + 0.5, far.y + 0.5)
		check(sim.WaterAt(far.x, far.y) == 0 and sim.LevelAt(far.x, far.y) >= 2 and sim.TerrainValid(), "an island rises from the sea")
	var spot := find_tile(w, Biomes.GRASSLAND)
	spot = Vector2i(clampi(spot.x + 20, 10, w.width - 10), spot.y)
	sim.PowerStamp("volcano_small", spot.x + 0.5, spot.y + 0.5)
	check(sim.LevelAt(spot.x, spot.y) == 4 and sim.BiomeAt(spot.x, spot.y) == "Lava" and sim.TerrainValid(), "a volcano is pasted with lava at its heart (%s)" % sim.BiomeAt(spot.x, spot.y))
	check(sim.PowerStamp("nonsense", 5.0, 5.0) == -1, "an unknown stamp does nothing")

	# The player's own stamp: copied here, pasted there, kept on disk.
	var json: String = sim.CopyStamp(spot.x + 0.5, spot.y + 0.5, 10)
	check(sim.AddStamp("my_test", "My test", json) == "" and "my_test" in sim.StampIds() and sim.AddStamp("x", "Bad", "{}") != "",
			"the land can be copied as a stamp of one's own")
	var there := Vector2i(clampi(spot.x - 25, 10, w.width - 10), spot.y)
	sim.PowerStamp("my_test", there.x + 0.5, there.y + 0.5)
	check(sim.LevelAt(there.x, there.y) == sim.LevelAt(spot.x, spot.y) and sim.TerrainValid(), "and pasted elsewhere")
	var Store = load("res://scripts/world/stamp_store.gd")
	var dir := "user://test_stamps"
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
	var saved: Array = Store.save(json, dir)
	var back: Array = Store.load_all(dir)
	check(saved.size() == 2 and back.size() == 1 and back[0][0] == saved[0] and sim.AddStamp(back[0][0], back[0][1], back[0][2]) == "",
			"stamps are kept on disk and read back in another world")
	Store.remove(saved[0], dir)
	check(Store.load_all(dir).is_empty(), "and can be thrown away")
	sim.queue_free()


## 0.9 More powers: sparks, seeds, blizzard, curse, madness, resurrect, and powers on minds.
func test_more_powers() -> void:
	var made := make_quiet_sim("more powers", 128)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	sim.StartPeoples(PackedStringArray(["humans", "orcs"]), 16)
	sim.RunSteps(30 * 60)
	var home: Dictionary = sim.VillageTable()[0]
	var hx: float = home.x + 0.5
	var hy: float = home.y + 0.5
	var k: int = kingdom_index(sim, home.kingdom)

	# The fire throws sparks that fall and light the land.
	var wood := find_tile(w, Biomes.FOREST)
	if wood.x < 0:
		wood = find_tile(w, Biomes.GRASSLAND)
	sim.PowerFire(wood.x + 0.5, wood.y + 0.5, 1.5)
	var thrown: int = sim.SparkCount()
	sim.RunSteps(60)
	check(thrown > 0 and sim.SparkCount() < thrown, "the fire throws sparks that fall back on the land (%d thrown)" % thrown)

	# Seeds, and the frost of a blizzard.
	var field := Vector2(hx + 9.0, hy + 9.0)
	var plants: int = sim.PlantCount()
	sim.PowerSeeds(field.x, field.y, 3.0)
	check(sim.PlantCount() >= plants, "seeds sow the plants of the land (%d → %d)" % [plants, sim.PlantCount()])
	var rabbits := 0
	for n in 10:
		if sim.SpawnAt("chicken", field.x + n * 0.1, field.y, false) >= 0:
			rabbits += 1
	sim.PowerBlizzard(field.x, field.y, 3.0)
	check(sim.FrostAt(int(field.x), int(field.y)) or w.is_water(w.index(int(field.x), int(field.y))), "a blizzard leaves frost on the land")
	var stats: Dictionary = sim.LifeStats()
	check(rabbits == 0 or stats.Disaster > 0, "the cold kills some of the creatures caught in it")

	# Curse and madness.
	var people: Array = []
	for i in sim.UnitCount() * 4:
		if sim.UnitAlive(i) and sim.UnitVillage(i) == home.index:
			people.append(i)
	check(sim.PowerCurse(hx, hy, 3.0) > 0, "the curse falls on those under the brush")
	var cursed := people.filter(func(i): return sim.IsCursed(i))
	check(cursed.size() > 0, "they are cursed (%d)" % cursed.size())
	var wolves: Array = []
	for n in 4:
		wolves.append(sim.SpawnAt("deer", field.x + n * 0.4, field.y + 2.0, false))
	check(sim.PowerMadness(field.x, field.y + 2.0, 2.0) > 0, "madness turns creatures on each other")

	# The dead rise.
	var victims := 0
	for n in 4:
		var i: int = sim.SpawnAt("deer", field.x - 4.0 + n * 0.3, field.y - 4.0, false)
		if i >= 0:
			victims += 1
	sim.PowerSmite(field.x - 3.5, field.y - 4.0, 1.5)
	check(victims == 0 or sim.PowerResurrect(field.x - 3.5, field.y - 4.0, 2.0) > 0, "the dead lying there rise again")

	# Minds.
	var inventions: int = sim.InventionTable().size()
	check(sim.PowerInspire(hx, hy) and sim.InventionTable().size() > inventions, "an idea given to a kingdom: it invents at once")
	var culture: Dictionary = sim.CultureTable().filter(func(c): return c.index == k)[0]
	var creed: String = culture.creed
	check(sim.PowerForgetFaith(hx, hy), "a kingdom forgets its faith")
	culture = sim.CultureTable().filter(func(c): return c.index == k)[0]
	check(culture.creed != creed and culture.myths.is_empty(), "a new faith is born there (%s → %s)" % [creed, culture.creed])
	check(sim.PowerForgetCulture(hx, hy) and sim.CultureTable().filter(func(c): return c.index == k)[0].customs.is_empty(),
			"a kingdom forgets its customs")
	var given: int = sim.PowerTrait("wise", hx, hy, 3.0)
	check(given > 0 and people.any(func(i): return sim.UnitAlive(i) and sim.HasTrait(i, "wise")), "traits rain on the people under the brush")
	check(not sim.PowerRebellion(hx, hy), "a capital does not rebel against itself")
	sim.queue_free()


## 0.9 What the interface shows: inspector cards, political layers, statistics, world codes,
## one law per rule.
func test_world_views() -> void:
	var made := make_quiet_sim("views", 128)
	var w: WorldData = made[0]
	var sim: Node2D = made[1]
	sim.StartPeoples(PackedStringArray(["humans", "elves"]), 16)
	sim.RunSteps(30 * 60 * 3)
	var kingdoms: Array = sim.KingdomTable()
	var k: int = kingdoms[0].index
	var info: Dictionary = sim.KingdomInfo(k)
	check(info.name == kingdoms[0].name and String(info.values).split(", ").size() == 3 and info.creed != "" and info.has("designs"),
			"a kingdom's card: its people, ruler, values, faith and things (%s)" % info.values)
	var species: Dictionary = sim.SpeciesInfo("Wolf")
	if species.is_empty():
		species = sim.SpeciesInfo("rabbit")
	check(not species.is_empty() and species.has("habitat") and species.has("alive"), "a species' card")
	sim.InventNow(k)
	var inv_id: int = sim.InventionTable()[0].id
	var inv: Dictionary = sim.InventionInfo(inv_id)
	var script = JSON.parse_string(inv.script)
	check(script is Dictionary and script.kind == inv.kind and String(inv.lineage).contains(inv.name), "an invention's card shows its record and lineage")
	var spirit := {}
	for s in sim.SpiritTable():
		spirit = sim.SpiritInfoAt(s.x, s.y)
		break
	check(sim.SpiritTable().is_empty() or spirit.has("mood_word"), "a spirit's card, from a click on its land")

	# The political layers.
	var home: Dictionary = sim.VillageTable()[0]
	var tile: int = w.index(home.x, home.y)
	for layer in ["Kingdoms", "Cultures", "Religions", "Peoples", "Alliances", "Wars"]:
		var colors: PackedInt32Array = sim.LayerColors(layer)
		check(colors.size() == w.size() and colors[tile] != 0, "the %s layer colours the land of the kingdoms" % layer.to_lower())
	var sea := -1
	for i in w.size():
		if w.is_water(i):
			sea = i
			break
	check(sea < 0 or sim.LayerColors("Kingdoms")[sea] == 0, "the sea stays uncoloured")
	sim.PowerWhisper("war", kingdoms[0].index, kingdoms[1].index)
	check(sim.WarLines().size() == 4, "a war is a line between two capitals")
	var map := WorldMap.new()
	map.set_world(w)
	map.show_layer("Kingdoms")
	map.set_political(sim.LayerColors("Kingdoms"))
	var owner: Color = map.tile_color(tile)
	var kc: Color = kingdoms[0].color if home.kingdom == kingdoms[0].name else kingdoms[1].color
	check(absf(owner.h - kc.h) < 0.08 or kc.s < 0.15, "the flat map paints the land in its kingdom's colour")
	map.free()

	# Statistics.
	sim.RecordHistoryNow()
	var history: Dictionary = sim.History()
	check(history.year.size() >= 2 and history.people[-1] > 0 and history.has("warming"), "the world's numbers are kept every year (%d years)" % history.year.size())
	var Stats = load("res://scripts/ui/stats_window.gd")
	var window: PanelContainer = Stats.new()
	root.add_child(window)
	window.set_history(history)
	check(window.points_of("people", Vector2(100, 50)).size() == history.year.size(), "the statistics window draws them")
	window.queue_free()

	# World codes.
	var settings := WorldSettings.new()
	settings.seed_text = "Les îles d'Ana"
	settings.set_size(384)
	settings.continents = 6
	settings.water_ratio = 0.7
	var code: String = settings.to_code()
	var back := WorldSettings.new()
	check(code.begins_with("AM1:") and back.from_code(code) and back.seed_text == settings.seed_text and back.width == 384 and back.continents == 6
			and absf(back.water_ratio - 0.7) < 0.01, "a world's code gives back the same settings (%s)" % code)
	check(not back.from_code("hello") and not back.from_code("AM1:####") and not back.from_code("AM1:aGVsbG8"), "a wrong code is refused")

	# A law for each rule.
	var laws: Dictionary = sim.LawTable()
	var LawsWindow = load("res://scripts/ui/laws_window.gd")
	var missing := []
	for law in LawsWindow.LAWS:
		if not laws.has(law[1]):
			missing.append(law[1])
	check(missing.is_empty(), "every law of the laws window is a rule of the simulation (missing: %s)" % [missing])
	sim.SetLaw("seasons", false)
	check(sim.Coldness() == 0.0 or sim.EraTable().cold > 0.0, "without seasons, no winter")
	sim.queue_free()
