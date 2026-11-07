## Scatters plants over the world, by biome, from the world's seed: trees, bushes, cacti, giant
## mushrooms, dead trees and rocks (low-poly models), plus grass tufts and flowers (camera-facing
## quads drawn by shaders/grass.gdshader). Each kind is one MultiMesh.
##
## Models follow docs/ART_DIRECTION.md: foliage is made of a few clumps whose normals point away
## from the crown's centre, so light wraps around the whole crown softly instead of faceting.
## Each instance has a colour (foliage, rock or cactus colour). Model parts are tagged in UV.x:
## 0 = takes the instance colour, 1 = trunk, 2 = mushroom stem, 3 = bare dead wood.
extends RefCounted

const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const SeededRng = preload("res://scripts/core/seeded_rng.gd")
const TerrainBuilder = preload("res://scripts/render3d/terrain_builder.gd")

enum Kind { BROADLEAF, PINE, PALM, ACACIA, CACTUS, BUSH, MUSHROOM, DEAD, ROCK, GRASS, FLOWER }

const LEAF := 0
const TRUNK := 1
const STEM := 2
const BARE := 3

## Per biome: list of [kind, chance per tile]. Grass and flowers may appear several times per tile.
const FLORA := {
	Biomes.FOREST: [[Kind.BROADLEAF, 0.4], [Kind.PINE, 0.05], [Kind.BUSH, 0.08], [Kind.GRASS, 0.8], [Kind.FLOWER, 0.05]],
	Biomes.JUNGLE: [[Kind.BROADLEAF, 0.5], [Kind.PALM, 0.12], [Kind.BUSH, 0.15], [Kind.GRASS, 0.9]],
	Biomes.TAIGA: [[Kind.PINE, 0.45], [Kind.GRASS, 0.4]],
	Biomes.SNOW: [[Kind.PINE, 0.03]],
	Biomes.TUNDRA: [[Kind.BUSH, 0.03], [Kind.ROCK, 0.03], [Kind.GRASS, 0.5]],
	Biomes.GRASSLAND: [[Kind.BROADLEAF, 0.03], [Kind.BUSH, 0.04], [Kind.ROCK, 0.01], [Kind.GRASS, 1.8], [Kind.FLOWER, 0.35]],
	Biomes.MEADOW: [[Kind.BROADLEAF, 0.02], [Kind.BUSH, 0.05], [Kind.GRASS, 1.8], [Kind.FLOWER, 1.4]],
	Biomes.HILLS: [[Kind.BROADLEAF, 0.07], [Kind.PINE, 0.04], [Kind.ROCK, 0.04], [Kind.GRASS, 1.4], [Kind.FLOWER, 0.2]],
	Biomes.SAVANNA: [[Kind.ACACIA, 0.04], [Kind.BUSH, 0.03], [Kind.GRASS, 1.2]],
	Biomes.DESERT: [[Kind.CACTUS, 0.025], [Kind.ROCK, 0.015]],
	Biomes.BEACH: [[Kind.PALM, 0.04], [Kind.GRASS, 0.15]],
	Biomes.SWAMP: [[Kind.BROADLEAF, 0.15], [Kind.DEAD, 0.05], [Kind.BUSH, 0.1], [Kind.GRASS, 1.2]],
	Biomes.MOUNTAIN: [[Kind.ROCK, 0.08], [Kind.PINE, 0.03], [Kind.GRASS, 0.2]],
	Biomes.VOLCANIC: [[Kind.ROCK, 0.08], [Kind.DEAD, 0.03]],
	Biomes.MUSHROOM: [[Kind.MUSHROOM, 0.3], [Kind.GRASS, 0.8], [Kind.FLOWER, 0.3]],
	Biomes.CURSED: [[Kind.DEAD, 0.25], [Kind.ROCK, 0.03], [Kind.GRASS, 0.4]],
}

## Foliage colours per biome; a few autumn trees in temperate forests (as in the references).
const LEAVES := {
	Biomes.FOREST: [Color("#7cb85c"), Color("#88c262"), Color("#6aa854")],
	Biomes.JUNGLE: [Color("#6ab05a"), Color("#78bc60"), Color("#5aa052")],
	Biomes.TAIGA: [Color("#5a8c6c"), Color("#64967a")],
	Biomes.SNOW: [Color("#6f9a88"), Color("#e8eef2")],
	Biomes.SWAMP: [Color("#8a9c5c"), Color("#7c9256")],
	Biomes.SAVANNA: [Color("#b0b464"), Color("#a2aa5c")],
	Biomes.MUSHROOM: [Color("#e2786a"), Color("#eea0bc"), Color("#bb92d8")],
	Biomes.CURSED: [Color("#7e6496")],
}
const AUTUMN := [Color("#e8984a"), Color("#d8704a"), Color("#ecc05a")]
const DEFAULT_LEAVES := [Color("#7cb85c"), Color("#88c262")]
const FLOWERS := [Color("#ffffff"), Color("#fff4c8"), Color("#f5d04a"), Color("#f2a7c0"), Color("#c9b6f0")]

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
				var kind: int = entry[0]
				var chance: float = entry[1]
				while chance > 0.0:
					if rng.randf() < chance:
						_place(world, h, x, z, kind, b, rng, transforms, colors)
					chance -= 1.0
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


static func is_ground_cover(kind: int) -> bool:
	return kind == Kind.GRASS or kind == Kind.FLOWER


static func _place(world: WorldData, h: PackedFloat32Array, x: int, z: int, kind: int, b: int,
		rng: RandomNumberGenerator, transforms: Dictionary, colors: Dictionary) -> void:
	var px := x + rng.randf_range(-0.5, 0.5)
	var pz := z + rng.randf_range(-0.5, 0.5)
	var py := TerrainBuilder.sample(world, h, px, pz)
	var basis: Basis
	if is_ground_cover(kind):
		# Quads face the fixed camera (they are built in the XY plane): no rotation, just size.
		var s := rng.randf_range(0.7, 1.2)
		basis = Basis.from_scale(Vector3(s * rng.randf_range(0.9, 1.3), s, s))
	else:
		var s := rng.randf_range(0.75, 1.3)
		basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
	transforms[kind].append(Transform3D(basis, Vector3(px, py - 0.03, pz)))
	colors[kind].append(_colour(kind, b, rng))


static func _colour(kind: int, b: int, rng: RandomNumberGenerator) -> Color:
	match kind:
		Kind.ROCK:
			var g := rng.randf_range(0.72, 0.84)
			return Color(g, g * 0.98, g * 1.02)
		Kind.CACTUS:
			return Color("#7cb064")
		Kind.GRASS:
			# Close to the ground colour, a touch lighter, so tufts read softly against it.
			var c: Color = Biomes.COLORS[b]
			return c.lightened(rng.randf_range(0.02, 0.08))
		Kind.FLOWER:
			return FLOWERS[rng.randi_range(0, FLOWERS.size() - 1)]
	if kind == Kind.BROADLEAF and b == Biomes.FOREST and rng.randf() < 0.12:
		return AUTUMN[rng.randi_range(0, AUTUMN.size() - 1)]
	var palette: Array = LEAVES.get(b, DEFAULT_LEAVES)
	return palette[rng.randi_range(0, palette.size() - 1)]


## The model of a kind (built once, then shared).
static func model(kind: int) -> Mesh:
	if _models.has(kind):
		return _models[kind]
	var mesh: Mesh
	if is_ground_cover(kind):
		var q := QuadMesh.new()
		q.size = Vector2(0.55, 0.45) if kind == Kind.GRASS else Vector2(0.35, 0.4)
		q.center_offset = Vector3(0.0, q.size.y / 2.0, 0.0)
		mesh = q
	else:
		mesh = _build_model(kind)
	_models[kind] = mesh
	return mesh


static func _build_model(kind: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		Kind.BROADLEAF:
			_trunk(st, 0.08, 0.12, 0.95, Vector3.ZERO)
			var crown := Vector3(0, 1.2, 0)
			_clump(st, 0.55, crown + Vector3(0, 0.05, 0), crown)
			_clump(st, 0.4, crown + Vector3(0.38, -0.12, 0.1), crown)
			_clump(st, 0.38, crown + Vector3(-0.34, -0.1, -0.12), crown)
			_clump(st, 0.36, crown + Vector3(0.05, 0.28, -0.2), crown)
		Kind.PINE:
			_trunk(st, 0.06, 0.09, 0.5, Vector3.ZERO)
			for layer in [[0.6, 0.55, 0.75], [0.46, 1.0, 0.65], [0.3, 1.4, 0.55]]:
				_add(st, _cylinder(0.0, layer[0], layer[2], 7), Transform3D(Basis(), Vector3(0, layer[1], 0)),
						LEAF, Vector3(0, layer[1] - 0.4, 0))
		Kind.PALM:
			_add(st, _cylinder(0.05, 0.08, 1.5, 5), Transform3D(Basis(Vector3.FORWARD, 0.12), Vector3(0.08, 0.75, 0)),
					TRUNK, Vector3(0.08, 0.75, 0), true)
			var top := Vector3(0.18, 1.52, 0)
			for a in 5:
				var d := Vector3(cos(a * TAU / 5.0), 0.0, sin(a * TAU / 5.0))
				_add(st, _sphere(0.3, 0.1, 5, 2), Transform3D(Basis(), top + d * 0.32 - Vector3(0, 0.08, 0)), LEAF, top)
		Kind.ACACIA:
			_trunk(st, 0.06, 0.09, 0.95, Vector3.ZERO)
			var crown := Vector3(0, 1.0, 0)
			for o in [Vector3(0, 0, 0), Vector3(0.4, -0.03, 0.1), Vector3(-0.38, -0.02, -0.08)]:
				_add(st, _sphere(0.42, 0.22, 7, 2), Transform3D(Basis(), crown + o), LEAF, crown - Vector3(0, 0.3, 0))
		Kind.CACTUS:
			_add(st, _cylinder(0.11, 0.12, 0.9, 7), Transform3D(Basis(), Vector3(0, 0.45, 0)), LEAF, Vector3(0, 0.45, 0), true)
			_add(st, _cylinder(0.07, 0.07, 0.35, 6), Transform3D(Basis(), Vector3(0.22, 0.6, 0)), LEAF, Vector3(0.22, 0.6, 0), true)
		Kind.BUSH:
			var c := Vector3(0, 0.15, 0)
			_clump(st, 0.3, c, c)
			_clump(st, 0.22, c + Vector3(0.22, -0.04, 0.05), c)
			_clump(st, 0.2, c + Vector3(-0.2, -0.05, -0.04), c)
		Kind.MUSHROOM:
			_add(st, _cylinder(0.1, 0.13, 0.8, 6), Transform3D(Basis(), Vector3(0, 0.4, 0)), STEM, Vector3(0, 0.4, 0), true)
			_add(st, _sphere(0.55, 0.5, 8, 4), Transform3D(Basis(), Vector3(0, 0.82, 0)), LEAF, Vector3(0, 0.6, 0))
		Kind.DEAD:
			_add(st, _cylinder(0.05, 0.1, 1.1, 5), Transform3D(Basis(), Vector3(0, 0.55, 0)), BARE, Vector3(0, 0.55, 0), true)
			_add(st, _cylinder(0.02, 0.04, 0.5, 4), Transform3D(Basis(Vector3.FORWARD, 0.8), Vector3(0.18, 0.95, 0)), BARE, Vector3(0.18, 0.95, 0), true)
			_add(st, _cylinder(0.02, 0.04, 0.45, 4), Transform3D(Basis(Vector3.BACK, 0.7), Vector3(-0.15, 0.8, 0)), BARE, Vector3(-0.15, 0.8, 0), true)
		Kind.ROCK:
			var c := Vector3(0, 0.05, 0)
			_add(st, _sphere(0.42, 0.42, 6, 3), Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(1.0, 0.75, 0.9)), Vector3(0, 0.12, 0)), LEAF, c)
			_add(st, _sphere(0.25, 0.25, 5, 3), Transform3D(Basis(), Vector3(0.3, 0.05, 0.15)), LEAF, c)
	return st.commit()


static func _trunk(st: SurfaceTool, top: float, bottom: float, height: float, base: Vector3) -> void:
	var centre := base + Vector3(0, height / 2.0, 0)
	_add(st, _cylinder(top, bottom, height, 6), Transform3D(Basis(), centre), TRUNK, centre, true)


## A foliage clump: a rounded blob whose normals point away from the crown centre.
static func _clump(st: SurfaceTool, radius: float, at: Vector3, crown: Vector3) -> void:
	_add(st, _sphere(radius, radius * 1.7, 8, 5), Transform3D(Basis(), at), LEAF, crown)


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


## Appends a primitive mesh, transformed and tagged with its part. Normals point away from
## `centre` (rounded lighting); with `radial` they point away from the vertical axis through it
## (trunks, stems, cacti).
static func _add(st: SurfaceTool, mesh: PrimitiveMesh, xform: Transform3D, part: int,
		centre: Vector3, radial := false) -> void:
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for idx in indices:
		var v: Vector3 = xform * verts[idx]
		var n := v - centre
		if radial:
			n = Vector3(n.x, 0.15, n.z)
		st.set_color(Color.WHITE)
		st.set_uv(Vector2(part, 0.0))
		st.set_normal(n.normalized() if n.length() > 0.0001 else Vector3.UP)
		st.add_vertex(v)
