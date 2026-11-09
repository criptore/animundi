## World-generation HUD: seed and settings bar, map layer buttons, hovered tile info, stage timings.
extends CanvasLayer

signal generate_requested
signal layer_selected(layer: String)
## The player picked a speed of time (0 = pause).
signal speed_selected(scale: float)
## The player started the world with these peoples (from the setup panel).
signal start_requested(races: PackedStringArray, per_village: int)
## The player asked for more animals (stress test of the simulation).
signal spawn_requested(count: int)

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")
const SetupPanel = preload("res://scripts/ui/setup_panel.gd")

var settings: WorldSettings

var _seed_edit: LineEdit
var _size_option: OptionButton
var _continents: SpinBox
var _water: SpinBox
var _climate: SpinBox
var _hover_label: Label
var _stats_label: Label
var _layer_buttons := {}
var _world_stats := ""
var _sprite_count := 0
var _sim_stats := ""
var _time_label: Label
var _events_label: Label
var _population_label: Label
var _events: PackedStringArray = []
var _villages_label: Label
var _setup: PanelContainer
var _root: Control
## Village names drawn over the map.
var _name_labels: Array[Label] = []

## Event lines kept on screen.
const EVENTS_SHOWN := 6
## Speeds of time offered (0 = pause).
const SPEEDS := [0.0, 1.0, 2.0, 5.0, 10.0]

var _speed_buttons := []
var _speed := 1.0
var _speed_before_pause := 1.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root

	# Top bar: world settings.
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)

	bar.add_child(_label("Seed"))
	_seed_edit = LineEdit.new()
	_seed_edit.text = settings.seed_text
	_seed_edit.custom_minimum_size.x = 160
	_seed_edit.text_submitted.connect(func(_t): _request())
	bar.add_child(_seed_edit)

	var random_button := Button.new()
	random_button.text = "Random"
	random_button.tooltip_text = "New random seed (R)"
	random_button.pressed.connect(randomize_seed)
	bar.add_child(random_button)

	bar.add_child(_label("Size"))
	_size_option = OptionButton.new()
	for size_name in WorldSettings.SIZES:
		_size_option.add_item("%s (%d)" % [size_name, WorldSettings.SIZES[size_name]])
	_size_option.select(WorldSettings.SIZES.values().find(settings.width))
	bar.add_child(_size_option)

	bar.add_child(_label("Continents"))
	_continents = _spin(1, 8, 1, settings.continents)
	bar.add_child(_continents)
	bar.add_child(_label("Water %"))
	_water = _spin(20, 85, 5, roundi(settings.water_ratio * 100))
	bar.add_child(_water)
	bar.add_child(_label("Climate"))
	_climate = _spin(-30, 30, 5, roundi(settings.temperature_offset * 100))
	_climate.tooltip_text = "-30 = ice age, +30 = hot world"
	bar.add_child(_climate)

	var generate_button := Button.new()
	generate_button.text = "Generate"
	generate_button.pressed.connect(_request)
	bar.add_child(generate_button)

	# Right: map layers.
	var side := PanelContainer.new()
	side.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(side)
	var layers := VBoxContainer.new()
	side.add_child(layers)
	layers.add_child(_label("Layer"))
	var group := ButtonGroup.new()
	for k in MapRenderer.LAYERS.size():
		var layer: String = MapRenderer.LAYERS[k]
		var b := Button.new()
		b.text = "%d  %s" % [k + 1, layer]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == 0
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): layer_selected.emit(layer))
		layers.add_child(b)
		_layer_buttons[layer] = b
	var spawn := Button.new()
	spawn.text = "+1000 animals (U)"
	spawn.tooltip_text = "Spawn 1000 wandering animals: a stress test of the C# simulation"
	spawn.pressed.connect(func(): spawn_requested.emit(1000))
	layers.add_child(spawn)
	var help := _label("\nWheel / pinch / + -: zoom\nDrag / two fingers / WASD: pan\nSpace: pause · , . : time speed\nHover a creature: who it is\nR: new world\nF: fire under the mouse (test)")
	help.add_theme_font_size_override("font_size", 12)
	layers.add_child(help)

	# Left: the time of year, the world's latest events and its living creatures.
	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	left.custom_minimum_size.x = 300
	root.add_child(left)
	var life := VBoxContainer.new()
	left.add_child(life)
	_time_label = _label("")
	_time_label.add_theme_font_size_override("font_size", 18)
	life.add_child(_time_label)
	var speeds := HBoxContainer.new()
	var speed_group := ButtonGroup.new()
	for v in SPEEDS:
		var b := Button.new()
		b.text = "Pause" if v == 0.0 else "×%d" % v
		b.toggle_mode = true
		b.button_group = speed_group
		b.button_pressed = v == 1.0
		b.focus_mode = Control.FOCUS_NONE  # Space must not press a focused button
		b.tooltip_text = "Space: pause / resume · , and . : slower / faster"
		b.pressed.connect(func(): _set_speed(v))
		speeds.add_child(b)
		_speed_buttons.append(b)
	life.add_child(speeds)
	_population_label = _label("")
	_population_label.add_theme_font_size_override("font_size", 12)
	life.add_child(_population_label)
	life.add_child(_label("Villages"))
	_villages_label = _label("")
	_villages_label.add_theme_font_size_override("font_size", 12)
	life.add_child(_villages_label)
	life.add_child(_label("Events"))
	_events_label = _label("")
	_events_label.add_theme_font_size_override("font_size", 12)
	_events_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_events_label.custom_minimum_size.x = 290
	life.add_child(_events_label)

	# Bottom: hovered tile, generation stats, controls help.
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	var info := HBoxContainer.new()
	bottom.add_child(info)
	_hover_label = _label("")
	_hover_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The stats on the right keep their room; the hover text is cut if it doesn't fit.
	_hover_label.clip_text = true
	info.add_child(_hover_label)
	_stats_label = _label("")
	info.add_child(_stats_label)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		randomize_seed()
	elif key.keycode == KEY_U:
		spawn_requested.emit(1000)
	elif key.keycode == KEY_SPACE:
		_set_speed(_speed_before_pause if _speed == 0.0 else 0.0)
	elif key.keycode == KEY_PERIOD or key.keycode == KEY_COMMA:
		var k := SPEEDS.find(_speed)
		k = clampi(k + (1 if key.keycode == KEY_PERIOD else -1), 1, SPEEDS.size() - 1)
		_set_speed(SPEEDS[k])
	elif key.keycode >= KEY_1 and key.keycode < KEY_1 + MapRenderer.LAYERS.size():
		var layer: String = MapRenderer.LAYERS[key.keycode - KEY_1]
		_layer_buttons[layer].button_pressed = true
		layer_selected.emit(layer)


func randomize_seed() -> void:
	_seed_edit.text = str(randi() % 1000000)
	_request()


func set_hover_text(text: String) -> void:
	_hover_label.text = text


func set_stats(world) -> void:
	var total := 0.0
	for ms in world.stage_ms.values():
		total += ms
	_world_stats = "Seed %d · %d² · %.1f s" % [world.seed_value, world.width, total / 1000.0]
	_refresh_stats()


## Units alive, average milliseconds of a simulation step, frames per second.
func set_sim_stats(units: int, step_ms: float, fps: float) -> void:
	_sim_stats = "%d animals · sim %.2f ms · %d fps" % [units, step_ms, fps]
	_refresh_stats()


## "Year 3 · Winter".
func set_time(text: String) -> void:
	_time_label.text = text


## A line in the event log (newest first).
func add_event(text: String) -> void:
	_events.insert(0, text)
	if _events.size() > EVENTS_SHOWN:
		_events.resize(EVENTS_SHOWN)
	_events_label.text = "\n".join(_events)


## Living creatures by species name, the most numerous first.
func set_populations(table: Dictionary) -> void:
	var names := table.keys()
	names.sort_custom(func(a, b): return table[a] > table[b])
	var parts := PackedStringArray()
	for n in names.slice(0, 8):
		parts.append("%s %d" % [n, table[n]])
	_population_label.text = "  ".join(parts)
	_population_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_population_label.custom_minimum_size.x = 290


## Shows the world setup (choosing the peoples) over a new world.
func show_setup() -> void:
	if _setup == null:
		_setup = SetupPanel.new()
		_setup.start_requested.connect(func(races, n):
			_setup.visible = false
			start_requested.emit(races, n))
		_root.add_child(_setup)
	_setup.visible = true


func setup_visible() -> bool:
	return _setup != null and _setup.visible


## One line per village: name, people, population, stores, houses.
func set_villages(villages: Array) -> void:
	var lines := PackedStringArray()
	for v in villages:
		lines.append("%s (%s) %d · food %d · wood %d · %d houses" % [v.name, v.people, v.population, v.food, v.wood, v.houses])
	_villages_label.text = "\n".join(lines) if lines.size() > 0 else "none yet"


## Village names over the map: `labels` is [[name, screen position], ...].
func set_map_labels(labels: Array) -> void:
	while _name_labels.size() < labels.size():
		var l := Label.new()
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_font_size_override("font_size", 14)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(l)
		_root.move_child(l, 0)
		_name_labels.append(l)
	for k in _name_labels.size():
		var l := _name_labels[k]
		l.visible = k < labels.size()
		if l.visible:
			l.text = labels[k][0]
			l.position = labels[k][1] - Vector2(l.size.x / 2.0, 34)


func set_sprite_count(n: int) -> void:
	_sprite_count = n
	_refresh_stats()


func _refresh_stats() -> void:
	if _stats_label != null:
		_stats_label.text = "%s · %d plants%s" % [_world_stats, _sprite_count, (" · " + _sim_stats) if _sim_stats != "" else ""]


func _request() -> void:
	settings.seed_text = _seed_edit.text if _seed_edit.text.strip_edges() != "" else "animundi"
	settings.set_size(WorldSettings.SIZES.values()[_size_option.selected])
	settings.continents = int(_continents.value)
	settings.water_ratio = _water.value / 100.0
	settings.temperature_offset = _climate.value / 100.0
	generate_requested.emit()


## Changes the speed of time and shows it on the buttons.
func _set_speed(v: float) -> void:
	if v == 0.0 and _speed != 0.0:
		_speed_before_pause = _speed
	_speed = v
	var k := SPEEDS.find(v)
	if k >= 0:
		_speed_buttons[k].button_pressed = true
	speed_selected.emit(v)


func clear_events() -> void:
	_events.clear()
	if _events_label != null:
		_events_label.text = ""


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _spin(lo: float, hi: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	return s
