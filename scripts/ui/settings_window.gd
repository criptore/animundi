## Settings: game, display, sound and controls. Display and interface settings act at once;
## sound waits for the game's sounds (docs/ROADMAP.md, 1.0) and language for translations.
extends "res://scripts/ui/window.gd"

## Developer figures in the bottom bar (seed, plants, step time, frames per second).
## The autosave (1.0) was switched.
## A volume was moved (1.0): bus (Master, Music, Effects, Ambience) and 0..1.
## Switches of 1.0: pause on great events, screen shake, weather particles.
signal pause_on_events_toggled(on: bool)
signal shake_toggled(on: bool)
signal weather_toggled(on: bool)
signal volume_changed(bus: String, value: float)
signal autosave_toggled(on: bool)
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
	["Tilt view / flat map", "V"],
	["Hour of the day (tilt view)", "T"],
	["New random world", "R"],
	["Menu", "Esc"],
]

var _mods_label: Label
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
	_switch(box, "Save the world every ten years", true, false).toggled.connect(func(on): autosave_toggled.emit(on))
	_switch(box, "Pause when a great event happens", false, false).toggled.connect(func(on): pause_on_events_toggled.emit(on))
	_mods_label = UI.label("No mods: put them in the game's data folder, under mods/.", "Muted")
	_mods_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mods_label.custom_minimum_size.x = 380
	box.add_child(_mods_label)


## The mods found and what each brought (the simulation's ModTable).
func set_mods(mods: Dictionary) -> void:
	if _mods_label == null:
		return
	if mods.is_empty():
		_mods_label.text = "No mods: put them in %s (docs/MODS.md)." % ProjectSettings.globalize_path("user://mods")
		return
	var lines := PackedStringArray(["Mods:"])
	for name in mods:
		lines.append("%s · %s" % [name, mods[name]])
	_mods_label.text = "\n".join(lines)


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
	_switch(box, "Screen shake on disasters", true, false).toggled.connect(func(on): shake_toggled.emit(on))
	_switch(box, "Weather and magic particles", true, false).toggled.connect(func(on): weather_toggled.emit(on))


func _sound(box: VBoxContainer) -> void:
	for channel in [["Master", 80], ["Music", 55], ["Effects", 80], ["Ambience", 35]]:
		var s := _slider(0, 100, 5, channel[1], "%d%%")
		var bus: String = channel[0]
		s[0].value_changed.connect(func(v): volume_changed.emit(bus, v / 100.0))
		_row(box, bus, s[1])
	var note := UI.label("Every sound and the music are made by the game as it plays; the music follows the mood of the world.", "Muted")
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
