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
	_timed(world, "levels", func(): _levels(world))
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

## Tectonic plates (docs/MAP_GENERATION.md): the map is split into plates with irregular
## (domain-warped) borders, a few clusters of plates are continental and the rest oceanic, and
## every plate drifts. Where plates collide, mountain chains rise along the border (high between two
## continents, on the coast where an ocean plate dives under a continent, island arcs between two
## ocean plates); where they pull apart, rifts sink. The continent shape is then blurred and
## roughened with warped fractal noise so coasts get bays, capes and islands, and mountains get
## ridged crests. The sea level is set so that `water_ratio` of the map ends up under water.
##
## Plates are worked out on a coarse grid (about 128 cells across) and sampled smoothly, which keeps
## large maps fast.
static func _shape(world: WorldData, s, rng: SeededRng) -> void:
	var w := world.width
	var h := world.height
	var plates := _plates(world, s, rng)
	var cw: int = plates.cw
	var ch: int = plates.ch
	var cell: float = plates.cell
	var land: PackedFloat32Array = plates.land
	var uplift: PackedFloat32Array = plates.uplift

	var warp := _noise(rng, "shape:warp", 2.5 / w, 3)
	var coast := _noise(rng, "shape:coast", 4.0 / w, 5)
	var detail := _noise(rng, "shape:detail", 16.0 / w, 3)
	var ridges := _noise(rng, "shape:ridges", 6.0 / w, 4, FastNoiseLite.FRACTAL_RIDGED)
	var edge_band := 0.12 * minf(w, h)

	var raw := PackedFloat32Array()
	raw.resize(w * h)
	for y in h:
		for x in w:
			# Warp the sampling point so plate shapes turn into organic coastlines.
			var wx := x + warp.get_noise_2d(x, y) * 0.09 * w
			var wy := y + warp.get_noise_2d(x + 731.0, y - 211.0) * 0.09 * h
			var cx := clampf(wx / cell - 0.5, 0.0, cw - 1.001)
			var cy := clampf(wy / cell - 0.5, 0.0, ch - 1.001)
			var c := _bilinear(land, cw, cx, cy)
			var u := _bilinear(uplift, cw, cx, cy)
			var v := (c - 0.5) * 1.4 + coast.get_noise_2d(wx, wy) * 0.5
			# Mountains: chains along colliding borders, with ridged crests and valleys.
			var r := ridges.get_noise_2d(wx, wy) * 0.5 + 0.5
			v += maxf(u, 0.0) * (0.5 + 0.9 * r) + minf(u, 0.0)
			v += detail.get_noise_2d(wx, wy) * 0.1
			# Ocean towards the map edge, measured from the warped point so the outer coasts are
			# as ragged as the others (no straight coast along the edge).
			var to_edge := minf(minf(wx, w - 1 - wx), minf(wy, h - 1 - wy))
			var edge := clampf(to_edge / edge_band, 0.0, 1.0)
			raw[world.index(x, y)] = lerpf(-1.2, v, smoothstep(0.0, 1.0, edge))

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


## The plates on a coarse grid: {cw, ch, cell (tiles per cell), land (0 ocean .. 1 continent,
## blurred), uplift (mountains > 0, rifts and trenches < 0)}.
static func _plates(world: WorldData, s, rng: SeededRng) -> Dictionary:
	var w := world.width
	var h := world.height
	var cell := maxf(1.0, w / 128.0)
	var cw := ceili(w / cell)
	var ch := ceili(h / cell)
	var prng := rng.stream("plates")
	var count: int = clampi(7 + s.continents * 3, 8, 26)

	# Plate centres, spread out (best of a few random candidates each time).
	var seeds: Array[Vector2] = []
	for k in count:
		var best := Vector2.ZERO
		var best_d := -1.0
		for t in 12:
			var p := Vector2(prng.randf() * cw, prng.randf() * ch)
			var d := INF
			for q in seeds:
				d = minf(d, p.distance_squared_to(q))
			if d > best_d:
				best_d = d
				best = p
		seeds.append(best)
	var velocity: Array[Vector2] = []
	for k in count:
		velocity.append(Vector2.from_angle(prng.randf() * TAU) * prng.randf_range(0.3, 1.0))

	# Plate of every cell: nearest centre from a warped position (irregular borders).
	var warp := _noise(rng, "plates:warp", 3.0 / cw, 3)
	var plate := PackedInt32Array()
	plate.resize(cw * ch)
	var area := PackedInt32Array()
	area.resize(count)
	for y in ch:
		for x in cw:
			var p := Vector2(x + warp.get_noise_2d(x, y) * 0.12 * cw, y + warp.get_noise_2d(x + 500.0, y) * 0.12 * ch)
			var best := 0
			var best_d := INF
			for k in count:
				var d := p.distance_squared_to(seeds[k])
				if d < best_d:
					best_d = d
					best = k
			plate[y * cw + x] = best
			area[best] += 1

	# Which plates touch which.
	var touching := []
	for k in count:
		touching.append({})
	for y in ch:
		for x in cw:
			var a := plate[y * cw + x]
			if x + 1 < cw and plate[y * cw + x + 1] != a:
				touching[a][plate[y * cw + x + 1]] = true
				touching[plate[y * cw + x + 1]][a] = true
			if y + 1 < ch and plate[(y + 1) * cw + x] != a:
				touching[a][plate[(y + 1) * cw + x]] = true
				touching[plate[(y + 1) * cw + x]][a] = true

	# Continents: `continents` clusters of plates, started far apart (away from the map edge) and
	# grown one neighbouring plate at a time until they cover a bit more than the land share
	# (coasts are cut back by noise and the sea level afterwards).
	var cluster := PackedInt32Array()
	cluster.resize(count)
	cluster.fill(-1)
	var cores: Array[int] = []
	var middle := Vector2(cw, ch) / 2.0
	for c in s.continents:
		var best := -1
		var best_score := -INF
		for k in count:
			if cluster[k] >= 0:
				continue
			var d := INF
			for core in cores:
				d = minf(d, seeds[k].distance_to(seeds[core]))
			var score := minf(d, cw) - seeds[k].distance_to(middle) * 0.6 + prng.randf() * cw * 0.1
			if score > best_score:
				best_score = score
				best = k
		if best < 0:
			break
		cores.append(best)
		cluster[best] = c
	var target: float = (1.0 - s.water_ratio) * 1.15 * cw * ch
	var land_area := 0.0
	for core in cores:
		land_area += area[core]
	var stuck := 0
	while land_area < target and stuck < cores.size():
		stuck = 0
		for c in cores.size():
			# Grow the cluster by a plate that touches it and no other continent.
			var options: Array[int] = []
			for k in count:
				if cluster[k] >= 0:
					continue
				var mine := false
				var other := false
				for j in touching[k]:
					if cluster[j] == c:
						mine = true
					elif cluster[j] >= 0:
						other = true
				if mine and not other:
					options.append(k)
			if options.is_empty():
				stuck += 1
				continue
			# Prefer plates towards the middle of the map.
			var k := options[0]
			var best_k := INF
			for o in options:
				var score := seeds[o].distance_to(middle) + prng.randf() * cw * 0.25
				if score < best_k:
					best_k = score
					k = o
			cluster[k] = c
			land_area += area[k]
			if land_area >= target:
				break

	# Plate borders: how fast the two plates close in (> 0 collide, < 0 pull apart).
	var land := PackedFloat32Array()
	land.resize(cw * ch)
	var conv := PackedFloat32Array()
	conv.resize(cw * ch)
	var kind := PackedByteArray()  # 0 ocean-ocean, 1 ocean side of ocean-continent, 2 continent side, 3 continent-continent
	kind.resize(cw * ch)
	var dist := PackedFloat32Array()
	dist.resize(cw * ch)
	dist.fill(INF)
	var queue := PackedInt32Array()
	for y in ch:
		for x in cw:
			var i := y * cw + x
			var a := plate[i]
			land[i] = 1.0 if cluster[a] >= 0 else 0.0
			for d in NEIGHBOURS_4:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
					continue
				var b := plate[ny * cw + nx]
				if b == a:
					continue
				var axis := (seeds[b] - seeds[a]).normalized()
				conv[i] = (velocity[a] - velocity[b]).dot(axis)
				var a_land := cluster[a] >= 0
				var b_land := cluster[b] >= 0
				kind[i] = 3 if a_land and b_land else (2 if a_land and not b_land else (1 if b_land else 0))
				dist[i] = 0.0
				queue.append(i)
				break
	# Spread the nearest border's values inland (breadth first).
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % cw
		var y := i / cw
		for d in NEIGHBOURS_4:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
				continue
			var j := ny * cw + nx
			if dist[j] == INF and plate[j] == plate[i]:
				dist[j] = dist[i] + 1.0
				conv[j] = conv[i]
				kind[j] = kind[i]
				queue.append(j)

	# Uplift from the border type and distance (in cells; a cell is `cell` tiles).
	var uplift := PackedFloat32Array()
	uplift.resize(cw * ch)
	var width := 0.045 * cw
	for i in cw * ch:
		var d := dist[i] / width
		var c := conv[i]
		var u := 0.0
		if c > 0.0:
			match kind[i]:
				3:  # two continents collide: the highest ranges, wide
					u = c * 1.1 * exp(-d * d * 0.35)
				2:  # an ocean plate dives under this continent: a coastal range a little inland
					u = c * 0.9 * exp(-(d - 1.2) * (d - 1.2) * 0.6)
				1:  # ocean side of that: a trench
					u = -c * 0.3 * exp(-d * d)
				0:  # two ocean plates: an arc of volcanic islands
					u = c * 0.75 * exp(-(d - 0.6) * (d - 0.6) * 1.5)
		else:
			# Plates pull apart: a rift valley on land, a mid-ocean ridge (still under water) at sea.
			u = c * 0.15 * exp(-d * d) if kind[i] >= 2 else -c * 0.1 * exp(-d * d)
		uplift[i] = u

	# Continents keep away from the map edge: the world is surrounded by ocean.
	var margin := 0.16 * minf(cw, ch)
	for y in ch:
		for x in cw:
			var e := minf(minf(x, cw - 1 - x), minf(y, ch - 1 - y)) / margin
			land[y * cw + x] *= smoothstep(0.0, 1.0, clampf(e, 0.0, 1.0))
	# Soften continent borders so coasts don't follow straight plate borders.
	for _pass in 3:
		land = _box_blur(land, cw, ch, maxi(1, roundi(0.02 * cw)))
	return {"cw": cw, "ch": ch, "cell": cell, "land": land, "uplift": uplift}


static func _bilinear(field: PackedFloat32Array, cw: int, x: float, y: float) -> float:
	var x0 := int(x)
	var y0 := int(y)
	var fx := x - x0
	var fy := y - y0
	var i := y0 * cw + x0
	var top := lerpf(field[i], field[i + 1], fx)
	var bottom := lerpf(field[i + cw], field[i + cw + 1], fx)
	return lerpf(top, bottom, fy)


static func _box_blur(field: PackedFloat32Array, cw: int, ch: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(field.size())
	var out := PackedFloat32Array()
	out.resize(field.size())
	for y in ch:
		for x in cw:
			var sum := 0.0
			for k in range(-r, r + 1):
				sum += field[y * cw + clampi(x + k, 0, cw - 1)]
			tmp[y * cw + x] = sum / (2 * r + 1)
	for y in ch:
		for x in cw:
			var sum := 0.0
			for k in range(-r, r + 1):
				sum += tmp[clampi(y + k, 0, ch - 1) * cw + x]
			out[y * cw + x] = sum / (2 * r + 1)
	return out


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
			# Cold only near the poles: temperature falls slowly at first, then fast.
			var t := 1.0 - pow(lat, 1.6) * 1.05 - maxf(world.land_height(i), 0.0) * 0.5
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
	var lake_depth := 0.012
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


# ------------------------------------------------------------------------------ 4. levels

## Terraced terrain with five levels: deep sea, shallow water (coasts, rivers, lakes), plain,
## hill, mountain.
##  1. Quantise: sea tiles by depth, land tiles by height band.
##  2. Smooth with a cellular automaton: each land tile takes the majority level of its 3x3
##     neighbourhood (removes lone bumps and pits, gives clean plateaus).
##  3. Stair constraint: neighbours differ by at most one level. Land is lowered towards lower
##     neighbours (mountains get a ring of hills, coasts and river banks are plains), and deep sea
##     next to land becomes shallow. Water tiles (sea, rivers, lakes) keep their water level.
static func _levels(world: WorldData) -> void:
	var w := world.width
	var h := world.height
	var L := WorldData.Level
	for i in world.size():
		match world.water[i]:
			WorldData.Water.OCEAN:
				world.level[i] = L.DEEP_SEA if world.sea_depth(i) > Biomes.DEEP_WATER_DEPTH else L.SHALLOW
			WorldData.Water.LAKE, WorldData.Water.RIVER:
				world.level[i] = L.SHALLOW
			_:
				var e := world.land_height(i)
				world.level[i] = L.MOUNTAIN if e > Biomes.MOUNTAIN_HEIGHT else (L.HILL if e > Biomes.HILLS_HEIGHT else L.PLAIN)

	for _pass in 2:
		var next := world.level.duplicate()
		for y in h:
			for x in w:
				var i := world.index(x, y)
				if world.is_water(i) or not _on_border(world.level, w, h, x, y):
					continue
				var votes := [0, 0, 0, 0, 0]
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if world.in_bounds(x + dx, y + dy):
							var j := world.index(x + dx, y + dy)
							if not world.is_water(j):
								votes[world.level[j]] += 1
				var best: int = world.level[i]
				for lv in range(L.PLAIN, L.MOUNTAIN + 1):
					if votes[lv] > votes[best]:
						best = lv
				next[i] = best
		world.level = next

	# Stair constraint as a distance transform: a land tile is at most one level above its lowest
	# neighbour, i.e. level <= neighbour + 1 everywhere. Two sweeps (down-right, then up-left) give
	# the exact result for 4-neighbours; land never goes under the plain level, and deep sea next
	# to anything higher than shallow water becomes shallow.
	var cap := PackedInt32Array()
	cap.resize(world.size())
	for i in world.size():
		cap[i] = world.level[i]
	for y in h:
		for x in w:
			var i := world.index(x, y)
			if world.is_water(i):
				continue
			if x > 0:
				cap[i] = mini(cap[i], cap[i - 1] + 1)
			if y > 0:
				cap[i] = mini(cap[i], cap[i - w] + 1)
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := world.index(x, y)
			if world.is_water(i):
				continue
			if x < w - 1:
				cap[i] = mini(cap[i], cap[i + 1] + 1)
			if y < h - 1:
				cap[i] = mini(cap[i], cap[i + w] + 1)
	for i in world.size():
		if not world.is_water(i):
			world.level[i] = maxi(cap[i], L.PLAIN)
	for y in h:
		for x in w:
			var i := world.index(x, y)
			if world.water[i] != WorldData.Water.OCEAN or world.level[i] != L.DEEP_SEA:
				continue
			for d in NEIGHBOURS_4:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if world.in_bounds(nx, ny) and world.level[world.index(nx, ny)] > L.SHALLOW:
					world.level[i] = L.SHALLOW
					break


# ------------------------------------------------------------------------------ 5. biomes

## Natural biomes only, from climate and height (Whittaker-style). Special biomes (mushroom land,
## cursed land, volcanoes and lava) are never placed at random: the player puts them on the map
## with the god tools. Small patches are then merged into their surroundings, so biomes form
## large, natural regions instead of a speckle.
static func _biomes(world: WorldData, s, rng: SeededRng) -> void:
	var w := world.width
	var h := world.height
	var meadow_noise := _noise(rng, "biomes:meadow", 6.0 / w, 2)

	for y in h:
		for x in w:
			var i := world.index(x, y)
			var t := world.temperature[i]
			var b: int
			match world.water[i]:
				WorldData.Water.OCEAN:
					b = Biomes.DEEP_WATER if world.level[i] == WorldData.Level.DEEP_SEA else Biomes.WATER
					if t < Biomes.ICE_TEMPERATURE:
						b = Biomes.ICE
				WorldData.Water.LAKE, WorldData.Water.RIVER:
					b = Biomes.ICE if t < Biomes.ICE_TEMPERATURE else Biomes.WATER
				_:
					b = _land_biome(world, i, x, y)
					if b == Biomes.GRASSLAND and world.humidity[i] > 0.35 and meadow_noise.get_noise_2d(x, y) > 0.3:
						b = Biomes.MEADOW
			world.biome[i] = b
	_smooth_biomes(world)
	_merge_small_regions(world, maxi(8, w * h / 4000))


## Whether any of the 8 neighbours of (x, y) holds a different value (majority filters only
## change tiles on a border, so the others are skipped).
static func _on_border(values: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	var v := values[y * w + x]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < w and ny < h and values[ny * w + nx] != v:
				return true
	return false


## Climate biomes that may change in smoothing: not water, beaches, mountains or peaks, which
## follow the terrain exactly.
static func _soft_biome(b: int) -> bool:
	return not (Biomes.is_water_biome(b) or b == Biomes.BEACH or b == Biomes.MOUNTAIN or b == Biomes.PEAK)


## Three passes of a majority filter: a soft-biome tile takes the biome most common around it (3x3).
static func _smooth_biomes(world: WorldData) -> void:
	var w := world.width
	var h := world.height
	for _pass in 3:
		var next := world.biome.duplicate()
		var votes := PackedInt32Array()
		votes.resize(Biomes.COUNT)
		for y in h:
			for x in w:
				var i := world.index(x, y)
				if not _soft_biome(world.biome[i]) or not _on_border(world.biome, w, h, x, y):
					continue
				votes.fill(0)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if world.in_bounds(x + dx, y + dy):
							var b := world.biome[world.index(x + dx, y + dy)]
							if _soft_biome(b):
								votes[b] += 1
				var best := world.biome[i]
				for b in Biomes.COUNT:
					if votes[b] > votes[best]:
						best = b
				# Keep the level rule: hills stay on the hill level, others off it.
				if (best == Biomes.HILLS) == (world.level[i] == WorldData.Level.HILL):
					next[i] = best
		world.biome = next


## Regions of one soft biome smaller than `min_tiles` take the biome they touch most.
static func _merge_small_regions(world: WorldData, min_tiles: int) -> void:
	var seen := PackedByteArray()
	seen.resize(world.size())
	for start in world.size():
		var b := world.biome[start]
		if seen[start] == 1 or not _soft_biome(b):
			continue
		var region := PackedInt32Array([start])
		seen[start] = 1
		var around := {}
		var head := 0
		while head < region.size():
			var i := region[head]
			head += 1
			var x := i % world.width
			var y := i / world.width
			for d in NEIGHBOURS_4:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if not world.in_bounds(nx, ny):
					continue
				var j := world.index(nx, ny)
				var bj := world.biome[j]
				if bj == b:
					if seen[j] == 0:
						seen[j] = 1
						region.append(j)
				elif _soft_biome(bj):
					around[bj] = around.get(bj, 0) + 1
		if region.size() >= min_tiles or around.is_empty():
			continue
		var best := -1
		for bj in around:
			if best < 0 or around[bj] > around[best]:
				best = bj
		for i in region:
			# Hills only where the ground is on the hill level.
			if (best == Biomes.HILLS) == (world.level[i] == WorldData.Level.HILL):
				world.biome[i] = best


static func _land_biome(world: WorldData, i: int, x: int, y: int) -> int:
	var e := world.land_height(i)
	var t := world.temperature[i]
	var lv := world.level[i]
	if lv == WorldData.Level.MOUNTAIN:
		return Biomes.PEAK if e > Biomes.PEAK_HEIGHT or t <= 0.12 else Biomes.MOUNTAIN
	if lv == WorldData.Level.PLAIN and t > 0.25 and _touches_ocean(world, x, y):
		return Biomes.BEACH
	var b := Biomes.classify_climate(t, world.humidity[i], e < 0.12)
	if lv == WorldData.Level.HILL and (b == Biomes.GRASSLAND or b == Biomes.FOREST or b == Biomes.SAVANNA):
		return Biomes.HILLS
	return b


static func _touches_ocean(world: WorldData, x: int, y: int) -> bool:
	for d in NEIGHBOURS_4:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if world.in_bounds(nx, ny) and world.water[world.index(nx, ny)] == WorldData.Water.OCEAN:
			return true
	return false
