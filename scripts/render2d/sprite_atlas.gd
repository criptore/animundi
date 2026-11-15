## Every game sprite packed into one texture, so that sprites of all kinds can be drawn in a single
## batch, in the right order (WorldBox loads its sprites into atlases the same way).
## Built once at start from assets/sprites/ (rows of sprites sorted by height, with padding so
## neighbours never bleed into each other, even in the smaller mipmaps).
extends RefCounted

const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")

const GROUPS := ["trees", "plants", "creatures", "buildings"]
const WIDTH := 1024
## Frames of the flame drawn over burning plants (made here, in pixel art: see fire_frame).
const FIRE_FRAMES := 3
## Frames of the whirlwind, the lairs of monsters (data/monsters.json) and the mark over the
## sick: made here too (tornado_frame, lair_image, sick_image).
const TORNADO_FRAMES := 3
const LAIRS := ["nest", "crypt", "pit", "cave", "pool", "cairn"]
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
	for k in TORNADO_FRAMES:
		images["effects/Tornado_%d" % k] = tornado_frame(k)
	for kind in LAIRS:
		images["effects/Lair_%s" % kind] = lair_image(kind)
	images["effects/Sick"] = sick_image()
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


## One frame of a whirlwind, 32x54: a grey funnel, wide at the top and thin at the ground, bent
## like a rope, with bands of darker wind that climb from frame to frame and dust at its foot.
static func tornado_frame(k: int) -> Image:
	var w := 32
	var h := 54
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4409 + k * 7717
	var rim := Color("#4a4c58")
	var dark := Color("#6c7080")
	var mid := Color("#8e93a2")
	var light := Color("#b9bdc9")
	for y in h:
		var t := float(y) / (h - 1)
		var half := lerpf(13.0, 2.0, pow(t, 0.75)) + sin(y * 0.55 + k * 2.1) * 0.9
		var cx := w / 2.0 + sin(t * 4.2 + k * 2.1) * 3.0 * t
		var x0 := int(round(cx - half))
		var x1 := int(round(cx + half))
		for x in range(maxi(0, x0), mini(w, x1 + 1)):
			var across := (x - cx) / maxf(half, 1.0)
			# Bands of wind wound around the funnel, climbing with the frames.
			var band := int(floor((y + across * 5.0 + k * 3.0) / 3.0)) % 3
			var c := mid
			if x == x0 or x == x1:
				c = rim
			elif band == 0:
				c = dark
			elif across < -0.25 and band == 1:
				c = light
			img.set_pixel(x, y, c)
	# Dust and splinters thrown around its foot.
	for n in 14:
		var dx := rng.randi_range(-12, 12)
		var dy := rng.randi_range(0, 9)
		var x := clampi(w / 2 + dx + int(sin(k * 2.1) * 3.0), 0, w - 1)
		img.set_pixel(x, h - 1 - dy, Color("#8a7a5c") if n % 3 else Color("#5c4a36"))
	return img


## The lair of a kind of monster, 28x24: a mound with a dark mouth (cave of rock, nest of webs,
## crypt of stone, cairn of piled stones), or a hollow in the ground (pit of fire, pool of slime).
static func lair_image(kind: String) -> Image:
	var w := 28
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var palettes := {
		"cave": [Color("#2e2b33"), Color("#5d5a66"), Color("#7e7b88"), Color("#a09dab")],
		"nest": [Color("#3a3640"), Color("#a9a6b4"), Color("#cfccd8"), Color("#f0eef5")],
		"crypt": [Color("#27222e"), Color("#57506a"), Color("#786f8c"), Color("#9c93b0")],
		"cairn": [Color("#33302c"), Color("#6b655c"), Color("#8f887c"), Color("#b3ac9f")],
		"pit": [Color("#2a1512"), Color("#5a2318"), Color("#b8421c"), Color("#ffb347")],
		"pool": [Color("#1d3a1c"), Color("#3f7a2e"), Color("#6fb83c"), Color("#c6ef7a")],
	}
	var p: Array = palettes.get(kind, palettes["cave"])
	var rim: Color = p[0]
	if kind == "pit" or kind == "pool":
		# A hollow: a flat ring on the ground with a bright heart.
		var cy := h - 7.0
		for y in h:
			for x in w:
				var dx := (x + 0.5 - w / 2.0) / (w / 2.0 - 1.0)
				var dy := (y + 0.5 - cy) / 6.0
				var d := dx * dx + dy * dy
				if d > 1.0:
					continue
				var c: Color = p[1]
				if d > 0.78:
					c = rim
				elif d < 0.22:
					c = p[3]
				elif d < 0.5:
					c = p[2]
				img.set_pixel(x, y, c)
		for n in 5:
			var bx := rng.randi_range(6, w - 7)
			var by := int(cy) + rng.randi_range(-3, 2)
			img.set_pixel(bx, by, p[3])
			if kind == "pit":
				img.set_pixel(bx, by - rng.randi_range(4, 9), p[2])
		return img
	# A mound: a hump with light from the upper left.
	var tops: Array[int] = []
	for x in w:
		var dx := absf(x + 0.5 - w / 2.0) / (w / 2.0)
		var hump := sqrt(maxf(0.0, 1.0 - dx * dx)) * (h - 3)
		if kind == "crypt":
			hump = (h - 4.0) if dx < 0.62 else ((h - 11.0) if dx < 0.9 else 0.0)
		elif kind == "cairn":
			hump = floor(hump / 5.0) * 5.0 + (2.0 if dx < 0.85 else 0.0)
		tops.append(int(hump))
	for x in w:
		var top: int = tops[x]
		for t in top:
			var y := h - 1 - t
			var edge: bool = t >= top - 1 or t == 0 or (x > 0 and t >= tops[x - 1]) or (x < w - 1 and t >= tops[x + 1])
			var c: Color = p[2]
			if edge:
				c = rim
			elif x < w * 0.42 and t > top * 0.45:
				c = p[3]
			elif x > w * 0.68 or t < top * 0.22:
				c = p[1]
			img.set_pixel(x, y, c)
	if kind == "cairn":
		# Joints between the piled stones.
		for y in range(h - 5, 4, -5):
			for x in w:
				if img.get_pixel(x, y).a > 0.5 and (x + y) % 7 != 0:
					img.set_pixel(x, y, rim)
	elif kind == "nest":
		# Strands of web across the dome.
		for n in 7:
			var sx := rng.randi_range(3, w - 4)
			for step in 9:
				var x := sx + (step if n % 2 == 0 else -step)
				var y := h - 3 - step * 2
				if x >= 0 and x < w and y >= 0 and img.get_pixel(x, y).a > 0.5:
					img.set_pixel(x, y, p[1])
	elif kind == "crypt":
		# A lintel over the door.
		for x in range(8, 20):
			img.set_pixel(x, h - 15, p[3])
			img.set_pixel(x, h - 16, rim)
	# The mouth: a dark arch at the foot.
	var mouth_w := 5.0 if kind != "cairn" else 3.0
	for y in range(h - 12, h):
		for x in w:
			var dx := (x + 0.5 - w / 2.0) / mouth_w
			var dy := (h - 0.5 - y) / 11.0
			if dx * dx + dy * dy < 1.0 and img.get_pixel(x, y).a > 0.5:
				img.set_pixel(x, y, Color("#0d0a12") if dx * dx + dy * dy < 0.6 else rim)
	if kind == "crypt" or kind == "cave":
		# Something watches from inside.
		img.set_pixel(w / 2 - 2, h - 6, Color("#e8d44a") if kind == "cave" else Color("#7ef0d0"))
		img.set_pixel(w / 2 + 1, h - 6, Color("#e8d44a") if kind == "cave" else Color("#7ef0d0"))
	return img


## The mark over a sick creature, 7x7: a sickly green drop with a dark rim.
static func sick_image() -> Image:
	var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	var rows := ["..#....", ".#o#...", ".#oo#..", "#oOo#..", "#oooo#.", "#oooo#.", ".####.."]
	for y in 7:
		for x in 7:
			var ch: String = rows[y][x]
			if ch == "#":
				img.set_pixel(x, y, Color("#22401c"))
			elif ch == "o":
				img.set_pixel(x, y, Color("#8fd43a"))
			elif ch == "O":
				img.set_pixel(x, y, Color("#e2ff9a"))
	return img
