## Renders an asset sheet: the game's sprites standing on a meadow, drawn with the game's own look
## (low-resolution render, sun shadows, terrain and water shaders), with labels, saved as a PNG.
##   godot --path . --script res://tools/asset_sheet.gd -- <nature|peoples|creatures> <out.png>
## Needs a display (use xvfb-run on a headless machine).
extends SceneTree

const Biomes = preload("res://scripts/world/biomes.gd")
const Races = preload("res://scripts/world/races.gd")
const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")
const SceneStyle = preload("res://scripts/render3d/scene_style.gd")
const PixelCamera = preload("res://scripts/ui/pixel_camera.gd")

## Screen pixels per render pixel; character sheets use 2 so that their sprites can be shown at
## one sprite pixel per render pixel and still fit.
var PIXEL := 3
const WINDOW := Vector2i(1920, 1080)
## Everything is placed around here, inside the water shader's map so it doesn't fade to ocean.
const ORIGIN := Vector3(200, 0, 200)
const MEADOW := Color("#66b043")

var _sheet := "nature"
var _out := "user://asset_sheet.png"
var _frames := 0
var _style := SceneStyle.new()
var _viewport := SubViewport.new()
var _camera := PixelCamera.new()
var _labels: Array = []  # [text, world position, font size, colour, left-aligned]
var _min := Vector3(INF, 0, INF)
var _max := Vector3(-INF, 0, -INF)
var _title := ""
var _stylizer: MeshInstance3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_sheet = args[0]
	if args.size() > 1:
		_out = args[1]
	if _sheet != "nature":
		PIXEL = 2
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
	_style.add_lighting(_viewport, MEADOW)
	_viewport.add_child(_camera)
	_camera.current = true
	_stylizer = _style.add_stylizer(_camera, 4)
	_add_ground()

	match _sheet:
		"peoples":
			_title = "Animundi · Peoples (12 races × 4 roles)"
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
		var view_h := maxf(span.z * sin(deg_to_rad(-PixelCamera.PITCH)) + 3.5, (span.x + 3.0) / aspect) * 1.1
		if _sheet == "peoples":
			# One sprite pixel per render pixel.
			view_h = SpriteLibrary.SCALE["peoples"] * WINDOW.y / PIXEL
		_camera.frame(ORIGIN + centre + Vector3(0, 0, -0.6), view_h)
	if _frames >= 2:
		_style.update_stylizer(_stylizer, _camera, float(WINDOW.x) / WINDOW.y)
	if _frames == 4:
		_add_labels()
	if _frames == 14:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false


# ------------------------------------------------------------------------------ sheets

func _build_nature() -> void:
	_row("Trees", SpriteLibrary.list("trees"), 0.0, 3.0)
	_row("Bushes, rocks, mushrooms, cacti, grass, flowers", SpriteLibrary.list("plants"), 3.6, 3.0)
	_section("Terrain (biome ground) and water", 6.4)
	var col := 0
	var row := 0
	for b in Biomes.COUNT:
		if b == Biomes.WATER or b == Biomes.DEEP_WATER:
			continue
		var p := Vector3(col * 2.1, 0, 7.0 + row * 2.4)
		_swatch(Biomes.COLORS[b], p)
		_label(Biomes.NAMES[b], p + Vector3(0, 0, 1.15), 12)
		col += 1
		if col == 11:
			col = 0
			row += 1
	_water(Vector3(col * 2.1 + 1.0, 0, 7.0 + row * 2.4), Vector2(3.6, 1.6), -0.45)
	_label("Shallow water", Vector3(col * 2.1 + 1.0, 0, 7.0 + row * 2.4 + 1.15), 12)
	_water(Vector3((col + 2) * 2.1 + 1.0, 0, 7.0 + row * 2.4), Vector2(3.6, 1.6), -1.4)
	_label("Deep water", Vector3((col + 2) * 2.1 + 1.0, 0, 7.0 + row * 2.4 + 1.15), 12)


func _build_peoples() -> void:
	var races: Array = Races.RACES.keys()
	var dz := 1.75
	for j in Races.ROLES.size():
		var z := j * dz
		_labels.append([Races.ROLES[j], ORIGIN + Vector3(-1.6, 0, z - 0.6), 15, Color.WHITE, true])
		for n in races.size():
			var id := "peoples/%s_%s" % [races[n], Races.ROLES[j]]
			if not SpriteLibrary.exists(id):
				id = "races/%s" % races[n]  # no role sheet yet: the race portrait stands in
			_sprite(id, Vector3(n * 1.55, 0, z))
	for n in races.size():
		_label(races[n], Vector3(n * 1.55, 0, (Races.ROLES.size() - 1) * dz + 0.55), 14)


func _build_creatures() -> void:
	_row("Animals", SpriteLibrary.list("animals"), 0.0, 1.9)
	_row("Monsters", SpriteLibrary.list("monsters"), 3.0, 2.6)


# ------------------------------------------------------------------------------ helpers

func _row(title: String, ids: PackedStringArray, z: float, spacing: float) -> void:
	_section(title, z)
	for n in ids.size():
		var p := Vector3(n * spacing, 0, z)
		_sprite(ids[n], p)
		_label(ids[n].get_slice("/", 1).replace("_", " "), p + Vector3(0, 0, 0.55))


func _sprite(id: String, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = SpriteLibrary.mesh(id)
	mi.material_override = _style.sprite(id)
	mi.transform = Transform3D(SpriteLibrary.basis(), ORIGIN + at)
	_viewport.add_child(mi)
	_track(at)


func _add_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 400.0
	for v in [Vector3(-s, 0, -s), Vector3(s, 0, -s), Vector3(-s, 0, s), Vector3(s, 0, -s), Vector3(s, 0, s), Vector3(-s, 0, s)]:
		st.set_color(MEADOW.srgb_to_linear())
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = _style.terrain
	_viewport.add_child(ground)


func _track(p: Vector3) -> void:
	_min = Vector3(minf(_min.x, p.x), 0, minf(_min.z, p.z))
	_max = Vector3(maxf(_max.x, p.x), 0, maxf(_max.z, p.z))


func _swatch(color: Color, at: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := Vector3(0.85, 0, 0.8)
	var y := Vector3(0, 0.08, 0)
	for v in [Vector3(-h.x, 0, -h.z), Vector3(h.x, 0, -h.z), Vector3(-h.x, 0, h.z), Vector3(h.x, 0, -h.z), Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z)]:
		st.set_color(color.srgb_to_linear())
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
	_labels.append([text, ORIGIN + at, font_size, Color.WHITE, false])


func _section(text: String, z: float) -> void:
	_labels.append([text, ORIGIN + Vector3(-1.6, 0, z - 2.4), 18, Color("#fff4c8"), true])


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
		label.position = screen - (Vector2.ZERO if l[4] else Vector2(w / 2.0, 0))
		layer.add_child(label)
	var title := Label.new()
	title.text = _title
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color("#24301c"))
	title.add_theme_constant_override("outline_size", 6)
	title.position = Vector2(24, 16)
	layer.add_child(title)
