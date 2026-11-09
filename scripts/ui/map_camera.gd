## 2D map camera: zooms toward the mouse with the wheel, pans by dragging or with WASD / arrows,
## and keeps the map in view. Zoom is in screen pixels per world pixel (a tile is
## WorldMap.TILE world pixels).
extends Camera2D

const ZOOM_STEP := 1.2
## Closest zoom: a tile covers TILE * MAX_ZOOM screen pixels.
const MAX_ZOOM := 12.0
const PAN_SPEED := 900.0  # screen pixels per second

## Map size in world pixels, for the zoom-out limit and the panning bounds.
var bounds := Vector2(2048, 2048)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO:
		pan_screen(-dir.normalized() * PAN_SPEED * delta)


## Smallest zoom: the whole map fits in the view, with a margin.
func min_zoom() -> float:
	var view := _view_size()
	return minf(view.x / bounds.x, view.y / bounds.y) * 0.9


## Multiplies the zoom by `factor`, keeping the world point under `screen_point` in place.
func zoom_at(factor: float, screen_point: Vector2) -> void:
	var before := screen_to_world(screen_point)
	zoom = Vector2.ONE * clampf(zoom.x * factor, min_zoom(), MAX_ZOOM)
	position += before - screen_to_world(screen_point)
	_clamp()


## Moves the view as if the map were dragged by `delta` screen pixels.
func pan_screen(delta: Vector2) -> void:
	position -= delta / zoom.x
	_clamp()


## Shows the whole map.
func frame_all() -> void:
	position = bounds / 2.0
	zoom = Vector2.ONE * min_zoom()


## Centres the view on `point` (world pixels) at `zoom_value`.
func look_at_point(point: Vector2, zoom_value: float) -> void:
	position = point
	zoom = Vector2.ONE * clampf(zoom_value, min_zoom(), MAX_ZOOM)
	_clamp()


## World position (pixels) under a screen position.
func screen_to_world(screen_point: Vector2) -> Vector2:
	return position + (screen_point - _view_size() / 2.0) / zoom.x


## The centre of the view stays on the map.
func _clamp() -> void:
	position = position.clamp(Vector2.ZERO, bounds)
	if is_inside_tree():
		force_update_scroll()


func _view_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
