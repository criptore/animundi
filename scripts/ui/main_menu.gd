## The title screen, over the first generated world: the emblem, the name of the game and the
## main choices. Continue and Load wait for saved worlds (docs/ROADMAP.md, 0.9).
extends Control

const UI = preload("res://scripts/ui/ui.gd")

## One of: "new_world", "continue", "load", "settings", "credits", "quit".
signal chosen(what: String)

const ENTRIES := [
	["new_world", "New world", "globe", "Primary"],
	["continue", "Continue", "play", ""],
	["load", "Load a world", "load", ""],
	["settings", "Settings", "gear", ""],
	["credits", "Credits", "heart", ""],
	["quit", "Quit", "door", ""],
]
## Choices that wait for a later version: shown locked.
const SOON := ["continue", "load"]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The world behind, darkened; the shade also keeps clicks off the map.
	var shade := ColorRect.new()
	shade.color = Color(UI.INK, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	centre.add_child(column)

	var emblem := UI.picture(_emblem())
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(emblem)
	var title := UI.label("ANIMUNDI", "Title")
	title.add_theme_font_size_override("font_size", 90)
	title.add_theme_color_override("font_color", UI.CREAM)
	title.add_theme_color_override("font_outline_color", UI.INK)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_shadow_color", UI.CRIMSON_DARK)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_outline_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var sub := UI.label("anima mundi · the soul of the world", "Muted")
	sub.add_theme_color_override("font_color", UI.GOLD)
	sub.add_theme_font_override("font", UI.theme().default_font)
	sub.add_theme_font_size_override("font_size", UI.SIZE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	column.add_child(gap)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 6)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.custom_minimum_size.x = 300
	column.add_child(menu)
	for entry in ENTRIES:
		var b := UI.button(entry[1], entry[2], "", entry[3])
		b.custom_minimum_size.y = 46 if entry[3] == "Primary" else 40
		b.pressed.connect(func(): chosen.emit(entry[0]))
		if entry[0] in SOON:
			b.modulate = Color(0.7, 0.66, 0.7)
			b.tooltip_text = "Saved worlds come in a later version"
		menu.add_child(b)

	var version := UI.label("version 0.9 · the world lives, the god awakes", "Muted")
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.position += Vector2(12, -34)
	add_child(version)


func _emblem() -> Texture2D:
	if not ResourceLoader.exists(UI.EMBLEM):
		return null
	var img := (load(UI.EMBLEM) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)
