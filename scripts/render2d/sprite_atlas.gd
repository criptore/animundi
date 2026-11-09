## Every game sprite packed into one texture, so that sprites of all kinds can be drawn in a single
## batch, in the right order (WorldBox loads its sprites into atlases the same way).
## Built once at start from assets/sprites/ (rows of sprites sorted by height, with padding so
## neighbours never bleed into each other, even in the smaller mipmaps).
extends RefCounted

const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")

const GROUPS := ["trees", "plants", "peoples", "races", "animals", "monsters"]
const WIDTH := 1024
## Frames of the flame drawn over burning plants (made here, in pixel art: see fire_frame).
const FIRE_FRAMES := 3
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
	for k in FIRE_FRAMES:
		images["effects/Fire_%d" % k] = fire_frame(k)
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


## One frame of a small pixel-art flame, 12x16: tongues of fire of uneven heights, highest in
## the middle, with a dark red rim, an orange body and a yellow heart low in the middle. Each frame
## draws different tongues, so cycling through them flickers.
static func fire_frame(k: int) -> Image:
	var w := 12
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + k * 104729
	var rim := Color("#9a2410")
	var body := Color("#f0621e")
	var heart := Color("#ffd84a")
	# Height of each column: a hump, cut into ragged tongues.
	var tops: Array[int] = []
	for x in w:
		var dx := absf(x + 0.5 - w / 2.0) / (w / 2.0)
		var hump := (1.0 - dx * dx) * h
		tops.append(int(hump * rng.randf_range(0.45, 1.0)))
	for x in w:
		var top: int = tops[x]
		for t in top:
			var y := h - 1 - t
			var c := body
			var edge: bool = t >= top - 1 or (x > 0 and t >= tops[x - 1]) or (x < w - 1 and t >= tops[x + 1])
			if edge:
				c = rim
			elif t < top * 0.55 and absf(x + 0.5 - w / 2.0) < 3.0:
				c = heart
			img.set_pixel(x, y, c)
	return img
