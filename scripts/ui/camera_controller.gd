## Map camera: mouse wheel zooms toward the cursor, right or middle drag pans, WASD / arrows pan.
extends Camera2D

const MIN_ZOOM := 0.1
const MAX_ZOOM := 8.0
const ZOOM_STEP := 1.15
const PAN_SPEED := 700.0  # screen pixels per second

var _dragging := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(ZOOM_STEP, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(1.0 / ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom


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
		position += dir.normalized() * PAN_SPEED * delta / zoom.x


## Zooms by `factor`, keeping the world point under `screen_pos` where it is.
func zoom_at(factor: float, screen_pos: Vector2) -> void:
	var offset_from_centre := screen_pos - get_viewport_rect().size / 2.0
	var world_point := position + offset_from_centre / zoom
	var z := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	position = world_point - offset_from_centre / zoom


## Centres the camera on `rect` (world pixels) and zooms so it fits the screen.
func fit(rect: Rect2) -> void:
	position = rect.get_center()
	var view := get_viewport_rect().size
	var z := clampf(minf(view.x / rect.size.x, view.y / rect.size.y) * 0.95, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
