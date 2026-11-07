## Scatters trees, bushes, cacti, giant mushrooms, dead trees and rocks over the world, by biome,
## from the world's seed. Each kind is one MultiMesh of a small low-poly model built in code.
##
## Each instance has a colour (its foliage, rock or cactus colour). Model parts are tagged in UV.x:
## 0 = takes the instance colour, 1 = trunk, 2 = mushroom stem, 3 = bare dead wood; the shader
## gives tagged parts their own fixed colour. See shaders/foliage.gdshader.
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const SeededRng = preload("res://scripts/core/seeded_rng.gd")
const TerrainBuilder = preload("res://scripts/render3d/terrain_builder.gd")

enum Kind { BROADLEAF, PINE, PALM, ACACIA, CACTUS, BUSH, MUSHROOM, DEAD, ROCK }

const LEAF := 0
const TRUNK := 1
const STEM := 2
const BARE := 3

## Per biome: list of [kind, chance per tile].
const FLORA := {
	Biomes.FOREST: [[Kind.BROADLEAF, 0.42], [Kind.PINE, 0.06], [Kind.BUSH, 0.05]],
	Biomes.JUNGLE: [[Kind.BROADLEAF, 0.55], [Kind.PALM, 0.12], [Kind.BUSH, 0.1]],
	Biomes.TAIGA: [[Kind.PINE, 0.45]],
	Biomes.SNOW: [[Kind.PINE, 0.03]],
	Biomes.TUNDRA: [[Kind.BUSH, 0.03], [Kind.ROCK, 0.02]],
	Biomes.GRASSLAND: [[Kind.BROADLEAF, 0.03], [Kind.BUSH, 0.03]],
	Biomes.MEADOW: [[Kind.BROADLEAF, 0.02], [Kind.BUSH, 0.06]],
	Biomes.HILLS: [[Kind.BROADLEAF, 0.06], [Kind.PINE, 0.04], [Kind.ROCK, 0.03]],
	Biomes.SAVANNA: [[Kind.ACACIA, 0.04], [Kind.BUSH, 0.03]],
	Biomes.DESERT: [[Kind.CACTUS, 0.025], [Kind.ROCK, 0.01]],
	Biomes.BEACH: [[Kind.PALM, 0.04]],
	Biomes.SWAMP: [[Kind.BROADLEAF, 0.15], [Kind.DEAD, 0.05], [Kind.BUSH, 0.08]],
	Biomes.MOUNTAIN: [[Kind.ROCK, 0.06], [Kind.PINE, 0.03]],
	Biomes.VOLCANIC: [[Kind.ROCK, 0.08], [Kind.DEAD, 0.03]],
	Biomes.MUSHROOM: [[Kind.MUSHROOM, 0.3]],
	Biomes.CURSED: [[Kind.DEAD, 0.25], [Kind.ROCK, 0.03]],
}

## Foliage colours per biome; a few autumn trees in temperate forests.
const LEAVES := {
	Biomes.FOREST: [Color("#3f9a3a"), Color("#4fae3e"), Color("#2f7f34")],
	Biomes.JUNGLE: [Color("#2fa040"), Color("#3dbb4a"), Color("#228a3a")],
	Biomes.TAIGA: [Color("#2c6a4a"), Color("#285e44")],
	Biomes.SNOW: [Color("#5f8a78"), Color("#d8e6ee")],
	Biomes.SWAMP: [Color("#5d7a3a"), Color("#4c6a34")],
	Biomes.SAVANNA: [Color("#8a9a3a"), Color("#7a8c34")],
	Biomes.MUSHROOM: [Color("#d83a3a"), Color("#e86aa0"), Color("#9b59c6")],
	Biomes.CURSED: [Color("#5e2b78")],
}
const AUTUMN := [Color("#d8742a"), Color("#c9482a"), Color("#e8b030")]
const DEFAULT_LEAVES := [Color("#4caf50"), Color("#5cbf55")]

static var _models := {}


## Returns {Kind: MultiMesh}.
static func build(world: WorldData, h: PackedFloat32Array) -> Dictionary:
	var rng := SeededRng.new(world.seed_value).stream("vegetation")
	var transforms := {}
	var colors := {}
	for k in Kind.values():
		transforms[k] = []
		colors[k] = []
	for z in world.height:
		for x in world.width:
			var i := world.index(x, z)
			if world.is_water(i):
				continue
			var b := world.biome[i]
			if not FLORA.has(b):
				continue
			for entry in FLORA[b]:
				if rng.randf() >= entry[1]:
					continue
				var kind: int = entry[0]
				var px := x + rng.randf_range(-0.45, 0.45)
				var pz := z + rng.randf_range(-0.45, 0.45)
				var py := TerrainBuilder.sample(world, h, px, pz)
				var s := rng.randf_range(0.75, 1.3)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
				transforms[kind].append(Transform3D(basis, Vector3(px, py - 0.05, pz)))
				colors[kind].append(_colour(kind, b, rng).srgb_to_linear())
	var out := {}
	for k in Kind.values():
		if transforms[k].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = model(k)
		mm.instance_count = transforms[k].size()
		for n in transforms[k].size():
			mm.set_instance_transform(n, transforms[k][n])
			mm.set_instance_color(n, colors[k][n])
		out[k] = mm
	return out


static func _colour(kind: int, b: int, rng: RandomNumberGenerator) -> Color:
	if kind == Kind.ROCK:
		var g := rng.randf_range(0.48, 0.62)
		return Color(g, g, g + 0.04)
	if kind == Kind.CACTUS:
		return Color("#4c9a3a")
	if kind == Kind.BROADLEAF and b == Biomes.FOREST and rng.randf() < 0.12:
		return AUTUMN[rng.randi_range(0, AUTUMN.size() - 1)]
	var palette: Array = LEAVES.get(b, DEFAULT_LEAVES)
	return palette[rng.randi_range(0, palette.size() - 1)]


## The low-poly model of a kind (built once, then shared).
static func model(kind: int) -> ArrayMesh:
	if _models.has(kind):
		return _models[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf := LEAF
	match kind:
		Kind.BROADLEAF:
			_add(st, _cylinder(0.07, 0.11, 0.9, 5), Transform3D(Basis(), Vector3(0, 0.45, 0)), TRUNK)
			_add(st, _sphere(0.55, 0.95, 6, 3), Transform3D(Basis(), Vector3(0, 1.15, 0)), leaf)
			_add(st, _sphere(0.38, 0.6, 5, 3), Transform3D(Basis(), Vector3(0.3, 0.95, 0.15)), leaf)
		Kind.PINE:
			_add(st, _cylinder(0.06, 0.09, 0.5, 5), Transform3D(Basis(), Vector3(0, 0.25, 0)), TRUNK)
			_add(st, _cylinder(0.0, 0.55, 0.9, 6), Transform3D(Basis(), Vector3(0, 0.85, 0)), leaf)
			_add(st, _cylinder(0.0, 0.4, 0.75, 6), Transform3D(Basis(), Vector3(0, 1.35, 0)), leaf)
		Kind.PALM:
			_add(st, _cylinder(0.05, 0.08, 1.5, 5), Transform3D(Basis(Vector3.FORWARD, 0.12), Vector3(0.08, 0.75, 0)), TRUNK)
			_add(st, _sphere(0.6, 0.22, 7, 2), Transform3D(Basis(), Vector3(0.18, 1.5, 0)), leaf)
		Kind.ACACIA:
			_add(st, _cylinder(0.06, 0.09, 0.9, 5), Transform3D(Basis(), Vector3(0, 0.45, 0)), TRUNK)
			_add(st, _sphere(0.75, 0.3, 7, 2), Transform3D(Basis(), Vector3(0, 0.95, 0)), leaf)
		Kind.CACTUS:
			_add(st, _cylinder(0.11, 0.12, 0.9, 6), Transform3D(Basis(), Vector3(0, 0.45, 0)), leaf)
			_add(st, _cylinder(0.07, 0.07, 0.35, 5), Transform3D(Basis(), Vector3(0.22, 0.6, 0)), leaf)
			_add(st, _cylinder(0.07, 0.07, 0.15, 5), Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0.14, 0.42, 0)), leaf)
		Kind.BUSH:
			_add(st, _sphere(0.32, 0.4, 6, 3), Transform3D(Basis(), Vector3(0, 0.15, 0)), leaf)
		Kind.MUSHROOM:
			_add(st, _cylinder(0.1, 0.13, 0.8, 6), Transform3D(Basis(), Vector3(0, 0.4, 0)), STEM)
			_add(st, _sphere(0.55, 0.5, 7, 3), Transform3D(Basis(), Vector3(0, 0.82, 0)), leaf)
		Kind.DEAD:
			_add(st, _cylinder(0.05, 0.1, 1.1, 5), Transform3D(Basis(), Vector3(0, 0.55, 0)), BARE)
			_add(st, _cylinder(0.02, 0.04, 0.5, 4), Transform3D(Basis(Vector3.FORWARD, 0.8), Vector3(0.18, 0.95, 0)), BARE)
			_add(st, _cylinder(0.02, 0.04, 0.45, 4), Transform3D(Basis(Vector3.BACK, 0.7), Vector3(-0.15, 0.8, 0)), BARE)
			_add(st, _sphere(0.18, 0.2, 5, 2), Transform3D(Basis(), Vector3(0, 1.15, 0)), leaf)
		Kind.ROCK:
			_add(st, _sphere(0.4, 0.45, 5, 3), Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 0.1, 0)), leaf)
	st.generate_normals()
	var mesh := st.commit()
	_models[kind] = mesh
	return mesh


static func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func _sphere(radius: float, height: float, segments: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = rings
	return m


## Appends a primitive mesh to the surface tool, flat-shaded, transformed and tagged with its part.
static func _add(st: SurfaceTool, mesh: PrimitiveMesh, xform: Transform3D, part: int) -> void:
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for idx in indices:
		st.set_color(Color.WHITE)
		st.set_uv(Vector2(part, 0.0))
		st.set_smooth_group(-1)
		st.add_vertex(xform * verts[idx])
