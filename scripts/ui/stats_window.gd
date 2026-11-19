## Statistics (0.9): the world's numbers through the years, a line a year from the simulation
## (sim/Cards.cs History): people, villages, kingdoms, animals, plants, wars, inventions, the
## highest age reached and the warming. Pick what to see; each curve fills the chart's height,
## from nothing to its highest value, its last value written beside it.
extends "res://scripts/ui/window.gd"

## Series that can be shown: column of History, name, colour.
const SERIES := [["people", "People", Color("#f2b84b")], ["villages", "Villages", Color("#d8334a")],
		["kingdoms", "Kingdoms", Color("#a563d0")], ["animals", "Animals", Color("#6cbe54")],
		["plants", "Plants", Color("#3a803e")], ["wars", "Wars", Color("#e8483c")],
		["inventions", "Inventions", Color("#49a0df")], ["age", "Highest age", Color("#f4e6c8")],
		["warming", "Warming", Color("#f08a2a")]]

var history := {}
var _shown := {"people": true, "villages": true, "kingdoms": true}
var _chart: Control
var _note: Label


func _init() -> void:
	build("Statistics", "chart", 640)
	var picks := HFlowContainer.new()
	picks.add_theme_constant_override("h_separation", 4)
	picks.add_theme_constant_override("v_separation", 4)
	body.add_child(picks)
	for s in SERIES:
		var b := CheckBox.new()
		b.text = s[1]
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = _shown.get(s[0], false)
		b.add_theme_color_override("font_color", s[2])
		b.add_theme_color_override("font_pressed_color", s[2])
		UI.small(b)
		var id: String = s[0]
		b.toggled.connect(func(on):
			_shown[id] = on
			_chart.queue_redraw())
		picks.add_child(b)
	_chart = Control.new()
	_chart.custom_minimum_size = Vector2(610, 280)
	_chart.draw.connect(_draw_chart)
	body.add_child(_chart)
	_note = UI.label("", "Small")
	_note.add_theme_color_override("font_color", UI.MUTED)
	body.add_child(_note)


## The simulation's History: column → values, a value a recorded year.
func set_history(h: Dictionary) -> void:
	history = h
	var years: PackedFloat32Array = h.get("year", PackedFloat32Array())
	_note.text = "Years %d to %d · each curve from nothing to its highest" % [int(years[0]), int(years[-1])] if years.size() > 1 \
			else "The first year is not over: the numbers come once a year."
	_chart.queue_redraw()


## The points of a series in the chart's frame (each curve scaled to its own range).
func points_of(id: String, size: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var values: PackedFloat32Array = history.get(id, PackedFloat32Array())
	if values.size() < 2:
		return pts
	var lo := 0.0
	var hi := values[0]
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if hi - lo < 1e-4:
		hi = lo + 1.0
	for k in values.size():
		pts.append(Vector2(size.x * k / (values.size() - 1), size.y - size.y * (values[k] - lo) / (hi - lo)))
	return pts


func _draw_chart() -> void:
	var area := Rect2(Vector2(6, 6), _chart.size - Vector2(70, 20))
	_chart.draw_rect(Rect2(Vector2.ZERO, _chart.size), Color(UI.INK, 0.6))
	for k in 5:
		var y := area.position.y + area.size.y * k / 4.0
		_chart.draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.06))
	var font := _chart.get_theme_default_font()
	var label_y := {}
	for s in SERIES:
		if not _shown.get(s[0], false):
			continue
		var pts := points_of(s[0], area.size)
		if pts.size() < 2:
			continue
		for k in pts.size():
			pts[k] += area.position
		_chart.draw_polyline(pts, s[2], 2.0)
		var values: PackedFloat32Array = history[s[0]]
		var y := clampf(pts[-1].y, area.position.y + 8, area.end.y)
		while label_y.has(int(y / 12)):
			y += 12
		label_y[int(y / 12)] = true
		var shown := ("%.1f°" % values[-1]) if s[0] == "warming" else str(int(values[-1]))
		_chart.draw_string(font, Vector2(area.end.x + 4, y + 4), shown, HORIZONTAL_ALIGNMENT_LEFT, 60, 12, s[2])
