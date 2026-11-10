## World setup, shown on a new world before time starts. On the left of the screen, so the world
## shows beside it: the land (seed, size, continents, water, climate; reshaping it redraws the
## map at once), then the peoples that will live in it (at least two) and how many found each
## village. Then the player starts the world and watches.
extends PanelContainer

const UI = preload("res://scripts/ui/ui.gd")
const Races = preload("res://scripts/world/races.gd")
const WorldSettings = preload("res://scripts/world/world_settings.gd")

## The player started the world with these peoples (ids from data/races.json).
## `ai`: the built-in language model invents for the peoples (0.5); it is downloaded once.
signal start_requested(races: PackedStringArray, per_village: int, ai: bool)
## The land's settings changed (they are written to `settings`): the world must be made again.
signal generate_requested
## Back to the title screen.
signal back_requested

## Peoples ticked when the panel first opens.
const DEFAULT := ["Humans", "Elves", "Orcs"]
const MIN_PEOPLES := 2

## The settings of the world being made (scripts/main.gd owns them).
var settings: WorldSettings = WorldSettings.new()

var _boxes := {}
var _per_village: HSlider
var _start: Button
var _hint: Label
var _ai: CheckButton
var _seed_edit: LineEdit
var _size_option: OptionButton
var _continents: HSlider
var _water: HSlider
var _climate: HSlider


func _ready() -> void:
	custom_minimum_size.x = 440
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	head.add_child(UI.picture(UI.icon("globe")))
	var title := UI.label("A new world", "Title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := UI.button("Title", "door", "Back to the title screen", "Ghost")
	back.pressed.connect(func(): back_requested.emit())
	head.add_child(back)

	# The land.
	box.add_child(UI.label("The land", "Heading"))
	var seed_row := HBoxContainer.new()
	box.add_child(seed_row)
	var seed_label := UI.label("Seed")
	seed_label.custom_minimum_size.x = 110
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.text = settings.seed_text
	_seed_edit.tooltip_text = "Any word or number: the same seed and settings always give the same world"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_submitted.connect(func(_t):
		_seed_edit.release_focus()
		request())
	seed_row.add_child(_seed_edit)
	var random_button := UI.tool_button(UI.icon("dice", 1), "A random world (R)", 34)
	random_button.pressed.connect(randomize_seed)
	seed_row.add_child(random_button)

	_size_option = OptionButton.new()
	_size_option.focus_mode = Control.FOCUS_NONE
	for size_name in WorldSettings.SIZES:
		_size_option.add_item("%s (%d × %d)" % [size_name, WorldSettings.SIZES[size_name], WorldSettings.SIZES[size_name]])
	_size_option.select(maxi(WorldSettings.SIZES.values().find(settings.width), 0))
	_size_option.item_selected.connect(func(_k): request())
	_row(box, "Size", _size_option)
	_continents = _slider(box, "Continents", 1, 8, 1, settings.continents, "%d", "")
	_water = _slider(box, "Water", 20, 85, 5, roundi(settings.water_ratio * 100), "%d%%", "")
	_climate = _slider(box, "Climate", -30, 30, 5, roundi(settings.temperature_offset * 100), "%+d", "-30 is an ice age, +30 a hot world")
	for s in [_continents, _water, _climate]:
		s.drag_ended.connect(func(changed):
			if changed:
				request())

	# The peoples.
	box.add_child(HSeparator.new())
	var peoples := UI.label("Its peoples", "Heading")
	peoples.tooltip_text = "Pick at least two. Each founds a village in a land it likes."
	peoples.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(peoples)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for race in Races.RACES:
		var card := Button.new()
		card.text = race
		card.icon = UI.creature(race.to_lower(), 36)
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.theme_type_variation = "Tool"
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		UI.small(card)
		card.custom_minimum_size = Vector2(102, 64)
		card.button_pressed = race in DEFAULT
		card.toggled.connect(func(_on): _update())
		grid.add_child(card)
		_boxes[race] = card

	_per_village = _slider(box, "Founders", 6, 40, 1, 12, "%d", "People who found each village")
	_ai = CheckButton.new()
	_ai.text = "AI minds invent for the peoples"
	_ai.focus_mode = Control.FOCUS_NONE
	_ai.tooltip_text = "A model built into the game, downloaded once (about 400 MB) and run on this computer;\nuntil it is ready, and without it, a procedural inventor invents."
	_ai.button_pressed = ProjectSettings.get_setting("animundi/ai/builtin_mind", true)
	box.add_child(_ai)
	_hint = UI.label("", "Muted")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)
	_start = UI.button("Start the world", "play", "", "Primary")
	_start.custom_minimum_size.y = 48
	_start.pressed.connect(_on_start)
	box.add_child(_start)
	_update()
	_place.call_deferred()


## On the left of the screen, under the top bar, at the size of its content.
func _place() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
	position.x = 12


## The ticked peoples, as ids of data/races.json.
func chosen() -> PackedStringArray:
	var ids := PackedStringArray()
	for race in _boxes:
		if _boxes[race].button_pressed:
			ids.append(race.to_lower())
	return ids


## A new random seed, and the world made again.
func randomize_seed() -> void:
	if _seed_edit == null:
		return
	_seed_edit.text = str(randi() % 1000000)
	request()


## Writes the land's settings and asks for the world to be made again.
func request() -> void:
	settings.seed_text = _seed_edit.text if _seed_edit.text.strip_edges() != "" else "animundi"
	settings.set_size(WorldSettings.SIZES.values()[_size_option.selected])
	settings.continents = int(_continents.value)
	settings.water_ratio = _water.value / 100.0
	settings.temperature_offset = _climate.value / 100.0
	generate_requested.emit()


func _update() -> void:
	var n := chosen().size()
	_start.disabled = n < MIN_PEOPLES
	_hint.text = "%d peoples chosen" % n if n >= MIN_PEOPLES else "Choose at least %d peoples" % MIN_PEOPLES


func _on_start() -> void:
	if chosen().size() >= MIN_PEOPLES:
		start_requested.emit(chosen(), int(_per_village.value), _ai.button_pressed)


func _row(box: VBoxContainer, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := UI.label(text)
	l.custom_minimum_size.x = 110
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	box.add_child(row)


func _slider(box: VBoxContainer, text: String, lo: float, hi: float, step: float, value: float, format: String, tip: String) -> HSlider:
	var row := HBoxContainer.new()
	row.tooltip_text = tip
	var l := UI.label(text)
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var shown := UI.label(format % int(value), "Small")
	shown.custom_minimum_size.x = 44
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v): shown.text = format % int(v))
	row.add_child(shown)
	box.add_child(row)
	return s
