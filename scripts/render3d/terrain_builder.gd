## Builds the 3D terrain of a world as terraces: every tile is a flat block at the height of its
## level (deep sea, shallow water, plain, hill, mountain), with cliff faces where a neighbour is
## lower (dirt under grass, rock under mountains, as in the biome reference sheet). Also builds the
## heightmap texture the water shader reads for depth and shore foam.
##
## World space: tile (x, y) covers x-0.5..x+0.5, y-0.5..y+0.5 at (x, height, y); sea level is y = 0
## and one water plane at y = 0 covers the sea, rivers and lakes (they all sit on the shallow level).
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")

## Top height of each level (WorldData.Level), in tiles: about one tile between levels, so the
## relief stays at the scale of the people and trees standing on it.
const LEVEL_HEIGHT := [-1.4, -0.45, 0.3, 1.2, 2.3]
## Ice floats just above the water.
const ICE_HEIGHT := 0.06
## Bottom of the cliff faces at the map edge.
const FLOOR := -3.0
## Volcano cones rise this high above the ground at their centre and spread this far (tiles).
const VOLCANO_HEIGHT := 2.4
const VOLCANO_RADIUS := 5.5
## For hover picking: highest and lowest ground.
const TOP := 2.3 + VOLCANO_HEIGHT
const BOTTOM := -1.4

## Surface pattern drawn by shaders/terrain.gdshader on tile tops (UV.x); cliff faces have UV.y = 1.
enum Pattern { PLAIN, GRASS, SAND, SNOW, ROCK, LAVA, FOREST_FLOOR }


static func ground_height(world: WorldData, i: int) -> float:
	if world.biome[i] == Biomes.ICE:
		return ICE_HEIGHT
	return LEVEL_HEIGHT[world.level[i]]


## Ground height of every tile, used for meshes, vegetation and mouse picking. Volcanic tiles
## rise into a stepped cone around each volcano, with the lava sitting in a crater at the top.
static func heights(world: WorldData) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(world.size())
	for i in world.size():
		h[i] = ground_height(world, i)
	for c in world.volcanoes:
		var cx := c % world.width
		var cz := c / world.width
		var r := ceili(VOLCANO_RADIUS)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if not world.in_bounds(cx + dx, cz + dz):
					continue
				var j := world.index(cx + dx, cz + dz)
				var b := world.biome[j]
				if b != Biomes.VOLCANIC and b != Biomes.LAVA:
					continue
				var d := Vector2(dx, dz).length()
				if b == Biomes.LAVA:
					d = 2.6  # crater floor: lower than the rim around it
				h[j] = maxf(h[j], ground_height(world, j) + VOLCANO_HEIGHT * clampf(1.0 - d / VOLCANO_RADIUS, 0.0, 1.0))
	return h


static func pattern(b: int) -> int:
	match b:
		Biomes.GRASSLAND, Biomes.MEADOW, Biomes.HILLS:
			return Pattern.GRASS
		Biomes.FOREST, Biomes.JUNGLE, Biomes.TAIGA, Biomes.SWAMP, Biomes.MUSHROOM, Biomes.CURSED:
			return Pattern.FOREST_FLOOR
		Biomes.BEACH, Biomes.DESERT, Biomes.SAVANNA, Biomes.WATER, Biomes.DEEP_WATER:
			return Pattern.SAND
		Biomes.SNOW, Biomes.ICE, Biomes.TUNDRA, Biomes.PEAK:
			return Pattern.SNOW
		Biomes.MOUNTAIN, Biomes.VOLCANIC:
			return Pattern.ROCK
		Biomes.LAVA:
			return Pattern.LAVA
	return Pattern.PLAIN


## Ground height under a point: the top of the tile it stands on (terraces are flat).
static func sample(world: WorldData, h: PackedFloat32Array, x: float, z: float) -> float:
	var tx := clampi(roundi(x), 0, world.width - 1)
	var tz := clampi(roundi(z), 0, world.height - 1)
	return h[world.index(tx, tz)]


## Colour of the cliff face under a tile of biome `b`.
static func side_color(b: int) -> Color:
	match b:
		Biomes.BEACH, Biomes.DESERT, Biomes.SAVANNA:
			return Color("#c89a58")
		Biomes.SNOW, Biomes.ICE, Biomes.TUNDRA, Biomes.PEAK:
			return Color("#9fb8c8")
		Biomes.MOUNTAIN:
			return Color("#5c5e68")
		Biomes.VOLCANIC, Biomes.LAVA:
			return Color("#2c2428")
		Biomes.MUSHROOM, Biomes.CURSED:
			return Color("#4a3448")
		Biomes.DEEP_WATER, Biomes.WATER:
			return Color("#c8b070")
	return Color("#7a5232")  # dirt under grass, forest, jungle, swamp, taiga, hills


## Terrain mesh. `layer` is "Biomes" or one of the data layers of MapRenderer.
## Palette colours are sRGB; vertex colours are stored linear, as the Forward+ renderer expects.
static func build_terrain(world: WorldData, h: PackedFloat32Array, layer := "Biomes",
		renderer: MapRenderer = null) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var jitter := FastNoiseLite.new()
	jitter.seed = world.seed_value
	jitter.frequency = 0.15
	var sides := [[Vector2i(1, 0), Vector3(1, 0, 0)], [Vector2i(-1, 0), Vector3(-1, 0, 0)],
			[Vector2i(0, 1), Vector3(0, 0, 1)], [Vector2i(0, -1), Vector3(0, 0, -1)]]
	for z in world.height:
		for x in world.width:
			var i := world.index(x, z)
			var top := h[i]
			var c: Color
			if layer == "Biomes" or renderer == null:
				var base: Color = Biomes.COLORS[world.biome[i]]
				# Gentle patchiness so big biomes are not one flat colour.
				var v := jitter.get_noise_2d(x, z) * 0.05
				c = Color(base.r + v, base.g + v, base.b + v * 0.5)
			else:
				c = renderer.layer_color(world, i, layer)
			c = c.srgb_to_linear()
			var top_uv := Vector2(pattern(world.biome[i]) if layer == "Biomes" else Pattern.PLAIN, 0.0)
			_quad(verts, normals, colors, uvs, Vector3(x - 0.5, top, z - 0.5), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3.UP, c, top_uv)
			var wall: Color = side_color(world.biome[i]).srgb_to_linear() if layer == "Biomes" or renderer == null else c.darkened(0.3)
			for s in sides:
				var d: Vector2i = s[0]
				var n: Vector3 = s[1]
				var below := FLOOR
				if world.in_bounds(x + d.x, z + d.y):
					below = h[world.index(x + d.x, z + d.y)]
				if below >= top:
					continue
				# A vertical face along the tile edge on side n, from `below` up to `top`.
				var centre := Vector3(x, 0, z) + n * 0.5
				var along := Vector3(-n.z, 0, n.x)
				_quad(verts, normals, colors, uvs, centre - along * 0.5 + Vector3(0, below, 0), along,
						Vector3(0, top - below, 0), n, wall, Vector2(0.0, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Appends the quad origin, origin+u, origin+v, origin+u+v (two triangles, facing `normal`).
static func _quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		uvs: PackedVector2Array, origin: Vector3, u: Vector3, v: Vector3, normal: Vector3, color: Color,
		uv: Vector2) -> void:
	var a := origin
	var b := origin + u
	var c := origin + v
	var d := origin + u + v
	# Wind so the face is front-facing (clockwise seen from `normal`).
	var tri := [a, b, c, b, d, c] if u.cross(v).dot(normal) < 0.0 else [a, c, b, b, c, d]
	for p in tri:
		verts.append(p)
		normals.append(normal)
		colors.append(color)
		uvs.append(uv)


## Ground heights as a float texture (one texel per tile) for the water shader's depth and foam.
static func heightmap_texture(world: WorldData, h: PackedFloat32Array) -> ImageTexture:
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RF)
	for z in world.height:
		for x in world.width:
			img.set_pixel(x, z, Color(h[world.index(x, z)], 0.0, 0.0))
	return ImageTexture.create_from_image(img)
