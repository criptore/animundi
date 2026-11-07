## Entry scene: generates a world and shows it in 3D, rendered at low resolution and scaled up
## with sharp pixels (the "3D pixel art" look), with the map camera and the HUD.
extends Node

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")
const TerrainBuilder = preload("res://scripts/render3d/terrain_builder.gd")
const VegetationBuilder = preload("res://scripts/render3d/vegetation_builder.gd")
const PixelCamera = preload("res://scripts/ui/pixel_camera.gd")
const SceneStyle = preload("res://scripts/render3d/scene_style.gd")
const Hud = preload("res://scripts/ui/hud.gd")

var settings := WorldSettings.new()
var world: WorldData
var renderer := MapRenderer.new()
var current_layer := "Biomes"
## Size of one render pixel on screen.
var pixel_scale := 3

var _heights := PackedFloat32Array()
var _container := SubViewportContainer.new()
var _viewport := SubViewport.new()
var _terrain := MeshInstance3D.new()
var _inland_water := MeshInstance3D.new()
var _ocean := MeshInstance3D.new()
var _vegetation := Node3D.new()
var _camera := PixelCamera.new()
var _hud := Hud.new()
var _style := SceneStyle.new()
var _dragging := false
## Grass and flower layers, hidden when zoomed out (see GROUND_COVER_MAX_PIXEL).
var _ground_cover: Array[Node3D] = []

## Ground cover shows only when a render pixel covers less ground than this.
const GROUND_COVER_MAX_PIXEL := 0.06


func _ready() -> void:
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.stretch_shrink = pixel_scale
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_container.add_child(_viewport)

	_style.add_lighting(_viewport)
	_terrain.material_override = _style.terrain
	_inland_water.material_override = _style.water
	_ocean.material_override = _style.water
	_inland_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node in [_terrain, _inland_water, _ocean, _vegetation, _camera]:
		_viewport.add_child(node)
	_camera.current = true

	_hud.settings = settings
	_hud.generate_requested.connect(generate)
	_hud.layer_selected.connect(show_layer)
	_hud.pixel_scale_changed.connect(set_pixel_scale)
	add_child(_hud)
	generate()


func generate() -> void:
	world = WorldGenerator.generate(settings)
	_heights = TerrainBuilder.heights(world)
	_inland_water.mesh = TerrainBuilder.build_inland_water(world)
	_style.water.set_shader_parameter("heightmap", TerrainBuilder.heightmap_texture(world, _heights))
	_style.water.set_shader_parameter("map_size", Vector2(world.width, world.height))

	var ocean := PlaneMesh.new()
	ocean.size = Vector2(world.width, world.height) * 4.0
	_ocean.mesh = ocean
	_ocean.position = Vector3(world.width / 2.0, 0.0, world.height / 2.0)

	for child in _vegetation.get_children():
		child.queue_free()
	var plants := VegetationBuilder.build(world, _heights)
	_ground_cover.clear()
	for id in plants:
		var cover := VegetationBuilder.is_ground_cover(id)
		var node := _style.add_sprites(_vegetation, id, plants[id], not cover)
		if cover:
			_ground_cover.append(node)

	show_layer(current_layer)
	_camera.frame(Vector3(world.width / 2.0, 0.0, world.height / 2.0), world.height * 0.8)
	_hud.set_stats(world)


func show_layer(layer: String) -> void:
	current_layer = layer
	_terrain.mesh = TerrainBuilder.build_terrain(world, _heights, layer, renderer)
	_vegetation.visible = layer == "Biomes"


func set_pixel_scale(value: int) -> void:
	pixel_scale = value
	_container.stretch_shrink = value
	_camera.apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom_by(PixelCamera.ZOOM_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom_by(1.0 / PixelCamera.ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_camera.pan_screen((event as InputEventMouseMotion).relative, get_viewport().get_visible_rect().size.y)


func _process(_delta: float) -> void:
	if world == null:
		return
	var close := _camera.world_per_pixel() < GROUND_COVER_MAX_PIXEL
	for node in _ground_cover:
		node.visible = close
	var tile := pick_tile(get_viewport().get_mouse_position())
	if tile.x < 0:
		_hud.set_hover_text("")
		return
	var i := world.index(tile.x, tile.y)
	var height_text := "%d m" % roundi(world.land_height(i) * 4000.0) if not world.is_water(i) \
			else "-%d m" % roundi(maxf(world.sea_depth(i), 0.0) * 6000.0)
	_hud.set_hover_text("(%d, %d)  %s  ·  height %s  ·  %d °C  ·  humidity %d%%" % [
		tile.x, tile.y, Biomes.NAMES[world.biome[i]], height_text,
		roundi(lerpf(-30.0, 45.0, world.temperature[i])), roundi(world.humidity[i] * 100.0)])


## Tile under a screen position, or (-1, -1): walks the camera ray until it goes under the ground.
func pick_tile(screen_pos: Vector2) -> Vector2i:
	var p := screen_pos / float(pixel_scale)
	var origin := _camera.project_ray_origin(p)
	var dir := _camera.project_ray_normal(p)
	if dir.y >= -0.01:
		return Vector2i(-1, -1)
	var top := TerrainBuilder.HEIGHT_SCALE + 2.0
	var t := (origin.y - top) / -dir.y
	var t_end := (origin.y + TerrainBuilder.SEA_FLOOR + 2.0) / -dir.y
	while t < t_end:
		var q := origin + dir * t
		var inside := q.x >= 0.0 and q.z >= 0.0 and q.x <= world.width - 1 and q.z <= world.height - 1
		if inside and q.y <= maxf(TerrainBuilder.sample(world, _heights, q.x, q.z), 0.0):
			return Vector2i(roundi(q.x), roundi(q.z))
		t += 0.25
	return Vector2i(-1, -1)
