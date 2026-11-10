## The tilt view's camera: a perspective camera with a long lens looking north and down at the
## world (the diorama look of Cult of the Lamb). It pans and zooms, never turns. Far away it rises
## toward a top-down view, so the whole world still reads like a map.
extends Camera3D

const FOV := 30.0
## Angle under the horizon, close up and far away, and the distances between which it rises.
const PITCH_NEAR := 52.0
const PITCH_FAR := 82.0
const RISE_FROM := 70.0
const RISE_TO := 260.0
const MIN_DISTANCE := 12.0
const MAX_DISTANCE := 900.0
const ZOOM_STEP := 1.12
## Pan speed with the keys, in screen heights per second.
const PAN_SPEED := 0.9

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


## Degrees under the horizon at the current distance.
func pitch() -> float:
	if fixed_pitch >= 0.0:
		return fixed_pitch
	return lerpf(PITCH_NEAR, PITCH_FAR, smoothstep(RISE_FROM, RISE_TO, distance))


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


func look_at_tile(point: Vector2, dist: float) -> void:
	target = point
	distance = clampf(dist, MIN_DISTANCE, MAX_DISTANCE)
	apply()


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


## Wheel and pinch zoom toward the pointer, drag to pan. Returns whether the event was used.
func handle_input(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				_zoom(1.0 / ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else ZOOM_STEP, button.position)
			return true
		if button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = button.pressed
			return false
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
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
	return false


func _process(delta: float) -> void:
	if not current:
		return
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	if move != Vector2.ZERO:
		target += move * view_height() * PAN_SPEED * delta
		apply()


func _zoom(factor: float, toward: Vector2) -> void:
	var before := ground_at(toward)
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	apply()
	target += before - ground_at(toward)
	apply()
