## The laws of the world: one switch per rule of the simulation, grouped, each with a line saying
## what it does. The laws the simulation has (sim/Powers.cs, LawTable) can be switched; the ones
## to come are shown locked.
extends "res://scripts/ui/window.gd"

## A law of the world was switched.
signal law_toggled(law: String, on: bool)

## Group, id, name, what it does. An id the simulation does not know yet is a law to come.
const LAWS := [
	["Nature", "animal_spawn", "Animals are born over time", "Scarce species come back in the lands they like."],
	["Nature", "trees_growth", "Plants grow and spread", "Saplings grow, plants seed their surroundings."],
	["Nature", "seasons", "Seasons", "Winter stops growth and frost creeps from the poles."],
	["Creatures", "hunger", "Hunger and thirst", "Creatures must eat and drink, or die."],
	["Creatures", "old_age", "Old age", "Creatures die when their time has come."],
	["Creatures", "legends", "Legends wake", "Unique legendary monsters may wake in their lairs as the years go by."],
	["Disasters", "natural_disasters", "Natural disasters", "Lightning strikes and starts wildfires."],
	["Disasters", "plagues", "Plagues", "Sicknesses appear and spread."],
	["Disasters", "eruptions", "Eruptions and earthquakes", "Volcanoes wake, the ground shakes."],
	["Civilisations", "diplomacy", "Kingdoms plot", "Rulers plan wars, alliances and peace on their own."],
	["Civilisations", "rebellions", "Rebellions", "Disloyal villages break away from their kingdom."],
	["Civilisations", "settlers", "Settlers", "Crowded villages send people to found new ones."],
	["Civilisations", "inventions", "Minds invent", "Each people's mind invents tools, weapons and buildings."],
	["Civilisations", "faiths", "Faiths spread and split", "Kingdoms take up the faith of fervent neighbours; faiths split in heresies."],
]

var _law_ids: Array = []
var _checks := {}
var _list: VBoxContainer


func _init() -> void:
	build("Laws of the world", "scales", 470)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 430
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	set_laws({})


## Shows the world's laws (name → on).
func set_laws(table: Dictionary) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_law_ids = table.keys()
	_checks.clear()
	var known := {}
	var group := ""
	for law in LAWS:
		if law[0] != group:
			group = law[0]
			_list.add_child(UI.label(group, "Heading"))
		known[law[1]] = true
		_add_row(law[1], law[2], law[3], table)
	# Laws the simulation has and this list does not name yet.
	for id in _law_ids:
		if not known.has(id):
			_add_row(id, String(id).capitalize(), "", table)


func _add_row(id: String, law_name: String, what: String, table: Dictionary) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	_list.add_child(card)
	var row := HBoxContainer.new()
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(UI.label(law_name))
	if what != "":
		var about := UI.label(what, "Muted")
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(about)
	var check := CheckButton.new()
	check.focus_mode = Control.FOCUS_NONE
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(check)
	if table.has(id):
		check.button_pressed = table[id]
		check.toggled.connect(func(on): law_toggled.emit(id, on))
		_checks[id] = check
	else:
		check.disabled = true
		check.tooltip_text = "A law to come"
		card.modulate = Color(1, 1, 1, 0.55)
		row.add_child(UI.picture(UI.icon("lock", 1)))


## Switches the k-th law of the table given to set_laws.
func _toggle_law(k: int) -> void:
	var check: CheckButton = _checks[_law_ids[k]]
	check.button_pressed = not check.button_pressed
