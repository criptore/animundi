## The tilt view's camera: a perspective camera with a long lens looking north and down at the
## world (the diorama look of Cult of the Lamb). It pans and zooms, never turns. The further it
## is, the more it rises, until it looks straight down: far away the world is the flat map again.
extends Camera3D

const FOV := 30.0
## Angle under the horizon, close up and far away, and the distances between which it rises.
const PITCH_NEAR := 50.0
const PITCH_FAR := 90.0
const RISE_FROM := 40.0
const RISE_TO := 170.0
const MIN_DISTANCE := 12.0
const ZOOM_STEP := 1.12
## Pan speed with the keys, in screen heights per second.
const PAN_SPEED := 0.9
## Share of a screen height moved per notch of a horizontal wheel.
const WHEEL_PAN := 0.08

## Ground point at the centre of the view, in tiles (x, y of the map).
var target := Vector2.ZERO
## Distance from the camera to the target, in tiles.
var distance := 34.0
## Size of the map in tiles: the target stays inside.
var bounds := Vector2.ZERO
## Forces the pitch (degrees) when not negative: the preview tool's flat comparison.
var fixed_pitch := -1.0

var _dragging := false


func _init() -> void:
	projection = PROJECTION_PERSPECTIVE
	fov = FOV
	near = 1.0


## 1 close up (full tilt, every effect), 0 far away (straight down, the plain map).
func closeness() -> float:
	return 1.0 - smoothstep(RISE_FROM, RISE_TO, distance)


## Degrees under the horizon at the current distance.
func pitch() -> float:
	if fixed_pitch >= 0.0:
		return fixed_pitch
	return lerpf(PITCH_FAR, PITCH_NEAR, closeness())


## How far standing sprites lean back from upright, in radians: partly toward the line of sight
## close up (they stay planted on the ground), fully when the camera looks straight down.
func sprite_lean() -> float:
	var p := pitch()
	return minf(deg_to_rad(p) * lerpf(0.42, 1.0, smoothstep(62.0, 90.0, p)), deg_to_rad(86.0))


## Vertical stretch that shows a leaning sprite at its true proportions.
func sprite_stretch() -> float:
	return 1.0 / cos(deg_to_rad(pitch()) - sprite_lean())


## Tiles covered by the height of the screen at the target.
func view_height() -> float:
	return 2.0 * distance * tan(deg_to_rad(FOV) / 2.0)


## Distance from which the height of the screen covers `tiles` at the target.
func distance_for(tiles: float) -> float:
	return tiles / (2.0 * tan(deg_to_rad(FOV) / 2.0))


## Furthest distance: the whole map fits in the view, with a margin.
func max_distance() -> float:
	var view := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	return maxf(distance_for(maxf(bounds.y, bounds.x * view.y / maxf(view.x, 1.0)) / 0.9), RISE_TO)


func look_at_tile(point: Vector2, dist: float) -> void:
	target = point
	distance = clampf(dist, MIN_DISTANCE, max_distance())
	apply()


## Shows the whole map, from straight above.
func frame_all() -> void:
	look_at_tile(bounds / 2.0, max_distance())


func apply() -> void:
	if bounds != Vector2.ZERO:
		target = target.clamp(Vector2.ZERO, bounds)
	var p := deg_to_rad(minf(pitch(), 89.5))
	position = Vector3(target.x, sin(p) * distance, target.y + cos(p) * distance)
	far = distance * 4.0 + 300.0
	look_at(Vector3(target.x, 0.0, target.y), Vector3(0, 0, -1) if pitch() > 85.0 else Vector3.UP)


## The ground point (tiles, at height 0) under a screen position.
func ground_at(screen_pos: Vector2) -> Vector2:
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-5:
		return target
	var hit := from - dir * (from.y / dir.y)
	return Vector2(hit.x, hit.z)


## Wheel, pinch and + / - zoom toward the pointer; dragging with any mouse button, a two-finger
## scroll or a horizontal wheel pans (the same gestures as the flat map's camera, ui/map_camera.gd).
## Returns whether the event was used.
func handle_input(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button != null:
		# Trackpads send fractions of a notch in `factor` (0 when the platform doesn't say).
		var notches := button.factor if button.factor > 0.0 else 1.0
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom(pow(ZOOM_STEP, -notches if button.button_index == MOUSE_BUTTON_WHEEL_UP else notches), button.position)
				return true
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT:
				if button.pressed:
					target.x += (-1.0 if button.button_index == MOUSE_BUTTON_WHEEL_LEFT else 1.0) * notches * WHEEL_PAN * view_height()
					apply()
				return true
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = button.pressed
				return true
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		# The button was let go over the interface: the drag is over.
		if motion.button_mask == 0:
			_dragging = false
			return false
		target -= ground_at(motion.position) - ground_at(motion.position - motion.relative)
		apply()
		return true
	var pinch := event as InputEventMagnifyGesture
	if pinch != null:
		_zoom(1.0 / pinch.factor, pinch.position)
		return true
	var pan := event as InputEventPanGesture
	if pan != null:
		target += pan.delta * view_height() * 0.02
		apply()
		return true
	var key := event as InputEventKey
	if key != null and key.pressed:
		var centre := get_viewport().get_visible_rect().size / 2.0
		if key.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			_zoom(1.0 / ZOOM_STEP, centre)
			return true
		if key.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			_zoom(ZOOM_STEP, centre)
			return true
	return false


## WASD (wherever those keys sit on the keyboard) and the arrows pan.
func _process(delta: float) -> void:
	if not current or not is_visible_in_tree():
		return
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y += 1.0
	if move != Vector2.ZERO:
		target += move * view_height() * PAN_SPEED * delta
		apply()


func _zoom(factor: float, toward: Vector2) -> void:
	var before := ground_at(toward)
	distance = clampf(distance * factor, MIN_DISTANCE, max_distance())
	apply()
	target += before - ground_at(toward)
	apply()
