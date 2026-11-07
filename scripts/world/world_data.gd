## The generated world: one value per tile in flat packed arrays (index = y * width + x).
extends RefCounted

enum Water { LAND, OCEAN, LAKE, RIVER }
## The five terrain levels (docs/GAME_DESIGN.md § 3.2): every tile sits on one of them, and two
## neighbouring tiles never differ by more than one level.
enum Level { DEEP_SEA, SHALLOW, PLAIN, HILL, MOUNTAIN }

var width: int
var height: int
var seed_value: int

## Raw elevation, 0..1. Tiles below `sea_level` are sea.
var elevation := PackedFloat32Array()
var sea_level := 0.5
## 0 = freezing, 1 = scorching.
var temperature := PackedFloat32Array()
## 0 = bone dry, 1 = soaked.
var humidity := PackedFloat32Array()
## Water collected from all the tiles upstream (rivers are where it gets large).
var flow := PackedFloat32Array()
## Tile that water flows to from each tile, -1 for sea tiles.
var downstream := PackedInt32Array()
## One of Water.
var water := PackedByteArray()
## One of the ids in biomes.gd.
var biome := PackedByteArray()
## One of Level.
var level := PackedByteArray()
## Volcano centre tiles.
var volcanoes := PackedInt32Array()
## Milliseconds spent in each generation stage, for the HUD and tuning.
var stage_ms := {}


func _init(w: int, h: int, seed_v: int) -> void:
	width = w
	height = h
	seed_value = seed_v
	var n := w * h
	for arr in [elevation, temperature, humidity, flow]:
		arr.resize(n)
	downstream.resize(n)
	downstream.fill(-1)
	water.resize(n)
	biome.resize(n)
	level.resize(n)


func size() -> int:
	return width * height


func index(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


## Height above the sea, 0 at the shore and 1 at the highest peak. Negative under water.
func land_height(i: int) -> float:
	return (elevation[i] - sea_level) / (1.0 - sea_level)


## Depth below the sea, 0 at the shore and 1 at the deepest point. Negative on land.
func sea_depth(i: int) -> float:
	return (sea_level - elevation[i]) / sea_level


func is_water(i: int) -> bool:
	return water[i] != Water.LAND
