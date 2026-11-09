## A kingdom's banner, generated from its record (sim/Kingdoms.cs): the kingdom's colour, a second
## colour, a division of the field and a symbol, on a small pixel-art flag with a swallowtail.
extends RefCounted

const W := 10
const H := 13

## 3×3 symbols, row by row ("#" = drawn): sun, tower, star, crown, tree, wave, eye, axe.
const SYMBOLS := [
	[".#.", "###", ".#."],
	["#.#", "###", "###"],
	["#.#", ".#.", "#.#"],
	["#.#", "###", "###"],
	[".#.", "###", ".#."],
	["#..", ".#.", "..#"],
	["###", "#.#", "###"],
	["##.", "###", ".#."],
]


static func image(colour: Color, second: Color, division: int, symbol: int) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var dark := colour.darkened(0.55)
	for y in H:
		for x in W:
			# Swallowtail: the bottom two rows are cut in the middle.
			if y >= H - 2 and abs(x - (W - 1) / 2.0) < (y - (H - 3)) * 1.5:
				continue
			var c := colour
			var u := x - 1
			var v := y - 1
			match division:
				1:
					c = second if u >= (W - 2) / 2 else colour
				2:
					c = second if v >= (H - 4) / 2 else colour
				3:
					c = second if u > v - 1 else colour
				4:
					c = second if v > absi(u - (W - 2) / 2) + 2 else colour
				5:
					c = second if u == (W - 2) / 2 or v == (H - 4) / 2 else colour
			var edge := x == 0 or x == W - 1 or y == 0 or (y >= H - 3 and img.get_pixel(x, y - 1).a == 0.0)
			img.set_pixel(x, y, dark if edge else c)
	# The symbol in the middle, in whichever colour stands out.
	var glyph: Array = SYMBOLS[symbol % SYMBOLS.size()]
	var ink := Color(0.98, 0.95, 0.85) if colour.get_luminance() < 0.55 else Color(0.12, 0.1, 0.1)
	for gy in 3:
		for gx in 3:
			if glyph[gy][gx] == "#":
				img.set_pixel(3 + gx, 4 + gy, ink)
	return img


static func texture(colour: Color, second: Color, division: int, symbol: int) -> ImageTexture:
	var img := image(colour, second, division, symbol)
	img.resize(W * 2, H * 2, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)
