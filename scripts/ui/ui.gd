## The look of the interface: one palette, one theme, the icons and the small widgets every panel
## shares. Dark wine panels with a thick ink outline, bone-white text, crimson and gold accents
## (the mood of Cult of the Lamb), around pixel-art icons and a bar of powers as in WorldBox.
## Icons come from one atlas drawn by art/ui_icons.py; creatures and biomes show their own sprites.
extends RefCounted

const UiIcons = preload("res://scripts/generated/ui_icons.gd")
const TerrainAtlas = preload("res://scripts/generated/terrain_atlas.gd")

const INK := Color("#140c12")
const PANEL := Color("#2a1a23")
const PANEL_DEEP := Color("#1c1118")
const RAISED := Color("#3f2632")
const RAISED_HOVER := Color("#58323f")
const EDGE := Color("#6b4250")
const CREAM := Color("#f4e6c8")
const MUTED := Color("#b59c8f")
const DIM := Color("#7a6268")
const CRIMSON := Color("#d8334a")
const CRIMSON_DARK := Color("#8c1d2e")
const GOLD := Color("#f2b84b")
const GREEN := Color("#6cbe54")
const BLUE := Color("#96daff")

## Jersey (OFL) is drawn for whole multiples of its size: Jersey 10 at 20 and 30 pixels for text
## and titles, Jersey 15 at 15 pixels for small print.
const FONT := "res://assets/fonts/Jersey10-Regular.woff2"
const FONT_SMALL := "res://assets/fonts/Jersey15-Regular.woff2"
const SIZE := 20
const SIZE_SMALL := 15
const SIZE_TITLE := 30
const EMBLEM := "res://assets/ui/emblem.png"

static var _theme: Theme
static var _atlas: Image
static var _icons := {}
static var _sprites := {}
static var _small: Font


## A filled, outlined box: the base of every panel and button.
static func box(fill: Color, border: Color, width := 2, radius := 6, margin := 8, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = false
	if shadow > 0:
		# A hard shadow under the box: the panel reads as a thick sticker on the map.
		s.shadow_color = Color(INK, 0.55)
		s.shadow_size = 1
		s.shadow_offset = Vector2(0, shadow)
	return s


static func small_font() -> Font:
	if _small == null:
		_small = load(FONT_SMALL) if ResourceLoader.exists(FONT_SMALL) else ThemeDB.fallback_font
	return _small


## Small print on a label or a button.
static func small(control: Control) -> void:
	control.add_theme_font_override("font", small_font())
	control.add_theme_font_size_override("font_size", SIZE_SMALL)


## The theme of the whole interface, built once.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	_theme = t
	if ResourceLoader.exists(FONT):
		t.default_font = load(FONT)
	t.default_font_size = SIZE

	t.set_color("font_color", "Label", CREAM)
	t.set_constant("line_spacing", "Label", 1)

	# Panels.
	t.set_stylebox("panel", "PanelContainer", box(Color(PANEL, 0.96), INK, 3, 8, 10, 3))
	t.set_stylebox("panel", "Panel", box(Color(PANEL, 0.96), INK, 3, 8, 10, 3))
	_variation(t, "Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(PANEL_DEEP, Color(INK, 0.9), 2, 6, 8))
	_variation(t, "Bar", "PanelContainer")
	var bar := box(Color(PANEL, 0.97), INK, 0, 0, 6)
	bar.border_width_bottom = 3
	t.set_stylebox("panel", "Bar", bar)
	_variation(t, "Chip", "PanelContainer")
	var chip := box(PANEL_DEEP, Color(INK, 0.9), 2, 12, 4)
	chip.content_margin_left = 8
	chip.content_margin_right = 10
	t.set_stylebox("panel", "Chip", chip)
	_variation(t, "Toast", "PanelContainer")
	var toast := box(Color(INK, 0.92), GOLD, 2, 14, 6)
	toast.content_margin_left = 14
	toast.content_margin_right = 14
	t.set_stylebox("panel", "Toast", toast)

	# Buttons.
	_button(t, "Button", RAISED, RAISED_HOVER, CRIMSON, 6, 8)
	_variation(t, "Primary", "Button")
	_button(t, "Primary", CRIMSON, CRIMSON.lightened(0.15), CRIMSON_DARK, 8, 12)
	t.set_font_size("font_size", "Primary", SIZE_TITLE)
	_variation(t, "Tool", "Button")
	_button(t, "Tool", RAISED, RAISED_HOVER, CRIMSON, 6, 3)
	_variation(t, "Ghost", "Button")
	_button(t, "Ghost", Color(RAISED, 0.0), Color(RAISED_HOVER, 0.8), CRIMSON, 6, 4)
	t.set_stylebox("normal", "Ghost", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 2, 6, 4))
	# Tabs of the powers bar: the open one joins the tray under it.
	_variation(t, "Tab", "Button")
	_button(t, "Tab", RAISED, RAISED_HOVER, PANEL, 6, 6)
	var open_tab := box(Color(PANEL, 0.96), INK, 3, 8, 6)
	open_tab.border_color = GOLD
	t.set_stylebox("pressed", "Tab", open_tab)
	t.set_stylebox("hover_pressed", "Tab", open_tab)
	t.set_color("font_pressed_color", "Tab", GOLD)
	t.set_color("font_hover_pressed_color", "Tab", GOLD)
	for type in ["OptionButton", "MenuButton"]:
		_button(t, type, RAISED, RAISED_HOVER, CRIMSON, 6, 8)
	t.set_constant("arrow_margin", "OptionButton", 8)

	# Check boxes and switches, drawn here so they match the icons.
	for type in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			t.set_stylebox(state, type, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 3))
		t.set_color("font_color", type, CREAM)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, CREAM)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, DIM)
		t.set_constant("h_separation", type, 8)
	t.set_icon("checked", "CheckBox", _check_icon(true, false))
	t.set_icon("unchecked", "CheckBox", _check_icon(false, false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, true))
	t.set_icon("checked", "CheckButton", _switch_icon(true, false))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false, false))
	t.set_icon("checked_disabled", "CheckButton", _switch_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false, true))

	# Text fields.
	var field := box(PANEL_DEEP, INK, 2, 6, 6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("read_only", "LineEdit", field)
	var focus := box(PANEL_DEEP, GOLD, 2, 6, 6)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(CRIMSON, 0.6))

	# Sliders, bars and scrolling.
	var groove := box(PANEL_DEEP, INK, 2, 5, 0)
	groove.content_margin_top = 5
	groove.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", groove)
	var filled := box(CRIMSON, INK, 2, 5, 0)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_icon("grabber", "HSlider", _knob(CREAM))
	t.set_icon("grabber_highlight", "HSlider", _knob(Color.WHITE))
	t.set_icon("grabber_disabled", "HSlider", _knob(DIM))
	t.set_stylebox("background", "ProgressBar", box(PANEL_DEEP, INK, 2, 5, 0))
	t.set_stylebox("fill", "ProgressBar", box(CRIMSON, INK, 2, 5, 0))
	t.set_color("font_color", "ProgressBar", CREAM)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, box(Color(PANEL_DEEP, 0.6), Color(0, 0, 0, 0), 0, 4, 3))
		t.set_stylebox("grabber", type, box(EDGE, Color(0, 0, 0, 0), 0, 4, 3))
		t.set_stylebox("grabber_highlight", type, box(MUTED, Color(0, 0, 0, 0), 0, 4, 3))
		t.set_stylebox("grabber_pressed", type, box(CRIMSON, Color(0, 0, 0, 0), 0, 4, 3))

	# Menus and tooltips.
	t.set_stylebox("panel", "PopupMenu", box(PANEL, INK, 3, 6, 6))
	t.set_stylebox("hover", "PopupMenu", box(CRIMSON, INK, 0, 4, 2))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_stylebox("panel", "TooltipPanel", box(INK, GOLD, 2, 6, 8))
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_font("font", "TooltipLabel", small_font())
	t.set_font_size("font_size", "TooltipLabel", SIZE_SMALL)

	# Separators.
	var line := StyleBoxLine.new()
	line.color = Color(EDGE, 0.8)
	line.thickness = 2
	t.set_stylebox("separator", "HSeparator", line)
	var vline := line.duplicate()
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)
	t.set_constant("separation", "HSeparator", 8)
	t.set_constant("separation", "VSeparator", 8)

	# Kinds of text.
	_variation(t, "Title", "Label")
	t.set_font_size("font_size", "Title", SIZE_TITLE)
	t.set_color("font_color", "Title", CREAM)
	_variation(t, "Heading", "Label")
	t.set_font_size("font_size", "Heading", SIZE)
	t.set_color("font_color", "Heading", GOLD)
	_variation(t, "Muted", "Label")
	t.set_font("font", "Muted", small_font())
	t.set_font_size("font_size", "Muted", SIZE_SMALL)
	t.set_color("font_color", "Muted", MUTED)
	_variation(t, "Small", "Label")
	t.set_font("font", "Small", small_font())
	t.set_font_size("font_size", "Small", SIZE_SMALL)
	return t


static func _variation(t: Theme, name: String, base: String) -> void:
	t.set_type_variation(name, base)


static func _button(t: Theme, type: String, fill: Color, hover: Color, on: Color, radius: int, margin: int) -> void:
	var normal := box(fill, INK, 2, radius, margin)
	normal.border_width_bottom = 4
	var over := box(hover, INK, 2, radius, margin)
	over.border_width_bottom = 4
	# Pressed: the button sinks by the thickness of its bottom edge.
	var down := box(on, INK, 2, radius, margin)
	down.content_margin_top = margin + 2
	down.content_margin_bottom = margin
	down.border_color = Color(CREAM, 0.95) if on == CRIMSON else INK
	var off := box(Color(PANEL_DEEP, 0.9), Color(INK, 0.8), 2, radius, margin)
	off.border_width_bottom = 4
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, over)
	t.set_stylebox("pressed", type, down)
	t.set_stylebox("hover_pressed", type, down)
	t.set_stylebox("disabled", type, off)
	t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), Color(GOLD, 0.0), 0, radius, margin))
	t.set_color("font_color", type, CREAM)
	t.set_color("font_hover_color", type, Color.WHITE)
	t.set_color("font_pressed_color", type, Color.WHITE)
	t.set_color("font_hover_pressed_color", type, Color.WHITE)
	t.set_color("font_focus_color", type, CREAM)
	t.set_color("font_disabled_color", type, DIM)
	t.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.35))
	t.set_constant("h_separation", type, 6)


## A 20×20 tick box.
static func _check_icon(on: bool, disabled: bool) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	var fill := (CRIMSON if on else PANEL_DEEP) if not disabled else PANEL_DEEP.lightened(0.05)
	for y in 20:
		for x in 20:
			var edge := x < 2 or y < 2 or x > 17 or y > 17
			var corner := (x < 2 or x > 17) and (y < 2 or y > 17)
			if not corner:
				img.set_pixel(x, y, INK if edge else fill)
	if on:
		var ink := DIM if disabled else CREAM
		for p in [[5, 10], [7, 12], [9, 14], [11, 12], [13, 10], [15, 8], [15, 6], [13, 8], [11, 10], [9, 12], [7, 10], [5, 8]]:
			img.fill_rect(Rect2i(p[0] - 1, p[1] - 1, 2, 2), ink)
	return ImageTexture.create_from_image(img)


## A 36×20 switch, its knob on the right when on.
static func _switch_icon(on: bool, disabled: bool) -> ImageTexture:
	var img := Image.create(36, 20, false, Image.FORMAT_RGBA8)
	var fill := (GREEN.darkened(0.25) if on else PANEL_DEEP) if not disabled else PANEL_DEEP.lightened(0.05)
	for y in 20:
		for x in 36:
			var d := 0.0
			if x < 10:
				d = Vector2(x, y).distance_to(Vector2(9.5, 9.5))
			elif x > 25:
				d = Vector2(x, y).distance_to(Vector2(25.5, 9.5))
			else:
				d = absf(y - 9.5)
			if d <= 9.5:
				img.set_pixel(x, y, INK if d > 7.5 else fill)
	var cx := 25.5 if on else 9.5
	var knob := DIM if disabled else CREAM
	for y in 20:
		for x in 36:
			if Vector2(x, y).distance_to(Vector2(cx, 9.5)) <= 5.5:
				img.set_pixel(x, y, knob)
	return ImageTexture.create_from_image(img)


static func _knob(colour: Color) -> ImageTexture:
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 18:
			var d := Vector2(x, y).distance_to(Vector2(8.5, 8.5))
			if d <= 8.5:
				img.set_pixel(x, y, INK if d > 6.0 else colour)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ pictures

## An interface icon by name (scripts/generated/ui_icons.gd), `scale` screen pixels per icon pixel.
static func icon(name: String, scale := 2) -> Texture2D:
	var key := "%s@%d" % [name, scale]
	if _icons.has(key):
		return _icons[key]
	var index := UiIcons.NAMES.find(name)
	if index < 0 or not ResourceLoader.exists(UiIcons.TEXTURE):
		push_warning("No interface icon named %s" % name)
		index = maxi(UiIcons.NAMES.find("info"), 0)
	if _atlas == null:
		_atlas = _image_of(UiIcons.TEXTURE)
	var tex: Texture2D = null
	if _atlas != null:
		var size := UiIcons.SIZE
		var img := _atlas.get_region(Rect2i((index % UiIcons.COLUMNS) * size, (index / UiIcons.COLUMNS) * size, size, size))
		img.resize(size * scale, size * scale, Image.INTERPOLATE_NEAREST)
		tex = ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## A game sprite as an icon: "creatures/wolf_idle", "buildings/market"… scaled up with sharp pixels
## to fit a square of `fit` pixels. Null when the sprite does not exist.
static func sprite(path: String, fit := 32) -> Texture2D:
	var key := "%s@%d" % [path, fit]
	if _sprites.has(key):
		return _sprites[key]
	var img := _image_of("res://assets/sprites/%s.png" % path)
	var tex: Texture2D = null
	if img != null:
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			img = img.get_region(used)
		var k := maxi(1, mini(fit / img.get_width(), fit / img.get_height()))
		img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
		tex = ImageTexture.create_from_image(img)
	_sprites[key] = tex
	return tex


## The portrait of a creature or a person of a people ("wolf", "humans"), or null.
static func creature(id: String, fit := 32, role := "villager") -> Texture2D:
	var tex := sprite("creatures/%s_idle" % id, fit)
	return tex if tex != null else sprite("creatures/%s_%s_idle" % [id, role], fit)


## A square of a biome's ground, from the terrain atlas, framed in ink.
static func biome_swatch(tile_name: String, size := 28) -> Texture2D:
	var key := "biome:%s@%d" % [tile_name, size]
	if _sprites.has(key):
		return _sprites[key]
	var column := TerrainAtlas.TILES.find(tile_name)
	var atlas := _image_of(TerrainAtlas.TEXTURE)
	var tex: Texture2D = null
	if column >= 0 and atlas != null:
		var tile := atlas.get_region(Rect2i(column * TerrainAtlas.TILE_SIZE, 0, TerrainAtlas.TILE_SIZE, TerrainAtlas.TILE_SIZE))
		var k := maxi(1, (size - 4) / TerrainAtlas.TILE_SIZE)
		tile.resize(TerrainAtlas.TILE_SIZE * k, TerrainAtlas.TILE_SIZE * k, Image.INTERPOLATE_NEAREST)
		var side := tile.get_width() + 4
		var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
		img.fill_rect(Rect2i(1, 0, side - 2, side), INK)
		img.fill_rect(Rect2i(0, 1, side, side - 2), INK)
		img.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(2, 2))
		tex = ImageTexture.create_from_image(img)
	_sprites[key] = tex
	return tex


static func _image_of(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var img := (load(path) as Texture2D).get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


# ------------------------------------------------------------------ widgets

static func label(text: String, kind := "") -> Label:
	var l := Label.new()
	l.text = text
	if kind != "":
		l.theme_type_variation = kind
	return l


## A picture that keeps its pixels and lets the mouse through.
static func picture(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## A button with text and, if named, an icon. It never takes the keyboard: Space must keep
## pausing the world.
static func button(text: String, icon_name := "", tip := "", kind := "") -> Button:
	var b := Button.new()
	b.text = text
	if icon_name != "":
		b.icon = icon(icon_name, 1 if kind == "Ghost" and text != "" else 2)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if kind != "":
		b.theme_type_variation = kind
	return b


## A square button showing one picture (an icon, a creature, a biome).
static func tool_button(tex: Texture2D, tip := "", side := 44) -> Button:
	var b := Button.new()
	b.icon = tex
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "Tool"
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(side, side)
	return b


## An icon and a number in a pill (people, villages… in the top bar). Returns [chip, label].
static func chip(icon_name: String, tip: String) -> Array:
	var p := PanelContainer.new()
	p.theme_type_variation = "Chip"
	p.tooltip_text = tip
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	row.add_child(picture(icon(icon_name, 1)))
	var l := label("0")
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return [p, l]


## Marks a button as a feature to come: dimmed, with a lock in its corner. It still answers
## clicks, so the game can say what it will do.
static func mark_soon(b: Button) -> void:
	b.modulate = Color(0.62, 0.58, 0.62, 0.95)
	var lock := picture(icon("lock", 1))
	lock.position = Vector2(b.custom_minimum_size.x - 18, b.custom_minimum_size.y - 20)
	lock.size = Vector2(16, 16)
	lock.modulate = Color(1.6, 1.6, 1.6)
	b.add_child(lock)
	b.set_meta("soon", true)
