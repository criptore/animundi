## Entry scene: generates a world and shows it with the HUD, in the tilt view (the world seen at an
## angle, scripts/render_tilt/tilt_view.gd) or as a flat 2D map (one texture, one texel per tile).
## V goes from one to the other, looking at the same place.
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
const TiltView = preload("res://scripts/render_tilt/tilt_view.gd")
const StampStore = preload("res://scripts/world/stamp_store.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")
const WorldStore = preload("res://scripts/world/world_store.gd")
const Soundscape = preload("res://scripts/audio/soundscape.gd")
const Achievements = preload("res://scripts/world/achievements.gd")
const Weather = preload("res://scripts/render2d/weather.gd")

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
## The tilt view and whether it is the one shown (set_tilt); its brush is drawn on the screen.
var _tilt := TiltView.new()
var tilt_on := true
var _tilt_brush := BrushCursor.new()
## Left button held with a power: the tile last acted on (drag powers act once per tile entered).
var _stroking := false
var _stroke_tile := Vector2i(-1, -1)
## Where the left button went down while inspecting (a click inspects, a drag pans).
var _press_at := Vector2(-1, -1)
## First kingdom clicked for a whisper (war, peace, alliance, convert), or -1.
var _whisper_from := -1
## What the inspector follows: a unit or a village, or -1.
var _pinned_unit := -1
var _pinned_village := -1
## Whether the camera follows what the inspector shows.
var _following := false
## People a settled village starts with.
const SETTLERS := 10
## Where mods live (docs/MODS.md); the simulation reads their data (sim/AssetLibrary.cs).
const MODS_DIR := "user://mods"
## The light of the mood of the world over the flat map (sim/Eras.cs).
var _world_tint := CanvasModulate.new()
## Another card pinned in the inspector (0.9): kind (kingdom, species, spirit, invention) and id.
var _pinned_card := ["", null]
## Lines between the capitals of kingdoms at war, over the flat map's Wars layer.
var _war_lines := Node2D.new()
var _stats_rounds := 0
## The world is saved in the autosave slot every ten years (settings).
var autosave := true
## Sound effects, the music and the ambience (1.0), all made by the game.
var sound := Soundscape.new()
## The creatures and villages the player follows: [{kind, id, name, alive}] (1.0).
var _favourites: Array = []
## Settings of 1.0: pause on great events, shake the screen, weather over it.
var pause_on_events := false
var shake := true
var weather := Weather.new()
var _shake_left := 0.0
var _shake_strength := 0.0
## The first click of the Wind power: where the wind comes from (or none).
var _wind_from := Vector2(-1, -1)
## Achievements won in any world (1.0).
var achievements := Achievements.new()
## The sound of each power when it is used.
const POWER_SOUNDS := {"fire": "fire", "wildfire": "fire", "lightning": "lightning", "rain": "rain", "meteor": "boom", "nuke": "bomb",
		"earthquake": "quake", "eruption": "quake", "raise": "land", "lower": "land", "water": "rain", "stamp": "land", "tornado": "wind",
		"blizzard": "wind", "drought": "wind", "flood": "rain", "bless": "bless", "heal": "bless", "seeds": "bless", "miracle": "miracle",
		"enlighten": "miracle", "inspire": "miracle", "plague": "sick", "curse": "curse", "madness": "curse", "resurrect": "curse",
		"dark_age": "curse", "forget_culture": "curse", "forget_faith": "curse", "war": "drums", "smite": "lightning", "era": "chime"}
var _autosaved_year := 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Biomes.COLORS[Biomes.DEEP_WATER].darkened(0.4))
	add_child(_map)
	add_child(sound)
	add_child(weather)
	add_child(_world_tint)
	add_child(_sim)
	add_child(_brush)
	add_child(_camera)
	_camera.make_current()
	add_child(_tilt)
	var over := CanvasLayer.new()
	over.layer = 0
	over.add_child(_tilt_brush)
	add_child(over)
	_hud.tilt_toggled.connect(set_tilt)
	_hud.hour_requested.connect(next_hour)
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
		_pinned_card = ["", null]
		_following = false)
	_hud.inspector.follow_toggled.connect(func(on): _following = on)
	_hud.focus_requested.connect(func(tile):
		_look_at(tile + Vector2(0.5, 0.5), 2.0))
	_hud.card_requested.connect(show_card)
	_hud.saves.save_requested.connect(func(slot):
		var error := save_world(slot)
		_hud.notice("The world is kept." if error == "" else "The world could not be saved: %s" % error)
		_hud.saves.refresh())
	_hud.saves.load_requested.connect(func(slot):
		var error := load_world(slot)
		if error != "":
			_hud.notice("That world could not be loaded: %s" % error, 5.0))
	_hud._settings_window.autosave_toggled.connect(func(on): autosave = on)
	_hud._settings_window.volume_changed.connect(func(bus, v): sound.set_volume(bus, v))
	_hud._settings_window.pause_on_events_toggled.connect(func(on): pause_on_events = on)
	_hud._settings_window.shake_toggled.connect(func(on): shake = on)
	_hud._settings_window.weather_toggled.connect(func(on):
		weather.enabled = on
		weather.set_weather(""))
	_hud.achievements_requested.connect(func(): _hud.achievements.show_list(achievements.list, achievements.won))
	_hud.scenarios_requested.connect(func(): _hud.scenarios.show_list(scenarios()))
	_hud.scenarios.scenario_chosen.connect(start_scenario)
	_hud.inspector.action_requested.connect(_inspector_action)
	_hud.favourites_requested.connect(func(): _hud.favourites.show_list(_favourite_rows()))
	_hud.favourites.show_requested.connect(func(kind, id):
		if kind == "unit":
			_pinned_village = -1
			_pinned_card = ["", null]
			_pinned_unit = id
			_look_at(_sim.UnitPosition(id), 3.0)
		else:
			_pinned_unit = -1
			_pinned_card = ["", null]
			_pinned_village = id
			var v: Dictionary = _sim.VillageInfo(id)
			if not v.is_empty():
				_look_at(Vector2(v.x + 0.5, v.y + 0.5), 2.0)
		_hud.favourites.close()
		_refresh_inspector())
	_hud.favourites.remove_requested.connect(func(kind, id):
		_favourites = _favourites.filter(func(f): return not (f.kind == kind and f.id == id))
		_hud.favourites.show_list(_favourite_rows()))
	_hud._setup.code_copied.connect(func(code): _hud.notice("Copied this world's code: %s" % code, 5.0))
	add_child(_war_lines)
	_war_lines.draw.connect(_draw_war_lines)
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
	# The tilt view is built over the new world's ground and the simulation's new batches.
	_tilt.setup(self)
	_apply_view()
	_hud.set_stats(world)
	_hud.clear_events()
	# A new world: nothing of the old one is followed, the powers know its creatures and laws.
	_hud.inspector.close()
	_whisper_from = -1
	_favourites.clear()
	load_stamps()
	_hud.powers.setup(_sim.SpawnableSpecies(), _sim.RaceIds(), _sim.PaintableBiomes(), _sim.EraIds(), stamp_names())
	_hud.laws.set_laws(_sim.LawTable())
	_hud._settings_window.set_mods(_sim.ModTable())
	# The world waits while the player chooses its peoples.
	_sim.SetTimeScale(0.0)
	_hud.show_setup()


## Brings the chosen peoples into the world and lets time run.
func start_peoples(races: PackedStringArray, per_village: int, ai := false) -> void:
	_sim.StartPeoples(races, per_village)
	_sim.SetTimeScale(1.0)
	sound.start()
	# The model built into the game (0.5 AI minds): found next to the game or in the player's data,
	# else downloaded once in the background. The procedural inventor invents until it is ready.
	if ai:
		_sim.StartMind(ProjectSettings.get_setting("animundi/ai/model_file", ""),
				ProjectSettings.get_setting("animundi/ai/model_url", ""), true)


func show_layer(layer: String) -> void:
	current_layer = layer
	_map.show_layer(layer)
	_refresh_political()
	_apply_view()


## A political layer (0.9) is drawn from the simulation's kingdoms: again now and then.
func _refresh_political() -> void:
	var political: bool = Hud.POLITICAL_LAYERS.any(func(p): return p[0] == current_layer)
	if political and world != null:
		_map.set_political(_sim.LayerColors(current_layer))
	_war_lines.visible = current_layer == "Wars" and not tilt_on
	_war_lines.queue_redraw()


func _draw_war_lines() -> void:
	var lines: PackedFloat32Array = _sim.WarLines()
	for k in range(0, lines.size(), 4):
		var a := Vector2(lines[k], lines[k + 1]) * WorldMap.TILE
		var b := Vector2(lines[k + 2], lines[k + 3]) * WorldMap.TILE
		var width := 3.0 / maxf(_camera.zoom.x, 0.1)
		_war_lines.draw_line(a, b, Color(0.1, 0.02, 0.03, 0.8), width * 2.0)
		_war_lines.draw_line(a, b, Color(0.95, 0.25, 0.25), width)
		_war_lines.draw_circle(a, width * 2.5, Color(0.95, 0.25, 0.25))
		_war_lines.draw_circle(b, width * 2.5, Color(0.95, 0.25, 0.25))


## Shows the tilt view or the flat map, looking at the same place from as far.
func set_tilt(on: bool) -> void:
	if on != tilt_on and world != null:
		if on:
			var tiles := get_viewport().get_visible_rect().size.y / (_camera.zoom.x * WorldMap.TILE)
			_tilt.camera.look_at_tile(_camera.position / WorldMap.TILE, _tilt.camera.distance_for(tiles))
		else:
			_camera.look_at_point(_tilt.camera.target * WorldMap.TILE, _view_zoom())
	tilt_on = on
	_apply_view()


## The next hour of the day in the tilt view: dawn, noon, afternoon, dusk, night.
func next_hour() -> void:
	var hours := TiltView.HOURS
	var next := 0
	for i in hours.size():
		if hours[i].t <= _tilt.time_of_day + 0.01:
			next = (i + 1) % hours.size()
	var hour_name := _tilt.set_time(hours[next].t)
	_hud.notice("Hour: %s%s" % [hour_name, "" if tilt_on else " (seen in the tilt view, V)"])


## Shows what the chosen view and layer call for: one view draws the world, the data layers
## hide plants and creatures.
func _apply_view() -> void:
	var life := current_layer == "Biomes"
	_map.visible = not tilt_on
	_sim.SetLifeVisible(life and not tilt_on)
	_tilt.set_enabled(tilt_on)
	_tilt.set_plain(not life)
	_hud.show_tilt(tilt_on)
	_war_lines.visible = current_layer == "Wars" and not tilt_on


## Screen pixels per world pixel in the current view (in the tilt view, at the place looked at).
func _view_zoom() -> float:
	if tilt_on:
		return get_viewport().get_visible_rect().size.y / (_tilt.camera.view_height() * WorldMap.TILE)
	return _camera.zoom.x


## Centres the view shown on a point (in tiles), at least as close as a flat zoom of min_zoom.
func _look_at(tile: Vector2, min_zoom := 0.0) -> void:
	if tilt_on:
		var dist := _tilt.camera.distance
		if min_zoom > 0.0:
			dist = minf(dist, _tilt.camera.distance_for(get_viewport().get_visible_rect().size.y / (min_zoom * WorldMap.TILE)))
		_tilt.camera.look_at_tile(tile, dist)
	else:
		_camera.look_at_point(tile * WorldMap.TILE, maxf(_camera.zoom.x, min_zoom))


## The point of the world (tiles) under a screen position, in the current view.
func _ground_at(screen_pos: Vector2) -> Vector2:
	if tilt_on:
		return _tilt.pick(screen_pos)
	return _camera.screen_to_world(screen_pos) / WorldMap.TILE


func _unhandled_input(event: InputEvent) -> void:
	if _over_interface(event):
		return
	if world != null and not _hud.blocking() and _power_input(event):
		get_viewport().set_input_as_handled()
		return
	if _tilt.camera.handle_input(event) if tilt_on else _camera.handle_input(event):
		get_viewport().set_input_as_handled()


## Godot lets the wheel and trackpad gestures through buttons and panels: they must not zoom or
## pan the map behind the interface. Releases still go through, so a drag ends anywhere.
func _over_interface(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	var gesture: bool = (button != null and button.pressed) or event is InputEventGesture
	return gesture and get_viewport().gui_get_hovered_control() != null


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
	var at := _ground_at(screen_pos)
	var tile := Vector2i(floori(at.x), floori(at.y))
	if tile == _stroke_tile:
		return
	_stroke_tile = tile
	var r: float = powers.radius()
	# Faith mode: a power costs the faith the peoples put in the player.
	if not _sim.SpendFaith(powers.power):
		_hud.notice("Not enough faith: %s needs %d (you have %d). Faith comes each year from those who worship or fear you." % [
				powers.POWERS[powers.power][0], int(_sim.PowerCost(powers.power)), int(_sim.GodFaith)], 4.0)
		return
	sound.play(POWER_SOUNDS.get(powers.power, "click"), -4.0 if powers.drags() else 0.0)
	match powers.power:
		"meteor", "earthquake", "eruption", "stamp":
			shake_screen(6.0, 0.6)
		"nuke":
			shake_screen(14.0, 1.2)
	match powers.power:
		"fire":
			_sim.PowerFire(at.x, at.y, r)
		"rain":
			_sim.PowerRain(at.x, at.y, r)
		"smite":
			_sim.PowerSmite(at.x, at.y, r)
		"bless":
			_sim.PowerBless(at.x, at.y, r)
		"miracle":
			_sim.PowerMiracle(at.x, at.y, r)
		"biome":
			_sim.PowerBiome(powers.arg, at.x, at.y, r)
		"lightning":
			_sim.PowerLightning(at.x, at.y)
		"meteor":
			_sim.PowerMeteor(at.x, at.y, r)
		"wildfire", "drought", "tornado", "earthquake", "flood", "eruption":
			if _sim.PowerDisaster(powers.power, at.x, at.y, r) == 0:
				_hud.notice({"flood": "Water needs low land to rise over.", "wildfire": "Nothing burns here."}.get(powers.power, "Disasters need land to strike."))
		"plague":
			if _sim.PowerPlague(at.x, at.y, r) == 0:
				_hud.notice("A sickness needs living creatures to take hold of.")
		"heal":
			_sim.PowerHeal(at.x, at.y, r)
		"spawn":
			if _sim.PowerSpawn(powers.arg, at.x, at.y, powers.brush) == 0:
				_hud.notice("A legend is unique: it already walks this world, or it needs land to stand on." if _sim.IsLegend(powers.arg) \
						else "Creatures need land to stand on.")
		"settle":
			if _sim.PowerSettle(powers.arg, at.x, at.y, SETTLERS) < 0:
				_hud.notice("A village needs free land: not the sea, not another village's ground.")
		"war", "peace", "alliance", "convert":
			_whisper(powers.power, _sim.KingdomAt(at.x, at.y))
		"raise":
			_sim.PowerRaise(at.x, at.y, r)
		"lower":
			_sim.PowerLower(at.x, at.y, r)
		"water":
			_sim.PowerWater(at.x, at.y, r)
		"stamp":
			if _sim.PowerStamp(powers.arg, at.x, at.y) <= 0:
				_hud.notice("Nothing changes there: the stamp needs the map under it.")
		"copy":
			var json: String = _sim.CopyStamp(at.x, at.y, copy_size())
			var saved: Array = StampStore.save(json)
			if saved.is_empty() or _sim.AddStamp(saved[0], saved[1], json) != "":
				_hud.notice("The land could not be kept.")
			else:
				_hud.powers.set_stamps(stamp_names())
				_hud.notice("Kept as \"%s\": paste it from the Stamps tab, in this world or another." % saved[1], 5.0)
		"seeds":
			_sim.PowerSeeds(at.x, at.y, r)
		"blizzard":
			_sim.PowerBlizzard(at.x, at.y, r + 1.5)
		"curse":
			_sim.PowerCurse(at.x, at.y, r)
		"madness":
			if _sim.PowerMadness(at.x, at.y, r) == 0:
				_hud.notice("No creatures there to turn on each other.")
		"resurrect":
			if _sim.PowerResurrect(at.x, at.y, r + 1.0) == 0:
				_hud.notice("No dead lie there (the dead lie only a few seconds where they fell).")
		"rebellion":
			if not _sim.PowerRebellion(at.x, at.y):
				_hud.notice("Click a village that is not a kingdom's capital.")
		"inspire":
			if not _sim.PowerInspire(at.x, at.y):
				_hud.notice("No kingdom owns this land.")
		"forget_culture":
			if not _sim.PowerForgetCulture(at.x, at.y):
				_hud.notice("No kingdom owns this land.")
		"forget_faith":
			if not _sim.PowerForgetFaith(at.x, at.y):
				_hud.notice("No kingdom owns this land.")
		"trait":
			_sim.PowerTrait(powers.arg, at.x, at.y, r)
		"hail":
			_sim.PowerHail(at.x, at.y, r + 1.5)
		"wind":
			if _wind_from.x < 0.0:
				_wind_from = at
				_sim.AddGodFaith(_sim.PowerCost("wind"))
				_hud.notice("The wind gathers… now click where it blows.", 5.0)
			else:
				_sim.PowerWind(_wind_from.x, _wind_from.y, at.x, at.y)
				_wind_from = Vector2(-1, -1)
		"forget_language":
			if not _sim.PowerForgetLanguage(at.x, at.y):
				_hud.notice("No kingdom owns this land.")
		"story":
			var told: String = _sim.PowerStory(powers.arg, at.x, at.y)
			_hud.notice(("The storyteller speaks: %s." % told) if told != "" else "This story finds no one to be told of here.", 5.0)
		"enlighten":
			if not _sim.PowerEnlighten(at.x, at.y):
				_hud.notice("No kingdom owns this land.")
		"dark_age":
			if not _sim.PowerDarkAge(at.x, at.y):
				_hud.notice("No kingdom owns this land.")
		"nuke":
			if _sim.PowerNuke(at.x, at.y) < 0:
				_hud.notice("The bomb needs land to fall on.")
		"era":
			if _sim.PowerEra(powers.arg):
				_hud.notice("The world turns: a %s era begins." % powers.arg)


## The side of the square "Copy the land" keeps, from the brush.
func copy_size() -> int:
	return clampi(_hud.powers.brush * 4, 6, 32)


## Saves the world in a slot of WorldStore (the land, its settings and the whole simulation).
## Returns "" or why it failed.
func save_world(slot: String) -> String:
	if world == null:
		return "no world"
	var peoples := {}
	for k in _sim.KingdomTable():
		peoples[k.people] = true
	var about := {"year": _sim.Year(), "people": _sim.PeopleCount(), "kingdoms": _sim.KingdomCount(), "era": _sim.EraName(),
			"peoples": ", ".join(peoples.keys())}
	return WorldStore.save(slot, world, settings, _sim.SaveState(), about)


## Brings back the world of a slot: its land, its settings, everything that lived in it.
## Returns "" or why it could not.
func load_world(slot: String) -> String:
	var data := WorldStore.read(slot)
	if data.is_empty():
		return "the slot is empty or unreadable"
	settings.from_code(data.code)
	world = data.world
	_map.set_world(world)
	_map.show_layer(current_layer)
	_sim.Start(world, PackedStringArray(Biomes.NAMES))
	var error: String = _sim.LoadState(data.sim)
	if error != "":
		generate()
		return error
	_camera.bounds = _map.pixel_size()
	_camera.frame_all()
	_tilt.setup(self)
	_apply_view()
	_hud.set_stats(world)
	_hud.clear_events()
	_hud.inspector.close()
	_whisper_from = -1
	_favourites.clear()
	_autosaved_year = _sim.Year()
	load_stamps()
	_hud.powers.setup(_sim.SpawnableSpecies(), _sim.RaceIds(), _sim.PaintableBiomes(), _sim.EraIds(), stamp_names())
	_hud.laws.set_laws(_sim.LawTable())
	_hud.show_game()
	sound.start()
	_sim.SetTimeScale(1.0)
	_hud.show_speed(1.0)
	_hud.notice("Year %d: the world goes on." % _sim.Year(), 4.0)
	return ""


## Shakes the flat view for a moment (meteors, bombs, quakes), if the settings allow it.
func shake_screen(strength: float, seconds: float) -> void:
	if shake:
		_shake_strength = maxf(_shake_strength, strength)
		_shake_left = maxf(_shake_left, seconds)


## The sound of a great event of the chronicle, if it has one; a great event may pause the
## world (settings) and shake it.
func _event_sound(cat: String, text: String) -> void:
	var great := "drops the bomb" in text or "a sun falls" in text or "declares war" in text or "wakes" in text and cat == "legends" \
			or "is a plague now" in text or "The first people of the world" in text or "has fallen" in text
	if great and pause_on_events and _sim.GetTimeScale() > 0.0:
		_sim.SetTimeScale(0.0)
		_hud.show_speed(0.0)
		_hud.notice("Paused: %s" % text.get_slice(": ", 1) if ": " in text else "Paused for a great event.", 5.0)
	if "drops the bomb" in text or "a sun falls" in text:
		shake_screen(14.0, 1.2)
		sound.play("bomb")
	elif cat == "wars" and ("declares war" in text or "goes to war" in text):
		sound.play("drums", -6.0)
	elif cat == "ages" and (" enter " in text or "rocket" in text):
		sound.play("rocket" if "rocket" in text else "fanfare", -4.0)
	elif cat == "disasters" and ("earth" in text or "erupt" in text or "quake" in text):
		shake_screen(5.0, 0.8)
		sound.play("quake", -8.0)
	elif " era begins" in text:
		sound.play("chime", -6.0)


## The player's stamps and those of the mods, given to the simulation.
func load_stamps() -> void:
	for saved in StampStore.load_all():
		_sim.AddStamp(saved[0], saved[1], saved[2])
	var mods := DirAccess.open(MODS_DIR)
	if mods != null:
		for mod in mods.get_directories():
			for saved in StampStore.load_all(MODS_DIR.path_join(mod).path_join("stamps")):
				_sim.AddStamp("%s_%s" % [mod, saved[0]], saved[1], saved[2])


## The scenarios: data/scenarios.json, then those of the mods.
func scenarios() -> Array:
	var out := []
	var files := ["res://data/scenarios.json"]
	var mods := DirAccess.open(MODS_DIR)
	if mods != null:
		for mod in mods.get_directories():
			files.append(MODS_DIR.path_join(mod).path_join("scenarios.json"))
	for path in files:
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and data.get("scenarios") is Array:
			for s in data.scenarios:
				if s is Dictionary and s.has("id") and s.has("peoples"):
					out.append(s)
	return out


## Begins a scenario: its land, its peoples, then their age, the mood of the world, the war and
## the laws it asks for.
func start_scenario(id: String) -> void:
	var found := scenarios().filter(func(s): return s.id == id)
	if found.is_empty():
		return
	var s: Dictionary = found[0]
	var land: Dictionary = s.get("settings", {})
	settings.seed_text = String(land.get("seed", id))
	settings.set_size(int(land.get("size", 256)))
	settings.continents = int(land.get("continents", 3))
	settings.water_ratio = float(land.get("water", 0.55))
	settings.temperature_offset = float(land.get("climate", 0.0))
	generate()
	for law in s.get("laws", {}):
		_sim.SetLaw(law, bool(s.laws[law]))
	_hud.laws.set_laws(_sim.LawTable())
	start_peoples(PackedStringArray(s.peoples), int(s.get("per_village", 12)))
	var kingdoms: Array = _sim.KingdomTable()
	if s.has("age"):
		for k in kingdoms:
			_sim.SetKingdomAge(k.index, int(s.age))
	if s.has("era"):
		_sim.SetEra(String(s.era))
	if s.get("war", false) and kingdoms.size() >= 2:
		_sim.PowerWhisper("war", kingdoms[0].index, kingdoms[1].index)
	_hud.show_game()
	_hud.show_speed(1.0)
	_hud.notice("%s · %s" % [s.name, s.text], 7.0)


## The stamps the simulation knows, id → name.
func stamp_names() -> Dictionary:
	var names := {}
	for id in _sim.StampIds():
		names[id] = _sim.StampName(id)
	return names


## Copies the simulation's terrain changes (tile, level, water, biome quads) into the world,
## and redraws the tiles and their neighbours, flat and tilted.
func apply_terrain(quads: PackedInt32Array) -> void:
	var tiles := PackedInt32Array()
	var redraw := {}
	var land_heights := [0.0, 0.0, 0.3, 0.7, 0.9]
	for k in range(0, quads.size(), 4):
		var i := quads[k]
		var level := quads[k + 1]
		world.level[i] = level
		world.water[i] = quads[k + 2]
		world.biome[i] = quads[k + 3]
		# An elevation that agrees with the level (the data layers and the sea's shades read it).
		if level >= WorldData.Level.PLAIN:
			world.elevation[i] = world.sea_level + land_heights[level] * (1.0 - world.sea_level)
		else:
			world.elevation[i] = world.sea_level * (0.97 if level == WorldData.Level.SHALLOW else 0.7)
		tiles.append(i)
		var x := i % world.width
		var y := i / world.width
		for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if world.in_bounds(x + d.x, y + d.y):
				redraw[world.index(x + d.x, y + d.y)] = true
	_map.update_tiles(PackedInt32Array(redraw.keys()))
	_tilt.update_terrain(world, tiles)


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
				"peace": "They are not at war.", "alliance": "They are at war, already allies, or the same kingdom.",
				"convert": "They already share a faith, or it is the same kingdom."}[kind])


## Pins the creature under a screen position in the inspector, else the village owning the land.
func _inspect(screen_pos: Vector2) -> void:
	var at := _ground_at(screen_pos)
	_following = false
	_pinned_card = ["", null]
	_pinned_unit = _sim.UnitAt(at.x, at.y, 0.9)
	_pinned_village = _sim.VillageAt(at.x, at.y) if _pinned_unit < 0 else -1
	if _pinned_unit < 0 and _pinned_village < 0:
		# Land of no village: its spirit, if it has one.
		if not _sim.SpiritInfoAt(at.x, at.y).is_empty():
			_pinned_card = ["spirit", at]
		else:
			_hud.inspector.close()
	_refresh_inspector()


## The inspector's actions (1.0): follow as a favourite, the family, the story, the mind.
func _inspector_action(action: String) -> void:
	var name := ""
	if _pinned_unit >= 0 and _sim.UnitAlive(_pinned_unit):
		name = _sim.UnitName(_pinned_unit)
	elif _pinned_village >= 0:
		name = String(_sim.VillageInfo(_pinned_village).get("name", ""))
	elif _pinned_card[0] == "kingdom":
		name = String(_sim.KingdomInfo(_pinned_card[1]).get("name", ""))
	match action:
		"favourite":
			var kind := "unit" if _pinned_unit >= 0 else ("village" if _pinned_village >= 0 else "")
			var id: int = _pinned_unit if _pinned_unit >= 0 else _pinned_village
			if kind == "":
				_hud.notice("Only creatures and villages can be followed.")
				return
			var had := _favourites.any(func(f): return f.kind == kind and f.id == id)
			if had:
				_favourites = _favourites.filter(func(f): return not (f.kind == kind and f.id == id))
			else:
				_favourites.append({"kind": kind, "id": id, "name": name, "alive": true})
			_hud.inspector.set_favourite(not had)
			_hud.notice(("%s is no longer followed." if had else "%s is among your favourites.") % name)
		"family":
			_hud.inspector.show_extra(_sim.FamilyOf(_pinned_unit) if _pinned_unit >= 0 else "Only people have families.")
		"story":
			_hud.inspector.show_extra(_sim.StoryOf(name) if name != "" else "")
		"mind":
			_hud.inspector.show_extra(_sim.MindOf(_pinned_unit) if _pinned_unit >= 0 else "Villages have no mind of their own: their kingdom does.")


## The favourites as the window shows them, and the news of those who are gone.
func _favourite_rows() -> Array:
	for f in _favourites:
		if not f.alive:
			continue
		var gone: bool = not _sim.UnitAlive(f.id) if f.kind == "unit" else _sim.VillageInfo(f.id).is_empty()
		if gone:
			f.alive = false
			_hud.notice("%s %s." % [f.name, "has died" if f.kind == "unit" else "is no more"], 6.0)
			sound.play("chime", -8.0)
	return _favourites.map(func(f): return {"kind": f.kind, "id": f.id, "name": f.name, "alive": f.alive,
			"about": (_sim.UnitInfo(f.id) if f.kind == "unit" else "village") if f.alive else "gone"})


## Pins a card in the inspector: "kingdom" (index), "species" (name), "invention" (id).
func show_card(kind: String, id: Variant) -> void:
	_pinned_unit = -1
	_pinned_village = -1
	_following = false
	_pinned_card = [kind, id]
	_refresh_inspector()


func _refresh_inspector() -> void:
	if _pinned_unit >= 0:
		if _sim.UnitAlive(_pinned_unit):
			_hud.inspector.show_unit(_sim.UnitName(_pinned_unit), _sim.UnitInfo(_pinned_unit))
		else:
			_hud.inspector.close()
	elif _pinned_village >= 0:
		_hud.inspector.show_village(_sim.VillageInfo(_pinned_village))
	else:
		match _pinned_card[0]:
			"kingdom":
				_hud.inspector.show_kingdom(_sim.KingdomInfo(_pinned_card[1]))
			"species":
				_hud.inspector.show_species(_sim.SpeciesInfo(_pinned_card[1]))
			"spirit":
				_hud.inspector.show_spirit(_sim.SpiritInfoAt(_pinned_card[1].x, _pinned_card[1].y))
			"invention":
				_hud.inspector.show_invention(_sim.InventionInfo(_pinned_card[1]))


func _process(delta: float) -> void:
	if world == null:
		return
	# The screen shakes after a meteor, a bomb, a quake (settings).
	if _shake_left > 0.0:
		_shake_left -= delta
		var k := _shake_strength * clampf(_shake_left, 0.0, 1.0)
		_camera.offset = Vector2(randf_range(-k, k), randf_range(-k, k)) / maxf(_camera.zoom.x, 0.1)
		if _shake_left <= 0.0:
			_camera.offset = Vector2.ZERO
			_shake_strength = 0.0
	# What the simulation draws follows the flat camera; the tilt view asks for what it needs.
	if not tilt_on:
		_sim.SetZoom(_camera.zoom.x)
		_sim.SetView(_camera.position, get_viewport().get_visible_rect().size / _camera.zoom.x)
	_map.set_scorch(_sim.TakeScorchChanges())
	_map.set_overlay(_sim.TakeOverlayChanges())
	_map.set_frost(_sim.Coldness())
	var tint: Color = _sim.EraTint()
	_world_tint.color = Color.WHITE if tilt_on else tint
	_tilt.set_world_tint(tint)
	# Land raised, lowered, flooded or stamped (the terrain tools).
	var reshaped: PackedInt32Array = _sim.TakeTerrainChanges()
	if not reshaped.is_empty():
		apply_terrain(reshaped)
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
	var brushing: bool = _hud.powers.power != "inspect" and not _hud.blocking()
	var reach: float = _hud.powers.radius() if _hud.powers.power in ["fire", "rain", "smite", "bless", "biome", "meteor", "miracle", "wildfire",
			"drought", "earthquake", "flood", "eruption", "plague", "heal", "raise", "lower", "water", "seeds", "curse", "madness",
			"resurrect", "trait", "hail"] else 0.6
	match _hud.powers.power:
		"nuke":
			reach = 6.0
		"copy":
			reach = copy_size() / 2.0
		"stamp":
			reach = 5.0
		"blizzard":
			reach = _hud.powers.radius() + 1.5
	var at := _ground_at(pointer)
	_brush.visible = brushing and not tilt_on
	_tilt_brush.visible = brushing and tilt_on
	if tilt_on:
		_tilt_brush.outline = _tilt.ring(at, reach)
	else:
		_brush.position = at * WorldMap.TILE
		_brush.zoom = _camera.zoom.x
		_brush.radius = reach * WorldMap.TILE
	var tagged: PackedStringArray = _sim.TakeTaggedEvents()
	for k in range(0, tagged.size(), 2):
		_hud.add_event(tagged[k + 1], tagged[k])
		_event_sound(tagged[k], tagged[k + 1])
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
			_hud.set_time("Year %d · %s · %s · %s%s" % [_sim.Year(), _sim.SeasonName(), _sim.AgeName().trim_prefix("The "),
					_sim.EraName(), "  (paused)" if speed == 0.0 else ""])
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
		_hud.set_cultures(_sim.CultureTable())
		_hud.set_legends(_sim.LegendTable())
		_hud.set_nature(_sim.NatureTable())
		var world_now: Dictionary = _sim.WorldAges()
		_hud.set_ages(world_now, _sim.ProgressTable())
		sound.set_mood("winter" if float(world_now.winter) >= 2.0 else _sim.EraId())
		var era: String = _sim.EraId()
		weather.set_weather("ash" if float(world_now.winter) >= 2.0 else {"rainy": "rain", "cold": "snow", "magical": "motes"}.get(era, ""))
		if _hud.stats.visible:
			_hud.stats.set_history(_sim.History())
		_stats_rounds += 1
		_hud.set_faith(_sim.GodFaith, _sim.LawTable().get("faith_mode", false))
		if not _favourites.is_empty():
			_favourite_rows()
		if _sim.KingdomCount() > 0:
			for won in achievements.check(_sim.Facts()):
				_hud.notice("Achievement: %s · %s" % [won.name, won.text], 6.0)
				sound.play("achievement")
		# The autosave, every ten years of a world with peoples.
		if autosave and _sim.Year() % 10 == 0 and _sim.Year() != _autosaved_year and _sim.KingdomCount() > 0:
			_autosaved_year = _sim.Year()
			save_world(WorldStore.AUTO)
		if _stats_rounds % 3 == 0 and current_layer != "Biomes" and not current_layer in MapRenderer.LAYERS:
			_refresh_political()
		_hud.set_chronicle(_sim.AgeName(), _sim.ChronicleTable())
		_refresh_inspector()
	# The camera stays on the creature or the village the player follows.
	if _following:
		if _pinned_unit >= 0 and _sim.UnitAlive(_pinned_unit):
			_look_at(_sim.UnitPosition(_pinned_unit))
		elif _pinned_village >= 0:
			var followed: Dictionary = _sim.VillageInfo(_pinned_village)
			if not followed.is_empty():
				_look_at(Vector2(followed.x + 0.5, followed.y + 0.5))
	_update_map_labels()
	var mouse := pointer
	# A creature under the mouse: who it is.
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
	if _view_zoom() >= 0.8 and current_layer == "Biomes":
		var view := get_viewport().get_visible_rect().size
		for v in _sim.VillageLabels():
			var p: Vector2 = _tilt.screen_of(Vector2(v.x + 0.5, v.y + 0.5), 1.0) if tilt_on \
					else (Vector2(v.x + 0.5, v.y) * WorldMap.TILE - _camera.position) * _camera.zoom.x + view / 2.0
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
		# The legends that walk the world, named over their heads.
		for l in _sim.LegendLabels():
			var p: Vector2 = _tilt.screen_of(Vector2(l.x, l.y), 1.0) if tilt_on \
					else (Vector2(l.x, l.y - 3.0) * WorldMap.TILE - _camera.position) * _camera.zoom.x + view / 2.0
			if Rect2(Vector2.ZERO, view).has_point(p):
				labels.append([String(l.name), p])
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
	return _map.tile_at(_ground_at(screen_pos) * WorldMap.TILE)
