## Builds a world from its settings, stage by stage (see docs/GAME_DESIGN.md § 2):
## shape -> climate -> hydrology -> biomes. Each stage only reads earlier stages and its own
## named random stream, so the same settings always give the same world.
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")
const SeededRng = preload("res://scripts/core/seeded_rng.gd")
const PriorityQueue = preload("res://scripts/core/priority_queue.gd")
const Biomes = preload("res://scripts/world/biomes.gd")

const NEIGHBOURS_4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func generate(settings) -> WorldData:
	var seed_value := SeededRng.seed_from_text(settings.seed_text)
	var rng := SeededRng.new(seed_value)
	var world := WorldData.new(settings.width, settings.height, seed_value)
	_timed(world, "shape", func(): _shape(world, settings, rng))
	_timed(world, "climate", func(): _climate(world, settings, rng))
	_timed(world, "hydrology", func(): _hydrology(world, settings))
	_timed(world, "biomes", func(): _biomes(world, settings, rng))
	return world


static func _timed(world: WorldData, stage: String, step: Callable) -> void:
	var start := Time.get_ticks_usec()
	step.call()
	world.stage_ms[stage] = (Time.get_ticks_usec() - start) / 1000.0


static func _noise(rng: SeededRng, name: String, frequency: float, octaves: int,
		fractal := FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = rng.sub_seed(name)
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


# ------------------------------------------------------------------------------ 1. shape

## Heightmap = continent blobs + fractal noise + ridged noise for mountain chains, sinking at the
## map edges. The sea level is then set so that `water_ratio` of the map ends up under water.
static func _shape(world: WorldData, s, rng: SeededRng) -> void:
	var w := world.width
	var h := world.height
	var shape_rng := rng.stream("shape")
	var base := _noise(rng, "shape:base", 3.0 / w, 5)
	var warp := _noise(rng, "shape:warp", 2.0 / w, 3)
	var fine_warp := _noise(rng, "shape:fine_warp", 9.0 / w, 3)
	var detail := _noise(rng, "shape:detail", 14.0 / w, 3)
	var ridges := _noise(rng, "shape:ridges", 3.5 / w, 4, FastNoiseLite.FRACTAL_RIDGED)

	# Continent centres, kept apart from each other so they don't merge into one blob.
	var centres: Array[Vector2] = []
	var spacing := 0.62 * minf(w, h) / sqrt(float(s.continents))
	for attempt in 500:
		if centres.size() >= s.continents:
			break
		var p := Vector2(shape_rng.randf_range(0.2, 0.8) * w, shape_rng.randf_range(0.2, 0.8) * h)
		var far_enough := true
		for c in centres:
			if p.distance_to(c) < spacing * (1.0 - attempt / 600.0):
				far_enough = false
				break
		if far_enough:
			centres.append(p)
	var radius := 0.33 * minf(w, h) / sqrt(float(s.continents))
	var edge_band := 0.1 * minf(w, h)

	var raw := PackedFloat32Array()
	raw.resize(w * h)
	for y in h:
		for x in w:
			# Warp the sampling point at two scales so coasts are ragged (bays, capes, fjords).
			var wx := x + warp.get_noise_2d(x, y) * 0.12 * w + fine_warp.get_noise_2d(x, y) * 0.05 * w
			var wy := y + warp.get_noise_2d(x + 999.0, y) * 0.12 * h + fine_warp.get_noise_2d(x, y + 999.0) * 0.05 * h
			var mask := -1.0
			for c in centres:
				var d := Vector2(wx, wy).distance_to(c) / radius
				mask = maxf(mask, 1.0 - d * d)
			var n := base.get_noise_2d(x, y)
			var r := ridges.get_noise_2d(x, y)
			var v := mask * 0.85 + n * 0.4 + maxf(r, 0.0) * 0.45 * clampf(mask + 0.4, 0.0, 1.0)
			# Small-scale detail: jagged shorelines, rocky points and offshore islets.
			v += detail.get_noise_2d(wx, wy) * 0.3
			var edge := clampf(minf(minf(x, w - 1 - x), minf(y, h - 1 - y)) / edge_band, 0.0, 1.0)
			raw[world.index(x, y)] = lerpf(-1.0, v, edge)

	# Sea level: the height under which `water_ratio` of the tiles lie.
	# Land height is then taken from each tile's rank among land tiles (squared, so most land is
	# low and mountains stay rare): the share of hills, mountains and peaks is the same on every map.
	var sorted := raw.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sea_index := clampi(int(s.water_ratio * (n - 1)), 1, n - 2)
	var lo := sorted[0]
	var sea := sorted[sea_index]
	world.sea_level = 0.5
	for i in raw.size():
		if raw[i] < sea:
			world.elevation[i] = 0.5 * (raw[i] - lo) / maxf(sea - lo, 0.00001)
			world.water[i] = WorldData.Water.OCEAN
		else:
			var rank := float(sorted.bsearch(raw[i]) - sea_index) / float(n - 1 - sea_index)
			rank = clampf(rank, 0.0, 1.0)
			world.elevation[i] = 0.5 + 0.5 * rank * rank
			world.water[i] = WorldData.Water.LAND
	_fill_inland_seas(world)


## Water below sea level that is not connected to the open ocean becomes land again for now;
## the hydrology stage turns real basins into lakes.
static func _fill_inland_seas(world: WorldData) -> void:
	var w := world.width
	var h := world.height
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	for x in w:
		for y in [0, h - 1]:
			var i := world.index(x, y)
			if world.water[i] == WorldData.Water.OCEAN and seen[i] == 0:
				seen[i] = 1
				stack.append(i)
	for y in h:
		for x in [0, w - 1]:
			var i := world.index(x, y)
			if world.water[i] == WorldData.Water.OCEAN and seen[i] == 0:
				seen[i] = 1
				stack.append(i)
	while stack.size() > 0:
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x := i % w
		var y := i / w
		for d in NEIGHBOURS_4:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if world.in_bounds(nx, ny):
				var j := world.index(nx, ny)
				if seen[j] == 0 and world.water[j] == WorldData.Water.OCEAN:
					seen[j] = 1
					stack.append(j)
	for i in world.size():
		if world.water[i] == WorldData.Water.OCEAN and seen[i] == 0:
			world.water[i] = WorldData.Water.LAND
			world.elevation[i] = world.sea_level + 0.0001


# ------------------------------------------------------------------------------ 2. climate

## Temperature from latitude and altitude. Humidity carried by prevailing winds from the sea:
## it rains on slopes facing the wind and dries out behind mountains (rain shadow).
static func _climate(world: WorldData, s, rng: SeededRng) -> void:
	var w := world.width
	var h := world.height
	var t_noise := _noise(rng, "climate:temperature", 4.0 / w, 3)
	var h_noise := _noise(rng, "climate:humidity", 5.0 / w, 3)
	var coast := _distance_to_ocean(world)
	var coast_range := 0.08 * w

	for y in h:
		var lat := absf((y + 0.5) / h - 0.5) * 2.0  # 0 at the equator, 1 at the poles
		for x in w:
			var i := world.index(x, y)
			var t := 1.0 - lat - maxf(world.land_height(i), 0.0) * 0.5
			t += t_noise.get_noise_2d(x, y) * 0.12 + s.temperature_offset
			world.temperature[i] = clampf(t, 0.0, 1.0)

	# Moisture carried by the wind in both directions; each latitude blends them by its prevailing
	# wind (trade winds and polar easterlies blow west, mid-latitude westerlies blow east).
	var from_west := _wind_moisture(world, true)
	var from_east := _wind_moisture(world, false)
	for y in h:
		var lat := absf((y + 0.5) / h - 0.5) * 2.0
		var westerly := smoothstep(0.22, 0.42, lat) * (1.0 - smoothstep(0.58, 0.78, lat))
		for x in w:
			var i := world.index(x, y)
			if world.water[i] == WorldData.Water.OCEAN:
				world.humidity[i] = 1.0
				continue
			var wind := lerpf(from_east[i], from_west[i], westerly)
			var near_sea := 1.0 - clampf(coast[i] / coast_range, 0.0, 1.0)
			var hum := 0.15 + wind * 0.5 + near_sea * 0.15 + _latitude_rain(lat)
			hum += h_noise.get_noise_2d(x, y) * 0.2 + s.humidity_offset
			world.humidity[i] = clampf(hum, 0.0, 1.0)


## Moisture of air blowing across each row (west to east when `eastward`): it picks up water over
## the sea, slowly dries over land, rains out on rising slopes (wetter there) and leaves a dry
## rain shadow behind mountains.
static func _wind_moisture(world: WorldData, eastward: bool) -> PackedFloat32Array:
	var w := world.width
	var out := PackedFloat32Array()
	out.resize(world.size())
	for y in world.height:
		var moisture := 0.6
		var previous := 0.0
		for k in w:
			var x := k if eastward else w - 1 - k
			var i := world.index(x, y)
			if world.water[i] == WorldData.Water.OCEAN:
				moisture = minf(1.0, moisture + 0.1)
				previous = 0.0
				out[i] = 1.0
				continue
			var e := world.land_height(i)
			var rise := maxf(e - previous, 0.0)
			previous = e
			out[i] = clampf(moisture + minf(rise * 3.0, 0.25), 0.0, 1.0)
			moisture = maxf(0.0, moisture * 0.995 - rise * 0.9)
	return out


## Rain from the global air circulation: wet equator, dry subtropics (where the great deserts
## are), wet mid-latitudes, dry poles.
static func _latitude_rain(lat: float) -> float:
	return 0.3 * cos(lat * PI * 3.0)


## Breadth-first distance (in tiles) from every tile to the nearest ocean tile.
static func _distance_to_ocean(world: WorldData) -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(world.size())
	dist.fill(INF)
	var queue := PackedInt32Array()
	for i in world.size():
		if world.water[i] == WorldData.Water.OCEAN:
			dist[i] = 0.0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % world.width
		var y := i / world.width
		for d in NEIGHBOURS_4:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if world.in_bounds(nx, ny):
				var j := world.index(nx, ny)
				if dist[j] == INF:
					dist[j] = dist[i] + 1.0
					queue.append(j)
	return dist


# ------------------------------------------------------------------------------ 3. hydrology

## Priority-flood from the ocean: every land tile gets a downstream tile that leads to the sea,
## basins fill up into lakes, and rain collected along the way (flow) carves rivers.
static func _hydrology(world: WorldData, s) -> void:
	var w := world.width
	var n := world.size()
	var filled := world.elevation.duplicate()
	var visited := PackedByteArray()
	visited.resize(n)
	var order := PackedInt32Array()  # land tiles from lowest to highest filled height
	var queue := PriorityQueue.new()

	for i in n:
		var x := i % w
		var y := i / w
		var border := x == 0 or y == 0 or x == w - 1 or y == world.height - 1
		if world.water[i] == WorldData.Water.OCEAN or border:
			visited[i] = 1
			queue.push(world.elevation[i], i)

	while queue.size() > 0:
		var c := queue.pop()
		if world.water[c] != WorldData.Water.OCEAN:
			order.append(c)
		var x := c % w
		var y := c / w
		for d in NEIGHBOURS_4:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if not world.in_bounds(nx, ny):
				continue
			var j := world.index(nx, ny)
			if visited[j] == 1:
				continue
			visited[j] = 1
			filled[j] = maxf(world.elevation[j], filled[c] + 0.000001)
			world.downstream[j] = c
			queue.push(filled[j], j)

	# Lakes: tiles the flood had to raise noticeably above their real height. Tiny ponds are dropped.
	var lake_depth := 0.006
	for i in order:
		if filled[i] - world.elevation[i] > lake_depth:
			world.water[i] = WorldData.Water.LAKE
	_remove_small_lakes(world, 6)

	# Flow accumulation from the highest tiles down to the sea.
	for i in n:
		world.flow[i] = 0.0 if world.water[i] == WorldData.Water.OCEAN else 0.25 + world.humidity[i]
	for k in range(order.size() - 1, -1, -1):
		var i := order[k]
		var down := world.downstream[i]
		if down >= 0:
			world.flow[down] += world.flow[i]

	# Rivers: land tiles that collect more than a threshold; more `rivers` = lower threshold.
	var threshold := lerpf(0.006, 0.0012, clampf(s.rivers, 0.0, 1.0)) * n
	for i in order:
		if world.water[i] == WorldData.Water.LAND and world.flow[i] > threshold:
			world.water[i] = WorldData.Water.RIVER

	# Fresh water makes the land around it greener.
	var wet := world.humidity.duplicate()
	for i in order:
		if world.water[i] == WorldData.Water.RIVER or world.water[i] == WorldData.Water.LAKE:
			var x := i % w
			var y := i / w
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if world.in_bounds(x + dx, y + dy):
						var j := world.index(x + dx, y + dy)
						wet[j] = minf(1.0, maxf(wet[j], world.humidity[j] + 0.12))
	world.humidity = wet


## Lakes smaller than `min_tiles` turn back into land (rivers still flow through them).
static func _remove_small_lakes(world: WorldData, min_tiles: int) -> void:
	var seen := PackedByteArray()
	seen.resize(world.size())
	for start in world.size():
		if world.water[start] != WorldData.Water.LAKE or seen[start] == 1:
			continue
		var component := PackedInt32Array([start])
		seen[start] = 1
		var head := 0
		while head < component.size():
			var i := component[head]
			head += 1
			var x := i % world.width
			var y := i / world.width
			for d in NEIGHBOURS_4:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if world.in_bounds(nx, ny):
					var j := world.index(nx, ny)
					if seen[j] == 0 and world.water[j] == WorldData.Water.LAKE:
						seen[j] = 1
						component.append(j)
		if component.size() < min_tiles:
			for i in component:
				world.water[i] = WorldData.Water.LAND


# ------------------------------------------------------------------------------ 4. biomes

static func _biomes(world: WorldData, s, rng: SeededRng) -> void:
	var w := world.width
	var h := world.height
	var meadow_noise := _noise(rng, "biomes:meadow", 10.0 / w, 2)
	var magic_noise := _noise(rng, "biomes:magic", 7.0 / w, 3)
	var curse_noise := _noise(rng, "biomes:curse", 6.0 / w, 3)
	var magic := clampf(s.magic, 0.0, 1.0)
	var mushroom_cut := lerpf(0.65, 0.05, magic)  # noise above this turns forests into mushroom land
	var curse_cut := lerpf(0.7, 0.3, magic)

	for y in h:
		for x in w:
			var i := world.index(x, y)
			var t := world.temperature[i]
			var b: int
			match world.water[i]:
				WorldData.Water.OCEAN:
					b = Biomes.DEEP_WATER if world.sea_depth(i) > Biomes.DEEP_WATER_DEPTH else Biomes.WATER
					if t < Biomes.ICE_TEMPERATURE:
						b = Biomes.ICE
				WorldData.Water.LAKE, WorldData.Water.RIVER:
					b = Biomes.ICE if t < Biomes.ICE_TEMPERATURE else Biomes.WATER
				_:
					b = _land_biome(world, i, x, y)
					if b == Biomes.GRASSLAND and world.humidity[i] > 0.35 and meadow_noise.get_noise_2d(x, y) > 0.35:
						b = Biomes.MEADOW
					if (b == Biomes.FOREST or b == Biomes.JUNGLE or b == Biomes.SWAMP) \
							and magic_noise.get_noise_2d(x, y) > mushroom_cut:
						b = Biomes.MUSHROOM
					elif not Biomes.is_water_biome(b) and b != Biomes.PEAK \
							and curse_noise.get_noise_2d(x, y) > curse_cut:
						b = Biomes.CURSED
			world.biome[i] = b
	_place_volcanoes(world, s, rng)


static func _land_biome(world: WorldData, i: int, x: int, y: int) -> int:
	var e := world.land_height(i)
	var t := world.temperature[i]
	if e > Biomes.PEAK_HEIGHT:
		return Biomes.PEAK
	if e > Biomes.MOUNTAIN_HEIGHT:
		return Biomes.MOUNTAIN if t > 0.12 else Biomes.PEAK
	if e < Biomes.BEACH_HEIGHT and t > 0.25 and _touches_ocean(world, x, y):
		return Biomes.BEACH
	var b := Biomes.classify_climate(t, world.humidity[i], e < 0.12)
	if e > Biomes.HILLS_HEIGHT and (b == Biomes.GRASSLAND or b == Biomes.FOREST or b == Biomes.SAVANNA):
		return Biomes.HILLS
	return b


static func _touches_ocean(world: WorldData, x: int, y: int) -> bool:
	for d in NEIGHBOURS_4:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if world.in_bounds(nx, ny) and world.water[world.index(nx, ny)] == WorldData.Water.OCEAN:
			return true
	return false


## Volcanoes rise on high ground, away from each other: lava at the crater, volcanic rock around.
static func _place_volcanoes(world: WorldData, s, rng: SeededRng) -> void:
	var v_rng := rng.stream("volcanoes")
	var candidates := PackedInt32Array()
	for i in world.size():
		if world.water[i] == WorldData.Water.LAND and world.land_height(i) > 0.3:
			candidates.append(i)
	var min_spacing := 0.15 * world.width
	var placed := PackedInt32Array()
	var tries := 0
	while placed.size() < s.volcanoes and candidates.size() > 0 and tries < 200:
		tries += 1
		var c := candidates[v_rng.randi_range(0, candidates.size() - 1)]
		var cx := c % world.width
		var cy := c / world.width
		var ok := true
		for p in placed:
			if Vector2(cx, cy).distance_to(Vector2(p % world.width, p / world.width)) < min_spacing:
				ok = false
				break
		if not ok:
			continue
		placed.append(c)
		var radius := v_rng.randi_range(3, 5)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var x := cx + dx
				var y := cy + dy
				if not world.in_bounds(x, y):
					continue
				var j := world.index(x, y)
				if world.is_water(j):
					continue
				var d := sqrt(dx * dx + dy * dy)
				if d <= 1.0:
					world.biome[j] = Biomes.LAVA
				elif d <= radius - v_rng.randf() * 1.5:
					world.biome[j] = Biomes.VOLCANIC
	world.volcanoes = placed
