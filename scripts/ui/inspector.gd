## The inspector card: who or what the player clicked, kept on screen and refreshed while it
## lives (scripts/main.gd follows the unit or the village and calls show_unit / show_village).
extends PanelContainer

signal closed

var _title: Label
var _body: Label


func _init() -> void:
	visible = false
	custom_minimum_size.x = 300
	var box := VBoxContainer.new()
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 17)
	head.add_child(_title)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 290
	_body.add_theme_font_size_override("font_size", 13)
	box.add_child(_body)


## A creature: `info` is the simulation's line about it ("Name · people · role · …").
func show_unit(unit_name: String, info: String) -> void:
	_title.text = unit_name
	# The line starts with the name of a person: the title says it already.
	var lines := info.split(" · ")
	if lines.size() > 1 and lines[0] == unit_name:
		lines.remove_at(0)
	_body.text = "\n".join(lines)
	visible = true


## A village: `info` is its row of the simulation's village table.
func show_village(info: Dictionary) -> void:
	if info.is_empty():
		close()
		return
	_title.text = "%s%s" % ["♛ " if info.get("capital", false) else "", info.name]
	var lines := [
		"%s of the %s%s" % [String(info.rank).capitalize(), info.people, ", kingdom of %s" % info.kingdom if info.kingdom != "" else ""],
		"Founded in year %d" % info.founded,
		"%d people in %d homes · loyalty %d" % [info.population, info.homes, info.loyalty],
		"Food %d · wood %d · stone %d · metal %d · gold %d" % [info.food, info.wood, info.stone, info.metal, info.gold],
		"Tools %d · weapons %d · %d fields" % [info.tools, info.weapons, info.fields],
	]
	if info.building != "":
		lines.append("Building: %s (%d%%)" % [info.building, int(float(info.site) * 100.0)])
	if String(info.buildings) != "":
		lines.append("Buildings: %s" % info.buildings)
	if String(info.jobs) != "":
		lines.append("Jobs: %s" % info.jobs)
	if float(info.siege) > 0.0:
		lines.append("⚔ Under siege (%d%%)" % int(float(info.siege) * 100.0))
	_body.text = "\n".join(lines)
	visible = true


func close() -> void:
	if visible:
		visible = false
		closed.emit()
