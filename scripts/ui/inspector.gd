## The inspector card: who or what the player clicked, kept on screen and refreshed while it
## lives (scripts/main.gd follows the unit or the village and calls show_unit / show_village).
## A portrait, a name, what the simulation says, the village's stores as icons, and the actions
## on what is shown (follow it with the camera; favourites and the family tree come later).
extends PanelContainer

const UI = preload("res://scripts/ui/ui.gd")

signal closed
## The player wants the camera to follow (or stop following) what the card shows.
signal follow_toggled(on: bool)
## An action that is not in the game yet: its name and what it will do.
signal soon_requested(action: String, what: String)

## Stores shown as icons on a village's card: key of the village's row, icon, name.
const STORES := [["food", "bread", "Food"], ["wood", "log", "Wood"], ["stone", "stone", "Stone"],
		["metal", "ingot", "Metal"], ["gold", "coin", "Gold"], ["tools", "hammer", "Tools"],
		["weapons", "sword", "Weapons"], ["fields", "wheat", "Fields"]]

var _title: Label
var _body: Label
var _portrait: TextureRect
var _stores: HFlowContainer
var _store_labels := {}
var _follow: Button


func _init() -> void:
	visible = false
	custom_minimum_size.x = 320
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "Card"
	frame.custom_minimum_size = Vector2(52, 52)
	head.add_child(frame)
	_portrait = UI.picture(null)
	frame.add_child(_portrait)
	_title = UI.label("", "Title")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.add_theme_font_size_override("font_size", UI.SIZE)
	head.add_child(_title)
	var close_button := UI.tool_button(UI.icon("close", 1), "Close", 30)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	head.add_child(close_button)

	_stores = HFlowContainer.new()
	_stores.add_theme_constant_override("h_separation", 4)
	_stores.add_theme_constant_override("v_separation", 4)
	box.add_child(_stores)
	for store in STORES:
		var chip: Array = UI.chip(store[1], store[2])
		_stores.add_child(chip[0])
		_store_labels[store[0]] = chip[1]

	_body = UI.label("", "Small")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 300
	box.add_child(_body)

	box.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	box.add_child(actions)
	_follow = UI.tool_button(UI.icon("target", 1), "Follow with the camera", 34)
	_follow.toggle_mode = true
	_follow.toggled.connect(func(on): follow_toggled.emit(on))
	actions.add_child(_follow)
	for action in [["star", "Favourite", "Keep it in your favourites and hear of what happens to it."],
			["people", "Family", "Its parents, partner and children."],
			["scroll", "Story", "What it lived through, written by the chronicle."],
			["bulb", "Mind", "What it wants and how it decides."]]:
		var b := UI.tool_button(UI.icon(action[0], 1), "%s (coming later)\n%s" % [action[1], action[2]], 34)
		b.modulate = Color(0.62, 0.58, 0.62)
		b.pressed.connect(func(): soon_requested.emit(action[1], action[2]))
		actions.add_child(b)


## A creature: `info` is the simulation's line about it ("Name · people · role · …").
func show_unit(unit_name: String, info: String) -> void:
	_title.text = unit_name
	# The line starts with the name of a person: the title says it already.
	var lines := info.split(" · ")
	if lines.size() > 1 and lines[0] == unit_name:
		lines.remove_at(0)
	_body.text = "\n".join(lines)
	_portrait.texture = _portrait_of(lines[0] if lines.size() > 0 else "")
	_stores.visible = false
	visible = true


## A village: `info` is its row of the simulation's village table.
func show_village(info: Dictionary) -> void:
	if info.is_empty():
		close()
		return
	_title.text = info.name
	_portrait.texture = UI.icon("crown" if info.get("capital", false) else "house")
	var lines := [
		"%s of the %s%s" % [String(info.rank).capitalize(), info.people, ", kingdom of %s" % info.kingdom if info.kingdom != "" else ""],
		"Founded in year %d" % info.founded,
		"%d people in %d homes · loyalty %d" % [info.population, info.homes, info.loyalty],
	]
	for store in STORES:
		_store_labels[store[0]].text = str(int(info.get(store[0], 0)))
	_stores.visible = true
	if info.building != "":
		lines.append("Building: %s (%d%%)" % [info.building, int(float(info.site) * 100.0)])
	if String(info.buildings) != "":
		lines.append("Buildings: %s" % info.buildings)
	if String(info.jobs) != "":
		lines.append("Jobs: %s" % info.jobs)
	if float(info.siege) > 0.0:
		lines.append("Under siege (%d%%)" % int(float(info.siege) * 100.0))
	_body.text = "\n".join(lines)
	visible = true


func close() -> void:
	if visible:
		visible = false
		_follow.set_pressed_no_signal(false)
		closed.emit()


## The sprite of the creature a line of the simulation describes: "Wolf, 3 years" or
## "Humans man, chief, 20 years".
func _portrait_of(line: String) -> Texture2D:
	var parts := line.split(", ")
	var id := parts[0].split(" ")[0].to_lower()
	var role := parts[1].to_lower() if parts.size() > 2 else "villager"
	var tex: Texture2D = UI.creature(id, 44, role)
	return tex if tex != null else UI.icon("paw")
