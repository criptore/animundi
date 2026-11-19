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
## Vehicles of the ages beyond the cart and the boat (sim/Draw.cs VehicleSprite): wagon, steam
## train, motor car, hovercar; sailing ship, galleon, steamship, liner, hovership.
const LAND_VEHICLES := 4
const SEA_VEHICLES := 5
## Buildings of later ages (data/buildings.json "age") and the eras of great homes (Draw.cs HomeEra).
const ERA_BUILDINGS := ["university", "factory", "power_plant", "silo", "launch_pad"]
const HOME_ERAS := 4
const MUSHROOM_FRAMES := 3
## The colour mask: magenta shades painted in the owner's colour by the sprite shader.
const MASK := Color(0.816, 0.0, 0.816)
const MASK_DARK := Color(0.58, 0.0, 0.58)
const INK := Color("#1b1418")

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
	# The ages (sim/Ages.cs): vehicles, buildings and homes of later ages, the bomb and rockets.
	for k in range(1, LAND_VEHICLES + 1):
		images["effects/Vehicle_land_%d" % k] = land_vehicle(k)
	for k in range(1, SEA_VEHICLES + 1):
		images["effects/Vehicle_sea_%d" % k] = sea_vehicle(k)
	for id in ERA_BUILDINGS:
		images["effects/Era_%s" % id] = era_building(id)
	for era in HOME_ERAS:
		for tier in 2:
			for variant in 2:
				images["effects/Home_%d_%d_%d" % [era, tier, variant]] = era_home(era, tier, variant)
	for k in MUSHROOM_FRAMES:
		images["effects/Mushroom_%d" % k] = mushroom_frame(k)
	for k in 2:
		images["effects/Rocket_%d" % k] = rocket_frame(k)
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


# ---------------------------------------------------------------- the ages (sim/Ages.cs)

## Fills a rectangle (inclusive corners) clipped to the image.
static func _fill(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(maxi(0, y0), mini(img.get_height(), y1 + 1)):
		for x in range(maxi(0, x0), mini(img.get_width(), x1 + 1)):
			img.set_pixel(x, y, c)


static func _dot(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


## A filled ellipse inside the box (inclusive).
static func _oval(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var cx := (x0 + x1) / 2.0
	var cy := (y0 + y1) / 2.0
	var rx := (x1 - x0) / 2.0 + 0.5
	var ry := (y1 - y0) / 2.0 + 0.5
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := (x + 0.5 - cx - 0.5) / rx
			var dy := (y + 0.5 - cy - 0.5) / ry
			if dx * dx + dy * dy <= 1.0:
				_dot(img, x, y, c)


## Rings the shapes in ink, the way every sprite of the game is outlined, and shades their
## lowest row.
static func _outline(img: Image) -> Image:
	var src := img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and src.get_pixel(n.x, n.y).a > 0.5 and src.get_pixel(n.x, n.y) != INK:
					img.set_pixel(x, y, INK)
					break
	return img


## A vehicle of trade on land, by step of the ages: 1 a covered wagon, 2 a steam train, 3 a motor
## car, 4 a hovercar. The owner's colour paints the canvas, the coach and the body.
static func land_vehicle(k: int) -> Image:
	var wood := Color("#8a5a32")
	var dark := Color("#4a3426")
	var wheel := Color("#2e2a30")
	var steel := Color("#7c8494")
	var glass := Color("#9fd6f0")
	var img: Image
	match k:
		1:
			img = Image.create(13, 10, false, Image.FORMAT_RGBA8)
			_oval(img, 2, 1, 10, 7, Color("#efe2c2"))
			_fill(img, 1, 5, 11, 6, MASK)
			_fill(img, 1, 7, 11, 7, wood)
			_fill(img, 3, 3, 9, 4, Color("#d9c9a4"))
			_dot(img, 3, 8, wheel); _dot(img, 9, 8, wheel); _dot(img, 2, 8, dark); _dot(img, 10, 8, dark)
		2:
			img = Image.create(21, 12, false, Image.FORMAT_RGBA8)
			# The engine: a black boiler, a chimney with a puff of steam, the cab in front.
			_fill(img, 1, 5, 9, 8, Color("#34323a"))
			_fill(img, 2, 2, 3, 4, Color("#34323a"))
			_oval(img, 0, 0, 3, 2, Color("#d8d8de"))
			_fill(img, 7, 3, 9, 4, MASK)
			_dot(img, 8, 4, Color("#ffe27a"))
			_dot(img, 1, 7, Color("#e8483c"))
			# The coach, in the owner's colour, with windows.
			_fill(img, 11, 4, 19, 8, MASK)
			_fill(img, 11, 4, 19, 4, MASK_DARK)
			for x in [12, 15, 18]:
				_dot(img, x, 6, Color("#ffe9a8"))
			for x in [2, 6, 12, 17]:
				_dot(img, x, 9, wheel)
				_dot(img, x + 1, 9, wheel)
			_fill(img, 0, 10, 20, 10, steel)
		3:
			img = Image.create(13, 9, false, Image.FORMAT_RGBA8)
			_fill(img, 1, 4, 11, 6, MASK)
			_fill(img, 3, 2, 8, 3, MASK_DARK)
			_fill(img, 4, 2, 5, 3, glass)
			_fill(img, 7, 2, 8, 3, glass)
			_dot(img, 11, 5, Color("#ffe27a"))
			_dot(img, 1, 5, Color("#e8483c"))
			for x in [3, 9]:
				_fill(img, x, 7, x + 1, 7, wheel)
		_:
			img = Image.create(13, 10, false, Image.FORMAT_RGBA8)
			_oval(img, 1, 2, 11, 6, MASK)
			_oval(img, 3, 1, 8, 4, glass)
			_fill(img, 2, 5, 10, 5, MASK_DARK)
			# It floats on a cyan glow.
			_fill(img, 3, 8, 9, 8, Color("#7ef0e8"))
			_dot(img, 6, 9, Color("#c9fff9"))
	return _outline(img)


## A trade boat by step of the ages: 1 a sailing ship, 2 a galleon, 3 a steamship, 4 a liner,
## 5 a hovership. Sails and hulls carry the owner's colour.
static func sea_vehicle(k: int) -> Image:
	var hull := Color("#7a4a2a")
	var mast := Color("#5a3a24")
	var sail := Color("#f0e6cc")
	var steel := Color("#5f6878")
	var white := Color("#e8ecf2")
	var img: Image
	match k:
		1:
			img = Image.create(14, 14, false, Image.FORMAT_RGBA8)
			_fill(img, 6, 1, 6, 10, mast)
			_fill(img, 3, 2, 9, 7, MASK)
			_fill(img, 3, 2, 9, 2, MASK_DARK)
			_fill(img, 1, 9, 12, 11, hull)
			_fill(img, 2, 12, 11, 12, hull.darkened(0.3))
		2:
			img = Image.create(17, 17, false, Image.FORMAT_RGBA8)
			for mx in [5, 11]:
				_fill(img, mx, 1, mx, 12, mast)
			_fill(img, 2, 2, 8, 6, sail)
			_fill(img, 8, 3, 14, 8, sail)
			_fill(img, 3, 7, 7, 9, sail)
			_fill(img, 4, 0, 6, 1, MASK)
			_fill(img, 10, 0, 12, 1, MASK)
			_fill(img, 1, 11, 15, 14, hull)
			_fill(img, 12, 9, 15, 11, hull)
			_fill(img, 1, 12, 15, 12, MASK_DARK)
		3:
			img = Image.create(18, 12, false, Image.FORMAT_RGBA8)
			_fill(img, 1, 7, 16, 10, Color("#2c2a32"))
			_fill(img, 2, 10, 15, 10, Color("#a43a2e"))
			_fill(img, 4, 4, 12, 6, white)
			_fill(img, 7, 1, 8, 4, MASK)
			_fill(img, 7, 1, 8, 1, Color("#2c2a32"))
			_oval(img, 3, 0, 6, 2, Color("#c8c8d0"))
			for x in [5, 8, 11]:
				_dot(img, x, 5, Color("#4a6a8a"))
		4:
			img = Image.create(19, 12, false, Image.FORMAT_RGBA8)
			_fill(img, 0, 7, 18, 10, white)
			_fill(img, 1, 10, 17, 10, steel)
			_fill(img, 3, 4, 14, 6, white)
			_fill(img, 5, 2, 11, 3, white)
			_fill(img, 12, 1, 13, 3, MASK)
			_fill(img, 0, 8, 18, 8, MASK)
			for x in range(4, 15, 2):
				_dot(img, x, 5, Color("#4a6a8a"))
		_:
			img = Image.create(16, 11, false, Image.FORMAT_RGBA8)
			_oval(img, 1, 3, 14, 7, MASK)
			_oval(img, 4, 1, 10, 4, Color("#9fd6f0"))
			_fill(img, 2, 6, 13, 6, MASK_DARK)
			_fill(img, 3, 9, 12, 9, Color("#7ef0e8"))
	return _outline(img)


## Buildings of later ages: the university (a dome over columns), the factory (sawtooth roofs, a
## smoking chimney), the power plant (a cooling tower), the missile silo (a hatch in a fenced
## yard), the launch pad (a gantry and a rocket). Roofs and flags carry the owner's colour.
static func era_building(id: String) -> Image:
	var stone := Color("#c9c1b1")
	var stone_dark := Color("#8e8676")
	var brick := Color("#a4523a")
	var brick_dark := Color("#6e3426")
	var concrete := Color("#a7a9ae")
	var concrete_dark := Color("#74777e")
	var window := Color("#ffe9a8")
	var smoke := Color("#8c8a90")
	var img: Image
	match id:
		"university":
			img = Image.create(26, 26, false, Image.FORMAT_RGBA8)
			_fill(img, 2, 12, 23, 23, stone)
			_fill(img, 1, 10, 24, 11, MASK)
			_oval(img, 7, 2, 18, 12, MASK)
			_fill(img, 12, 0, 13, 2, Color("#e8c24a"))
			for x in range(4, 23, 4):
				_fill(img, x, 13, x + 1, 22, Color("#ece6d8"))
			_fill(img, 11, 17, 14, 23, stone_dark)
			_fill(img, 1, 24, 24, 24, stone_dark)
		"factory":
			img = Image.create(26, 24, false, Image.FORMAT_RGBA8)
			_fill(img, 1, 11, 24, 22, brick)
			for x in range(1, 24, 6):
				for t in 5:
					_fill(img, x + t, 11 - t, x + t, 11, MASK if t < 4 else MASK_DARK)
			_fill(img, 19, 1, 21, 10, brick_dark)
			_oval(img, 16, 0, 21, 3, smoke)
			for x in range(3, 22, 4):
				_fill(img, x, 15, x + 1, 17, window)
			_fill(img, 10, 18, 13, 22, brick_dark)
		"power_plant":
			img = Image.create(26, 26, false, Image.FORMAT_RGBA8)
			# The cooling tower: waisted, steaming.
			for y in range(5, 24):
				var t := (y - 5) / 18.0
				var half := int(round(6.0 - 2.4 * sin(t * PI) + 1.2 * t))
				_fill(img, 9 - half, y, 9 + half, y, concrete if y % 5 else concrete_dark)
			_oval(img, 3, 0, 14, 5, Color("#e4e6ea"))
			_fill(img, 15, 13, 24, 23, concrete)
			_fill(img, 15, 11, 24, 12, MASK)
			_fill(img, 21, 6, 22, 10, concrete_dark)
			for x in [17, 20, 23]:
				_dot(img, x, 16, window)
		"silo":
			img = Image.create(16, 14, false, Image.FORMAT_RGBA8)
			_fill(img, 1, 6, 14, 12, Color("#7c8a5a"))
			_oval(img, 4, 7, 11, 11, concrete)
			_oval(img, 6, 8, 9, 10, Color("#2e2a30"))
			_fill(img, 7, 9, 8, 9, Color("#e8c24a"))
			for x in range(1, 15, 3):
				_fill(img, x, 3, x, 6, concrete_dark)
			_fill(img, 1, 4, 14, 4, concrete_dark)
			_fill(img, 13, 0, 13, 4, concrete_dark)
			_fill(img, 11, 0, 12, 1, MASK)
		_:
			img = Image.create(18, 32, false, Image.FORMAT_RGBA8)
			_fill(img, 1, 28, 16, 30, concrete)
			# The gantry.
			for y in range(4, 28):
				_dot(img, 3, y, Color("#c8463a"))
				if y % 3 == 0:
					_fill(img, 3, y, 6, y, Color("#c8463a"))
			# The rocket waiting on it.
			_fill(img, 9, 6, 12, 27, Color("#ecedf0"))
			_fill(img, 10, 2, 11, 5, Color("#ecedf0"))
			_fill(img, 9, 12, 12, 13, MASK)
			_fill(img, 8, 24, 8, 27, MASK_DARK)
			_fill(img, 13, 24, 13, 27, MASK_DARK)
			_dot(img, 10, 1, Color("#c8463a"))
	return _outline(img)


## The great homes of later ages, by era: 0 a row of brick houses, 1 an apartment block, 2 a glass
## tower, 3 an arcology of domes and gardens. tier 0 for a stone house, 1 for a big house;
## variant changes the windows. Roofs and bands carry the owner's colour.
static func era_home(era: int, tier: int, variant: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = era * 1009 + tier * 101 + variant * 7 + 3
	var lit := Color("#ffe9a8")
	var dim := Color("#4a5468")
	var w: int
	var h: int
	var img: Image
	match era:
		0:
			w = 18 if tier == 0 else 24
			h = 15 if tier == 0 else 19
			img = Image.create(w, h, false, Image.FORMAT_RGBA8)
			var wall := Color("#a4523a") if variant == 0 else Color("#8c4a3a")
			_fill(img, 1, 5, w - 2, h - 2, wall)
			var houses := 2 if tier == 0 else 3
			var each := (w - 2) / houses
			for k in houses:
				var x0 := 1 + k * each
				for t in 4:
					_fill(img, x0 + t, 4 - t, x0 + each - 1 - t, 4 - t, MASK if t else MASK_DARK)
				_fill(img, x0 + each - 3, 0, x0 + each - 2, 2, Color("#5a3428"))
				_fill(img, x0 + 2, h - 6, x0 + 3, h - 2, Color("#4a2a20"))
				_dot(img, x0 + each - 3, h - 6, lit if rng.randf() < 0.7 else dim)
				_dot(img, x0 + 2, 7, lit if rng.randf() < 0.6 else dim)
				_dot(img, x0 + each - 3, 7, lit if rng.randf() < 0.6 else dim)
		1:
			w = 16 if tier == 0 else 22
			h = 19 if tier == 0 else 26
			img = Image.create(w, h, false, Image.FORMAT_RGBA8)
			var wall := Color("#b8b4aa") if variant == 0 else Color("#c4a98a")
			_fill(img, 1, 2, w - 2, h - 2, wall)
			_fill(img, 1, 1, w - 2, 2, MASK)
			for y in range(4, h - 4, 3):
				for x in range(3, w - 3, 3):
					_fill(img, x, y, x + 1, y, lit if rng.randf() < 0.55 else dim)
			_fill(img, w / 2 - 1, h - 4, w / 2, h - 2, Color("#3a3640"))
		2:
			w = 14 if tier == 0 else 18
			h = 26 if tier == 0 else 34
			img = Image.create(w, h, false, Image.FORMAT_RGBA8)
			var glass := Color("#6fa8cc") if variant == 0 else Color("#7fb8b8")
			_fill(img, 2, 3, w - 3, h - 2, glass)
			_fill(img, 2, 3, 3, h - 2, glass.lightened(0.35))
			for y in range(5, h - 2, 4):
				_fill(img, 2, y, w - 3, y, MASK if y % 8 == 1 else glass.darkened(0.25))
			for n in 10:
				_dot(img, rng.randi_range(4, w - 4), rng.randi_range(5, h - 3), lit)
			_fill(img, w / 2, 0, w / 2, 2, Color("#c8ccd4"))
		_:
			w = 20 if tier == 0 else 26
			h = 24 if tier == 0 else 32
			img = Image.create(w, h, false, Image.FORMAT_RGBA8)
			var shell := Color("#e8ecf2")
			_fill(img, 2, h / 2, w - 3, h - 2, shell)
			_oval(img, 1, h / 3, w - 2, h - 2, shell)
			_oval(img, w / 4, 1, w - w / 4 - 1, h / 2 + 2, Color("#a8e0f0") if variant == 0 else Color("#c0e8d8"))
			_fill(img, 2, h - 5, w - 3, h - 5, MASK)
			for n in 8:
				_dot(img, rng.randi_range(w / 4 + 2, w - w / 4 - 3), rng.randi_range(4, h / 2), Color("#5fb85a"))
			for x in range(4, w - 4, 3):
				_dot(img, x, h - 8, lit if rng.randf() < 0.7 else dim)
	return _outline(img)


## A mushroom cloud, 46x58: frame 0 the fireball rising, 1 the full cloud, 2 the cloud fading
## into grey ash.
static func mushroom_frame(k: int) -> Image:
	var w := 46
	var h := 58
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 911 + k * 31
	var core: Color = [Color("#fff4b0"), Color("#ffd04a"), Color("#c8c4bc")][k]
	var body: Color = [Color("#ff9a3a"), Color("#d8643a"), Color("#8e8a88")][k]
	var rim: Color = [Color("#c8402a"), Color("#7a3a2e"), Color("#5c5a5e")][k]
	# The stem.
	for y in range(20, h):
		var half := 3 + int((y - 20) / 9.0) + (2 if y > h - 6 else 0)
		_fill(img, w / 2 - half, y, w / 2 + half, y, body if y % 4 else rim)
		_fill(img, w / 2 - 1, y, w / 2 + 1, y, core)
	# The cap, a ring of puffs around a bright heart.
	_oval(img, 4, 2, w - 5, 24, rim)
	_oval(img, 6, 3, w - 7, 22, body)
	for n in 14:
		var px := rng.randi_range(8, w - 9)
		var py := rng.randi_range(5, 18)
		_oval(img, px - 3, py - 2, px + 3, py + 2, body.lightened(0.15) if n % 3 else rim)
	_oval(img, 15, 8, w - 16, 18, core)
	# A skirt of dust at the foot.
	_oval(img, 6, h - 7, w - 7, h - 1, rim)
	_oval(img, 9, h - 6, w - 10, h - 2, body)
	return img


## A rocket rising on its flame, 7x22; the two frames flicker the flame.
static func rocket_frame(k: int) -> Image:
	var img := Image.create(7, 22, false, Image.FORMAT_RGBA8)
	_fill(img, 2, 2, 4, 13, Color("#ecedf0"))
	_dot(img, 3, 1, Color("#ecedf0"))
	_dot(img, 3, 0, Color("#c8463a"))
	_fill(img, 2, 6, 4, 7, MASK)
	_fill(img, 1, 11, 1, 14, MASK_DARK)
	_fill(img, 5, 11, 5, 14, MASK_DARK)
	var flame := 6 if k == 0 else 8
	for y in range(14, 14 + flame):
		var half := 1 if y < 14 + flame - 2 else 0
		_fill(img, 3 - half, y, 3 + half, y, Color("#ffd04a") if y < 17 else Color("#f0621e"))
	_dot(img, 3, 15, Color("#fff4b0"))
	return _outline(img)
