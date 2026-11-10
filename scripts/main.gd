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
const BrushCursor = preload("res://scripts/ui/brush_cursor.gd")

## Animals placed on a new world: one per this many tiles.
const TILES_PER_ANIMAL := 300

const LEVEL_NAMES := ["deep sea", "shallow water", "plain", "hill", "mountain"]

## Whether the "go to year" mode is running (to show the pause once it ends).
var _going := false
var settings := WorldSettings.new()
var world: WorldData
var current_layer := "Biomes"

var _map := WorldMap.new()
## Plants and creatures, simulated and drawn by C#.
var _sim: Node2D = SimulationScript.new()
var _stats_frames := 0
var _camera := MapCamera.new()
var _hud := Hud.new()
## God powers (scripts/ui/power_bar.gd picks, sim/Powers.cs acts).
var _brush := BrushCursor.new()
## Left button held with a power: the tile last acted on (drag powers act once per tile entered).
var _stroking := false
var _stroke_tile := Vector2i(-1, -1)
## Where the left button went down while inspecting (a click inspects, a drag pans).
var _press_at := Vector2(-1, -1)
## First kingdom clicked for a whisper (war, peace, alliance), or -1.
var _whisper_from := -1
## What the inspector follows: a unit or a village, or -1.
var _pinned_unit := -1
var _pinned_village := -1
## Whether the camera follows what the inspector shows.
var _following := false
## People a settled village starts with.
const SETTLERS := 10


func _ready() -> void:
	RenderingServer.set_default_clear_color(Biomes.COLORS[Biomes.DEEP_WATER].darkened(0.4))
	add_child(_map)
	add_child(_sim)
	add_child(_brush)
	add_child(_camera)
	_camera.make_current()
	_hud.settings = settings
	_hud.generate_requested.connect(generate)
	_hud.layer_selected.connect(show_layer)
	_hud.spawn_requested.connect(spawn_animals)
	_hud.speed_selected.connect(func(v): _sim.SetTimeScale(v))
	_hud.go_to_year_requested.connect(func(year, seconds): _going = _sim.GoToYear(year, seconds))
	_hud.start_requested.connect(start_peoples)
	add_child(_hud)
	_hud.powers.power_changed.connect(func(_power, _arg):
		_whisper_from = -1
		_stroking = false
		_hud.notice(_hud.powers.hint(), 4.0))
	_hud.laws.law_toggled.connect(func(law, on): _sim.SetLaw(law, on))
	_hud.inspector.closed.connect(func():
		_pinned_unit = -1
		_pinned_village = -1
		_following = false)
	_hud.inspector.follow_toggled.connect(func(on): _following = on)
	_hud.focus_requested.connect(func(tile):
		_camera.look_at_point((tile + Vector2(0.5, 0.5)) * WorldMap.TILE, maxf(_camera.zoom.x, 2.0)))
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
	# A new world: nothing of the old one is followed, the powers know its creatures and laws.
	_hud.inspector.close()
	_whisper_from = -1
	_hud.powers.setup(_sim.SpawnableSpecies(), _sim.RaceIds(), _sim.PaintableBiomes())
	_hud.laws.set_laws(_sim.LawTable())
	# The world waits while the player chooses its peoples.
	_sim.SetTimeScale(0.0)
	_hud.show_setup()


## Brings the chosen peoples into the world and lets time run.
func start_peoples(races: PackedStringArray, per_village: int, ai := false) -> void:
	_sim.StartPeoples(races, per_village)
	_sim.SetTimeScale(1.0)
	# The model built into the game (0.5 AI minds): found next to the game or in the player's data,
	# else downloaded once in the background. The procedural inventor invents until it is ready.
	if ai:
		_sim.StartMind(ProjectSettings.get_setting("animundi/ai/model_file", ""),
				ProjectSettings.get_setting("animundi/ai/model_url", ""), true)


func show_layer(layer: String) -> void:
	current_layer = layer
	_map.show_layer(layer)
	_sim.SetLifeVisible(layer == "Biomes")


func _unhandled_input(event: InputEvent) -> void:
	if world != null and not _hud.blocking() and _power_input(event):
		get_viewport().set_input_as_handled()
		return
	if _camera.handle_input(event):
		get_viewport().set_input_as_handled()


## The left button with a power chosen acts on the world (the other buttons, the wheel and the
## trackpad still move the camera); while inspecting, a click inspects and a drag pans.
## Returns true when the event was used.
func _power_input(event: InputEvent) -> bool:
	var powers := _hud.powers
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if powers.power == "inspect":
			if mb.pressed:
				_press_at = mb.position
			elif _press_at.distance_to(mb.position) < 5.0:
				_inspect(mb.position)
			return false
		_stroking = mb.pressed
		_stroke_tile = Vector2i(-1, -1)
		if mb.pressed:
			_use_power(mb.position)
		return true
	var motion := event as InputEventMouseMotion
	if motion != null and _stroking:
		# The button was let go over the interface: the stroke is over.
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			_stroking = false
			return false
		if powers.drags():
			_use_power(motion.position)
		return true
	return false


## Applies the chosen power under a screen position.
func _use_power(screen_pos: Vector2) -> void:
	var powers := _hud.powers
	var at := _camera.screen_to_world(screen_pos) / WorldMap.TILE
	var tile := Vector2i(floori(at.x), floori(at.y))
	if tile == _stroke_tile:
		return
	_stroke_tile = tile
	var r: float = powers.radius()
	match powers.power:
		"fire":
			_sim.PowerFire(at.x, at.y, r)
		"rain":
			_sim.PowerRain(at.x, at.y, r)
		"smite":
			_sim.PowerSmite(at.x, at.y, r)
		"bless":
			_sim.PowerBless(at.x, at.y, r)
		"biome":
			_sim.PowerBiome(powers.arg, at.x, at.y, r)
		"lightning":
			_sim.PowerLightning(at.x, at.y)
		"meteor":
			_sim.PowerMeteor(at.x, at.y, r)
		"spawn":
			if _sim.PowerSpawn(powers.arg, at.x, at.y, powers.brush) == 0:
				_hud.notice("Creatures need land to stand on.")
		"settle":
			if _sim.PowerSettle(powers.arg, at.x, at.y, SETTLERS) < 0:
				_hud.notice("A village needs free land: not the sea, not another village's ground.")
		"war", "peace", "alliance":
			_whisper(powers.power, _sim.KingdomAt(at.x, at.y))


## Whispers take two clicks: the kingdom that acts, then the other one.
func _whisper(kind: String, kingdom: int) -> void:
	if kingdom < 0:
		_hud.notice("No kingdom owns this land.")
		return
	var names := {}
	for k in _sim.KingdomTable():
		names[k.index] = k.name
	if _whisper_from < 0:
		_whisper_from = kingdom
		_hud.notice("%s listens… now click the other kingdom's land." % names.get(kingdom, "The kingdom"), 6.0)
		return
	var from := _whisper_from
	_whisper_from = -1
	if not _sim.PowerWhisper(kind, from, kingdom):
		_hud.notice({"war": "They are already at war, or it is the same kingdom.",
				"peace": "They are not at war.", "alliance": "They are at war, already allies, or the same kingdom."}[kind])


## Pins the creature under a screen position in the inspector, else the village owning the land.
func _inspect(screen_pos: Vector2) -> void:
	var at := _camera.screen_to_world(screen_pos) / WorldMap.TILE
	_following = false
	_pinned_unit = _sim.UnitAt(at.x, at.y, 0.9)
	_pinned_village = _sim.VillageAt(at.x, at.y) if _pinned_unit < 0 else -1
	if _pinned_unit < 0 and _pinned_village < 0:
		_hud.inspector.close()
	_refresh_inspector()


func _refresh_inspector() -> void:
	if _pinned_unit >= 0:
		if _sim.UnitAlive(_pinned_unit):
			_hud.inspector.show_unit(_sim.UnitName(_pinned_unit), _sim.UnitInfo(_pinned_unit))
		else:
			_hud.inspector.close()
	elif _pinned_village >= 0:
		_hud.inspector.show_village(_sim.VillageInfo(_pinned_village))


func _process(_delta: float) -> void:
	if world == null:
		return
	_sim.SetZoom(_camera.zoom.x)
	_sim.SetView(_camera.position, get_viewport().get_visible_rect().size / _camera.zoom.x)
	_map.set_scorch(_sim.TakeScorchChanges())
	_map.set_overlay(_sim.TakeOverlayChanges())
	_map.set_frost(_sim.Coldness())
	# Land repainted by the biome brush.
	var repainted: PackedInt32Array = _sim.TakeBiomeChanges()
	if not repainted.is_empty():
		var tiles := PackedInt32Array()
		for k in range(0, repainted.size(), 2):
			world.biome[repainted[k]] = repainted[k + 1]
			tiles.append(repainted[k])
		_map.update_tiles(tiles)
	# The brush follows the mouse while a power is chosen.
	var pointer := get_viewport().get_mouse_position()
	_brush.visible = _hud.powers.power != "inspect" and not _hud.blocking()
	_brush.position = _camera.screen_to_world(pointer)
	_brush.zoom = _camera.zoom.x
	_brush.radius = (_hud.powers.radius() if _hud.powers.power in ["fire", "rain", "smite", "bless", "biome", "meteor"] else 0.6) * WorldMap.TILE
	var tagged: PackedStringArray = _sim.TakeTaggedEvents()
	for k in range(0, tagged.size(), 2):
		_hud.add_event(tagged[k + 1], tagged[k])
	_stats_frames += 1
	if _stats_frames >= 30:
		_stats_frames = 0
		_hud.set_sim_stats(_sim.UnitCount(), _sim.TakeStepMs(), Engine.get_frames_per_second())
		var speed: float = _sim.GetTimeScale()
		var target: int = _sim.TargetYear
		if target > 0:
			var left: float = _sim.GoToSecondsLeft()
			_hud.set_time("Year %d · → %d (%d%%%s)" % [_sim.Year(), target, int(_sim.GoToProgress() * 100.0),
					", %d:%02d left" % [int(left) / 60, int(left) % 60] if left >= 0.0 else ""])
		else:
			if _going:
				_going = false
				_hud.show_speed(speed)
			_hud.set_time("Year %d · %s%s" % [_sim.Year(), _sim.SeasonName(), "  (paused)" if speed == 0.0 else ""])
		_hud.set_season(_sim.Season())
		var people: int = _sim.PeopleCount()
		_hud.set_counts(people, _sim.VillageCount(), _sim.KingdomCount(), _sim.UnitCount() - people)
		_hud.set_sprite_count(_sim.PlantCount())
		_hud.set_populations(_sim.PopulationTable())
		_hud.set_villages(_sim.VillageTable())
		_hud.set_kingdoms(_sim.KingdomTable())
		_hud.set_plans(_sim.PlanTable())
		_hud.set_inventions(_sim.InventionTable())
		_hud.set_mind(_sim.MindStatus())
		_refresh_inspector()
	# The camera stays on the creature or the village the player follows.
	if _following:
		if _pinned_unit >= 0 and _sim.UnitAlive(_pinned_unit):
			_camera.look_at_point(_sim.UnitPosition(_pinned_unit) * WorldMap.TILE, _camera.zoom.x)
		elif _pinned_village >= 0:
			var followed: Dictionary = _sim.VillageInfo(_pinned_village)
			if not followed.is_empty():
				_camera.look_at_point(Vector2(followed.x + 0.5, followed.y + 0.5) * WorldMap.TILE, _camera.zoom.x)
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
		for v in _sim.VillageLabels():
			var p := (Vector2(v.x + 0.5, v.y) * WorldMap.TILE - _camera.position) * _camera.zoom.x + view / 2.0
			if Rect2(Vector2.ZERO, view).has_point(p):
				# The rank (town, city), a crown on capitals, a siege under way.
				var text: String = v.name
				if v.capital:
					text = "♛ " + text
				if v.rank == "town" or v.rank == "city":
					text += " (%s)" % v.rank
				if v.siege > 0.0:
					text += "  ⚔ siege %d%%" % int(v.siege * 100.0)
				labels.append([text, p])
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
