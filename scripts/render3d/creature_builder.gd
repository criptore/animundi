## Builds the 3D models of people, animals and monsters in the chunky 3D-pixel-art style
## (docs/ART_DIRECTION.md): a few coloured blocks and blobs that read well at a few pixels tall.
## Colours are vertex colours (UV.x = 0, drawn by shaders/foliage.gdshader with `leafy` off).
## Models face the camera (+Z) for people and look right (+X) for animals. About 1 unit tall.
extends RefCounted

const Races = preload("res://scripts/world/races.gd")

const EYE := Color("#22222a")
const WHITE := Color("#f4f0e6")
const STEEL := Color("#b8bcc6")
const GOLD := Color("#e8b030")
const WOOD := Color("#7a5230")


# ------------------------------------------------------------------------------ people

static func person(race: String, role: String) -> ArrayMesh:
	var r: Dictionary = Races.RACES[race]
	var tr: Array = r["traits"]
	var skin := Color(r["skin"])
	var hair := Color(r["hair"])
	var clothes := Color(r["clothes"])
	var legs := Color(r["legs"])
	var banner := Color(r["banner"])
	var magic := Color(r["magic"])
	var st := _begin()
	var short := tr.has("short")
	var leg_h := 0.2 if short else 0.3
	var body_y := leg_h + 0.16
	var head_y := body_y + 0.3
	var robe := role == "Shaman"

	# Legs (hidden under a robe), body, arms with hands.
	if not robe:
		_box(st, Vector3(0.11, leg_h, 0.12), Vector3(-0.08, leg_h / 2.0, 0), legs)
		_box(st, Vector3(0.11, leg_h, 0.12), Vector3(0.08, leg_h / 2.0, 0), legs)
	else:
		_box(st, Vector3(0.36, leg_h + 0.05, 0.24), Vector3(0, (leg_h + 0.05) / 2.0, 0), clothes.darkened(0.1))
	var body_w := 0.4 if short else 0.34
	_box(st, Vector3(body_w, 0.32, 0.2), Vector3(0, body_y, 0), clothes)
	for side in [-1.0, 1.0]:
		_box(st, Vector3(0.09, 0.26, 0.1), Vector3(side * (body_w / 2.0 + 0.05), body_y + 0.01, 0), clothes.darkened(0.08))
		_box(st, Vector3(0.08, 0.07, 0.09), Vector3(side * (body_w / 2.0 + 0.05), body_y - 0.15, 0), skin)

	# Head and face.
	_box(st, Vector3(0.3, 0.27, 0.26), Vector3(0, head_y, 0), skin)
	var eye := EYE
	var eye_size := Vector3(0.045, 0.05, 0.02)
	if tr.has("sockets"):
		eye_size = Vector3(0.07, 0.07, 0.02)
	for side in [-1.0, 1.0]:
		_box(st, eye_size, Vector3(side * 0.065, head_y + 0.01, 0.131), eye)

	# Hair or headwear.
	var top_y := head_y + 0.15
	match role:
		"Warrior":
			_box(st, Vector3(0.33, 0.12, 0.29), Vector3(0, top_y - 0.02, 0), STEEL)
			_box(st, Vector3(0.04, 0.1, 0.04), Vector3(0, top_y + 0.08, 0), banner)
		"Chief":
			_box(st, Vector3(0.31, 0.06, 0.27), Vector3(0, top_y, 0), hair)
			_box(st, Vector3(0.32, 0.07, 0.28), Vector3(0, top_y + 0.05, 0), GOLD)
			for x in [-0.12, 0.0, 0.12]:
				_box(st, Vector3(0.05, 0.07, 0.05), Vector3(x, top_y + 0.11, 0.12), GOLD)
		"Shaman":
			_box(st, Vector3(0.34, 0.14, 0.3), Vector3(0, top_y - 0.01, -0.01), magic.darkened(0.35))
			_box(st, Vector3(0.18, 0.1, 0.18), Vector3(0, top_y + 0.1, -0.03), magic.darkened(0.35))
		_:
			if not tr.has("foliage") and not tr.has("crest"):
				_box(st, Vector3(0.32, 0.08, 0.28), Vector3(0, top_y, 0), hair)
				_box(st, Vector3(0.32, 0.18, 0.06), Vector3(0, head_y + 0.04, -0.12), hair)

	# Race traits.
	if tr.has("ears"):
		for side in [-1.0, 1.0]:
			_box(st, Vector3(0.12, 0.05, 0.05), Vector3(side * 0.19, head_y + 0.04, 0), skin, Basis(Vector3.BACK, side * 0.5))
	if tr.has("big_ears"):
		for side in [-1.0, 1.0]:
			_box(st, Vector3(0.18, 0.09, 0.04), Vector3(side * 0.23, head_y + 0.03, 0), skin, Basis(Vector3.BACK, side * 0.25))
	if tr.has("cat_ears") and role != "Warrior" and role != "Shaman":
		for side in [-1.0, 1.0]:
			_box(st, Vector3(0.08, 0.1, 0.06), Vector3(side * 0.1, top_y + 0.08, 0), hair, Basis(Vector3.BACK, side * 0.3))
	if tr.has("round_ears"):
		for side in [-1.0, 1.0]:
			_box(st, Vector3(0.1, 0.1, 0.04), Vector3(side * 0.16, top_y + 0.04, 0), Color("#f49ac1"))
	if tr.has("tusks"):
		for side in [-1.0, 1.0]:
			_box(st, Vector3(0.03, 0.06, 0.03), Vector3(side * 0.06, head_y - 0.1, 0.13), WHITE)
	if tr.has("beard"):
		_box(st, Vector3(0.28, 0.2, 0.06), Vector3(0, head_y - 0.12, 0.13), hair)
		_box(st, Vector3(0.18, 0.12, 0.05), Vector3(0, head_y - 0.26, 0.12), hair)
	if tr.has("crest") and role == "Villager":
		_box(st, Vector3(0.06, 0.12, 0.24), Vector3(0, top_y + 0.02, 0), hair)
	if tr.has("tail"):
		_box(st, Vector3(0.06, 0.06, 0.3), Vector3(0.08, leg_h + 0.02, -0.2), Color(r["skin"]), Basis(Vector3.RIGHT, 0.6))
	if tr.has("fins"):
		for side in [-1.0, 1.0]:
			_box(st, Vector3(0.04, 0.14, 0.12), Vector3(side * 0.17, head_y + 0.03, -0.02), hair)
	if tr.has("foliage"):
		_blob(st, 0.22, Vector3(0, top_y + 0.06, -0.02), hair)
		_blob(st, 0.13, Vector3(0.15, top_y + 0.0, 0.02), hair.lightened(0.1))
	if tr.has("wings"):
		for side in [-1.0, 1.0]:
			_box(st, Vector3(0.24, 0.3, 0.02), Vector3(side * 0.2, body_y + 0.12, -0.14), Color(0.8, 0.94, 1.0), Basis(Vector3.UP, side * 0.5))
	if tr.has("horns"):
		for side in [-1.0, 1.0]:
			_box(st, Vector3(0.06, 0.16, 0.06), Vector3(side * 0.17, top_y + 0.06, 0), WHITE, Basis(Vector3.BACK, side * 0.7))

	# Role gear.
	var hand_y := body_y - 0.15
	var right_x := body_w / 2.0 + 0.05
	match role:
		"Warrior":
			_box(st, Vector3(0.04, 0.42, 0.04), Vector3(right_x, hand_y + 0.24, 0.06), STEEL)
			_box(st, Vector3(0.14, 0.03, 0.05), Vector3(right_x, hand_y + 0.04, 0.06), GOLD)
			_box(st, Vector3(0.05, 0.26, 0.26), Vector3(-right_x - 0.04, body_y, 0.04), banner)
			_box(st, Vector3(0.055, 0.08, 0.08), Vector3(-right_x - 0.045, body_y, 0.04), GOLD)
		"Chief":
			_box(st, Vector3(body_w + 0.1, 0.42, 0.04), Vector3(0, body_y - 0.05, -0.13), banner)
		"Shaman":
			_box(st, Vector3(0.04, 0.85, 0.04), Vector3(right_x + 0.02, 0.42, 0.06), WOOD)
			_blob(st, 0.08, Vector3(right_x + 0.02, 0.88, 0.06), magic)
	return st.commit()


# ------------------------------------------------------------------------------ animals

const ANIMALS := ["Sheep", "Cow", "Pig", "Chicken", "Horse", "Wolf", "Bear", "Deer", "Rabbit", "Fox", "Fish", "Crab"]


static func animal(kind: String) -> ArrayMesh:
	var st := _begin()
	match kind:
		"Sheep":
			_quad_legs(st, 0.32, 0.18, 0.12, Color("#3a3a40"))
			_blob(st, 0.3, Vector3(0, 0.36, 0), WHITE, Vector3(1.3, 0.9, 1.0))
			_box(st, Vector3(0.18, 0.18, 0.16), Vector3(0.36, 0.42, 0), Color("#3a3a40"))
			_box(st, Vector3(0.05, 0.05, 0.02), Vector3(0.42, 0.45, 0.085), WHITE)
		"Cow":
			_quad_legs(st, 0.4, 0.22, 0.14, WHITE)
			_box(st, Vector3(0.72, 0.34, 0.36), Vector3(0, 0.42, 0), WHITE)
			_box(st, Vector3(0.2, 0.18, 0.02), Vector3(-0.12, 0.46, 0.185), Color("#2a2a30"))
			_box(st, Vector3(0.14, 0.12, 0.02), Vector3(0.16, 0.36, 0.185), Color("#2a2a30"))
			_box(st, Vector3(0.24, 0.24, 0.26), Vector3(0.46, 0.5, 0), WHITE)
			_box(st, Vector3(0.1, 0.12, 0.2), Vector3(0.6, 0.44, 0), Color("#f2a7c0"))
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.04, 0.12, 0.04), Vector3(0.42, 0.66, side * 0.1), WHITE.darkened(0.15))
			_eye(st, Vector3(0.55, 0.54, 0.0), 0.13)
		"Pig":
			_quad_legs(st, 0.28, 0.14, 0.1, Color("#e88aa8"))
			_blob(st, 0.26, Vector3(0, 0.3, 0), Color("#f4a6be"), Vector3(1.4, 0.95, 1.0))
			_box(st, Vector3(0.08, 0.12, 0.12), Vector3(0.4, 0.3, 0), Color("#e88aa8"))
			_eye(st, Vector3(0.3, 0.38, 0), 0.12)
		"Chicken":
			_box(st, Vector3(0.03, 0.14, 0.03), Vector3(0, 0.07, -0.04), Color("#f0a030"))
			_box(st, Vector3(0.03, 0.14, 0.03), Vector3(0, 0.07, 0.04), Color("#f0a030"))
			_blob(st, 0.17, Vector3(0, 0.26, 0), WHITE, Vector3(1.2, 1.0, 1.0))
			_blob(st, 0.1, Vector3(0.16, 0.42, 0), WHITE)
			_box(st, Vector3(0.06, 0.06, 0.04), Vector3(0.27, 0.42, 0), Color("#f0a030"))
			_box(st, Vector3(0.08, 0.06, 0.03), Vector3(0.15, 0.52, 0), Color("#d83a3a"))
			_eye(st, Vector3(0.21, 0.45, 0), 0.07)
		"Horse":
			_quad_legs(st, 0.42, 0.34, 0.14, Color("#8b5a2b"))
			_box(st, Vector3(0.76, 0.3, 0.3), Vector3(0, 0.56, 0), Color("#9a6a3a"))
			_box(st, Vector3(0.16, 0.38, 0.18), Vector3(0.38, 0.8, 0), Color("#9a6a3a"), Basis(Vector3.BACK, -0.35))
			_box(st, Vector3(0.3, 0.14, 0.16), Vector3(0.52, 0.94, 0), Color("#9a6a3a"))
			_box(st, Vector3(0.06, 0.34, 0.08), Vector3(0.3, 0.86, 0), Color("#4a2a18"), Basis(Vector3.BACK, -0.35))
			_box(st, Vector3(0.06, 0.3, 0.06), Vector3(-0.42, 0.5, 0), Color("#4a2a18"), Basis(Vector3.BACK, 0.3))
			_eye(st, Vector3(0.56, 0.98, 0), 0.085)
		"Wolf":
			_quad_legs(st, 0.3, 0.2, 0.09, Color("#7a7a86"))
			_box(st, Vector3(0.56, 0.22, 0.22), Vector3(0, 0.34, 0), Color("#8a8a96"))
			_box(st, Vector3(0.2, 0.2, 0.2), Vector3(0.34, 0.44, 0), Color("#8a8a96"))
			_box(st, Vector3(0.14, 0.1, 0.12), Vector3(0.48, 0.4, 0), Color("#b8b8c2"))
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.05, 0.1, 0.05), Vector3(0.32, 0.58, side * 0.06), Color("#6a6a76"))
			_box(st, Vector3(0.28, 0.07, 0.07), Vector3(-0.38, 0.4, 0), Color("#8a8a96"), Basis(Vector3.BACK, 0.5))
			_eye(st, Vector3(0.42, 0.47, 0), 0.105)
		"Bear":
			_quad_legs(st, 0.4, 0.22, 0.16, Color("#5a3a1e"))
			_blob(st, 0.34, Vector3(0, 0.46, 0), Color("#7a4e2a"), Vector3(1.35, 0.95, 1.0))
			_blob(st, 0.18, Vector3(0.46, 0.56, 0), Color("#7a4e2a"))
			_box(st, Vector3(0.12, 0.1, 0.12), Vector3(0.62, 0.52, 0), Color("#c49a6a"))
			for side in [-1.0, 1.0]:
				_blob(st, 0.06, Vector3(0.42, 0.74, side * 0.1), Color("#5a3a1e"))
			_eye(st, Vector3(0.56, 0.6, 0), 0.12)
		"Deer":
			_quad_legs(st, 0.3, 0.34, 0.08, Color("#8b5a2b"))
			_box(st, Vector3(0.52, 0.24, 0.22), Vector3(0, 0.5, 0), Color("#a8743e"))
			_box(st, Vector3(0.1, 0.26, 0.12), Vector3(0.28, 0.68, 0), Color("#a8743e"), Basis(Vector3.BACK, -0.3))
			_box(st, Vector3(0.2, 0.12, 0.12), Vector3(0.38, 0.82, 0), Color("#a8743e"))
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.03, 0.22, 0.03), Vector3(0.32, 0.98, side * 0.06), Color("#e8dcc0"), Basis(Vector3.BACK, 0.3))
				_box(st, Vector3(0.1, 0.03, 0.03), Vector3(0.28, 1.04, side * 0.06), Color("#e8dcc0"))
			_eye(st, Vector3(0.42, 0.85, 0), 0.065)
		"Rabbit":
			_blob(st, 0.15, Vector3(0, 0.15, 0), Color("#c8c8d0"), Vector3(1.25, 1.0, 1.0))
			_blob(st, 0.09, Vector3(0.16, 0.26, 0), Color("#c8c8d0"))
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.04, 0.18, 0.04), Vector3(0.13, 0.42, side * 0.04), Color("#c8c8d0"))
			_blob(st, 0.05, Vector3(-0.19, 0.18, 0), WHITE)
			_eye(st, Vector3(0.22, 0.28, 0), 0.07)
		"Fox":
			_quad_legs(st, 0.26, 0.16, 0.07, Color("#3a2a20"))
			_box(st, Vector3(0.46, 0.18, 0.18), Vector3(0, 0.27, 0), Color("#e8822a"))
			_box(st, Vector3(0.18, 0.16, 0.16), Vector3(0.28, 0.36, 0), Color("#e8822a"))
			_box(st, Vector3(0.12, 0.07, 0.1), Vector3(0.41, 0.32, 0), WHITE)
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.05, 0.09, 0.04), Vector3(0.26, 0.48, side * 0.05), Color("#e8822a"))
			_blob(st, 0.1, Vector3(-0.32, 0.28, 0), Color("#e8822a"), Vector3(1.6, 0.8, 0.8))
			_blob(st, 0.05, Vector3(-0.46, 0.3, 0), WHITE)
			_eye(st, Vector3(0.34, 0.39, 0), 0.085)
		"Fish":
			_blob(st, 0.16, Vector3(0, 0.2, 0), Color("#4a9ae0"), Vector3(1.6, 1.0, 0.6))
			_box(st, Vector3(0.12, 0.2, 0.03), Vector3(-0.28, 0.2, 0), Color("#3a7ac0"))
			_eye(st, Vector3(0.18, 0.24, 0), 0.06)
		"Crab":
			_blob(st, 0.17, Vector3(0, 0.14, 0), Color("#e05a4a"), Vector3(1.3, 0.6, 1.0))
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.1, 0.08, 0.08), Vector3(side * 0.3, 0.18, 0.08), Color("#e05a4a"))
				for k in 3:
					_box(st, Vector3(0.12, 0.03, 0.03), Vector3(side * 0.2, 0.05, -0.1 + k * 0.08), Color("#c04a3a"))
				_box(st, Vector3(0.03, 0.08, 0.03), Vector3(side * 0.06, 0.26, 0.08), EYE)
	return st.commit()


# ------------------------------------------------------------------------------ monsters

const MONSTERS := ["Skeleton", "Zombie", "Slime", "Demon", "Ghost", "Spider", "Golem", "Yeti", "Dragon"]


static func monster(kind: String) -> ArrayMesh:
	var st := _begin()
	match kind:
		"Skeleton":
			_humanoid(st, Color("#e8e0c8"), Color("#d8d0b8"), Color("#e8e0c8"), Color("#d8d0b8"), 0.0, true)
		"Zombie":
			_humanoid(st, Color("#8fbf6a"), Color("#6a4a8a"), Color("#4a3a5a"), Color("#5a3a1e"), 0.0, false)
		"Demon":
			_humanoid(st, Color("#d84a3a"), Color("#8c2323"), Color("#6a1a1a"), Color("#2a1a1a"), 0.0, false)
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.06, 0.18, 0.06), Vector3(side * 0.14, 0.98, 0), WHITE, Basis(Vector3.BACK, side * 0.5))
		"Yeti":
			_humanoid(st, Color("#f2f2f6"), Color("#e2e6ee"), Color("#e2e6ee"), Color("#d2d6de"), 0.15, false)
		"Golem":
			_humanoid(st, Color("#8a8a96"), Color("#7a7a86"), Color("#6a6a76"), Color("#6a6a76"), 0.25, false)
		"Slime":
			_blob(st, 0.3, Vector3(0, 0.2, 0), Color("#8fd65a"), Vector3(1.0, 0.75, 1.0))
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.06, 0.08, 0.02), Vector3(side * 0.09, 0.26, 0.29), EYE)
		"Ghost":
			_blob(st, 0.26, Vector3(0, 0.55, 0), Color(0.93, 0.95, 1.0), Vector3(1.0, 1.4, 1.0))
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.06, 0.08, 0.02), Vector3(side * 0.08, 0.66, 0.25), EYE)
		"Spider":
			_blob(st, 0.2, Vector3(-0.1, 0.25, 0), Color("#2e2a34"), Vector3(1.3, 0.9, 1.1))
			_blob(st, 0.12, Vector3(0.16, 0.22, 0), Color("#2e2a34"))
			for side in [-1.0, 1.0]:
				for k in 4:
					_box(st, Vector3(0.04, 0.04, 0.34), Vector3(-0.12 + k * 0.09, 0.14, side * 0.2), Color("#2e2a34"), Basis(Vector3.RIGHT, side * 0.6))
				_box(st, Vector3(0.04, 0.04, 0.02), Vector3(0.26, 0.25, side * 0.05), Color("#e04a4a"))
		"Dragon":
			_quad_legs(st, 0.5, 0.3, 0.14, Color("#3f8a42"))
			_blob(st, 0.35, Vector3(0, 0.56, 0), Color("#4f9e48"), Vector3(1.5, 0.9, 1.0))
			_blob(st, 0.2, Vector3(0, 0.5, 0.0), Color("#c8d870"), Vector3(1.6, 0.8, 1.15))
			_box(st, Vector3(0.14, 0.42, 0.16), Vector3(0.52, 0.86, 0), Color("#4f9e48"), Basis(Vector3.BACK, -0.4))
			_box(st, Vector3(0.36, 0.18, 0.2), Vector3(0.74, 1.06, 0), Color("#4f9e48"))
			_box(st, Vector3(0.5, 0.1, 0.1), Vector3(-0.66, 0.5, 0), Color("#4f9e48"), Basis(Vector3.BACK, 0.25))
			for side in [-1.0, 1.0]:
				_box(st, Vector3(0.6, 0.04, 0.42), Vector3(-0.05, 0.9, side * 0.34), Color("#3f8a42"), Basis(Vector3.RIGHT, side * -0.6))
				_box(st, Vector3(0.05, 0.14, 0.05), Vector3(0.68, 1.2, side * 0.06), WHITE, Basis(Vector3.BACK, 0.6))
			_eye(st, Vector3(0.8, 1.1, 0), 0.105)
	return st.commit()


## A plain humanoid body used by monsters; `bulk` makes it wider and taller.
static func _humanoid(st: SurfaceTool, skin: Color, body: Color, legs: Color, feet: Color, bulk: float, thin: bool) -> void:
	var w := 0.34 + bulk
	var limb := 0.06 if thin else 0.1
	for side in [-1.0, 1.0]:
		_box(st, Vector3(limb, 0.3, limb), Vector3(side * 0.08, 0.15, 0), legs)
		_box(st, Vector3(limb, 0.04, limb + 0.04), Vector3(side * 0.08, 0.02, 0.02), feet)
		_box(st, Vector3(limb, 0.28 + bulk * 0.5, limb), Vector3(side * (w / 2.0 + 0.05), 0.46, 0), skin)
	_box(st, Vector3(w if not thin else 0.24, 0.32 + bulk * 0.5, 0.2 + bulk * 0.4), Vector3(0, 0.47, 0), body)
	_box(st, Vector3(0.28, 0.26, 0.24), Vector3(0, 0.77 + bulk * 0.3, 0), skin)
	for side in [-1.0, 1.0]:
		_box(st, Vector3(0.055, 0.06, 0.02), Vector3(side * 0.065, 0.78 + bulk * 0.3, 0.121), EYE)


static func _quad_legs(st: SurfaceTool, spread: float, height: float, thick: float, color: Color) -> void:
	for x in [-spread / 2.0, spread / 2.0]:
		for z in [-0.08, 0.08]:
			_box(st, Vector3(thick, height, thick), Vector3(x, height / 2.0, z), color)


## An eye on both sides of a head facing +X, at `at`, `half_width` from the centre line.
static func _eye(st: SurfaceTool, at: Vector3, half_width: float) -> void:
	for side in [-1.0, 1.0]:
		_box(st, Vector3(0.04, 0.045, 0.02), at + Vector3(0, 0, side * half_width), EYE)


# ------------------------------------------------------------------------------ geometry

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _box(st: SurfaceTool, size: Vector3, at: Vector3, color: Color, rot := Basis()) -> void:
	var m := BoxMesh.new()
	m.size = size
	_append(st, m, Transform3D(rot, at), color)


static func _blob(st: SurfaceTool, radius: float, at: Vector3, color: Color, stretch := Vector3.ONE) -> void:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 10
	m.rings = 6
	_append(st, m, Transform3D(Basis.from_scale(stretch), at), color)


static func _append(st: SurfaceTool, mesh: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var nb := xform.basis.inverse().transposed()
	var lin := color
	for idx in indices:
		st.set_color(lin)
		st.set_uv(Vector2.ZERO)
		st.set_normal((nb * normals[idx]).normalized())
		st.add_vertex(xform * verts[idx])
