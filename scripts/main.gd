## Entry scene: generates a world and shows it as a flat 2D map (one texture, one texel per tile),
## with the map camera and the HUD.
extends Node2D

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const WorldMap = preload("res://scripts/render2d/world_map.gd")
const MapCamera = preload("res://scripts/ui/map_camera.gd")
const Hud = preload("res://scripts/ui/hud.gd")

const LEVEL_NAMES := ["deep sea", "shallow water", "plain", "hill", "mountain"]

var settings := WorldSettings.new()
var world: WorldData
var current_layer := "Biomes"

var _map := WorldMap.new()
var _camera := MapCamera.new()
var _hud := Hud.new()
var _dragging := false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Biomes.COLORS[Biomes.DEEP_WATER].darkened(0.4))
	add_child(_map)
	add_child(_camera)
	_camera.make_current()
	_hud.settings = settings
	_hud.generate_requested.connect(generate)
	_hud.layer_selected.connect(show_layer)
	add_child(_hud)
	generate()


func generate() -> void:
	world = WorldGenerator.generate(settings)
	_map.set_world(world)
	_map.show_layer(current_layer)
	_camera.bounds = _map.pixel_size()
	_camera.frame_all()
	_hud.set_stats(world)


func show_layer(layer: String) -> void:
	current_layer = layer
	_map.show_layer(layer)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom_at(MapCamera.ZOOM_STEP, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom_at(1.0 / MapCamera.ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_camera.pan_screen((event as InputEventMouseMotion).relative)


func _process(_delta: float) -> void:
	if world == null:
		return
	var tile := pick_tile(get_viewport().get_mouse_position())
	if tile.x < 0:
		_hud.set_hover_text("")
		return
	var i := world.index(tile.x, tile.y)
	var height_text := "%d m" % roundi(world.land_height(i) * 4000.0) if not world.is_water(i) \
			else "-%d m" % roundi(maxf(world.sea_depth(i), 0.0) * 6000.0)
	_hud.set_hover_text("(%d, %d)  %s  ·  %s  ·  height %s  ·  %d °C  ·  humidity %d%%" % [
		tile.x, tile.y, Biomes.NAMES[world.biome[i]], LEVEL_NAMES[world.level[i]], height_text,
		roundi(lerpf(-30.0, 45.0, world.temperature[i])), roundi(world.humidity[i] * 100.0)])


## Tile under a screen position, or (-1, -1).
func pick_tile(screen_pos: Vector2) -> Vector2i:
	return _map.tile_at(_camera.screen_to_world(screen_pos))
