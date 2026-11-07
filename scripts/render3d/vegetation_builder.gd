## Scatters plant sprites over the world, by biome, from the world's seed: trees, bushes, rocks,
## cacti, mushrooms, grass and flowers (sprites from assets/sprites/, see sprite_library.gd).
## Each sprite is one MultiMesh of camera-facing quads.
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const SeededRng = preload("res://scripts/core/seeded_rng.gd")
const TerrainBuilder = preload("res://scripts/render3d/terrain_builder.gd")
const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")

## Per biome: list of [sprite id, chance per tile]. A chance above 1 places several per tile.
const FLORA := {
	Biomes.FOREST: [["trees/Oak", 0.34], ["trees/Autumn_oak", 0.03], ["trees/Red_oak", 0.02],
			["trees/Golden_oak", 0.02], ["trees/Pine", 0.04], ["plants/Bush", 0.08], ["plants/Grass", 0.15]],
	Biomes.JUNGLE: [["trees/Jungle_tree", 0.35], ["trees/Palm", 0.08], ["plants/Jungle_bush", 0.2]],
	Biomes.TAIGA: [["trees/Pine", 0.4], ["trees/Snowy_pine", 0.05], ["plants/Grass", 0.2]],
	Biomes.SNOW: [["trees/Snowy_pine", 0.05]],
	Biomes.TUNDRA: [["trees/Snowy_pine", 0.02], ["plants/Rock", 0.03], ["plants/Grass", 0.1]],
	Biomes.GRASSLAND: [["trees/Oak", 0.025], ["plants/Bush", 0.035], ["plants/Grassy_rock", 0.012],
			["plants/Grass", 0.1], ["plants/Flowers", 0.06]],
	Biomes.MEADOW: [["trees/Oak", 0.015], ["plants/Bush", 0.03], ["plants/Grass", 0.2], ["plants/Flowers", 0.35]],
	Biomes.HILLS: [["trees/Oak", 0.06], ["trees/Pine", 0.04], ["plants/Grassy_rock", 0.04], ["plants/Grass", 0.2]],
	Biomes.SAVANNA: [["trees/Acacia", 0.03], ["plants/Bush", 0.02], ["plants/Grass", 0.15]],
	Biomes.DESERT: [["plants/Cactus", 0.02], ["plants/Rock", 0.012]],
	Biomes.BEACH: [["trees/Palm", 0.035]],
	Biomes.SWAMP: [["trees/Swamp_tree", 0.16], ["trees/Dead_tree", 0.03], ["plants/Bush", 0.06], ["plants/Grass", 0.2]],
	Biomes.MOUNTAIN: [["plants/Rock", 0.05], ["plants/Boulder", 0.025], ["trees/Pine", 0.03]],
	Biomes.PEAK: [["plants/Boulder", 0.01]],
	Biomes.VOLCANIC: [["plants/Rock", 0.06], ["trees/Dead_tree", 0.03]],
	Biomes.MUSHROOM: [["plants/Red_mushroom", 0.12], ["plants/Pink_mushroom", 0.1], ["plants/Purple_mushroom", 0.08],
			["plants/Grass", 0.12]],
	Biomes.CURSED: [["trees/Dead_tree", 0.2], ["plants/Purple_mushroom", 0.05], ["plants/Rock", 0.03]],
}


## Returns {sprite id: MultiMesh}.
static func build(world: WorldData, h: PackedFloat32Array) -> Dictionary:
	var rng := SeededRng.new(world.seed_value).stream("vegetation")
	var transforms := {}
	for z in world.height:
		for x in world.width:
			var i := world.index(x, z)
			if world.is_water(i):
				continue
			var b := world.biome[i]
			if not FLORA.has(b):
				continue
			for entry in FLORA[b]:
				var id: String = entry[0]
				var chance: float = entry[1]
				while chance > 0.0:
					if rng.randf() < chance:
						var px := x + rng.randf_range(-0.5, 0.5)
						var pz := z + rng.randf_range(-0.5, 0.5)
						var py := TerrainBuilder.sample(world, h, px, pz)
						var basis := SpriteLibrary.basis(rng.randf() < 0.5, rng.randf_range(0.85, 1.15))
						if not transforms.has(id):
							transforms[id] = []
						transforms[id].append(Transform3D(basis, Vector3(px, py - 0.05, pz)))
					chance -= 1.0
	var out := {}
	for id in transforms:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = SpriteLibrary.mesh(id)
		mm.instance_count = transforms[id].size()
		for n in transforms[id].size():
			mm.set_instance_transform(n, transforms[id][n])
		out[id] = mm
	return out


## Grass and flowers: no shadows (they would only darken the ground in speckles), and hidden when
## zoomed out, where they would shrink to dark dots.
static func is_ground_cover(id: String) -> bool:
	return id == "plants/Grass" or id == "plants/Flowers"
