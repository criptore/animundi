## Scatters plant sprites over the world, by biome, from the world's seed: trees, bushes, rocks,
## cacti, mushrooms, grass and flowers (sprites from assets/sprites/, see sprite_library.gd).
## Each sprite is one MultiMesh of camera-facing quads.
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const SeededRng = preload("res://scripts/core/seeded_rng.gd")
const TerrainBuilder = preload("res://scripts/render3d/terrain_builder.gd")
const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")
const Flora = preload("res://scripts/world/flora.gd")

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
			if not Flora.table().has(b):
				continue
			for entry in Flora.table()[b]:
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


## Flowers: no shadows (they would only darken the ground in speckles), and hidden when zoomed out,
## where they would shrink to dots.
static func is_ground_cover(id: String) -> bool:
	return id in Flora.ground_cover()


## Dense grass tufts per biome (instances per tile), drawn by shaders/grass.gdshader.
const GRASS := {
	Biomes.GRASSLAND: 4, Biomes.MEADOW: 4, Biomes.HILLS: 4, Biomes.FOREST: 2, Biomes.JUNGLE: 3,
	Biomes.TAIGA: 2, Biomes.SWAMP: 3, Biomes.SAVANNA: 2, Biomes.TUNDRA: 1, Biomes.MUSHROOM: 2,
}
## Size of a grass tuft quad, in world units (8 atlas pixels at the sprites' pixel density).
const GRASS_SIZE := 0.26


## One MultiMesh of grass tufts over every grassy tile, coloured like the ground (a little lighter).
static func build_grass(world: WorldData, h: PackedFloat32Array) -> MultiMesh:
	var rng := SeededRng.new(world.seed_value).stream("grass")
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for z in world.height:
		for x in world.width:
			var i := world.index(x, z)
			var b := world.biome[i]
			if world.is_water(i) or not GRASS.has(b):
				continue
			var ground: Color = Biomes.COLORS[b]
			for k in GRASS[b]:
				var px := x + rng.randf_range(-0.5, 0.5)
				var pz := z + rng.randf_range(-0.5, 0.5)
				transforms.append(Transform3D(SpriteLibrary.basis(false, rng.randf_range(0.8, 1.2)), Vector3(px, h[i], pz)))
				colors.append(ground.lightened(rng.randf_range(0.04, 0.14)).srgb_to_linear())
	var quad := QuadMesh.new()
	quad.size = Vector2(GRASS_SIZE, GRASS_SIZE)
	quad.center_offset = Vector3(0.0, GRASS_SIZE / 2.0, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = transforms.size()
	for n in transforms.size():
		mm.set_instance_transform(n, transforms[n])
		mm.set_instance_color(n, colors[n])
	return mm
