## Orthographic camera looking north over the world at a fixed angle, for the low-resolution pixel
## render. It pans and zooms but never rotates: a fixed angle keeps pixel outlines clean
## (docs/ART_DIRECTION.md). Its position snaps to the render's pixel grid, so nothing shimmers.
extends Camera3D

const DISTANCE := 300.0
const MIN_SIZE := 10.0
const MAX_SIZE := 700.0
const PAN_SPEED := 500.0  # screen pixels per second
const ZOOM_STEP := 1.15
const YAW := 0.0
const PITCH := -42.0

## Ground point at the centre of the view.
var target := Vector3.ZERO
## Height of the view in world units (tiles).
var ortho_size := 120.0


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	near = 1.0
	far = 1000.0
	apply()


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
		pan_screen(-dir.normalized() * PAN_SPEED * delta, 720.0)


func zoom_by(factor: float) -> void:
	ortho_size = clampf(ortho_size / factor, MIN_SIZE, MAX_SIZE)
	apply()


## Moves the view as if the ground were dragged by `delta` pixels on a screen `screen_height` tall.
func pan_screen(delta: Vector2, screen_height: float) -> void:
	var units := ortho_size / screen_height
	var b := Basis.from_euler(Vector3(deg_to_rad(PITCH), deg_to_rad(YAW), 0.0))
	var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var forward := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	# Screen height maps to more ground than its length because the view is tilted.
	target -= right * delta.x * units
	target += forward * delta.y * units / sin(absf(deg_to_rad(PITCH)))
	apply()


## Centres the view on `centre` with `view_size` world units visible vertically.
func frame(centre: Vector3, view_size: float) -> void:
	target = centre
	ortho_size = clampf(view_size, MIN_SIZE, MAX_SIZE)
	apply()


## World units covered by one render pixel (for pixel-sized effects such as outlines).
func world_per_pixel() -> float:
	return ortho_size / maxf(get_viewport().get_visible_rect().size.y, 1.0)


func apply() -> void:
	size = ortho_size
	var b := Basis.from_euler(Vector3(deg_to_rad(PITCH), deg_to_rad(YAW), 0.0))
	var pos := target + b.z * DISTANCE
	if is_inside_tree():
		# Snap to whole render pixels in the camera's own plane.
		var texel := world_per_pixel()
		var local := b.inverse() * pos
		local.x = roundf(local.x / texel) * texel
		local.y = roundf(local.y / texel) * texel
		pos = b * local
	global_transform = Transform3D(b, pos)
