## Draws many sprites in a few draw calls: every sprite of the atlas goes into the same MultiMesh,
## sorted by the height of its feet on screen so that nearer sprites (lower on the screen) cover
## those behind them. The map is cut into horizontal strips, one MultiMesh each, drawn top to
## bottom: the order holds across strips, and strips out of view are culled. Each sprite also gets
## a small drawn shadow, in a layer under all the sprites (no real-time lighting, as in WorldBox).
## Tall sprites sway in the wind, and far away every sprite becomes a dot of its average colour
## (shaders/sprite_batch.gdshader).
##
## Positions are in world pixels (a tile is WorldMap.TILE world pixels), at the sprite's feet.
extends Node2D

const SpriteAtlas = preload("res://scripts/render2d/sprite_atlas.gd")
const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")
const BatchShader = preload("res://shaders/sprite_batch.gdshader")

## World pixels per tile (same as WorldMap.TILE).
const TILE := 8
## Height of a strip in world pixels.
const STRIP := 16 * TILE
## Shadow size relative to the sprite's width, and its shift to the right (light from the left).
const SHADOW_WIDTH := 0.75
const SHADOW_HEIGHT := 0.28
const SHADOW_SHIFT := 0.08
const SHADOW_ALPHA := 0.32
## Shadows are hidden below this zoom (screen pixels per world pixel), where sprites turn to dots.
const SHADOWS_MIN_ZOOM := 0.6

var atlas: SpriteAtlas = SpriteAtlas.shared()
## Number of sprites drawn.
var count := 0

var _shadows := Node2D.new()
var _sprites := Node2D.new()
var _sprite_material := ShaderMaterial.new()
var _shadow_material := ShaderMaterial.new()
static var _quad: ArrayMesh
static var _shadow_texture: ImageTexture


func _init() -> void:
	_sprite_material.shader = BatchShader
	_shadow_material.shader = BatchShader
	_shadow_material.set_shader_parameter("from_atlas", false)
	add_child(_shadows)
	add_child(_sprites)


## Replaces every sprite. `ids[k]` is drawn at `positions[k]` (feet, world pixels), mirrored when
## `flips[k]` is 1, resized by `scales[k]`. Unknown sprite ids are skipped.
func set_sprites(ids: PackedStringArray, positions: PackedVector2Array, flips: PackedByteArray,
		scales: PackedFloat32Array) -> void:
	for layer in [_shadows, _sprites]:
		for child in layer.get_children():
			child.queue_free()
	# Sort by feet height, then by x so that the order never depends on input order.
	var order := []
	for k in ids.size():
		if atlas.has(ids[k]):
			order.append(k)
	order.sort_custom(func(a, b):
		return positions[a].y < positions[b].y or positions[a].y == positions[b].y and positions[a].x < positions[b].x)
	count = order.size()

	var start := 0
	while start < order.size():
		var strip := floori(positions[order[start]].y / STRIP)
		var end := start
		while end < order.size() and floori(positions[order[end]].y / STRIP) == strip:
			end += 1
		_add_strip(order.slice(start, end), ids, positions, flips, scales)
		start = end


## Follows the camera zoom (screen pixels per world pixel): far away, sprites turn into dots and
## shadows are hidden.
func set_zoom(zoom: float) -> void:
	_sprite_material.set_shader_parameter("zoom", zoom)
	_shadows.visible = zoom >= SHADOWS_MIN_ZOOM


## Wind strength: how far the top of a tall sprite sways, in world pixels (0 = still).
func set_wind(amount: float) -> void:
	_sprite_material.set_shader_parameter("wind", amount)


## Size of a sprite in world pixels.
static func world_size(id: String) -> Vector2:
	return SpriteLibrary.world_size(id) * TILE


func _add_strip(order: Array, ids: PackedStringArray, positions: PackedVector2Array,
		flips: PackedByteArray, scales: PackedFloat32Array) -> void:
	var sprites := _multimesh(order.size(), true)
	var shadows := _multimesh(order.size(), false)
	for n in order.size():
		var k: int = order[n]
		var size := world_size(ids[k]) * scales[k]
		var sx := -size.x if flips[k] else size.x
		sprites.set_instance_transform_2d(n, Transform2D(0.0, Vector2(sx, size.y), 0.0, positions[k]))
		var r: Rect2 = atlas.regions[ids[k]]
		sprites.set_instance_custom_data(n, Color(r.position.x, r.position.y, r.size.x, r.size.y))
		# Colour: the average colour (for the far-away dot) and the height in world pixels / 256.
		var avg: Color = atlas.colors[ids[k]]
		sprites.set_instance_color(n, Color(avg.r, avg.g, avg.b, size.y / 256.0))
		var shadow := Vector2(size.x * SHADOW_WIDTH, size.x * SHADOW_HEIGHT)
		shadows.set_instance_transform_2d(n, Transform2D(0.0, shadow, 0.0,
				positions[k] + Vector2(size.x * SHADOW_SHIFT, shadow.y * 0.45)))
	_add_instance(_shadows, shadows, _shadow_texture_get(), _shadow_material)
	_add_instance(_sprites, sprites, atlas.texture, _sprite_material)


func _add_instance(layer: Node2D, mm: MultiMesh, tex: Texture2D, mat: ShaderMaterial) -> void:
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = tex
	mmi.material = mat
	mmi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	layer.add_child(mmi)


static func _multimesh(n: int, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = custom
	mm.use_colors = custom
	mm.mesh = _unit_quad()
	mm.instance_count = n
	return mm


## A quad one unit wide and tall, with its bottom centre (the feet) at the origin.
static func _unit_quad() -> ArrayMesh:
	if _quad == null:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -1), Vector2(0.5, -1), Vector2(0.5, 0), Vector2(-0.5, 0)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		_quad = ArrayMesh.new()
		_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _quad


## A small pixel-art ellipse, black and see-through, stretched under each sprite.
static func _shadow_texture_get() -> ImageTexture:
	if _shadow_texture == null:
		var w := 16
		var h := 6
		var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var d := Vector2((x + 0.5 - w / 2.0) / (w / 2.0), (y + 0.5 - h / 2.0) / (h / 2.0))
				if d.length_squared() <= 1.0:
					img.set_pixel(x, y, Color(0.05, 0.08, 0.15, SHADOW_ALPHA))
		img.generate_mipmaps()
		_shadow_texture = ImageTexture.create_from_image(img)
	return _shadow_texture
