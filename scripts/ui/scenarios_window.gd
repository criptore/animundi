## Scenarios (1.0): ready-made beginnings, chosen from the title screen (data/scenarios.json, and
## those of mods).
extends "res://scripts/ui/window.gd"

signal scenario_chosen(id: String)

var _list: VBoxContainer


func _init() -> void:
	build("Scenarios", "book", 520)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 420
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func show_list(scenarios: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	for s in scenarios:
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		text.add_child(UI.label(s.name))
		var line := UI.label(s.text, "Small")
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 330
		line.add_theme_color_override("font_color", UI.MUTED)
		text.add_child(line)
		var play := UI.button("Play", "play", "Begin this world", "Primary")
		var id: String = s.id
		play.pressed.connect(func(): scenario_chosen.emit(id))
		row.add_child(play)
		_list.add_child(card)
