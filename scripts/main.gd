## Entry scene: generates a world, shows it with the map camera and the HUD.
extends Node2D

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")
const CameraController = preload("res://scripts/ui/camera_controller.gd")
const Hud = preload("res://scripts/ui/hud.gd")

const TILE := MapRenderer.TILE

var settings := WorldSettings.new()
var world: WorldData
var renderer := MapRenderer.new()
var current_layer := "Biomes"

var _map := Sprite2D.new()
var _layer := Sprite2D.new()
var _camera := CameraController.new()
var _hud := Hud.new()


func _ready() -> void:
	for sprite in [_map, _layer]:
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
	_layer.scale = Vector2(TILE, TILE)
	add_child(_camera)
	_hud.settings = settings
	_hud.generate_requested.connect(generate)
	_hud.layer_selected.connect(show_layer)
	add_child(_hud)
	generate()


func generate() -> void:
	world = WorldGenerator.generate(settings)
	_map.texture = ImageTexture.create_from_image(renderer.render_biomes(world))
	show_layer(current_layer)
	_camera.fit(Rect2(Vector2.ZERO, Vector2(world.width, world.height) * TILE))
	_hud.set_stats(world)


func show_layer(layer: String) -> void:
	current_layer = layer
	_layer.visible = layer != "Biomes"
	if _layer.visible:
		_layer.texture = ImageTexture.create_from_image(renderer.render_layer(world, layer))


func _process(_delta: float) -> void:
	if world == null:
		return
	var p := get_global_mouse_position() / TILE
	var x := floori(p.x)
	var y := floori(p.y)
	if not world.in_bounds(x, y):
		_hud.set_hover_text("")
		return
	var i := world.index(x, y)
	var height_text := "%d m" % roundi(world.land_height(i) * 4000.0) if not world.is_water(i) \
			else "-%d m" % roundi(maxf(world.sea_depth(i), 0.0) * 6000.0)
	_hud.set_hover_text("(%d, %d)  %s  ·  height %s  ·  %d °C  ·  humidity %d%%" % [
		x, y, Biomes.NAMES[world.biome[i]], height_text,
		roundi(lerpf(-30.0, 45.0, world.temperature[i])), roundi(world.humidity[i] * 100.0)])
