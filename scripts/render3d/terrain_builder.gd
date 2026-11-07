## Builds the 3D meshes of a world: the terrain (one vertex per tile, coloured by biome or by a
## data layer), the lake and river surfaces, and the heightmap texture the water shader reads.
##
## World space: tile (x, y) is at (x, height, y); sea level is y = 0.
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")

## Height of the highest peak above the sea, in tiles.
const HEIGHT_SCALE := 24.0
## Depth of the deepest sea, in tiles.
const SEA_FLOOR := 7.0
## Land starts this far above the sea so beaches don't flicker against the water.
const SHORE_LIFT := 0.25
## River beds and lake floors sit this far under their water surface.
const BED_DEPTH := 0.7


static func ground_height(world: WorldData, i: int) -> float:
	match world.water[i]:
		WorldData.Water.OCEAN:
			return -0.3 - maxf(world.sea_depth(i), 0.0) * SEA_FLOOR
		WorldData.Water.LAKE, WorldData.Water.RIVER:
			return water_height(world, i) - BED_DEPTH
	return SHORE_LIFT + maxf(world.land_height(i), 0.0) * HEIGHT_SCALE


## Water surface height of a tile (0 for the sea).
static func water_height(world: WorldData, i: int) -> float:
	if world.water[i] == WorldData.Water.OCEAN:
		return 0.0
	return SHORE_LIFT + maxf(world.surface_height(i), 0.0) * HEIGHT_SCALE


## Ground height of every tile, used for meshes, vegetation and mouse picking.
static func heights(world: WorldData) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(world.size())
	for i in world.size():
		h[i] = ground_height(world, i)
	return h


## Ground height anywhere on the map, interpolated between tile centres.
static func sample(world: WorldData, h: PackedFloat32Array, x: float, z: float) -> float:
	x = clampf(x, 0.0, world.width - 1.001)
	z = clampf(z, 0.0, world.height - 1.001)
	var x0 := int(x)
	var z0 := int(z)
	var fx := x - x0
	var fz := z - z0
	var a := lerpf(h[world.index(x0, z0)], h[world.index(x0 + 1, z0)], fx)
	var b := lerpf(h[world.index(x0, z0 + 1)], h[world.index(x0 + 1, z0 + 1)], fx)
	return lerpf(a, b, fz)


## Terrain mesh. `layer` is "Biomes" or one of the data layers of MapRenderer.
## Colours are used as they are: the renderer (GL Compatibility) lights them directly.
static func build_terrain(world: WorldData, h: PackedFloat32Array, layer := "Biomes",
		renderer: MapRenderer = null) -> ArrayMesh:
	var w := world.width
	var d := world.height
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(w * d)
	normals.resize(w * d)
	colors.resize(w * d)
	var jitter := FastNoiseLite.new()
	jitter.seed = world.seed_value
	jitter.frequency = 0.15
	for z in d:
		for x in w:
			var i := world.index(x, z)
			verts[i] = Vector3(x, h[i], z)
			var hl := h[world.index(maxi(x - 1, 0), z)]
			var hr := h[world.index(mini(x + 1, w - 1), z)]
			var hu := h[world.index(x, maxi(z - 1, 0))]
			var hd := h[world.index(x, mini(z + 1, d - 1))]
			normals[i] = Vector3(hl - hr, 2.0, hu - hd).normalized()
			if layer == "Biomes" or renderer == null:
				var c: Color = Biomes.COLORS[world.biome[i]]
				# Gentle patchiness so big biomes are not flat colour.
				var v := jitter.get_noise_2d(x, z) * 0.07
				colors[i] = Color(c.r + v, c.g + v, c.b + v * 0.5)
			else:
				colors[i] = renderer.layer_color(world, i, layer)
	var indices := PackedInt32Array()
	indices.resize((w - 1) * (d - 1) * 6)
	var k := 0
	for z in d - 1:
		for x in w - 1:
			var a := world.index(x, z)
			var b := a + 1
			var c := a + w
			var e := c + 1
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = e
			indices[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One flat quad per lake or river tile, at its water surface. (The sea is a separate plane.)
static func build_inland_water(world: WorldData) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for z in world.height:
		for x in world.width:
			var i := world.index(x, z)
			if world.water[i] != WorldData.Water.LAKE and world.water[i] != WorldData.Water.RIVER:
				continue
			if world.biome[i] == Biomes.ICE:
				continue
			var y := water_height(world, i)
			var p := [Vector3(x - 0.5, y, z - 0.5), Vector3(x + 0.5, y, z - 0.5),
					Vector3(x - 0.5, y, z + 0.5), Vector3(x + 0.5, y, z + 0.5)]
			for v in [p[0], p[1], p[2], p[1], p[3], p[2]]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
			count += 1
	if count == 0:
		return null
	return st.commit()


## Ground heights as a float texture (one texel per tile) for the water shader's depth and foam.
static func heightmap_texture(world: WorldData, h: PackedFloat32Array) -> ImageTexture:
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RF)
	for z in world.height:
		for x in world.width:
			img.set_pixel(x, z, Color(h[world.index(x, z)], 0.0, 0.0))
	return ImageTexture.create_from_image(img)
