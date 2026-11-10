## The interface of the game (scripts/ui/ui.gd gives it its look):
## - the title screen, then the world setup, over a new world;
## - a top bar: menu, date and season, speed of time, the world's numbers, laws and settings;
## - a dock on the left with the world's books: kingdoms and plots, villages, living creatures,
##   inventions and the chronicle;
## - the map layers on the right, the inspector card under the top bar;
## - the god powers at the bottom (scripts/ui/power_bar.gd) over a line telling what is under
##   the mouse;
## - windows: laws, settings, the pause menu.
## Buttons of features to come are there already, locked: clicking one says what it will do.
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
## The player clicked a village in the dock: show this tile.
signal focus_requested(tile: Vector2)

const UI = preload("res://scripts/ui/ui.gd")
const WorldSettings = preload("res://scripts/world/world_settings.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")
const SetupPanel = preload("res://scripts/ui/setup_panel.gd")
const Banner = preload("res://scripts/ui/banner.gd")
const PowerBar = preload("res://scripts/ui/power_bar.gd")
const Inspector = preload("res://scripts/ui/inspector.gd")
const LawsWindow = preload("res://scripts/ui/laws_window.gd")
const SettingsWindow = preload("res://scripts/ui/settings_window.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")

## Event lines kept on screen.
const EVENTS_SHOWN := 14
## Speeds of time; above ×10 is the ultra-fast mode (coarse steps, to watch centuries go by).
const SPEEDS := [0.0, 1.0, 2.0, 5.0, 10.0, 100.0]
## The dock's books: id, name, icon.
const BOOKS := [["kingdoms", "Kingdoms", "crown"], ["villages", "Villages", "house"], ["life", "Life", "paw"],
		["inventions", "Inventions", "bulb"], ["chronicle", "Chronicle", "scroll"]]
const LAYER_ICONS := {"Biomes": "biome", "Height": "height", "Temperature": "thermo", "Humidity": "humidity", "Rivers": "river"}
## Map layers to come (docs/ROADMAP.md, 0.9): name, icon.
const LAYERS_SOON := [["Kingdoms", "crown"], ["Cultures", "book"], ["Religions", "ankh"], ["Armies", "swords"]]
const SEASON_ICONS := ["spring", "summer", "autumn", "winter"]
const EVENT_FILTERS := [["", "All", "scroll"], ["kings", "Kings", "crown"], ["wars", "Wars", "swords"], ["cities", "Cities", "house"],
		["inventions", "Inventions", "bulb"], ["disasters", "Disasters", "fire"]]
const DOCK_WIDTH := 330
const DOCK_MAX_HEIGHT := 360.0

var settings: WorldSettings

## The god powers bar, the inspector card and the laws window (scripts/main.gd drives them).
var powers := PowerBar.new()
var inspector := Inspector.new()
var laws := LawsWindow.new()

var _root: Control
var _game: Control
var _hover_label: Label
var _stats_label: Label
var _time_label: Label
var _season_icon: TextureRect
var _toast: PanelContainer
var _toast_label: Label
var _toast_until := 0
var _layer_buttons := {}
var _world_stats := ""
var _sprite_count := 0
var _sim_stats := ""
var _counts := {}
var _speed_buttons := []
var _speed := 1.0
var _speed_before_pause := 1.0
var _go_box: PanelContainer
## The dock: one page per book.
var _book := "kingdoms"
var _dock: PanelContainer
var _dock_title: Label
var _dock_scroll: ScrollContainer
var _dock_icon: TextureRect
var _pages := {}
var _book_buttons := {}
var _events_label: Label
## Recent events as [category, text], newest first, and the category shown ("" = all).
var _events: Array = []
var _event_filter := ""
var _kingdoms_box: VBoxContainer
var _plans_label: Label
var _inventions_label: Label
var _mind_label: Label
## Kingdom rows by name: banner and text are updated in place.
var _kingdom_rows := {}
var _village_rows: Array = []
var _villages_box: VBoxContainer
var _life_rows: Array = []
var _life_box: VBoxContainer
## The built-in model's state, shown over the inventions.
var _mind_text := ""
## Village names drawn over the map.
var _name_labels: Array[Label] = []
var _labels_on := true
## Screens and windows over the game.
var _setup: PanelContainer
var _title: Control
var _shade: ColorRect
var _settings_window := SettingsWindow.new()
var _pause := PauseMenu.new()
## Whether the title screen is still to be left (the setup waits behind it).
var _at_title := true
## The speed of time before the pause menu opened.
var _speed_before_menu := -1.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)
	_root = root
	# Menus and tooltips are windows of their own: they take the theme from the game's window.
	if is_inside_tree():
		get_window().theme = UI.theme()

	# Everything of the game itself, hidden behind the title screen and the world setup.
	_game = Control.new()
	_game.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_game)
	_build_bottom()
	_build_top()
	_build_dock()
	_build_layers()

	inspector.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inspector.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	inspector.offset_right = -64
	inspector.offset_left = -64
	inspector.offset_top = 62
	inspector.offset_bottom = 62
	inspector.soon_requested.connect(_soon)
	_game.add_child(inspector)

	# What a power just did, or why it didn't: a line under the top bar, for a few seconds.
	_toast = PanelContainer.new()
	_toast.theme_type_variation = "Toast"
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 62
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_label = UI.label("")
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(_toast_label)
	root.add_child(_toast)

	# The world setup, on the left of a new world.
	_setup = SetupPanel.new()
	_setup.settings = settings
	_setup.visible = false
	_setup.start_requested.connect(func(races, n, ai):
		_setup.visible = false
		_refresh_screens()
		start_requested.emit(races, n, ai))
	_setup.generate_requested.connect(func(): generate_requested.emit())
	_setup.back_requested.connect(_show_title)
	root.add_child(_setup)

	# Windows, over a shade that keeps clicks off the map.
	_shade = ColorRect.new()
	_shade.color = Color(UI.INK, 0.6)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.visible = false
	root.add_child(_shade)
	_title = MainMenu.new()
	_title.chosen.connect(_on_title)
	root.add_child(_title)
	for window in [laws, _pause, _settings_window]:
		window.closed.connect(_refresh_screens)
		root.add_child(window)
	_pause.closed.connect(_leave_pause)
	_pause.chosen.connect(_on_pause)
	_settings_window.dev_stats_toggled.connect(func(on): _stats_label.visible = on)
	_settings_window.map_labels_toggled.connect(func(on):
		_labels_on = on
		if not on:
			set_map_labels([]))
	powers.soon_requested.connect(_soon)
	_refresh_screens()


# ------------------------------------------------------------------ building the interface

func _build_top() -> void:
	var top := PanelContainer.new()
	top.theme_type_variation = "Bar"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_game.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	top.add_child(bar)

	var menu := UI.tool_button(UI.icon("menu"), "Menu (Esc)", 40)
	menu.pressed.connect(_open_pause)
	bar.add_child(menu)

	# The date.
	var date := PanelContainer.new()
	date.theme_type_variation = "Chip"
	date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(date)
	var date_row := HBoxContainer.new()
	date_row.add_theme_constant_override("separation", 6)
	date.add_child(date_row)
	_season_icon = UI.picture(UI.icon("spring"))
	date_row.add_child(_season_icon)
	_time_label = UI.label("", "Heading")
	_time_label.custom_minimum_size.x = 190
	_time_label.add_theme_color_override("font_color", UI.CREAM)
	date_row.add_child(_time_label)

	# The speed of time.
	var speed_group := ButtonGroup.new()
	for v in SPEEDS:
		var b: Button
		if v == 0.0:
			b = UI.tool_button(UI.icon("pause", 1), "", 36)
		elif v > 10.0:
			b = UI.tool_button(UI.icon("fast", 1), "", 36)
		else:
			b = UI.button("×%d" % v, "", "", "Tool")
			b.custom_minimum_size = Vector2(36, 36)
		b.toggle_mode = true
		b.button_group = speed_group
		b.button_pressed = v == 1.0
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = ("Pause" if v == 0.0 else ("Ultra: ×100, in coarser steps (a century in a minute)" if v > 10.0 else "Time ×%d" % v)) \
				+ "\nSpace: pause / resume · , and . : slower / faster"
		b.pressed.connect(func(): _set_speed(v))
		bar.add_child(b)
		_speed_buttons.append(b)
	var go := UI.tool_button(UI.icon("hourglass", 1), "Go to a year: time runs there and pauses", 36)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func(): _go_box.visible = not _go_box.visible)
	bar.add_child(go)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(gap)

	# The world's numbers.
	for count in [["people", "people", "People alive"], ["villages", "house", "Villages, towns and cities"],
			["kingdoms", "crown", "Kingdoms"], ["animals", "paw", "Animals and monsters"]]:
		var chip: Array = UI.chip(count[1], count[2])
		chip[1].custom_minimum_size.x = 30
		bar.add_child(chip[0])
		_counts[count[0]] = chip[1]

	var gap2 := Control.new()
	gap2.custom_minimum_size.x = 8
	bar.add_child(gap2)

	var laws_button := UI.tool_button(UI.icon("scales"), "Laws of the world", 40)
	laws_button.pressed.connect(func(): _open(laws))
	bar.add_child(laws_button)
	for soon in [["chart", "Statistics", "Graphs of populations, wars and inventions through the years."],
			["star", "Favourites", "The creatures and villages you follow."],
			["save", "Save the world", "Keep this world and come back to it later."]]:
		var b := UI.tool_button(UI.icon(soon[0]), "%s (coming later)\n%s" % [soon[1], soon[2]], 40)
		UI.mark_soon(b)
		b.pressed.connect(func(): _soon(soon[1], soon[2]))
		bar.add_child(b)
	var settings_button := UI.tool_button(UI.icon("gear"), "Settings", 40)
	settings_button.pressed.connect(func(): _open(_settings_window))
	bar.add_child(settings_button)

	# "Go to year", under its button: the year to reach and how long it may take.
	_go_box = PanelContainer.new()
	_go_box.visible = false
	_go_box.position = Vector2(300, 60)
	_game.add_child(_go_box)
	var go_row := HBoxContainer.new()
	_go_box.add_child(go_row)
	go_row.add_child(UI.label("Go to year"))
	var year_box := _spin(2, 1000000, 1, 100)
	year_box.tooltip_text = "The year to reach; time pauses there"
	go_row.add_child(year_box)
	go_row.add_child(UI.label("in"))
	var minutes_box := _spin(0, 600, 0.5, 2)
	minutes_box.suffix = "min"
	minutes_box.tooltip_text = "Real time it should take (0 = as fast as the computer can)"
	go_row.add_child(minutes_box)
	var go_button := UI.button("Go", "play", "", "Primary")
	go_button.add_theme_font_size_override("font_size", UI.SIZE)
	go_button.pressed.connect(func():
		_go_box.visible = false
		for b in _speed_buttons:
			b.set_pressed_no_signal(false)
		go_to_year_requested.emit(int(year_box.value), minutes_box.value * 60.0))
	go_row.add_child(go_button)


func _build_dock() -> void:
	# The books' tabs, down the left edge.
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.position = Vector2(6, 64)
	_game.add_child(tabs)
	for book in BOOKS:
		var b := UI.tool_button(UI.icon(book[2]), book[1], 44)
		b.toggle_mode = true
		b.pressed.connect(_show_book.bind(book[0], true))
		tabs.add_child(b)
		_book_buttons[book[0]] = b

	_dock = PanelContainer.new()
	_dock.position = Vector2(56, 64)
	_dock.custom_minimum_size.x = DOCK_WIDTH
	_game.add_child(_dock)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_dock.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)
	_dock_icon = UI.picture(null)
	head.add_child(_dock_icon)
	_dock_title = UI.label("", "Title")
	_dock_title.add_theme_font_size_override("font_size", UI.SIZE)
	head.add_child(_dock_title)
	column.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(DOCK_WIDTH, 120)
	column.add_child(scroll)
	_dock_scroll = scroll
	var pages := MarginContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	for book in BOOKS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 4)
		page.visible = false
		pages.add_child(page)
		_pages[book[0]] = page

	# Kingdoms, and what their rulers plot.
	_kingdoms_box = VBoxContainer.new()
	_kingdoms_box.add_theme_constant_override("separation", 4)
	_pages["kingdoms"].add_child(_kingdoms_box)
	_pages["kingdoms"].add_child(UI.label("Plots", "Heading"))
	_plans_label = _text("No ruler plots anything.", UI.GOLD)
	_pages["kingdoms"].add_child(_plans_label)

	_villages_box = VBoxContainer.new()
	_villages_box.add_theme_constant_override("separation", 4)
	_pages["villages"].add_child(_villages_box)

	_life_box = VBoxContainer.new()
	_life_box.add_theme_constant_override("separation", 2)
	_pages["life"].add_child(_life_box)
	var more := UI.button("+1000 animals", "paw", "Bring 1000 wandering animals (U): a test of the simulation's speed")
	more.pressed.connect(func(): spawn_requested.emit(1000))
	_pages["life"].add_child(more)

	_mind_label = _text("", UI.MUTED)
	_pages["inventions"].add_child(_mind_label)
	_inventions_label = _text("Nothing invented yet.", UI.BLUE)
	_pages["inventions"].add_child(_inventions_label)

	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 3)
	var group := ButtonGroup.new()
	for filter in EVENT_FILTERS:
		var fb := UI.tool_button(UI.icon(filter[2], 1), filter[1], 30)
		fb.toggle_mode = true
		fb.button_group = group
		fb.button_pressed = filter[0] == ""
		fb.pressed.connect(func():
			_event_filter = filter[0]
			_show_events())
		filters.add_child(fb)
	_pages["chronicle"].add_child(filters)
	_events_label = _text("", UI.CREAM)
	_pages["chronicle"].add_child(_events_label)
	_show_book(_book, false)


func _build_layers() -> void:
	var side := PanelContainer.new()
	side.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.offset_top = 64
	side.offset_bottom = 64
	side.offset_right = -6
	side.offset_left = -6
	side.add_theme_stylebox_override("panel", UI.box(Color(UI.PANEL, 0.96), UI.INK, 3, 8, 4, 3))
	_game.add_child(side)
	var layers := VBoxContainer.new()
	layers.add_theme_constant_override("separation", 3)
	side.add_child(layers)
	var group := ButtonGroup.new()
	for k in MapRenderer.LAYERS.size():
		var layer: String = MapRenderer.LAYERS[k]
		var b := UI.tool_button(UI.icon(LAYER_ICONS.get(layer, "layers")), "Map of %s (%d)" % [layer.to_lower(), k + 1], 40)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == 0
		b.pressed.connect(func(): layer_selected.emit(layer))
		layers.add_child(b)
		_layer_buttons[layer] = b
	layers.add_child(HSeparator.new())
	for soon in LAYERS_SOON:
		var b := UI.tool_button(UI.icon(soon[1]), "Map of %s (coming later)" % soon[0].to_lower(), 40)
		UI.mark_soon(b)
		b.pressed.connect(func(): _soon("The map of %s" % soon[0].to_lower(), "It will colour the land by %s." % soon[0].to_lower()))
		layers.add_child(b)


func _build_bottom() -> void:
	# The line at the very bottom: what is under the mouse, and the developer's figures.
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var strip := UI.box(Color(UI.INK, 0.88), UI.INK, 0, 0, 3)
	strip.content_margin_left = 10
	strip.content_margin_right = 10
	bottom.add_theme_stylebox_override("panel", strip)
	_game.add_child(bottom)
	var info := HBoxContainer.new()
	bottom.add_child(info)
	_hover_label = UI.label("", "Small")
	_hover_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The figures on the right keep their room; the hover text is cut if it doesn't fit.
	_hover_label.clip_text = true
	info.add_child(_hover_label)
	_stats_label = UI.label("", "Muted")
	info.add_child(_stats_label)

	# The god powers, just above it.
	powers.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	powers.grow_horizontal = Control.GROW_DIRECTION_BOTH
	powers.grow_vertical = Control.GROW_DIRECTION_BEGIN
	powers.offset_bottom = -30
	powers.offset_top = -30
	_game.add_child(powers)


# ------------------------------------------------------------------ screens and windows

## Whether something stands between the player and the map: the title, the setup, a window.
func blocking() -> bool:
	return _at_title or setup_visible() or laws.visible or _pause.visible or _settings_window.visible


func setup_visible() -> bool:
	return _setup != null and _setup.visible


## Shows the world setup (the land and its peoples) over a new world; it waits behind the title
## screen until the player leaves it.
func show_setup() -> void:
	_setup.visible = not _at_title
	_refresh_screens()


## Leaves the title screen for the world setup (or for the game, when the setup is done).
func leave_title() -> void:
	_at_title = false


func _show_title() -> void:
	_at_title = true
	_setup.visible = false
	_pause.visible = false
	_refresh_screens()


func _refresh_screens() -> void:
	_title.visible = _at_title
	_game.visible = not _at_title and not setup_visible()
	_shade.visible = not _at_title and (laws.visible or _pause.visible or _settings_window.visible)
	for l in _name_labels:
		l.visible = l.visible and _game.visible


func _open(window: Control) -> void:
	window.open()
	# The window in front of the others.
	_root.move_child(window, -1)
	_refresh_screens()


func _on_title(what: String) -> void:
	match what:
		"new_world":
			_at_title = false
			show_setup()
		"settings":
			_open(_settings_window)
		"credits":
			notice("Animundi · a god sandbox in the spirit of WorldBox and Cult of the Lamb · font Pixelify Sans (OFL)", 6.0)
		"quit":
			get_tree().quit()
		_:
			_soon("Saved worlds", "Keep a world and come back to it later.")


func _open_pause() -> void:
	if _speed_before_menu < 0.0:
		_speed_before_menu = _speed
		_set_speed(0.0)
	_open(_pause)


## Time runs again as before the pause menu.
func _leave_pause() -> void:
	if _speed_before_menu >= 0.0:
		var before := _speed_before_menu
		_speed_before_menu = -1.0
		if not _at_title and not setup_visible():
			_set_speed(before)


func _on_pause(what: String) -> void:
	match what:
		"resume":
			_pause.close()
		"settings":
			_open(_settings_window)
		"new_world":
			_speed_before_menu = -1.0
			_pause.close()
			generate_requested.emit()
		"title":
			_speed_before_menu = -1.0
			_pause.close()
			generate_requested.emit()
			_show_title()
		"quit":
			get_tree().quit()
		_:
			_soon("Saved worlds", "Keep a world and come back to it later.")


## Says what a feature to come will do.
func _soon(feature: String, what: String) -> void:
	notice("%s comes in a later version. %s" % [feature, what], 4.5)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		# Esc closes what is open, then drops the power, then opens the menu.
		if _settings_window.visible:
			_settings_window.close()
		elif laws.visible:
			laws.close()
		elif _pause.visible:
			_pause.close()
		elif _go_box.visible:
			_go_box.visible = false
		elif _at_title or setup_visible():
			pass
		elif powers.power != "inspect":
			powers.deselect()
		else:
			_open_pause()
		return
	if _at_title or laws.visible or _pause.visible or _settings_window.visible:
		return
	if key.keycode == KEY_R:
		randomize_seed()
	elif setup_visible():
		return
	elif key.keycode == KEY_U:
		spawn_requested.emit(1000)
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


func _process(_delta: float) -> void:
	# The dock is as tall as its page, up to a limit; then it scrolls.
	if _dock != null and _dock.visible:
		var tall: float = clampf(_pages[_book].get_combined_minimum_size().y, 40.0, DOCK_MAX_HEIGHT)
		if _dock_scroll.custom_minimum_size.y != tall:
			_dock_scroll.custom_minimum_size.y = tall
			_dock.reset_size()
	if _toast != null and _toast.visible and Time.get_ticks_msec() >= _toast_until:
		_toast.visible = false


# ------------------------------------------------------------------ what the game tells

func randomize_seed() -> void:
	_setup.randomize_seed()


func set_hover_text(text: String) -> void:
	_hover_label.text = text


## Says something under the top bar for a few seconds (what a power just did, or why it didn't).
func notice(text: String, seconds := 3.0) -> void:
	_toast_label.text = text
	_toast_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	_toast.visible = true
	_toast.reset_size()


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


## The world's numbers in the top bar.
func set_counts(people: int, villages: int, kingdoms: int, animals: int) -> void:
	_counts["people"].text = str(people)
	_counts["villages"].text = str(villages)
	_counts["kingdoms"].text = str(kingdoms)
	_counts["animals"].text = str(animals)


## "Year 3 · Winter".
func set_time(text: String) -> void:
	_time_label.text = text


## The season's icon beside the date (0 = spring).
func set_season(season: int) -> void:
	_season_icon.texture = UI.icon(SEASON_ICONS[clampi(season, 0, 3)])


## A line in the chronicle (newest first).
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
	_events_label.text = "\n\n".join(lines) if not lines.is_empty() else "Nothing to tell yet."


## One card per kingdom: its banner, name, ruler, villages, people, wars and allies.
func set_kingdoms(kingdoms: Array) -> void:
	var seen := {}
	kingdoms = kingdoms.duplicate()
	kingdoms.sort_custom(func(a, b): return a.population > b.population)
	kingdoms = kingdoms.slice(0, 12)
	for k in kingdoms:
		seen[k.name] = true
		var row: Array = _kingdom_rows.get(k.name, [])
		if row.is_empty():
			var card := PanelContainer.new()
			card.theme_type_variation = "Card"
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 8)
			card.add_child(h)
			h.add_child(UI.picture(Banner.texture(k.color, k.banner2, k.division, k.symbol)))
			var text := VBoxContainer.new()
			text.add_theme_constant_override("separation", 0)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(text)
			var name_label := UI.label(k.name)
			name_label.clip_text = true
			text.add_child(name_label)
			var about := UI.label("", "Muted")
			about.clip_text = true
			text.add_child(about)
			var state := UI.label("", "Muted")
			state.clip_text = true
			text.add_child(state)
			_kingdoms_box.add_child(card)
			row = [card, name_label, about, state]
			_kingdom_rows[k.name] = row
		row[1].text = "%s · %s" % [k.name, k.people]
		row[2].text = "%d villages · %d people · %d soldiers" % [k.villages, k.population, k.soldiers]
		if k.wars != "":
			row[3].text = "At war with " + k.wars
			row[3].add_theme_color_override("font_color", UI.CRIMSON.lightened(0.2))
		elif k.allies != "":
			row[3].text = "Allied with " + k.allies
			row[3].add_theme_color_override("font_color", UI.GREEN)
		else:
			row[3].text = k.ruler
			row[3].add_theme_color_override("font_color", UI.MUTED)
		row[0].tooltip_text = "%s\ncapital %s · %d soldiers · founded year %d" % [k.ruler, k.capital, k.soldiers, k.founded]
	for name in _kingdom_rows.keys():
		if not seen.has(name):
			_kingdom_rows[name][0].queue_free()
			_kingdom_rows.erase(name)


func set_mind(status: Dictionary) -> void:
	match status.status:
		"downloading":
			_mind_text = "AI mind: downloading the model, %d%%" % int(status.progress * 100.0)
		"loading":
			_mind_text = "AI mind: loading the model"
		"ready":
			_mind_text = "AI mind: %s (%d inventions)" % [status.file, status.answers]
		"failed":
			_mind_text = "AI mind unavailable (%s): the procedural inventor invents" % status.error.left(60)
		_:
			_mind_text = "The procedural inventor invents."
	_mind_label.text = _mind_text


## The latest inventions of the peoples' minds (0.5).
func set_inventions(inventions: Array) -> void:
	var lines := PackedStringArray()
	for inv in inventions.slice(0, 10):
		var line := "%s (%s, %s, year %d)\n%s" % [inv.name, inv.kind, inv.people, inv.year, inv.effects]
		if inv.parent != "":
			line += " · from the " + inv.parent
		lines.append(line)
	_inventions_label.text = "\n\n".join(lines) if not lines.is_empty() else "Nothing invented yet."


## Plots under way, shown before they happen.
func set_plans(plans: Array) -> void:
	var lines := PackedStringArray()
	for p in plans:
		var what: String = {"war": "plots war on", "peace": "seeks peace with", "alliance": "courts", "rebellion": "is plotted against by"}.get(p.kind, p.kind)
		if p.kind == "rebellion":
			lines.append("%s plots to break away from %s (%d%%)" % [p.target, p.kingdom, int(p.progress * 100)])
		else:
			lines.append("%s %s %s (%d%%)" % [p.kingdom, what, p.target, int(p.progress * 100)])
	_plans_label.text = "\n".join(lines.slice(0, 8)) if not lines.is_empty() else "No ruler plots anything."


## Living creatures by species name, the most numerous first.
func set_populations(table: Dictionary) -> void:
	var names := table.keys()
	names.sort_custom(func(a, b): return table[a] > table[b])
	var most := 1
	for n in names:
		most = maxi(most, table[n])
	while _life_rows.size() < names.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := UI.picture(null)
		icon.custom_minimum_size = Vector2(30, 24)
		row.add_child(icon)
		var name_label := UI.label("", "Small")
		name_label.custom_minimum_size.x = 86
		row.add_child(name_label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size.y = 10
		row.add_child(bar)
		var count := UI.label("", "Small")
		count.custom_minimum_size.x = 40
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(count)
		_life_box.add_child(row)
		_life_rows.append([row, icon, name_label, bar, count])
	for k in _life_rows.size():
		var row: Array = _life_rows[k]
		row[0].visible = k < names.size()
		if row[0].visible:
			var n: String = names[k]
			if row[2].text != n:
				row[2].text = n
				row[1].texture = UI.creature(n.to_lower(), 24)
			row[3].max_value = most
			row[3].value = table[n]
			row[4].text = str(table[n])


## One card per village: name, people, population and homes, stores, what it builds. Clicking
## a card shows the village.
func set_villages(villages: Array) -> void:
	var biggest := villages.duplicate()
	biggest.sort_custom(func(a, b): return a.population > b.population)
	biggest = biggest.slice(0, 20)
	while _village_rows.size() < biggest.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		UI.small(b)
		b.custom_minimum_size.x = DOCK_WIDTH - 14
		var k := _village_rows.size()
		b.pressed.connect(func(): focus_requested.emit(_village_rows[k][1]))
		_villages_box.add_child(b)
		_village_rows.append([b, Vector2.ZERO])
	for k in _village_rows.size():
		var row: Array = _village_rows[k]
		row[0].visible = k < biggest.size()
		if row[0].visible:
			var v: Dictionary = biggest[k]
			var line := "%s %s · %s · %d/%d\nfood %d · wood %d · stone %d" % [v.rank.capitalize(), v.name, v.people, v.population, v.homes, v.food, v.wood, v.stone]
			if v.metal > 0 or v.gold > 0:
				line += " · metal %d · gold %d" % [v.metal, v.gold]
			if v.building != "":
				line += "\nbuilding a %s" % v.building
			row[0].text = line
			row[0].tooltip_text = "Show %s" % v.name
			row[1] = Vector2(v.x, v.y)


## Village names over the map: `labels` is [[name, screen position], ...].
func set_map_labels(labels: Array) -> void:
	if not _labels_on or not _game.visible:
		labels = []
	while _name_labels.size() < labels.size():
		var l := Label.new()
		l.add_theme_color_override("font_color", UI.CREAM)
		l.add_theme_color_override("font_outline_color", UI.INK)
		l.add_theme_constant_override("outline_size", 6)
		UI.small(l)
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


## Changes the speed of time and shows it on the buttons.
func _set_speed(v: float) -> void:
	show_speed(v)
	speed_selected.emit(v)


## Shows the speed buttons as `v` without changing the speed (after "go to year" ends).
func show_speed(v: float) -> void:
	if v == 0.0 and _speed != 0.0:
		_speed_before_pause = _speed
	_speed = v
	var k := SPEEDS.find(v)
	if k >= 0:
		_speed_buttons[k].set_pressed_no_signal(true)
		for other in _speed_buttons.size():
			if other != k:
				_speed_buttons[other].set_pressed_no_signal(false)


func clear_events() -> void:
	_events.clear()
	if _events_label != null:
		_show_events()
	for name in _kingdom_rows.keys():
		_kingdom_rows[name][0].queue_free()
	_kingdom_rows.clear()


## Opens a book of the dock. Clicking the open book's tab closes the dock, to see more map.
func _show_book(id: String, from_click: bool) -> void:
	var open := not (from_click and id == _book and _dock.visible)
	_book = id
	_dock.visible = open
	for book in BOOKS:
		_pages[book[0]].visible = book[0] == id
		_book_buttons[book[0]].set_pressed_no_signal(open and book[0] == id)
		if book[0] == id:
			_dock_title.text = book[1]
			_dock_icon.texture = UI.icon(book[2])


## Text of a book's page: small, wrapped to the dock's width.
func _text(text: String, colour: Color) -> Label:
	var l := UI.label(text, "Small")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = DOCK_WIDTH - 14
	l.add_theme_color_override("font_color", colour)
	return l


func _spin(lo: float, hi: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	return s
