## Which plants grow where: per biome, the plant sprites scattered over its tiles, and the seeded
## placement of every plant of a world (trees, bushes, rocks, cacti, mushrooms, flowers).
## Sprites are in assets/sprites/ (see scripts/render3d/sprite_library.gd for their sizes).
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const SeededRng = preload("res://scripts/core/seeded_rng.gd")
const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")

## Per biome: list of [sprite id, chance per tile]. A chance above 1 places several per tile.
const FLORA := {
	Biomes.FOREST: [["trees/Oak", 0.34], ["trees/Autumn_oak", 0.03], ["trees/Red_oak", 0.02],
			["trees/Golden_oak", 0.02], ["trees/Pine", 0.04], ["plants/Bush", 0.08]],
	Biomes.JUNGLE: [["trees/Jungle_tree", 0.35], ["trees/Palm", 0.08], ["plants/Jungle_bush", 0.2]],
	Biomes.TAIGA: [["trees/Pine", 0.4], ["trees/Snowy_pine", 0.05]],
	Biomes.SNOW: [["trees/Snowy_pine", 0.05]],
	Biomes.TUNDRA: [["trees/Snowy_pine", 0.02], ["plants/Rock", 0.03]],
	Biomes.GRASSLAND: [["trees/Oak", 0.025], ["plants/Bush", 0.035], ["plants/Grassy_rock", 0.012],
			["plants/Flowers", 0.06]],
	Biomes.MEADOW: [["trees/Oak", 0.015], ["plants/Bush", 0.03], ["plants/Flowers", 0.35]],
	Biomes.HILLS: [["trees/Oak", 0.06], ["trees/Pine", 0.04], ["plants/Grassy_rock", 0.04]],
	Biomes.SAVANNA: [["trees/Acacia", 0.03], ["plants/Bush", 0.02]],
	Biomes.DESERT: [["plants/Cactus", 0.02], ["plants/Rock", 0.012]],
	Biomes.BEACH: [["trees/Palm", 0.035]],
	Biomes.SWAMP: [["trees/Swamp_tree", 0.16], ["trees/Dead_tree", 0.03], ["plants/Bush", 0.06]],
	Biomes.MOUNTAIN: [["plants/Rock", 0.05], ["plants/Boulder", 0.025], ["trees/Pine", 0.03]],
	Biomes.PEAK: [["plants/Boulder", 0.01]],
	Biomes.VOLCANIC: [["plants/Rock", 0.06], ["trees/Dead_tree", 0.03]],
	Biomes.MUSHROOM: [["plants/Red_mushroom", 0.12], ["plants/Pink_mushroom", 0.1], ["plants/Purple_mushroom", 0.08]],
	Biomes.CURSED: [["trees/Dead_tree", 0.2], ["plants/Purple_mushroom", 0.05], ["plants/Rock", 0.03]],
}

## Low plants that would only be speckles from far away: drawn under the others, hidden when zoomed out.
const GROUND_COVER := ["plants/Flowers", "plants/Grass"]


## Every plant of the world: {"id": PackedStringArray, "pos": PackedVector2Array (in tiles, the
## point where the plant touches the ground; tile (x, y) covers x..x+1, y..y+1),
## "flip": PackedByteArray, "scale": PackedFloat32Array}. Same world, same plants.
## Each tile draws its plants from its own seed, so changing a few tiles (god tools) only changes
## the plants there. A plant is kept only if its whole sprite stands over land, so trees never
## hang over the sea, lakes or rivers.
static func place(world: WorldData) -> Dictionary:
	var base := SeededRng.new(world.seed_value).sub_seed("flora")
	var rng := RandomNumberGenerator.new()
	var ids := PackedStringArray()
	var pos := PackedVector2Array()
	var flip := PackedByteArray()
	var scale := PackedFloat32Array()
	var sizes := {}
	for y in world.height:
		for x in world.width:
			var i := world.index(x, y)
			if world.is_water(i) or not FLORA.has(world.biome[i]):
				continue
			rng.seed = hash(Vector3i(base, x, y))
			for entry in FLORA[world.biome[i]]:
				var id: String = entry[0]
				var chance: float = entry[1]
				while chance > 0.0:
					if rng.randf() < chance:
						var p := Vector2(x + rng.randf_range(0.1, 0.9), y + rng.randf_range(0.2, 0.95))
						var f := 1 if rng.randf() < 0.5 else 0
						var sc := rng.randf_range(0.85, 1.15)
						if not sizes.has(id):
							sizes[id] = SpriteLibrary.world_size(id)
						if on_land(world, p, sizes[id] * sc):
							ids.append(id)
							pos.append(p)
							flip.append(f)
							scale.append(sc)
					chance -= 1.0
	return {"id": ids, "pos": pos, "flip": flip, "scale": scale}


## Whether a sprite of `size` (tiles) with its feet at `feet` covers only land tiles. The sprite's
## outer edges are trimmed a little: sprite images have some empty margin.
static func on_land(world: WorldData, feet: Vector2, size: Vector2) -> bool:
	var half := size.x * 0.4
	var x0 := floori(feet.x - half)
	var x1 := floori(feet.x + half)
	var y0 := floori(feet.y - size.y * 0.9)
	var y1 := floori(feet.y)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if not world.in_bounds(tx, ty) or world.is_water(world.index(tx, ty)):
				return false
	return true
