## Headless tests for the tilt view's terrain mesh (scripts/render_tilt/tilt_terrain.gd).
##   godot --headless --path . --script res://tests/test_tilt.gd
## Exits with the number of failed checks (0 = all passed).
extends SceneTree

const WorldData = preload("res://scripts/world/world_data.gd")
const TiltTerrain = preload("res://scripts/render_tilt/tilt_terrain.gd")

var _failures := 0


func _initialize() -> void:
	test_heights()
	test_areas()
	print("%d failed" % _failures)
	quit(_failures)


func check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


## A 70x40 world (not a multiple of the chunk size) with every level, a lake and a river.
func _world() -> WorldData:
	var w := WorldData.new(70, 40, 1)
	for y in w.height:
		for x in w.width:
			var i := w.index(x, y)
			w.level[i] = (x / 9 + y / 7) % 5
			w.water[i] = WorldData.Water.OCEAN if w.level[i] < WorldData.Level.PLAIN else WorldData.Water.LAND
			if w.level[i] >= WorldData.Level.PLAIN and (x * 7 + y * 3) % 11 == 0:
				w.water[i] = WorldData.Water.LAKE
	return w


func test_heights() -> void:
	var w := WorldData.new(5, 1, 1)
	for x in 5:
		w.level[x] = x
	w.water[0] = WorldData.Water.OCEAN
	w.water[1] = WorldData.Water.OCEAN
	var h := TiltTerrain.heights(w)
	check(is_equal_approx(h[0], -0.35) and is_equal_approx(h[1], -0.35), "sea tiles sit at -0.35")
	check(is_equal_approx(h[2], 0.0), "plain at 0")
	check(is_equal_approx(h[3], 0.75), "hill at 0.75")
	check(is_equal_approx(h[4], 1.5), "mountain at 1.5")
	w.water[3] = WorldData.Water.RIVER
	check(is_equal_approx(TiltTerrain.heights(w)[3], 0.6), "water on a hill sits 0.15 lower")


func test_areas() -> void:
	var w := _world()
	var h := TiltTerrain.heights(w)
	var top := 0.0
	var wall := 0.0
	var chunks := 0
	for cy in range(0, w.height, TiltTerrain.CHUNK):
		for cx in range(0, w.width, TiltTerrain.CHUNK):
			chunks += 1
			var arrays := TiltTerrain.chunk_arrays(h, w.width, w.height, cx, cy)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for k in range(0, idx.size(), 3):
				var a := v[idx[k]]
				var area := 0.5 * (v[idx[k + 1]] - a).cross(v[idx[k + 2]] - a).length()
				if n[idx[k]].y > 0.5:
					top += area
				else:
					wall += area
			for p in v:
				if p.x < 0.0 or p.z < 0.0 or p.x > w.width or p.z > w.height:
					check(false, "vertex outside the map: %s" % p)
					return
	check(chunks == 6, "70x40 makes 6 chunks of 32")
	check(is_equal_approx(top, float(w.width * w.height)), "tops cover the map once: %f" % top)
	# Every drop between neighbours (the border counts as sea) has a wall of that height.
	var expected := 0.0
	for y in w.height:
		for x in w.width:
			var here := h[y * w.width + x]
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				var there := TiltTerrain.SEA if nx < 0 or ny < 0 or nx >= w.width or ny >= w.height else h[ny * w.width + nx]
				expected += maxf(0.0, here - there)
	check(absf(wall - expected) < 0.01, "walls match the drops: %f against %f" % [wall, expected])
	check(TiltTerrain.build(w).size() == 6, "build returns one mesh per chunk")
