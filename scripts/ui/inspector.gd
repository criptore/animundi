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


## Any other card: a title, a picture and lines of text (a kingdom, a species, a spirit, an
## invention). `code` is shown in a box of its own, in the invention language.
func show_card(title: String, picture: Texture2D, lines: Array, code := "") -> void:
	_title.text = title
	_portrait.texture = picture
	_stores.visible = false
	var text := "\n".join(lines.filter(func(l): return String(l) != ""))
	if code != "":
		text += "\n\n" + code
	_body.text = text
	visible = true


## A kingdom: `info` is the simulation's KingdomInfo.
func show_kingdom(info: Dictionary) -> void:
	if info.is_empty():
		close()
		return
	var lines := [
		"%s · %s · capital %s" % [info.people, info.get("age_name", ""), info.capital],
		"%s · founded in year %d" % [info.ruler, info.founded],
		"%d villages · %d people · %d soldiers" % [info.villages, info.population, info.soldiers],
		"They prize %s" % info.values,
		"Faith %d · %s" % [int(info.faith), info.creed],
		("Customs: %s" % info.customs) if String(info.customs) != "" else "",
		("At war with %s" % info.wars) if String(info.wars) != "" else "",
		("Allied with %s" % info.allies) if String(info.allies) != "" else "",
		("Of the others: %s" % info.opinions) if String(info.opinions) != "" else "",
		"They make: %s" % info.designs,
		{"worshipped": "They worship you as %s.", "feared": "They fear you as %s.", "hated": "They curse you as %s."}.get(info.stance, "%s") % info.god_name
				if info.stance != "unnoticed" else "",
		String(info.feats),
	]
	show_card(info.name, UI.icon("crown"), lines)


## A species: `info` is the simulation's SpeciesInfo.
func show_species(info: Dictionary) -> void:
	if info.is_empty():
		close()
		return
	var lines := [
		"%d alive%s" % [info.alive, (" · the land feeds %d" % info.capacity) if info.capacity > 0 else ""],
		"A people" if info.people else ("A legend" if info.legend else "%s · size %d" % [String(info.diet).capitalize(), info.size]),
		"Lives %d years · speed %.1f" % [int(info.lifespan), info.speed] if not info.legend else "",
		("Born in %s" % String(info.habitat).to_lower()) if String(info.habitat) != "" else "",
		("Changed: %s" % info.strain) if String(info.strain) != "" else "",
	]
	var tex: Texture2D = UI.creature(String(info.id), 44)
	show_card(info.name, tex if tex != null else UI.icon("paw"), lines)


## A spirit of nature: its row of the simulation's SpiritTable.
func show_spirit(info: Dictionary) -> void:
	if info.is_empty():
		close()
		return
	var lines := [
		"Spirit of %s · %d tiles" % [info.place, info.tiles],
		"%s (%+.2f)%s" % [String(info.mood_word).capitalize(), info.mood, (" · worshipped by %d" % info.worshippers) if info.worshippers > 0 else ""],
		"In anger: %s · its gift: %s" % [info.wrath, info.gift],
		("This year: %s" % info.wounds) if String(info.wounds) != "" else "",
		("\"%s\"" % info.words) if String(info.words) != "" else "",
		String(info.deeds),
		String(info.lore),
	]
	show_card(info.name, UI.icon("sprout"), lines)


## An invention: the simulation's InventionInfo, with its record (script) and lineage.
func show_invention(info: Dictionary) -> void:
	if info.is_empty():
		close()
		return
	var lines := [
		"%s of the %s of %s, year %d" % [String(info.kind).capitalize(), info.people, info.kingdom, info.year],
		info.effects,
		"%s · known in %d villages%s" % ["Written by the model" if info.mind == "model" else "Procedural", info.villages, " · lost" if info.lost else ""],
		"Lineage: %s" % info.lineage,
		("Improved %d times since" % info.children) if info.children > 0 else "",
		String(info.description),
	]
	show_card(info.name, UI.icon("bulb"), lines, info.script)


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
