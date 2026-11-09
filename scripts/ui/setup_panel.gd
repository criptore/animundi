## World setup, shown on a new world before time starts: the player picks the peoples that will
## live in it (at least two) and how many people found each village, then starts the world and
## watches. God powers come much later (docs/ROADMAP.md, order of work).
extends PanelContainer

## The player started the world with these peoples (ids from data/races.json).
## `ai`: the built-in language model invents for the peoples (0.5); it is downloaded once.
signal start_requested(races: PackedStringArray, per_village: int, ai: bool)

const Races = preload("res://scripts/world/races.gd")

## Peoples ticked when the panel first opens.
const DEFAULT := ["Humans", "Elves", "Orcs"]
const MIN_PEOPLES := 2

var _boxes := {}
var _per_village: SpinBox
var _start: Button
var _hint: Label
var _ai: CheckBox


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = "Who will live in this world?"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Pick at least two peoples. Each founds a village in a land it likes."
	box.add_child(sub)

	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for race in Races.RACES:
		var check := CheckBox.new()
		check.text = race
		check.button_pressed = race in DEFAULT
		check.toggled.connect(func(_on): _update())
		var swatch: Color = Color(Races.RACES[race].clothes)
		check.add_theme_color_override("font_color", swatch.lightened(0.35))
		grid.add_child(check)
		_boxes[race] = check

	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = "People per village"
	row.add_child(l)
	_per_village = SpinBox.new()
	_per_village.min_value = 6
	_per_village.max_value = 40
	_per_village.value = 12
	row.add_child(_per_village)

	_ai = CheckBox.new()
	_ai.text = "AI minds: a model built into the game invents for the peoples"
	_ai.tooltip_text = "Downloaded once (about 400 MB) and run on this computer; until it is ready, and without it, a procedural inventor invents."
	_ai.button_pressed = ProjectSettings.get_setting("animundi/ai/builtin_mind", true)
	box.add_child(_ai)
	_hint = Label.new()
	box.add_child(_hint)
	_start = Button.new()
	_start.text = "Start the world"
	_start.pressed.connect(_on_start)
	box.add_child(_start)
	_update()
	# Centred on the screen, at the size of its content.
	_center.call_deferred()


func _center() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


## The ticked peoples, as ids of data/races.json.
func chosen() -> PackedStringArray:
	var ids := PackedStringArray()
	for race in _boxes:
		if _boxes[race].button_pressed:
			ids.append(race.to_lower())
	return ids


func _update() -> void:
	var n := chosen().size()
	_start.disabled = n < MIN_PEOPLES
	_hint.text = "%d peoples chosen" % n if n >= MIN_PEOPLES else "Choose at least %d peoples" % MIN_PEOPLES


func _on_start() -> void:
	if chosen().size() >= MIN_PEOPLES:
		start_requested.emit(chosen(), int(_per_village.value), _ai.button_pressed)
