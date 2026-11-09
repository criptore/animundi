## Every game sprite packed into one texture, so that sprites of all kinds can be drawn in a single
## batch, in the right order (WorldBox loads its sprites into atlases the same way).
## Built once at start from assets/sprites/ (rows of sprites sorted by height, with padding so
## neighbours never bleed into each other, even in the smaller mipmaps).
extends RefCounted

const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")

const GROUPS := ["trees", "plants", "peoples", "races", "animals", "monsters"]
const WIDTH := 1024
const PAD := 4

var texture: ImageTexture
## Sprite id -> Rect2 of the sprite in the atlas, in UV (0..1).
var regions := {}
## Sprite id -> size in sprite pixels.
var sizes := {}
## Sprite id -> average colour of its opaque pixels (drawn as a dot when zoomed far out).
var colors := {}

static var _shared: RefCounted


## The atlas shared by every batch (built on first use).
static func shared() -> RefCounted:
	if _shared == null:
		_shared = load("res://scripts/render2d/sprite_atlas.gd").new()
	return _shared


func _init() -> void:
	var images := {}
	for group in GROUPS:
		for id in SpriteLibrary.list(group):
			var img := SpriteLibrary.texture(id).get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			images[id] = img
	var ids := images.keys()
	ids.sort_custom(func(a, b): return images[a].get_height() > images[b].get_height())

	# Shelf packing: fill rows left to right, tallest sprites first.
	var places := {}
	var x := PAD
	var y := PAD
	var row_h := 0
	for id in ids:
		var img: Image = images[id]
		if x + img.get_width() + PAD > WIDTH:
			x = PAD
			y += row_h + PAD * 2
			row_h = 0
		places[id] = Vector2i(x, y)
		x += img.get_width() + PAD * 2
		row_h = maxi(row_h, img.get_height())
	var height := 1 << int(ceil(log(float(y + row_h + PAD)) / log(2.0)))

	var atlas := Image.create(WIDTH, height, false, Image.FORMAT_RGBA8)
	for id in ids:
		var img: Image = images[id]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), places[id])
		sizes[id] = Vector2(img.get_size())
		colors[id] = _average(img)
		regions[id] = Rect2(Vector2(places[id]) / Vector2(WIDTH, height), Vector2(img.get_size()) / Vector2(WIDTH, height))
	atlas.generate_mipmaps()
	texture = ImageTexture.create_from_image(atlas)


func has(id: String) -> bool:
	return regions.has(id)


static func _average(img: Image) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				sum += c
				n += 1
	return Color(sum.r / n, sum.g / n, sum.b / n) if n > 0 else Color.BLACK
