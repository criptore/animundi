## World-generation HUD: seed and settings bar, map layer buttons, hovered tile info, stage timings.
extends CanvasLayer

signal generate_requested
signal layer_selected(layer: String)
signal effects_toggled(on: bool)

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")

var settings: WorldSettings

var _seed_edit: LineEdit
var _size_option: OptionButton
var _continents: SpinBox
var _water: SpinBox
var _climate: SpinBox
var _hover_label: Label
var _stats_label: Label
var _layer_buttons := {}
var _effects: CheckButton


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

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
	_effects = CheckButton.new()
	_effects.text = "Effects (E)"
	_effects.button_pressed = true
	_effects.toggled.connect(func(on): effects_toggled.emit(on))
	layers.add_child(_effects)
	var help := _label("\nWheel: zoom\nRight drag / WASD: pan\nR: random seed")
	help.add_theme_font_size_override("font_size", 12)
	layers.add_child(help)

	# Bottom: hovered tile, generation stats, controls help.
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	var info := HBoxContainer.new()
	bottom.add_child(info)
	_hover_label = _label("")
	_hover_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_hover_label)
	_stats_label = _label("")
	info.add_child(_stats_label)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		randomize_seed()
	elif key.keycode == KEY_E:
		_effects.button_pressed = not _effects.button_pressed
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
	_stats_label.text = "Seed %d · %dx%d · generated in %.0f ms" % [world.seed_value, world.width, world.height, total]


func _request() -> void:
	settings.seed_text = _seed_edit.text if _seed_edit.text.strip_edges() != "" else "animundi"
	settings.set_size(WorldSettings.SIZES.values()[_size_option.selected])
	settings.continents = int(_continents.value)
	settings.water_ratio = _water.value / 100.0
	settings.temperature_offset = _climate.value / 100.0
	generate_requested.emit()


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
