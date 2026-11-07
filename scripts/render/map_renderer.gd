## Turns a generated world into images: the biome map (8x8 pixel tiles from the terrain atlas)
## and one-pixel-per-tile data layers (height, temperature, humidity, rivers).
extends RefCounted

const TerrainAtlas = preload("res://scripts/generated/terrain_atlas.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const WorldData = preload("res://scripts/world/world_data.gd")

const TILE := TerrainAtlas.TILE_SIZE
const LAYERS := ["Biomes", "Height", "Temperature", "Humidity", "Rivers"]

## For each biome: 4 variants of its tile (as is, mirrored, flipped, both) to break up repetition.
var _variants: Array = []


func _init() -> void:
	var atlas := (load(TerrainAtlas.TEXTURE) as Texture2D).get_image()
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	for b in Biomes.COUNT:
		var column: int = TerrainAtlas.TILES.find(Biomes.TILES[b])
		assert(column >= 0, "No terrain tile named %s" % Biomes.TILES[b])
		var base := atlas.get_region(Rect2i(column * TILE, 0, TILE, TILE))
		var mirrored := base.duplicate()
		mirrored.flip_x()
		var flipped := base.duplicate()
		flipped.flip_y()
		var both := mirrored.duplicate()
		both.flip_y()
		_variants.append([base, mirrored, flipped, both])


## Full-resolution biome map: width * 8 by height * 8 pixels.
func render_biomes(world: WorldData) -> Image:
	var img := Image.create(world.width * TILE, world.height * TILE, false, Image.FORMAT_RGBA8)
	var src := Rect2i(0, 0, TILE, TILE)
	for y in world.height:
		for x in world.width:
			var b := world.biome[world.index(x, y)]
			img.blit_rect(_variants[b][_variant(x, y)], src, Vector2i(x * TILE, y * TILE))
	return img


## A data layer, one pixel per tile (display it scaled by TILE).
func render_layer(world: WorldData, layer: String) -> Image:
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RGBA8)
	for y in world.height:
		for x in world.width:
			img.set_pixel(x, y, layer_color(world, world.index(x, y), layer))
	return img


func layer_color(world: WorldData, i: int, layer: String) -> Color:
	var ocean := world.water[i] == WorldData.Water.OCEAN
	match layer:
		"Height":
			if ocean:
				return Color("#0d2a5c").lerp(Color("#3b8fe0"), 1.0 - world.sea_depth(i))
			var e := world.land_height(i)
			return Color("#2c6e35").lerp(Color("#c4a65a"), clampf(e * 2.0, 0.0, 1.0)) \
					.lerp(Color("#f4f4f0"), clampf(e * 2.0 - 1.0, 0.0, 1.0))
		"Temperature":
			var t := world.temperature[i]
			var c := Color("#3b5bdb").lerp(Color("#f0f0f0"), clampf(t * 2.0, 0.0, 1.0)) \
					.lerp(Color("#d83a3a"), clampf(t * 2.0 - 1.0, 0.0, 1.0))
			return c.darkened(0.45) if ocean else c
		"Humidity":
			if ocean:
				return Color("#1d4a94")
			return Color("#c4a65a").lerp(Color("#4caf50"), world.humidity[i])
		"Rivers":
			match world.water[i]:
				WorldData.Water.OCEAN:
					return Color("#1d4a94")
				WorldData.Water.LAKE:
					return Color("#3b8fe0")
				WorldData.Water.RIVER:
					return Color("#8fd8ff")
			var f := clampf(log(1.0 + world.flow[i]) / 8.0, 0.0, 1.0)
			return Color("#2b2b33").lerp(Color("#6aa0d8"), f)
	return Color.MAGENTA


static func _variant(x: int, y: int) -> int:
	return (((x * 73856093) ^ (y * 19349663)) >> 4) & 3
