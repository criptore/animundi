## The brush of the god powers: a circle on the map under the mouse, as wide as the power reaches.
## Flat view: lives in world space (a child of the main scene), so it scales with the camera.
## Tilt view: lives on the screen and draws `outline`, the circle as the tilted camera sees it.
extends Node2D

## Radius in world pixels.
var radius := 8.0:
	set(value):
		if radius != value:
			radius = value
			queue_redraw()
## Screen pixels per world pixel, to keep the line one screen pixel thick.
var zoom := 1.0:
	set(value):
		if zoom != value:
			zoom = value
			queue_redraw()
## The circle already projected on the screen (tilt view); empty = drawn from `radius`.
var outline := PackedVector2Array():
	set(value):
		outline = value
		queue_redraw()


func _init() -> void:
	z_index = 100
	visible = false


func _draw() -> void:
	if outline.size() > 2:
		draw_polyline(outline, Color(0, 0, 0, 0.55), 3.3)
		draw_polyline(outline, Color(1, 1, 1, 0.9), 1.5)
		return
	var width := 1.5 / maxf(zoom, 0.01)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0, 0, 0, 0.55), width * 2.2)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.9), width)
