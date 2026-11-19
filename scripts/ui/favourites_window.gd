## Favourites (1.0): the creatures and villages the player follows, from the inspector's heart.
## A click shows one; the game tells when a favourite dies or a village falls.
extends "res://scripts/ui/window.gd"

signal show_requested(kind: String, id: int)
signal remove_requested(kind: String, id: int)

var _list: VBoxContainer
var _empty: Label


func _init() -> void:
	build("Favourites", "heart", 420)
	_empty = UI.label("Nothing yet: click the heart on the inspector's card to follow a creature or a village.", "Muted")
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size.x = 380
	body.add_child(_empty)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	body.add_child(_list)


## `favourites`: [{kind, id, name, alive, about}].
func show_list(favourites: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	_empty.visible = favourites.is_empty()
	for f in favourites:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.picture(UI.icon("house" if f.kind == "village" else "people", 1)))
		var text := UI.label("%s%s\n%s" % [f.name, "" if f.alive else " †", f.get("about", "")], "Small")
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		if not f.alive:
			text.add_theme_color_override("font_color", UI.MUTED)
		row.add_child(text)
		var kind: String = f.kind
		var id: int = f.id
		if f.alive:
			var show := UI.tool_button(UI.icon("target", 1), "Show it", 30)
			show.pressed.connect(func(): show_requested.emit(kind, id))
			row.add_child(show)
		var drop := UI.tool_button(UI.icon("close", 1), "No longer follow", 30)
		drop.pressed.connect(func(): remove_requested.emit(kind, id))
		row.add_child(drop)
		_list.add_child(row)
