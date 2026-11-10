## World-generation HUD: seed and settings bar, map layer buttons, hovered tile info, stage timings.
extends CanvasLayer

signal generate_requested
signal layer_selected(layer: String)
## The player picked a speed of time (0 = pause).
signal speed_selected(scale: float)
## The player started the world with these peoples (from the setup panel).
signal start_requested(races: PackedStringArray, per_village: int, ai: bool)
## The player asked to run time to `year` in about `seconds` of real time (0 = as fast as possible).
signal go_to_year_requested(year: int, seconds: float)
## The player asked for more animals (stress test of the simulation).
signal spawn_requested(count: int)

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")
const SetupPanel = preload("res://scripts/ui/setup_panel.gd")
const Banner = preload("res://scripts/ui/banner.gd")
const PowerBar = preload("res://scripts/ui/power_bar.gd")
const Inspector = preload("res://scripts/ui/inspector.gd")

var settings: WorldSettings

var _seed_edit: LineEdit
var _size_option: OptionButton
var _continents: SpinBox
var _water: SpinBox
var _climate: SpinBox
var _hover_label: Label
## The god powers bar and the inspector card (scripts/main.gd drives them).
var powers := PowerBar.new()
var inspector := Inspector.new()
## A short message shown in the bottom bar instead of the hover text, until this time (ms).
var _notice := ""
var _notice_until := 0
var _stats_label: Label
var _layer_buttons := {}
var _world_stats := ""
var _sprite_count := 0
var _sim_stats := ""
var _time_label: Label
var _events_label: Label
var _population_label: Label
## Recent events as [category, text], newest first, and the category shown ("" = all).
var _events: Array = []
var _event_filter := ""
var _kingdoms_box: VBoxContainer
var _plans_label: Label
var _inventions_label: Label
## Kingdom rows by name: banner and text are updated in place.
var _kingdom_rows := {}
var _villages_label: Label
var _setup: PanelContainer
var _root: Control
## Village names drawn over the map.
var _name_labels: Array[Label] = []

## Event lines kept on screen.
const EVENTS_SHOWN := 6
## Speeds of time offered (0 = pause).
## Speeds of time; above ×10 is the ultra-fast mode (coarse steps, to watch centuries go by).
const SPEEDS := [0.0, 1.0, 2.0, 5.0, 10.0, 100.0]

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
	var help := _label("\nWheel / pinch / + -: zoom\nDrag / two fingers / WASD: pan\nSpace: pause · , . : time speed\nHover a creature: who it is\nR: new world\nPowers: pick one below, click the map\nEsc: back to Inspect · [ ]: brush size")
	help.add_theme_font_size_override("font_size", 12)
	layers.add_child(help)

	# Left: the time of year, the world's latest events and its living creatures.
	var left := PanelContainer.new()
	# Under the top bar, so the kingdoms, plots and events all fit.
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.position.y = 44
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
		b.text = "Pause" if v == 0.0 else ("Ultra" if v > 10.0 else "×%d" % v)
		b.toggle_mode = true
		b.button_group = speed_group
		b.button_pressed = v == 1.0
		b.focus_mode = Control.FOCUS_NONE  # Space must not press a focused button
		b.tooltip_text = "Space: pause / resume · , and . : slower / faster" + ("\nUltra: ×100, in coarser steps (a century in a minute)" if v > 10.0 else "")
		b.pressed.connect(func(): _set_speed(v))
		speeds.add_child(b)
		_speed_buttons.append(b)
	life.add_child(speeds)
	# "Go to year": pick the year to reach and how long it may take, time runs there and pauses.
	var go := HBoxContainer.new()
	go.add_child(_label("Go to year"))
	var year_box := SpinBox.new()
	year_box.min_value = 2
	year_box.max_value = 1000000
	year_box.value = 10000
	year_box.tooltip_text = "The year to reach; time pauses there"
	go.add_child(year_box)
	go.add_child(_label("in"))
	var minutes_box := SpinBox.new()
	minutes_box.min_value = 0
	minutes_box.max_value = 600
	minutes_box.step = 0.5
	minutes_box.value = 10
	minutes_box.suffix = "min"
	minutes_box.tooltip_text = "Real time it should take (0 = as fast as the computer can)"
	go.add_child(minutes_box)
	var go_button := Button.new()
	go_button.text = "Go"
	go_button.focus_mode = Control.FOCUS_NONE
	go_button.pressed.connect(func():
		for b in _speed_buttons:
			b.button_pressed = false
		go_to_year_requested.emit(int(year_box.value), minutes_box.value * 60.0))
	go.add_child(go_button)
	life.add_child(go)
	_population_label = _label("")
	_population_label.add_theme_font_size_override("font_size", 12)
	life.add_child(_population_label)
	life.add_child(_label("Kingdoms"))
	_kingdoms_box = VBoxContainer.new()
	_kingdoms_box.add_theme_constant_override("separation", 2)
	life.add_child(_kingdoms_box)
	_plans_label = _label("")
	_plans_label.add_theme_font_size_override("font_size", 12)
	_plans_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.55))
	life.add_child(_plans_label)
	_inventions_label = _label("")
	_inventions_label.add_theme_font_size_override("font_size", 12)
	_inventions_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	_inventions_label.clip_text = true
	_inventions_label.custom_minimum_size.x = 290
	life.add_child(_inventions_label)
	life.add_child(_label("Villages"))
	_villages_label = _label("")
	_villages_label.add_theme_font_size_override("font_size", 12)
	life.add_child(_villages_label)
	var head := HBoxContainer.new()
	head.add_child(_label("Events"))
	var filters := ButtonGroup.new()
	for cat in ["", "kings", "wars", "cities", "inventions", "disasters"]:
		var fb := Button.new()
		fb.text = "all" if cat == "" else cat
		fb.toggle_mode = true
		fb.button_group = filters
		fb.button_pressed = cat == ""
		fb.focus_mode = Control.FOCUS_NONE
		fb.add_theme_font_size_override("font_size", 11)
		fb.pressed.connect(func():
			_event_filter = cat
			_show_events())
		head.add_child(fb)
	life.add_child(head)
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

	# The god powers, just above the bottom bar, and the inspector card under the top bar.
	powers.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	powers.grow_horizontal = Control.GROW_DIRECTION_BOTH
	powers.grow_vertical = Control.GROW_DIRECTION_BEGIN
	powers.offset_bottom = -34
	powers.offset_top = -34
	root.add_child(powers)
	inspector.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inspector.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	inspector.offset_right = -8
	inspector.offset_left = -8
	inspector.offset_top = 40
	inspector.offset_bottom = 40
	root.add_child(inspector)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		randomize_seed()
	elif key.keycode == KEY_U:
		spawn_requested.emit(1000)
	elif key.keycode == KEY_ESCAPE:
		powers.deselect()
	elif key.keycode == KEY_BRACKETLEFT or key.keycode == KEY_BRACKETRIGHT:
		powers.step_brush(-1 if key.keycode == KEY_BRACKETLEFT else 1)
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
	_hover_label.text = _notice if Time.get_ticks_msec() < _notice_until else text


## Says something in the bottom bar for a few seconds (what a power just did, or why it didn't).
func notice(text: String, seconds := 3.0) -> void:
	_notice = text
	_notice_until = Time.get_ticks_msec() + int(seconds * 1000.0)
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
func add_event(text: String, category := "life") -> void:
	_events.insert(0, [category, text])
	if _events.size() > 200:
		_events.resize(200)
	_show_events()


## The latest events of the chosen category (kings, wars, cities, disasters; all by default).
func _show_events() -> void:
	var lines := PackedStringArray()
	for e in _events:
		if _event_filter == "" or e[0] == _event_filter:
			lines.append(e[1])
			if lines.size() >= EVENTS_SHOWN:
				break
	_events_label.text = "\n".join(lines)


## One row per kingdom: its banner, name, ruler, villages, people, wars and allies.
func set_kingdoms(kingdoms: Array) -> void:
	var seen := {}
	# The 7 biggest kingdoms, one line each (the inspector cards of 0.9 tell the rest).
	kingdoms = kingdoms.duplicate()
	kingdoms.sort_custom(func(a, b): return a.population > b.population)
	kingdoms = kingdoms.slice(0, 7)
	for k in kingdoms:
		seen[k.name] = true
		var row: Array = _kingdom_rows.get(k.name, [])
		if row.is_empty():
			var h := HBoxContainer.new()
			var icon := TextureRect.new()
			icon.texture = Banner.texture(k.color, k.banner2, k.division, k.symbol)
			icon.stretch_mode = TextureRect.STRETCH_KEEP
			h.add_child(icon)
			var l := _label("")
			l.add_theme_font_size_override("font_size", 12)
			l.clip_text = true
			l.custom_minimum_size.x = 270
			h.add_child(l)
			_kingdoms_box.add_child(h)
			row = [h, l]
			_kingdom_rows[k.name] = row
		var text := "%s (%s) %d villages, %d people" % [k.name, k.people, k.villages, k.population]
		if k.wars != "":
			text += " · ⚔ " + k.wars
		elif k.allies != "":
			text += " · ♥ " + k.allies
		row[1].text = text
		row[1].tooltip_text = "%s\ncapital %s · %d soldiers · founded year %d" % [k.ruler, k.capital, k.soldiers, k.founded]
		row[1].mouse_filter = Control.MOUSE_FILTER_PASS
	for name in _kingdom_rows.keys():
		if not seen.has(name):
			_kingdom_rows[name][0].queue_free()
			_kingdom_rows.erase(name)


## The built-in model's state, on the inventions line's tooltip and before it while it is not ready.
var _mind_text := ""


func set_mind(status: Dictionary) -> void:
	match status.status:
		"downloading":
			_mind_text = "AI mind: downloading the model, %d%%" % int(status.progress * 100.0)
		"loading":
			_mind_text = "AI mind: loading the model"
		"ready":
			_mind_text = "AI mind: %s (%d inventions)" % [status.file, status.answers]
		"failed":
			_mind_text = "AI mind unavailable (%s): procedural inventor" % status.error.left(60)
		_:
			_mind_text = ""


## The latest inventions of the peoples' minds (0.5).
func set_inventions(inventions: Array) -> void:
	var lines := PackedStringArray()
	for inv in inventions.slice(0, 3):
		var line := "✦ %s (%s, %s): %s" % [inv.name, inv.kind, inv.people, inv.effects]
		if inv.parent != "":
			line += " · from the " + inv.parent
		lines.append(line)
	if _mind_text != "":
		lines.insert(0, _mind_text)
	_inventions_label.text = "\n".join(lines)
	_inventions_label.tooltip_text = "\n".join(inventions.slice(0, 12).map(func(i): return "%s, %s by the %s in year %d%s: %s · known in %d villages (%s mind)" % [
		i.name, i.kind, i.people, i.year, (" from the " + i.parent) if i.parent != "" else "", i.effects, i.villages, i.mind]))
	_inventions_label.mouse_filter = Control.MOUSE_FILTER_PASS


## Plots under way, shown before they happen.
func set_plans(plans: Array) -> void:
	var lines := PackedStringArray()
	for p in plans:
		var what: String = {"war": "plots war on", "peace": "seeks peace with", "alliance": "courts", "rebellion": "is plotted against by"}.get(p.kind, p.kind)
		if p.kind == "rebellion":
			lines.append("⚑ %s plots to break away from %s (%d%%)" % [p.target, p.kingdom, int(p.progress * 100)])
		else:
			lines.append("⚑ %s %s %s (%d%%)" % [p.kingdom, what, p.target, int(p.progress * 100)])
	_plans_label.text = "\n".join(lines.slice(0, 4))


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
		_setup.start_requested.connect(func(races, n, ai):
			_setup.visible = false
			start_requested.emit(races, n, ai))
		_root.add_child(_setup)
	_setup.visible = true


func setup_visible() -> bool:
	return _setup != null and _setup.visible


## One line per village: name, people, population and homes, stores, what it builds.
func set_villages(villages: Array) -> void:
	var lines := PackedStringArray()
	# The biggest settlements only: the kingdoms panel tells the rest.
	var biggest := villages.duplicate()
	biggest.sort_custom(func(a, b): return a.population > b.population)
	for v in biggest.slice(0, 4):
		var line := "%s %s (%s) %d/%d · food %d · wood %d · stone %d" % [v.rank.capitalize(), v.name, v.people, v.population, v.homes, v.food, v.wood, v.stone]
		if v.metal > 0 or v.gold > 0:
			line += " · metal %d · gold %d" % [v.metal, v.gold]
		if v.building != "":
			line += " · building a %s" % v.building
		lines.append(line)
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


## Shows the speed buttons as `v` without changing the speed (after "go to year" ends).
func show_speed(v: float) -> void:
	if v == 0.0 and _speed != 0.0:
		_speed_before_pause = _speed
	_speed = v
	var k := SPEEDS.find(v)
	if k >= 0:
		_speed_buttons[k].button_pressed = true


func clear_events() -> void:
	_events.clear()
	if _events_label != null:
		_events_label.text = ""
	for name in _kingdom_rows.keys():
		_kingdom_rows[name][0].queue_free()
	_kingdom_rows.clear()


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
