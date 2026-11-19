## Saved worlds (1.0): the autosave and six slots, each with what it holds (year, peoples, era,
## when it was saved). Saving writes the world into a slot; loading brings one back.
extends "res://scripts/ui/window.gd"

const WorldStore = preload("res://scripts/world/world_store.gd")

signal save_requested(slot: String)
signal load_requested(slot: String)

## true: the window saves (and can load); false: it only loads (from the title screen).
var can_save := true
var _list: VBoxContainer


func _init() -> void:
	build("Saved worlds", "save", 520)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	body.add_child(_list)


func open() -> void:
	refresh()
	super.open()


## Shows the slots again (after a save).
func refresh(entries := []) -> void:
	if entries.is_empty():
		entries = WorldStore.list()
	for child in _list.get_children():
		child.queue_free()
	for e in entries:
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var title := UI.label("Autosave" if e.slot == WorldStore.AUTO else "Slot %s" % String(e.slot).trim_prefix("slot_"))
		text.add_child(title)
		var about := UI.label("Empty" if e.empty else describe(e), "Small")
		about.add_theme_color_override("font_color", UI.MUTED)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.custom_minimum_size.x = 300
		text.add_child(about)
		if can_save and e.slot != WorldStore.AUTO:
			var save := UI.button("Save", "save", "Keep this world here" + ("" if e.empty else " (in place of the one there)"), "Ghost")
			var slot: String = e.slot
			save.pressed.connect(func(): save_requested.emit(slot))
			row.add_child(save)
		if not e.empty:
			var load_button := UI.button("Load", "load", "Go back to this world", "Primary")
			var slot: String = e.slot
			load_button.pressed.connect(func(): load_requested.emit(slot))
			row.add_child(load_button)
		_list.add_child(card)


## "Year 230 · 4 kingdoms, 1,250 people · Dark Era · saved 2026-11-19 12:30".
static func describe(e: Dictionary) -> String:
	var a: Dictionary = e.about
	var parts := PackedStringArray()
	if a.has("year"):
		parts.append("Year %d" % a.year)
	if a.has("people"):
		parts.append("%d people in %d kingdoms" % [a.people, a.get("kingdoms", 0)])
	if a.get("era", "") != "":
		parts.append(a.era)
	if a.get("peoples", "") != "":
		parts.append(a.peoples)
	return " · ".join(parts) + "\nsaved %s" % String(e.saved).replace("T", " ").left(16)
