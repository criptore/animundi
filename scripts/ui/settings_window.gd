## Settings: game, display, sound and controls. Display and interface settings act at once;
## sound waits for the game's sounds (docs/ROADMAP.md, 1.0) and language for translations.
extends "res://scripts/ui/window.gd"

## Developer figures in the bottom bar (seed, plants, step time, frames per second).
signal dev_stats_toggled(on: bool)
## Village names over the map.
signal map_labels_toggled(on: bool)

const PAGES := [["game", "Game", "gear"], ["display", "Display", "monitor"], ["sound", "Sound", "note"], ["controls", "Controls", "keys"]]

const CONTROLS := [
	["Zoom", "mouse wheel, pinch, + and −"],
	["Move", "drag, two fingers, WASD, arrows"],
	["Pause / resume", "Space"],
	["Slower / faster time", ", and ."],
	["Use a power", "pick it below, click or drag the map"],
	["Back to Inspect", "Esc"],
	["Brush size", "[ and ]"],
	["Follow a creature or village", "click it with Inspect"],
	["Map layers", "1 to 5"],
	["New random world", "R"],
	["Menu", "Esc"],
]

var _pages := {}
var _page_buttons := {}


func _init() -> void:
	build("Settings", "gear", 520)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	body.add_child(tabs)
	var group := ButtonGroup.new()
	for page in PAGES:
		var b := UI.button(page[1], page[2])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show.bind(page[0]))
		tabs.add_child(b)
		_page_buttons[page[0]] = b
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		box.custom_minimum_size.y = 300
		box.visible = false
		body.add_child(box)
		_pages[page[0]] = box
	_game(_pages["game"])
	_display(_pages["display"])
	_sound(_pages["sound"])
	_controls(_pages["controls"])
	_show("game")


func _show(id: String) -> void:
	for p in _pages:
		_pages[p].visible = p == id
	_page_buttons[id].set_pressed_no_signal(true)


func _game(box: VBoxContainer) -> void:
	var language := OptionButton.new()
	language.focus_mode = Control.FOCUS_NONE
	language.add_item("English")
	language.add_item("Français (later)")
	language.set_item_disabled(1, true)
	_row(box, "Language", language)
	var scale := _slider(75, 150, 5, 100, "%d%%")
	scale[0].drag_ended.connect(func(_changed): _set_scale(scale[0].value / 100.0))
	_row(box, "Interface size", scale[1])
	_switch(box, "Village names on the map", true, false).toggled.connect(func(on): map_labels_toggled.emit(on))
	_switch(box, "Developer figures in the bottom bar", true, false).toggled.connect(func(on): dev_stats_toggled.emit(on))
	_switch(box, "Save the world every year", false, true)
	_switch(box, "Pause when a great event happens", false, true)


func _display(box: VBoxContainer) -> void:
	_switch(box, "Full screen", false, false).toggled.connect(func(on):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	_switch(box, "Vertical sync", true, false).toggled.connect(func(on):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED))
	var fps := OptionButton.new()
	fps.focus_mode = Control.FOCUS_NONE
	for limit in [0, 30, 60, 120, 144]:
		fps.add_item("No limit" if limit == 0 else "%d" % limit)
		fps.set_item_metadata(fps.item_count - 1, limit)
	fps.item_selected.connect(func(k): Engine.max_fps = fps.get_item_metadata(k))
	_row(box, "Frames per second", fps)
	_switch(box, "Screen shake on disasters", true, true)
	_switch(box, "Weather and magic particles", true, true)


func _sound(box: VBoxContainer) -> void:
	for channel in ["Master", "Music", "Effects", "Ambience"]:
		var s := _slider(0, 100, 5, 80, "%d%%")
		s[0].editable = false
		_row(box, channel, s[1])
	var note := UI.label("The world is silent for now: sounds and music come with version 1.0.", "Muted")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)


func _controls(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	box.add_child(grid)
	for line in CONTROLS:
		grid.add_child(UI.label(line[0], "Small"))
		var keys := UI.label(line[1], "Muted")
		keys.add_theme_color_override("font_color", UI.GOLD)
		grid.add_child(keys)


func _row(box: VBoxContainer, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := UI.label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 220)
	row.add_child(control)
	box.add_child(row)


func _switch(box: VBoxContainer, text: String, on: bool, soon: bool) -> CheckButton:
	var check := CheckButton.new()
	check.focus_mode = Control.FOCUS_NONE
	check.button_pressed = on
	check.disabled = soon
	if soon:
		check.tooltip_text = "Comes in a later version"
	var row := HBoxContainer.new()
	var l := UI.label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if soon:
		l.add_theme_color_override("font_color", UI.DIM)
		row.add_child(UI.picture(UI.icon("lock", 1)))
	row.add_child(l)
	row.add_child(check)
	box.add_child(row)
	return check


## A slider and its value: returns [slider, the row holding both].
func _slider(lo: float, hi: float, step: float, value: float, format: String) -> Array:
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var l := UI.label(format % int(value), "Small")
	l.custom_minimum_size.x = 46
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v): l.text = format % int(v))
	row.add_child(l)
	return [s, row]


func _set_scale(factor: float) -> void:
	if is_inside_tree():
		get_window().content_scale_factor = factor
		_center.call_deferred()
