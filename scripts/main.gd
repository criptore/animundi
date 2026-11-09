## Entry scene: generates a world and shows it as a flat 2D map (one texture, one texel per tile),
## with the map camera and the HUD.
extends Node2D

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const WorldData = preload("res://scripts/world/world_data.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const WorldMap = preload("res://scripts/render2d/world_map.gd")
const MapCamera = preload("res://scripts/ui/map_camera.gd")
const Flora = preload("res://scripts/world/flora.gd")
## The C# simulation core (sim/): creatures, plants, seasons, fire, and their drawing.
const SimulationScript = preload("res://sim/Simulation.cs")
const Hud = preload("res://scripts/ui/hud.gd")

## Animals placed on a new world: one per this many tiles.
const TILES_PER_ANIMAL := 300

const LEVEL_NAMES := ["deep sea", "shallow water", "plain", "hill", "mountain"]

var settings := WorldSettings.new()
var world: WorldData
var current_layer := "Biomes"

var _map := WorldMap.new()
## Plants and creatures, simulated and drawn by C#.
var _sim: Node2D = SimulationScript.new()
var _stats_frames := 0
var _camera := MapCamera.new()
var _hud := Hud.new()


func _ready() -> void:
	RenderingServer.set_default_clear_color(Biomes.COLORS[Biomes.DEEP_WATER].darkened(0.4))
	add_child(_map)
	add_child(_sim)
	add_child(_camera)
	_camera.make_current()
	_hud.settings = settings
	_hud.generate_requested.connect(generate)
	_hud.layer_selected.connect(show_layer)
	_hud.spawn_requested.connect(spawn_animals)
	_hud.speed_selected.connect(func(v): _sim.SetTimeScale(v))
	_hud.start_requested.connect(start_peoples)
	add_child(_hud)
	generate()


func generate() -> void:
	world = WorldGenerator.generate(settings)
	_map.set_world(world)
	_map.show_layer(current_layer)
	_sim.Start(world, PackedStringArray(Biomes.NAMES))
	_place_flora()
	_sim.SpawnNatural(world.size() / TILES_PER_ANIMAL)
	_camera.bounds = _map.pixel_size()
	_camera.frame_all()
	_hud.set_stats(world)
	_hud.clear_events()
	# The world waits while the player chooses its peoples.
	_sim.SetTimeScale(0.0)
	_hud.show_setup()


## Brings the chosen peoples into the world and lets time run.
func start_peoples(races: PackedStringArray, per_village: int) -> void:
	_sim.StartPeoples(races, per_village)
	_sim.SetTimeScale(1.0)


func show_layer(layer: String) -> void:
	current_layer = layer
	_map.show_layer(layer)
	_sim.SetLifeVisible(layer == "Biomes")


func _unhandled_input(event: InputEvent) -> void:
	if _camera.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F:
		# Test tool, not a god power yet (powers come once the simulation runs on its own): set
		# fire where the mouse points.
		var tile := pick_tile(get_viewport().get_mouse_position())
		if tile.x >= 0:
			_sim.Ignite(tile.x + 0.5, tile.y + 0.5, 1.5)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if world == null:
		return
	_sim.SetZoom(_camera.zoom.x)
	_map.set_scorch(_sim.TakeScorchChanges())
	_map.set_frost(_sim.Coldness())
	for e in _sim.TakeEvents():
		_hud.add_event(e)
	_stats_frames += 1
	if _stats_frames >= 30:
		_stats_frames = 0
		_hud.set_sim_stats(_sim.UnitCount(), _sim.TakeStepMs(), Engine.get_frames_per_second())
		var speed: float = _sim.GetTimeScale()
		_hud.set_time("Year %d · %s%s" % [_sim.Year(), _sim.SeasonName(), "  (paused)" if speed == 0.0 else ""])
		_hud.set_sprite_count(_sim.PlantCount())
		_hud.set_populations(_sim.PopulationTable())
		_hud.set_villages(_sim.VillageTable())
	_update_map_labels()
	var mouse := get_viewport().get_mouse_position()
	# A creature under the mouse: who it is.
	var at := _camera.screen_to_world(mouse) / WorldMap.TILE
	var unit: int = _sim.UnitAt(at.x, at.y, 0.9)
	if unit >= 0:
		_hud.set_hover_text(_sim.UnitInfo(unit))
		return
	var tile := pick_tile(mouse)
	if tile.x < 0:
		_hud.set_hover_text("")
		return
	var i := world.index(tile.x, tile.y)
	var height_text := "%d m" % roundi(world.land_height(i) * 4000.0) if not world.is_water(i) \
			else "-%d m" % roundi(maxf(world.sea_depth(i), 0.0) * 6000.0)
	_hud.set_hover_text("(%d, %d)  %s  ·  %s  ·  height %s  ·  %d °C  ·  humidity %d%%" % [
		tile.x, tile.y, Biomes.NAMES[world.biome[i]], LEVEL_NAMES[world.level[i]], height_text,
		roundi(lerpf(-30.0, 45.0, world.temperature[i])), roundi(world.humidity[i] * 100.0)])


## Village names over their bonfires, when zoomed in enough to read them.
func _update_map_labels() -> void:
	var labels := []
	if _camera.zoom.x >= 0.8 and current_layer == "Biomes":
		var view := get_viewport().get_visible_rect().size
		for v in _sim.VillageTable():
			var p := (Vector2(v.x + 0.5, v.y) * WorldMap.TILE - _camera.position) * _camera.zoom.x + view / 2.0
			if Rect2(Vector2.ZERO, view).has_point(p):
				labels.append([v.name, p])
	_hud.set_map_labels(labels)


## Adds `count` wandering animals of every species, spread over their biomes.
func spawn_animals(count: int) -> void:
	_sim.SpawnNatural(count)


## Scatters the world's plants (scripts/world/flora.gd) and hands them to the simulation, which
## makes them grow, spread, burn and grow back.
func _place_flora() -> void:
	var flora := Flora.place(world)
	_sim.LoadPlants(flora.id, flora.pos, flora.flip, flora.scale)


## Tile under a screen position, or (-1, -1).
func pick_tile(screen_pos: Vector2) -> Vector2i:
	return _map.tile_at(_camera.screen_to_world(screen_pos))
