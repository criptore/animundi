## Achievements (1.0): every one, won (with the day) or still to win.
extends "res://scripts/ui/window.gd"

var _list: VBoxContainer
var _count: Label


func _init() -> void:
	build("Achievements", "star", 480)
	_count = UI.label("", "Muted")
	body.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 440
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


## Shows the achievements of data/achievements.json: `won` is id → the day it was won.
func show_list(list: Array, won: Dictionary) -> void:
	for child in _list.get_children():
		child.queue_free()
	_count.text = "%d of %d won" % [won.size(), list.size()]
	for a in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := UI.picture(UI.icon(a.get("icon", "star")))
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		row.add_child(text)
		var title := UI.label(a.name)
		text.add_child(title)
		var line := UI.label(a.text + (" · won %s" % won[a.id] if won.has(a.id) else ""), "Small")
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 380
		line.add_theme_color_override("font_color", UI.GOLD if won.has(a.id) else UI.MUTED)
		text.add_child(line)
		if not won.has(a.id):
			row.modulate = Color(0.62, 0.58, 0.62)
		_list.add_child(row)
