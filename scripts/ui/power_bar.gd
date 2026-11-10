## The god powers bar (0.9), at the bottom of the screen as in WorldBox: the player picks a power
## and a brush size, then clicks or drags on the map (scripts/main.gd applies it by calling the
## simulation, sim/Powers.cs). "Inspect" is the power at rest: a click tells who or what is there.
extends PanelContainer

## A power was chosen: `power` is one of POWERS' keys, `arg` what it brings or paints (a species,
## race or biome), empty otherwise.
signal power_changed(power: String, arg: String)
## A law of the world was switched in the Laws menu.
signal law_toggled(law: String, on: bool)

## Brush sizes, in tiles across.
const BRUSHES := [1, 2, 3, 5, 8]

## Every power: its button's text, what the bottom bar says while it is chosen, and whether
## dragging keeps applying it (else one use per click).
const POWERS := {
	"inspect": ["Inspect", "Click a creature or a village to follow it.", false],
	"spawn": ["Creature", "Click to bring %s into the world (as many as the brush size).", false],
	"settle": ["People", "Click free land to found a village of %s.", false],
	"fire": ["Fire", "Click or drag to set the land alight.", true],
	"lightning": ["Lightning", "Click to strike: it kills and starts a fire.", false],
	"rain": ["Rain", "Click or drag to put out fires and make the grass grow.", true],
	"meteor": ["Meteor", "Click to drop a meteor the size of the brush.", false],
	"smite": ["Smite", "Click or drag to kill every creature under the brush.", true],
	"bless": ["Bless", "Click or drag to heal and feed every creature under the brush.", true],
	"biome": ["Biome", "Click or drag to paint %s.", true],
	"war": ["War", "Click a kingdom's land, then the kingdom it will attack.", false],
	"peace": ["Peace", "Click the lands of two kingdoms at war to make peace.", false],
	"alliance": ["Alliance", "Click the lands of two kingdoms to ally them.", false],
}

## Laws as the menu names them.
const LAW_NAMES := {
	"animal_spawn": "Animals are born over time",
	"hunger": "Hunger and thirst",
	"old_age": "Old age",
	"natural_disasters": "Natural disasters (lightning)",
	"trees_growth": "Plants grow and spread",
}

var power := "inspect"
var arg := ""
var brush := 2

var _buttons := {}
var _menus := {}
var _args := {"spawn": "", "settle": "", "biome": ""}
var _brush_label: Label
var _laws: MenuButton
var _law_ids: Array = []


func _init() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	add_child(row)
	# Thirteen powers, a brush and the laws on one line of a 1280-pixel window.
	var small := Theme.new()
	small.default_font_size = 14
	theme = small
	for id in POWERS:
		if id in ["spawn", "fire", "meteor", "biome", "war"]:
			row.add_child(VSeparator.new())
		if id in _args:
			var menu := MenuButton.new()
			menu.flat = false
			menu.toggle_mode = true
			menu.focus_mode = Control.FOCUS_NONE
			menu.get_popup().id_pressed.connect(func(k): _pick(id, menu.get_popup().get_item_metadata(k)))
			row.add_child(menu)
			_menus[id] = menu
			_buttons[id] = menu
		else:
			var b := Button.new()
			b.text = POWERS[id][0]
			b.tooltip_text = POWERS[id][1]
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE  # Space must keep pausing the world
			b.pressed.connect(func(): select("inspect" if power == id else id))
			row.add_child(b)
			_buttons[id] = b
	row.add_child(VSeparator.new())
	var smaller := Button.new()
	smaller.text = "−"
	smaller.tooltip_text = "Smaller brush ([)"
	smaller.focus_mode = Control.FOCUS_NONE
	smaller.pressed.connect(func(): step_brush(-1))
	row.add_child(smaller)
	_brush_label = Label.new()
	_brush_label.custom_minimum_size.x = 62
	_brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_brush_label)
	var bigger := Button.new()
	bigger.text = "+"
	bigger.tooltip_text = "Bigger brush (])"
	bigger.focus_mode = Control.FOCUS_NONE
	bigger.pressed.connect(func(): step_brush(1))
	row.add_child(bigger)
	row.add_child(VSeparator.new())
	_laws = MenuButton.new()
	_laws.text = "Laws"
	_laws.flat = false
	_laws.focus_mode = Control.FOCUS_NONE
	_laws.tooltip_text = "The rules of the world: switch them on and off."
	_laws.get_popup().hide_on_checkable_item_selection = false
	_laws.get_popup().id_pressed.connect(_toggle_law)
	row.add_child(_laws)
	_refresh()


## Fills the menus: creatures and peoples by id, biomes by name.
func setup(species: PackedStringArray, races: PackedStringArray, biomes: PackedStringArray) -> void:
	for pair in [["spawn", species], ["settle", races], ["biome", biomes]]:
		var popup: PopupMenu = _menus[pair[0]].get_popup()
		popup.clear()
		for value in pair[1]:
			popup.add_item(String(value).capitalize())
			popup.set_item_metadata(popup.item_count - 1, String(value))
		if _args[pair[0]] == "" and not pair[1].is_empty():
			_args[pair[0]] = pair[1][0]
	_refresh()


## Shows the world's laws (name → on) in the Laws menu.
func set_laws(table: Dictionary) -> void:
	var popup := _laws.get_popup()
	popup.clear()
	_law_ids = table.keys()
	for k in _law_ids.size():
		popup.add_check_item(LAW_NAMES.get(_law_ids[k], String(_law_ids[k]).capitalize()), k)
		popup.set_item_checked(k, table[_law_ids[k]])


## Chooses a power (keeping the creature, people or biome last chosen for it).
func select(id: String) -> void:
	if not POWERS.has(id):
		id = "inspect"
	power = id
	arg = _args.get(id, "")
	_refresh()
	power_changed.emit(power, arg)


## Back to inspecting.
func deselect() -> void:
	select("inspect")


## Whether dragging keeps applying the current power.
func drags() -> bool:
	return POWERS[power][2]


## What the bottom bar says about the current power.
func hint() -> String:
	var text: String = POWERS[power][1]
	return text % arg.capitalize().to_lower() if "%s" in text else text


## Radius of the brush in tiles.
func radius() -> float:
	return maxf(0.6, brush - 0.5)


func step_brush(by: int) -> void:
	brush = BRUSHES[clampi(BRUSHES.find(brush) + by, 0, BRUSHES.size() - 1)]
	_refresh()


func _pick(id: String, value: String) -> void:
	_args[id] = value
	select(id)


func _toggle_law(k: int) -> void:
	var popup := _laws.get_popup()
	popup.set_item_checked(k, not popup.is_item_checked(k))
	law_toggled.emit(_law_ids[k], popup.is_item_checked(k))


func _refresh() -> void:
	for id in _buttons:
		_buttons[id].button_pressed = id == power
	for id in _menus:
		_menus[id].text = "%s ▾" % (String(_args[id]).capitalize() if _args[id] != "" else POWERS[id][0])
		_menus[id].tooltip_text = "%s: %s" % [POWERS[id][0], POWERS[id][1].replace("%s", "what you pick here")]
	if _brush_label != null:
		_brush_label.text = "Brush %d" % brush
