## A framed window in the middle of the screen: an icon, a title, a close button, then `body`.
## Laws, settings and the pause menu are windows.
extends PanelContainer

const UI = preload("res://scripts/ui/ui.gd")

signal closed

## Where the window's content goes.
var body: VBoxContainer
var _title_label: Label


func build(title: String, icon_name: String, width := 420) -> void:
	visible = false
	custom_minimum_size.x = width
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)
	head.add_child(UI.picture(UI.icon(icon_name)))
	_title_label = UI.label(title, "Title")
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title_label)
	var close_button := UI.tool_button(UI.icon("close", 1), "Close (Esc)", 30)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	column.add_child(HSeparator.new())
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	column.add_child(body)


func open() -> void:
	visible = true
	_center.call_deferred()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _center() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
