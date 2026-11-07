## Renders an asset sheet: every 3D model of the game laid out on a meadow, drawn with the game's
## own look (low-resolution render, shaders, outlines, shadows), with labels, saved as a PNG.
##   godot --path . --script res://tools/asset_sheet.gd -- <nature|peoples|creatures> <out.png>
## Needs a display (use xvfb-run on a headless machine).
extends SceneTree

const Biomes = preload("res://scripts/world/biomes.gd")
const Races = preload("res://scripts/world/races.gd")
const VegetationBuilder = preload("res://scripts/render3d/vegetation_builder.gd")
const CreatureBuilder = preload("res://scripts/render3d/creature_builder.gd")
const SceneStyle = preload("res://scripts/render3d/scene_style.gd")
const PixelCamera = preload("res://scripts/ui/pixel_camera.gd")
const Main = preload("res://scripts/main.gd")

const PIXEL := 3
const WINDOW := Vector2i(1920, 1080)
## Everything is placed around here, inside the water shader's map so it doesn't fade to ocean.
const ORIGIN := Vector3(200, 0, 200)

var _sheet := "nature"
var _out := "user://asset_sheet.png"
var _frames := 0
var _style := SceneStyle.new()
var _viewport := SubViewport.new()
var _camera := PixelCamera.new()
var _labels: Array = []  # [text, world position, font size, colour]
var _min := Vector3(INF, 0, INF)
var _max := Vector3(-INF, 0, -INF)
var _title := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_sheet = args[0]
	if args.size() > 1:
		_out = args[1]
	DisplayServer.window_set_size(WINDOW)
	root.size = WINDOW

	var container := SubViewportContainer.new()
	container.size = WINDOW
	container.stretch = true
	container.stretch_shrink = PIXEL
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(container)
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	container.add_child(_viewport)
	_style.add_lighting(_viewport, Color("#8fbf58"))
	_viewport.add_child(_camera)
	_camera.current = true
	_add_ground()

	match _sheet:
		"peoples":
			_title = "Animundi · Peoples (13 races × 4 roles)"
			_build_peoples()
		"creatures":
			_title = "Animundi · Animals and monsters"
			_build_creatures()
		_:
			_title = "Animundi · Nature, terrain and water"
			_build_nature()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var centre := (_min + _max) / 2.0
		var span := _max - _min
		var aspect := float(WINDOW.x) / WINDOW.y
		var view_h := maxf(span.z * sin(deg_to_rad(42.0)) + 3.0, (span.x + 2.0) / aspect) * 1.12
		_camera.frame(ORIGIN + centre + Vector3(0, 0, -0.4), view_h)
	if _frames == 4:
		_style.update_outline(_camera.world_per_pixel())
		_add_labels()
	if _frames == 14:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false


# ------------------------------------------------------------------------------ sheets

func _build_nature() -> void:
	var K := VegetationBuilder.Kind
	var trees := [
		["Oak", K.BROADLEAF, "#7cb85c"], ["Autumn oak", K.BROADLEAF, "#e8984a"], ["Red oak", K.BROADLEAF, "#d8704a"],
		["Golden oak", K.BROADLEAF, "#ecc05a"], ["Jungle tree", K.BROADLEAF, "#6ab05a"], ["Swamp tree", K.BROADLEAF, "#8a9c5c"],
		["Pine", K.PINE, "#5a8c6c"], ["Snowy pine", K.PINE, "#e8eef2"], ["Palm", K.PALM, "#78bc60"],
		["Acacia", K.ACACIA, "#b0b464"], ["Dead tree", K.DEAD, "#6e4f86"],
	]
	_section("Trees", 0.0)
	for n in trees.size():
		var t: Array = trees[n]
		_plant(t[1], Color(t[2]), Vector3(n * 2.3, 0, 0.0), 1.6)
		_label(t[0], Vector3(n * 2.3, 0, 0.9))

	_section("Bushes, rocks, cacti, mushrooms, grass, flowers", 3.4)
	var small := [
		["Bush", K.BUSH, "#7cb85c"], ["Jungle bush", K.BUSH, "#6ab05a"], ["Rock", K.ROCK, "#c8c8cc"],
		["Boulder", K.ROCK, "#b8b6b0"], ["Cactus", K.CACTUS, "#7cb064"], ["Red mushroom", K.MUSHROOM, "#e2786a"],
		["Pink mushroom", K.MUSHROOM, "#eea0bc"], ["Purple mushroom", K.MUSHROOM, "#bb92d8"],
	]
	for n in small.size():
		var t: Array = small[n]
		var s := 2.4 if t[0] == "Boulder" else 1.6
		_plant(t[1], Color(t[2]), Vector3(n * 2.3, 0, 3.4), s)
		_label(t[0], Vector3(n * 2.3, 0, 4.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 18:
		_plant(K.GRASS, Color("#98c460"), Vector3(8 * 2.3 + rng.randf_range(-0.8, 0.8), 0, 3.4 + rng.randf_range(-0.5, 0.5)), 1.6)
	_label("Grass", Vector3(8 * 2.3, 0, 4.2))
	for k in 14:
		var c: Color = VegetationBuilder.FLOWERS[k % VegetationBuilder.FLOWERS.size()]
		_plant(K.FLOWER, c, Vector3(9 * 2.3 + rng.randf_range(-0.8, 0.8), 0, 3.4 + rng.randf_range(-0.5, 0.5)), 1.6)
	_label("Flowers", Vector3(9 * 2.3, 0, 4.2))

	_section("Terrain (biome ground) and water", 6.6)
	var row := 0
	var col := 0
	for b in Biomes.COUNT:
		if Biomes.is_water_biome(b) and b != Biomes.ICE:
			continue
		var p := Vector3(col * 2.1, 0, 6.8 + row * 2.4)
		_swatch(Biomes.COLORS[b], p)
		_label(Biomes.NAMES[b], p + Vector3(0, 0, 1.15), 12)
		col += 1
		if col == 10:
			col = 0
			row += 1
	_water(Vector3(col * 2.1 + 1.0, 0, 6.8 + row * 2.4), Vector2(3.6, 1.6), -0.4)
	_label("Shallow water", Vector3(col * 2.1 + 1.0, 0, 6.8 + row * 2.4 + 1.15), 12)
	_water(Vector3((col + 2) * 2.1 + 1.0, 0, 6.8 + row * 2.4), Vector2(3.6, 1.6), -6.0)
	_label("Deep water", Vector3((col + 2) * 2.1 + 1.0, 0, 6.8 + row * 2.4 + 1.15), 12)


func _build_peoples() -> void:
	var races: Array = Races.RACES.keys()
	for j in Races.ROLES.size():
		var z := j * 2.1
		_label(Races.ROLES[j], Vector3(-1.9, 0, z + 0.2), 15)
		for n in races.size():
			var p := Vector3(n * 1.7, 0, z)
			_mesh(CreatureBuilder.person(races[n], Races.ROLES[j]), p, 1.35)
	for n in races.size():
		_label(races[n], Vector3(n * 1.7, 0, Races.ROLES.size() * 2.1 - 0.9), 14)


func _build_creatures() -> void:
	_section("Animals", 0.0)
	var animals: Array = CreatureBuilder.ANIMALS
	for n in animals.size():
		var p := Vector3(n * 2.0, 0, 0.0)
		_mesh(CreatureBuilder.animal(animals[n]), p, 1.6)
		_label(animals[n], p + Vector3(0, 0, 0.9))
	_section("Monsters", 3.4)
	var monsters: Array = CreatureBuilder.MONSTERS
	for n in monsters.size():
		var p := Vector3(n * 2.6, 0, 3.4)
		_mesh(CreatureBuilder.monster(monsters[n]), p, 1.6 if monsters[n] != "Dragon" else 1.9)
		_label(monsters[n], p + Vector3(0, 0, 1.0))


# ------------------------------------------------------------------------------ helpers

func _add_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color("#8fbf58")
	var s := 400.0
	for v in [Vector3(-s, 0, -s), Vector3(s, 0, -s), Vector3(-s, 0, s), Vector3(s, 0, -s), Vector3(s, 0, s), Vector3(-s, 0, s)]:
		st.set_color(c)
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = _style.terrain
	_viewport.add_child(ground)


func _track(p: Vector3) -> void:
	_min = Vector3(minf(_min.x, p.x), 0, minf(_min.z, p.z))
	_max = Vector3(maxf(_max.x, p.x), 0, maxf(_max.z, p.z))


func _plant(kind: int, color: Color, at: Vector3, scale: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = VegetationBuilder.model(kind)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * scale), ORIGIN + at))
	mm.set_instance_color(0, color)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Main.material_for(_style, kind)
	if VegetationBuilder.is_ground_cover(kind):
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewport.add_child(mmi)
	_track(at)


func _mesh(mesh: Mesh, at: Vector3, scale: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _style.solid
	mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * scale), ORIGIN + at)
	_viewport.add_child(mi)
	_track(at)


func _swatch(color: Color, at: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := color
	var h := Vector3(0.85, 0, 0.8)
	var y := Vector3(0, 0.08, 0)
	for v in [Vector3(-h.x, 0, -h.z), Vector3(h.x, 0, -h.z), Vector3(-h.x, 0, h.z), Vector3(h.x, 0, -h.z), Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z)]:
		st.set_color(c)
		st.set_normal(Vector3.UP)
		st.add_vertex(v + y)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _style.terrain
	mi.position = ORIGIN + at
	_viewport.add_child(mi)
	_track(at)


## A water patch whose ground lies `floor_y` under it (shallow or deep colour).
func _water(at: Vector3, size: Vector2, floor_y: float) -> void:
	var mat := _style.water.duplicate() as ShaderMaterial
	var img := Image.create(1, 1, false, Image.FORMAT_RF)
	img.set_pixel(0, 0, Color(floor_y, 0, 0))
	mat.set_shader_parameter("heightmap", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("map_size", Vector2(400, 400))
	var plane := PlaneMesh.new()
	plane.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = ORIGIN + at + Vector3(0, 0.1, 0)
	_viewport.add_child(mi)
	_track(at)


func _label(text: String, at: Vector3, font_size := 14) -> void:
	_labels.append([text, ORIGIN + at, font_size, Color.WHITE])


func _section(text: String, z: float) -> void:
	_labels.append([text, ORIGIN + Vector3(-2.2, 0, z - 1.5), 18, Color("#fff4c8"), true])


func _add_labels() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	for l in _labels:
		var label := Label.new()
		label.text = l[0]
		label.add_theme_font_size_override("font_size", l[2])
		label.add_theme_color_override("font_color", l[3])
		label.add_theme_color_override("font_outline_color", Color("#24301c"))
		label.add_theme_constant_override("outline_size", 5)
		var screen := _camera.unproject_position(l[1]) * PIXEL
		var w := label.get_minimum_size().x
		label.position = screen - (Vector2(0, 0) if l.size() > 4 else Vector2(w / 2.0, 0))
		layer.add_child(label)
	var title := Label.new()
	title.text = _title
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color("#24301c"))
	title.add_theme_constant_override("outline_size", 6)
	title.position = Vector2(24, 16)
	layer.add_child(title)
