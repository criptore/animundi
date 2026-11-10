## The stepped ground of the tilt view: every tile is flat at the height of its level, with a
## vertical cliff face wherever a neighbour sits lower. Built in chunks of CHUNK tiles so chunks
## out of view are culled; runs of tiles at the same height share one quad (a sea is a few quads).
## Colours and patterns are not in the mesh: shaders/tilt_terrain.gdshader reads them from the
## map's textures by world position, so the mesh only changes when a tile changes level.
##
## World space: x = tile x, z = tile y (north is -z), y = height in tiles.
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")

const CHUNK := 32
## Height of one level step, in tiles (the same values as shaders/tilt_common.gdshaderinc).
const STEP := 0.75
## Height of the sea bed's surface (both sea levels) under the plain.
const SEA := -0.35
## How far lakes and rivers sit under the land of their level.
const WATER_DIP := 0.15


## Height of every tile.
static func heights(world: WorldData) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(world.size())
	for i in world.size():
		var level := world.level[i]
		if level < WorldData.Level.PLAIN:
			h[i] = SEA
		else:
			h[i] = (level - WorldData.Level.PLAIN) * STEP - (WATER_DIP if world.water[i] != WorldData.Water.LAND else 0.0)
	return h


## Where a ray meets the stepped ground: the (x, z) of the first point, going down from `from`
## along `dir`, that is under the top of its tile (`h` from heights(); the sea all around the map).
## A ray that does not go down gives the point under `from`.
static func ray_hit(h: PackedFloat32Array, width: int, height: int, from: Vector3, dir: Vector3) -> Vector2:
	if dir.y > -1e-4:
		return Vector2(from.x, from.z)
	# From the top of the mountains down to the sea, a twentieth of a tile at a time.
	var a := from + dir * ((2.0 * STEP - from.y) / dir.y)
	var b := from + dir * ((SEA - from.y) / dir.y)
	var steps := maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() * 20.0))
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		var x := floori(p.x)
		var y := floori(p.z)
		var ground := SEA if x < 0 or y < 0 or x >= width or y >= height else h[y * width + x]
		if p.y <= ground + 1e-4:
			return Vector2(p.x, p.z)
	return Vector2(b.x, b.z)


## One mesh per chunk, row by row. `h`: the heights, when the caller already has them.
static func build(world: WorldData, h := PackedFloat32Array()) -> Array[ArrayMesh]:
	if h.is_empty():
		h = heights(world)
	var out: Array[ArrayMesh] = []
	for cy in range(0, world.height, CHUNK):
		for cx in range(0, world.width, CHUNK):
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunk_arrays(h, world.width, world.height, cx, cy))
			out.append(mesh)
	return out


## Mesh arrays of the chunk whose first tile is (cx, cy). Vertex colour red = depth under the top
## of a cliff face, in tiles / 2 (0 on tops).
static func chunk_arrays(h: PackedFloat32Array, width: int, height: int, cx: int, cy: int) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var x1 := mini(cx + CHUNK, width)
	var y1 := mini(cy + CHUNK, height)
	# Tops, and the faces looking south and north: runs along x.
	for y in range(cy, y1):
		var x := cx
		while x < x1:
			var top := h[y * width + x]
			var end := x + 1
			while end < x1 and h[y * width + end] == top:
				end += 1
			_quad(verts, normals, colors, Vector3(x, top, y), Vector3(end, top, y), Vector3(end, top, y + 1), Vector3(x, top, y + 1), Vector3.UP, 0.0)
			x = end
		for dz in [1, -1]:
			var ny: int = y + dz
			var z := float(y + 1) if dz == 1 else float(y)
			x = cx
			while x < x1:
				var top := h[y * width + x]
				var low := SEA if ny < 0 or ny >= height else h[ny * width + x]
				if low >= top:
					x += 1
					continue
				var end := x + 1
				while end < x1 and h[y * width + end] == top and (SEA if ny < 0 or ny >= height else h[ny * width + end]) == low:
					end += 1
				_quad(verts, normals, colors, Vector3(x, top, z), Vector3(end, top, z), Vector3(end, low, z), Vector3(x, low, z), Vector3(0, 0, dz), top - low)
				x = end
	# The faces looking east and west: runs along y.
	for x in range(cx, x1):
		for dx in [1, -1]:
			var nx: int = x + dx
			var wx := float(x + 1) if dx == 1 else float(x)
			var y := cy
			while y < y1:
				var top := h[y * width + x]
				var low := SEA if nx < 0 or nx >= width else h[y * width + nx]
				if low >= top:
					y += 1
					continue
				var end := y + 1
				while end < y1 and h[end * width + x] == top and (SEA if nx < 0 or nx >= width else h[end * width + nx]) == low:
					end += 1
				_quad(verts, normals, colors, Vector3(wx, top, y), Vector3(wx, top, end), Vector3(wx, low, end), Vector3(wx, low, y), Vector3(dx, 0, 0), top - low)
				y = end
	var indices := PackedInt32Array()
	indices.resize(verts.size() / 4 * 6)
	for q in verts.size() / 4:
		var v := q * 4
		var i := q * 6
		indices[i] = v
		indices[i + 1] = v + 1
		indices[i + 2] = v + 2
		indices[i + 3] = v
		indices[i + 4] = v + 2
		indices[i + 5] = v + 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## A quad a, b (top edge), c, d (bottom edge); `drop` is the height of a cliff face (0 for a top).
static func _quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, drop: float) -> void:
	verts.append(a)
	verts.append(b)
	verts.append(c)
	verts.append(d)
	for k in 4:
		normals.append(normal)
	colors.append(Color(0, 0, 0))
	colors.append(Color(0, 0, 0))
	colors.append(Color(drop / 2.0, 0, 0))
	colors.append(Color(drop / 2.0, 0, 0))
