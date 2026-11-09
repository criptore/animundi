## The world drawn as one texture, one texel per tile, scaled up to TILE world pixels per tile and
## drawn in a single draw call whatever the size of the world (the way WorldBox does it, see
## docs/WORLDBOX_ANALYSIS.md). shaders/map.gdshader adds the close-up detail: ground patterns and
## step edges where the ground goes down a level.
##
## Two textures, both one texel per tile:
## - the colour texture: biome colour (or a data layer's colour), lighter on higher levels, with a
##   slight per-tile variation so large biomes are not one flat colour;
## - the data texture: level, pattern and water flag, read by the shader.
## Changing a few tiles (update_tiles) rewrites a few texels, never the whole map.
extends Sprite2D

const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")

## World pixels per tile: one pattern pixel of the shader = one world pixel = one sprite pixel.
const TILE := 8

## Ground pattern drawn up close (same ids as in shaders/map.gdshader).
enum Pattern { PLAIN, GRASS, SAND, SNOW, ROCK, LAVA, FOREST, WATER }

## Brightness of each level (WorldData.Level): higher ground is lighter.
const LEVEL_TINT := [0.9, 1.0, 1.0, 1.07, 1.12]

var world: WorldData
var layer := "Biomes"

var _renderer := MapRenderer.new()
var _colors := Image.new()
var _data := Image.new()
var _color_tex := ImageTexture.new()
var _data_tex := ImageTexture.new()
var _material := ShaderMaterial.new()
## Low-frequency colour variation per tile, from the world seed.
var _variation := PackedFloat32Array()


func _init() -> void:
	centered = false
	scale = Vector2(TILE, TILE)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_material.shader = preload("res://shaders/map.gdshader")
	material = _material


## Builds both textures for `w`. Call again after generating a new world.
func set_world(w: WorldData) -> void:
	world = w
	var noise := FastNoiseLite.new()
	noise.seed = w.seed_value
	noise.frequency = 0.08
	# Broad patches (noise image, 0..1, built natively) plus a little per-tile grain.
	var patches := noise.get_image(w.width, w.height, false, false, false).get_data()
	_variation.resize(w.size())
	for i in w.size():
		_variation[i] = (patches[i] / 255.0 - 0.5) * 0.08 + (_hash(i % w.width, i / w.width) - 0.5) * 0.03

	var data := PackedByteArray()
	data.resize(w.size() * 4)
	var patterns := PackedByteArray()
	for b in Biomes.COUNT:
		patterns.append(pattern(b) * 255 / 8)
	for i in w.size():
		data[i * 4] = w.level[i] * 255 / 4
		data[i * 4 + 1] = patterns[w.biome[i]]
		data[i * 4 + 2] = 255 if w.water[i] != WorldData.Water.LAND else 0
		data[i * 4 + 3] = 255
	_data = Image.create_from_data(w.width, w.height, false, Image.FORMAT_RGBA8, data)
	_data_tex = ImageTexture.create_from_image(_data)
	_material.set_shader_parameter("data", _data_tex)
	_material.set_shader_parameter("map_size", Vector2(w.width, w.height))
	_build_colors()


## Shows the biome map or one of the data layers of MapRenderer.LAYERS.
func show_layer(layer_name: String) -> void:
	layer = layer_name
	_material.set_shader_parameter("show_patterns", layer_name == "Biomes")
	if world != null:
		_build_colors()


## Redraws the given tiles after the world changed there (terrain powers, growth, fire...).
func update_tiles(indices: PackedInt32Array) -> void:
	for i in indices:
		var x := i % world.width
		var y := i / world.width
		_colors.set_pixel(x, y, tile_color(i))
		var d := _data_texel(i)
		_data.set_pixel(x, y, Color8(d[0], d[1], d[2], d[3]))
	_color_tex.update(_colors)
	_data_tex.update(_data)


## Colour of tile `i` on the current layer, before the shader's patterns and edges.
func tile_color(i: int) -> Color:
	if layer != "Biomes":
		return _renderer.layer_color(world, i, layer)
	var b := world.biome[i]
	var c: Color = Biomes.COLORS[b]
	if b == Biomes.WATER and world.water[i] == WorldData.Water.OCEAN:
		# Shallow sea darkens with depth toward the deep water colour.
		c = c.lerp(Biomes.COLORS[Biomes.DEEP_WATER], clampf(world.sea_depth(i) / Biomes.DEEP_WATER_DEPTH, 0.0, 1.0) * 0.45)
	elif b == Biomes.DEEP_WATER:
		c = c.darkened(clampf(world.sea_depth(i), 0.0, 1.0) * 0.35)
	var tint: float = LEVEL_TINT[world.level[i]] + _variation[i]
	return Color(c.r * tint, c.g * tint, c.b * tint)


## The colour image behind the map texture (one pixel per tile).
func color_image() -> Image:
	return _colors


## Tile under a point in this node's parent space, or (-1, -1) outside the map.
func tile_at(point: Vector2) -> Vector2i:
	var p := (point - position) / float(TILE)
	var t := Vector2i(floori(p.x), floori(p.y))
	return t if world != null and world.in_bounds(t.x, t.y) else Vector2i(-1, -1)


## Size of the map in world pixels.
func pixel_size() -> Vector2:
	return Vector2(world.width, world.height) * TILE if world != null else Vector2.ZERO


static func pattern(b: int) -> int:
	match b:
		Biomes.GRASSLAND, Biomes.MEADOW, Biomes.HILLS, Biomes.SAVANNA:
			return Pattern.GRASS
		Biomes.FOREST, Biomes.JUNGLE, Biomes.TAIGA, Biomes.SWAMP, Biomes.MUSHROOM, Biomes.CURSED:
			return Pattern.FOREST
		Biomes.BEACH, Biomes.DESERT:
			return Pattern.SAND
		Biomes.SNOW, Biomes.ICE, Biomes.TUNDRA, Biomes.PEAK:
			return Pattern.SNOW
		Biomes.MOUNTAIN, Biomes.VOLCANIC:
			return Pattern.ROCK
		Biomes.LAVA:
			return Pattern.LAVA
		Biomes.WATER, Biomes.DEEP_WATER:
			return Pattern.WATER
	return Pattern.PLAIN


func _build_colors() -> void:
	var bytes := PackedByteArray()
	bytes.resize(world.size() * 4)
	for i in world.size():
		var c := tile_color(i)
		bytes[i * 4] = clampi(roundi(c.r * 255.0), 0, 255)
		bytes[i * 4 + 1] = clampi(roundi(c.g * 255.0), 0, 255)
		bytes[i * 4 + 2] = clampi(roundi(c.b * 255.0), 0, 255)
		bytes[i * 4 + 3] = 255
	_colors = Image.create_from_data(world.width, world.height, false, Image.FORMAT_RGBA8, bytes)
	if _color_tex.get_width() == world.width and _color_tex.get_height() == world.height:
		_color_tex.update(_colors)
	else:
		_color_tex = ImageTexture.create_from_image(_colors)
	texture = _color_tex


## Data texel of tile `i`: level, pattern, water flag (see shaders/map.gdshader).
func _data_texel(i: int) -> PackedByteArray:
	return PackedByteArray([world.level[i] * 255 / 4, pattern(world.biome[i]) * 255 / 8,
			255 if world.is_water(i) else 0, 255])


static func _hash(x: int, y: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663)) & 0xffff) / 65535.0
