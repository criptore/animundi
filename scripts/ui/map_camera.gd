## 2D map camera: zooms toward the mouse (wheel, trackpad pinch, + / - keys), pans by dragging
## with any mouse button (so a trackpad's click-and-drag works), with a trackpad's two-finger
## scroll, a horizontal wheel or WASD / arrows, and keeps the map in view. Zoom is in screen pixels per world pixel (a tile is
## WorldMap.TILE world pixels).
extends Camera2D

const ZOOM_STEP := 1.2
## Closest zoom: a tile covers TILE * MAX_ZOOM screen pixels.
const MAX_ZOOM := 12.0
const PAN_SPEED := 900.0  # screen pixels per second
## Screen pixels moved per unit of a trackpad two-finger scroll (macOS sends these as gestures).
const PAN_GESTURE_SPEED := 24.0
## Screen pixels moved per notch of a horizontal wheel (sideways two-finger scroll elsewhere).
const WHEEL_PAN := 60.0

var _dragging := false

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


## Handles the camera's mouse, trackpad and key input. Returns true when the event was used.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Trackpads send fractions of a notch in `factor` (0 when the platform doesn't say).
		var notches := mb.factor if mb.factor > 0.0 else 1.0
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_at(pow(ZOOM_STEP, notches), mb.position)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(pow(ZOOM_STEP, -notches), mb.position)
				return true
			MOUSE_BUTTON_WHEEL_LEFT:
				if mb.pressed:
					pan_screen(Vector2(WHEEL_PAN * notches, 0.0))
				return true
			MOUSE_BUTTON_WHEEL_RIGHT:
				if mb.pressed:
					pan_screen(Vector2(-WHEEL_PAN * notches, 0.0))
				return true
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
				return true
	elif event is InputEventMouseMotion:
		if _dragging:
			pan_screen((event as InputEventMouseMotion).relative)
			return true
	elif event is InputEventPanGesture:
		pan_screen(-(event as InputEventPanGesture).delta * PAN_GESTURE_SPEED)
		return true
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		zoom_at(g.factor, g.position)
		return true
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			zoom_at(ZOOM_STEP, _view_size() / 2.0)
			return true
		if key.pressed and key.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			zoom_at(1.0 / ZOOM_STEP, _view_size() / 2.0)
			return true
	return false


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
