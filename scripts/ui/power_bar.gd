## The god powers bar (0.9), at the bottom of the screen as in WorldBox: tabs of powers (terrain,
## creatures, peoples, nature, wrath and mercy, whispers) over a tray of picture buttons, with the
## chosen power's name and what it does on the left and the brush on the right. The player picks
## a power and a brush size, then clicks or drags on the map (scripts/main.gd applies it by calling
## the simulation, sim/Powers.cs). "Inspect" is the power at rest: a click tells who or what is
## there. Powers the simulation does not have yet are shown locked (SOON): the interface is ready
## for them, and clicking one says what it will do.
extends PanelContainer

const UI = preload("res://scripts/ui/ui.gd")
const Biomes = preload("res://scripts/world/biomes.gd")

## A power was chosen: `power` is one of POWERS' keys, `arg` what it brings or paints (a species,
## race or biome), empty otherwise.
signal power_changed(power: String, arg: String)
## The player clicked a power that is not in the game yet: its name and what it will do.
signal soon_requested(power_name: String, what: String)

## Brush sizes, in tiles across.
const BRUSHES := [1, 2, 3, 5, 8]

## Every power: its name, what the game says while it is chosen, and whether dragging keeps
## applying it (else one use per click).
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
	"miracle": ["Miracle", "Click for a sign from the sky: it heals, and the faith of the villages that see it grows.", false],
	"biome": ["Biome", "Click or drag to paint %s.", true],
	"war": ["War", "Click a kingdom's land, then the kingdom it will attack.", false],
	"peace": ["Peace", "Click the lands of two kingdoms at war to make peace.", false],
	"alliance": ["Alliance", "Click the lands of two kingdoms to ally them.", false],
}

## The tabs: id, name, icon.
const TABS := [
	["terrain", "Terrain", "height"],
	["life", "Creatures", "paw"],
	["peoples", "Peoples", "people"],
	["nature", "Nature", "sprout"],
	["divine", "Wrath & Mercy", "bless"],
	["whispers", "Whispers", "scroll"],
]

## Tab and icon of each power. Powers that bring or paint something fill their whole tab with
## one button per creature, people or biome.
const PLACE := {
	"biome": ["terrain", "biome"], "spawn": ["life", "paw"], "settle": ["peoples", "people"],
	"fire": ["nature", "fire"], "lightning": ["nature", "lightning"], "rain": ["nature", "rain"],
	"meteor": ["divine", "meteor"], "smite": ["divine", "smite"], "bless": ["divine", "bless"], "miracle": ["divine", "halo"],
	"war": ["whispers", "swords"], "peace": ["whispers", "dove"], "alliance": ["whispers", "rings"],
}

## Powers to come (docs/ROADMAP.md, 0.7 and 0.9): tab, name, icon, what they will do.
const SOON := [
	["terrain", "Raise the land", "raise", "Lift the ground: plains into hills, hills into mountains."],
	["terrain", "Lower the land", "lower", "Dig the ground down, until the sea comes in."],
	["terrain", "Water", "water", "Pour lakes and rivers, or dry them up."],
	["terrain", "Stamps", "stamp", "Paste ready-made volcanoes, islands, craters and oases."],
	["nature", "Seeds", "sprout", "Sow plants and trees where the brush goes."],
	["nature", "Drought", "drought", "Dry the land: the grass dies, fires spread."],
	["nature", "Blizzard", "blizzard", "Freeze the land under the brush."],
	["nature", "Tornado", "tornado", "A whirlwind that throws creatures and tears buildings."],
	["nature", "Earthquake", "quake", "Shake the ground: buildings fall, the land cracks."],
	["nature", "Flood", "flood", "The sea rises over the low lands."],
	["nature", "Eruption", "volcano", "Wake a volcano: lava flows down its slopes."],
	["nature", "Plague", "plague", "A sickness that spreads from creature to creature."],
	["divine", "Curse", "curse", "Bad luck, weakness and fear on those under the brush."],
	["divine", "Heal", "heal", "Cure wounds and sickness."],
	["divine", "Madness", "spiral", "Creatures under the brush turn on each other."],
	["divine", "Resurrect", "grave", "Bring the dead back, as they were or as undead."],
	["whispers", "Rebellion", "flag", "Push a village to break away from its kingdom."],
	["whispers", "Inspire", "bulb", "Give a people's mind an idea: it invents at once."],
	["whispers", "Forget", "forget", "Make a people forget its language, culture or faith."],
	["whispers", "Convert", "ankh", "Turn a village to another faith."],
]

## Tools in a row of the tray, and the rows it shows.
const COLUMNS := 12
const TOOL := 44

var power := "inspect"
var arg := ""
var brush := 2

## A button per power (for the powers that bring or paint, the button of their tab).
var _buttons := {}
## Buttons of what a power brings or paints: power → {value: button}.
var _arg_buttons := {"spawn": {}, "settle": {}, "biome": {}}
var _args := {"spawn": "", "settle": "", "biome": ""}
var _tab := "life"
var _open := true
var _tab_buttons := {}
var _grids := {}
var _tray: PanelContainer
var _name_label: Label
var _hint_label: Label
var _icon_rect: TextureRect
var _brush_label: Label
var _brush_dot: Control


func _init() -> void:
	# The bar itself is invisible: tabs and tray are its panels.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	# Tabs, with Inspect before them.
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 4)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tabs)
	var inspect := UI.button("Inspect", "inspect", "%s (Esc)" % POWERS["inspect"][1])
	inspect.toggle_mode = true
	inspect.pressed.connect(func(): select("inspect"))
	tabs.add_child(inspect)
	_buttons["inspect"] = inspect
	for tab in TABS:
		var b := UI.button(tab[1], tab[2], "%s powers" % tab[1], "Tab")
		b.toggle_mode = true
		b.pressed.connect(_show_tab.bind(tab[0], true))
		tabs.add_child(b)
		_tab_buttons[tab[0]] = b

	# The tray: the chosen power, the tools of the tab, the brush.
	_tray = PanelContainer.new()
	_tray.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_tray)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_tray.add_child(row)

	var about := VBoxContainer.new()
	about.custom_minimum_size.x = 190
	about.add_theme_constant_override("separation", 2)
	row.add_child(about)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	about.add_child(head)
	_icon_rect = UI.picture(null)
	_icon_rect.custom_minimum_size = Vector2(32, 32)
	head.add_child(_icon_rect)
	_name_label = UI.label("", "Heading")
	_name_label.clip_text = true
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name_label)
	_hint_label = UI.label("", "Muted")
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(190, 50)
	about.add_child(_hint_label)
	row.add_child(VSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COLUMNS * (TOOL + 4) + 10, 2 * (TOOL + 4))
	row.add_child(scroll)
	var pages := MarginContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	for tab in TABS:
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		grid.visible = false
		pages.add_child(grid)
		_grids[tab[0]] = grid
	row.add_child(VSeparator.new())

	# Brush: how wide the power reaches.
	var brush_box := VBoxContainer.new()
	brush_box.alignment = BoxContainer.ALIGNMENT_CENTER
	brush_box.add_theme_constant_override("separation", 2)
	row.add_child(brush_box)
	_brush_label = UI.label("", "Small")
	_brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brush_box.add_child(_brush_label)
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 3)
	brush_box.add_child(sizes)
	var smaller := UI.tool_button(UI.icon("minus", 1), "Smaller brush ([)", 30)
	smaller.pressed.connect(func(): step_brush(-1))
	sizes.add_child(smaller)
	_brush_dot = Control.new()
	_brush_dot.custom_minimum_size = Vector2(34, 34)
	_brush_dot.draw.connect(_draw_brush)
	sizes.add_child(_brush_dot)
	var bigger := UI.tool_button(UI.icon("plus", 1), "Bigger brush (])", 30)
	bigger.pressed.connect(func(): step_brush(1))
	sizes.add_child(bigger)

	_fill_fixed()
	_show_tab(_tab, false)
	_refresh()


## The powers that need no list from the world, and the ones to come.
func _fill_fixed() -> void:
	for id in POWERS:
		if id == "inspect":
			continue
		var place: Array = PLACE[id]
		if _args.has(id):
			_buttons[id] = _tab_buttons[place[0]]
			continue
		var b := UI.tool_button(UI.icon(place[1]), "%s\n%s" % [POWERS[id][0], POWERS[id][1]], TOOL)
		b.toggle_mode = true
		b.pressed.connect(func(): select("inspect" if power == id else id))
		_grids[place[0]].add_child(b)
		_buttons[id] = b
	for soon in SOON:
		_add_soon(soon)


func _add_soon(soon: Array) -> void:
	var b := UI.tool_button(UI.icon(soon[2]), "%s (coming later)\n%s" % [soon[1], soon[3]], TOOL)
	UI.mark_soon(b)
	b.pressed.connect(func(): soon_requested.emit(soon[1], soon[3]))
	_grids[soon[0]].add_child(b)


## Fills the tabs of creatures, peoples and biomes: creatures and peoples by id, biomes by name.
func setup(species: PackedStringArray, races: PackedStringArray, biomes: PackedStringArray) -> void:
	for pair in [["spawn", species], ["settle", races], ["biome", biomes]]:
		var id: String = pair[0]
		var grid: HFlowContainer = _grids[PLACE[id][0]]
		for b in _arg_buttons[id].values():
			grid.remove_child(b)
			b.queue_free()
		_arg_buttons[id].clear()
		var at := 0
		for value in pair[1]:
			var text := String(value).capitalize()
			var tex := _picture_of(id, value)
			var b := UI.tool_button(tex, POWERS[id][1] % text.to_lower(), TOOL)
			if tex == null:
				b.text = text.left(3)
			b.toggle_mode = true
			b.pressed.connect(_pick.bind(id, String(value)))
			grid.add_child(b)
			# Before the powers to come of the same tab.
			grid.move_child(b, at)
			at += 1
			_arg_buttons[id][String(value)] = b
		if not _arg_buttons[id].has(_args[id]):
			_args[id] = pair[1][0] if not pair[1].is_empty() else ""
	_refresh()


## The picture of what a power brings or paints.
func _picture_of(id: String, value: String) -> Texture2D:
	if id == "biome":
		var b := Biomes.NAMES.find(value)
		return UI.biome_swatch(Biomes.TILES[b] if b >= 0 else value, 36)
	return UI.creature(value, 38)


## Chooses a power (keeping the creature, people or biome last chosen for it).
func select(id: String) -> void:
	if not POWERS.has(id):
		id = "inspect"
	power = id
	arg = _args.get(id, "")
	if id != "inspect":
		_show_tab(PLACE[id][0], false)
	_refresh()
	power_changed.emit(power, arg)


## Back to inspecting.
func deselect() -> void:
	select("inspect")


## Whether dragging keeps applying the current power.
func drags() -> bool:
	return POWERS[power][2]


## What the game says about the current power.
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


## Shows a tab's tools. Clicking the tab already shown folds the tray away, to see more map.
func _show_tab(id: String, from_click: bool) -> void:
	if from_click and id == _tab:
		_open = not _open
	else:
		_open = true
	_tab = id
	for t in _grids:
		_grids[t].visible = t == id
	_tray.visible = _open
	for t in _tab_buttons:
		_tab_buttons[t].set_pressed_no_signal(_open and t == _tab)


func _refresh() -> void:
	for id in _buttons:
		if not _args.has(id):
			_buttons[id].set_pressed_no_signal(id == power)
	for id in _arg_buttons:
		for value in _arg_buttons[id]:
			_arg_buttons[id][value].set_pressed_no_signal(id == power and value == arg)
	for t in _tab_buttons:
		_tab_buttons[t].set_pressed_no_signal(_open and t == _tab)
	if _name_label != null:
		var named := arg.capitalize() if arg != "" else String(POWERS[power][0])
		_name_label.text = named
		_name_label.tooltip_text = named
		_hint_label.text = hint()
		_icon_rect.texture = _picture_of(power, arg) if arg != "" else UI.icon("inspect" if power == "inspect" else PLACE[power][1])
	if _brush_label != null:
		_brush_label.text = "Brush %d" % brush
		_brush_dot.queue_redraw()


## The brush drawn at its size among the sizes.
func _draw_brush() -> void:
	var centre := _brush_dot.size / 2.0
	var r := 3.0 + 12.0 * BRUSHES.find(brush) / (BRUSHES.size() - 1.0)
	_brush_dot.draw_circle(centre, r + 2.0, UI.INK)
	_brush_dot.draw_circle(centre, r, UI.CREAM)
