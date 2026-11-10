## Films one shot of the teaser: the game runs, a scripted camera moves over it, scripted moments
## happen (lightning, a meteor, dragons…), and Godot's movie maker writes every frame at a fixed
## rate (the simulation follows the movie's clock).
##   godot --path . --resolution 1920x1080 --fixed-fps 30 --write-movie <dir>/f.png \
##       --script res://tools/teaser.gd -- <shot> [seed]
## Shots: see SHOTS below. tools/teaser/make_teaser.sh films them all and edits the teaser.
## The bolts of lightning, the falling meteor, the flashes and the shaking camera are drawn by
## this tool over the game (the game shows only what they do on the ground).
## Needs a display (xvfb-run on a headless machine) and the Godot .NET build.
extends SceneTree

const Biomes = preload("res://scripts/world/biomes.gd")
const TiltView = preload("res://scripts/render_tilt/tilt_view.gd")

const PEOPLES := ["humans", "elves", "orcs", "dwarves"]

## years: how long the world runs first. frames: length at 30 fps. hour: [from, to] (0 dawn,
## 0.3 noon, 0.8 dusk, 1 night; "dawn" goes from night straight to dawn). dist: camera distance
## [from, to] in tiles (0 = the whole map). pan: camera move in tiles over the shot, from the
## focus (+ from). people: the village filmed is this people's biggest. water: prefer a village
## by the water (reflections). hud: the interface is shown. events: [frame, kind, offset from
## the focus in tiles, ...].
const SHOTS := {
	# The whole world seen from above, falling down into a village in the afternoon.
	"descent": {years = 6.0, frames = 240, hour = [0.45, 0.58], dist = [0.0, 24.0], people = "humans"},
	# A slow slide over a village by the water, golden hour.
	"village": {years = 9.0, frames = 150, hour = [0.6, 0.66], dist = [22.0, 19.0], pan = Vector2(12, -2), from = Vector2(-6, 1), people = "elves", water = true},
	# From afternoon to night over a village by the water: the windows light up, the bonfire
	# glows, the houses shine in the water.
	"nightfall": {years = 12.0, frames = 210, hour = [0.62, 1.0], dist = [30.0, 18.0], pan = Vector2(3, -1), people = "humans", water = true},
	# Night, very close, along the shore: reflections and lit windows.
	"shore": {years = 12.0, frames = 180, hour = [0.97, 1.0], dist = [21.0, 18.0], pan = Vector2(10, 0), from = Vector2(-5, 2), people = "elves", water = true},
	# A storm at night: lightning strikes the village, the houses burn and light the night.
	"storm": {years = 10.0, frames = 210, hour = [0.95, 0.95], dist = [26.0, 20.0], pan = Vector2(0, -1), people = "humans", water = true,
		events = [[30, "bolt", Vector2(-5, 3)], [62, "bolt", Vector2(2, -1), "burn"], [80, "bolt", Vector2(6, 2)], [112, "bolt", Vector2(-1, 1), "burn"], [150, "bolt", Vector2(-6, -3), "burn"]]},
	# A meteor falls at night beside a village.
	"meteor": {years = 8.0, frames = 180, hour = [0.92, 0.92], dist = [32.0, 27.0], people = "dwarves",
		events = [[20, "meteor", Vector2(6, 2), 3.0]]},
	# Dragons at dusk: they come down on a village and it burns.
	"dragons": {years = 8.0, frames = 210, hour = [0.85, 0.95], dist = [22.0, 18.0], pan = Vector2(-2, 1), people = "orcs",
		events = [[1, "spawn", Vector2(-6, 4), "dragon", 2], [1, "spawn", Vector2(5, 5), "dragon", 1], [1, "spawn", Vector2(3, -4), "demon", 3],
			[40, "burn", Vector2.ZERO], [70, "burn", Vector2.ZERO], [100, "burn", Vector2.ZERO], [130, "burn", Vector2.ZERO]]},
	# Kingdoms at war: the village their army marches on, at dusk.
	"war": {years = 14.0, frames = 180, hour = [0.75, 0.85], dist = [34.0, 28.0], action = "war"},
	# Night turns to dawn over the water: the world goes on.
	"dawn": {years = 16.0, frames = 180, hour = "dawn", dist = [24.0, 30.0], pan = Vector2(0, -3), people = "elves", water = true},
	# The game as it is played: the interface over a living village.
	"interface": {years = 8.0, frames = 180, hour = [0.55, 0.6], dist = [40.0, 34.0], pan = Vector2(6, 0), people = "humans", hud = true},
}

var _shot := "descent"
var _cfg: Dictionary
var _main: Node
var _frame := 0
var _focus := Vector2.ZERO
var _from := Vector2.ZERO
var _fx := Effects.new()
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot = args[0]
	_cfg = SHOTS[_shot]
	_rng.seed = hash(_shot)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.settings.seed_text = args[1] if args.size() > 1 else "anima"
	# The interface at the size it has in a 1280×720 window (the other shots hide it, and keep
	# the 3D view at the full resolution).
	if _cfg.get("hud", false):
		root.content_scale_factor = root.size.y / 720.0
	root.add_child(_main)
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(_fx)
	root.add_child(layer)


func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_start()
	if _frame < 2:
		return false
	var k := _frame - 2
	var frames: int = _cfg.frames
	if k >= frames:
		OS.kill(OS.get_process_id())
		return true
	_film(k, frames, delta)
	return false


func _start() -> void:
	var sim = _main._sim
	_main._hud.leave_title()
	_main._hud._setup.visible = false
	_main._hud._refresh_screens()
	_main.start_peoples(PackedStringArray(PEOPLES), 12)
	sim.RunSteps(int(_cfg.years * 60.0 * 30.0))
	_main._hud.visible = _cfg.get("hud", false)
	_focus = _pick_village(_cfg.get("people", ""), _cfg.get("water", false))
	if _cfg.get("action", "") == "war":
		var kingdoms: Array = sim.KingdomTable()
		if kingdoms.size() >= 2:
			sim.PowerWhisper("war", kingdoms[0].index, kingdoms[1].index)
			sim.RunSteps(60 * 30)
		_focus = _war_target(_focus)
	_from = _focus + _cfg.get("from", Vector2.ZERO)
	_main.set_tilt(true)
	if _shot == "interface":
		_main._pinned_village = sim.VillageAt(_focus.x, _focus.y)
		_main._refresh_inspector()
		_main._hud.powers.select("fire")
	print("shot %s: focus %s, %d units, %d villages, %d kingdoms" % [_shot, _focus, sim.UnitCount(), sim.VillageCount(), sim.KingdomCount()])


func _film(k: int, frames: int, delta: float) -> void:
	var t := float(k) / float(frames - 1)
	var e := t * t * (3.0 - 2.0 * t)
	var view = _main._tilt
	if _cfg.hour is String:
		_night_to_dawn(view, e)
	else:
		view.set_time(lerpf(_cfg.hour[0], _cfg.hour[1], e))
	var d0: float = _cfg.dist[0] if _cfg.dist[0] > 0.0 else view.camera.max_distance()
	var d1: float = _cfg.dist[1]
	# Distances change on a log scale: a fall from the sky slows as it nears the ground.
	var dist := exp(lerpf(log(d0), log(d1), e))
	var target: Vector2 = _from + _cfg.get("pan", Vector2.ZERO) * e
	if _shot == "descent":
		# Hold on the whole world, then fall: the target reaches the village before the camera lands.
		var f := smoothstep(0.12, 1.0, t)
		dist = exp(lerpf(log(d0), log(d1), 1.0 - pow(1.0 - f, 2.2)))
		target = (Vector2(_main.world.width, _main.world.height) / 2.0).lerp(_focus, smoothstep(0.0, 0.75, f))
	# The camera shakes after an impact.
	_shake = maxf(0.0, _shake - delta * 2.2)
	target += Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake * _shake * 0.8
	view.camera.look_at_tile(target, dist)
	for ev in _cfg.get("events", []):
		if ev[0] == k:
			_event(ev)
	# From the 3D view's own viewport to the canvas the effects are drawn on.
	var scale: Vector2 = _fx.get_viewport_rect().size / Vector2(view._viewport.size)
	_fx.project = func(p: Vector2, lift: float) -> Vector2: return view.screen_of(p, lift) * scale
	_fx.queue_redraw()


## The tilt view's hours go dawn → noon → dusk → night; this blends night straight into dawn.
func _night_to_dawn(view, e: float) -> void:
	var a: Dictionary = TiltView.HOURS[TiltView.HOURS.size() - 1]
	var b: Dictionary = TiltView.HOURS[0]
	view.set_time(1.0)
	view._look = {
		ambient = a.ambient.lerp(b.ambient, e), haze = a.haze.lerp(b.haze, e), tint = a.tint.lerp(b.tint, e),
		fires = lerpf(a.fires, b.fires, e), cloud = lerpf(a.cloud, b.cloud, e), shadow = lerpf(a.shadow, b.shadow, e),
		vignette = lerpf(a.vignette, b.vignette, e),
	}
	view._apply_look()


func _event(ev: Array) -> void:
	var sim = _main._sim
	var at: Vector2 = _focus + ev[2]
	match ev[1]:
		"bolt":
			_fx.bolt(at, _rng.randi())
			_shake = maxf(_shake, 0.6)
			sim.PowerLightning(at.x, at.y)
			if ev.size() > 3 and ev[3] == "burn":
				_burn_near(at)
		"meteor":
			var radius: float = ev[3]
			_fx.meteor(at, 22, func():
				sim.PowerMeteor(at.x, at.y, radius)
				_shake = 1.0)
		"spawn":
			sim.PowerSpawn(ev[3], at.x, at.y, ev[4])
		"burn":
			_burn_near(at)


## Sets the nearest wooden building not yet burning alight.
func _burn_near(at: Vector2) -> void:
	var best := {}
	var best_d := INF
	for b in _main._sim.BuildingTable():
		if b.burning or not b.done or b.id == "bonfire":
			continue
		var d := at.distance_squared_to(Vector2(b.x, b.y))
		if d < best_d:
			best_d = d
			best = b
	if not best.is_empty():
		_main._sim.IgniteBuilding(best.x, best.y)


## The biggest village of a people (any people when none is given), by the water if asked.
func _pick_village(people: String, water: bool) -> Vector2:
	var world = _main.world
	var best := {}
	var best_score := -INF
	for v in _main._sim.VillageTable():
		if people != "" and not v.people.to_lower().begins_with(people.left(4)):
			continue
		var score: float = v.population
		if water:
			var wet := 0
			for y in range(v.y - 8, v.y + 9):
				for x in range(v.x - 10, v.x + 11):
					if world.in_bounds(x, y) and world.is_water(world.index(x, y)):
						wet += 1
			score += minf(wet, 90.0) * 0.6
		if score > best_score:
			best_score = score
			best = v
	if best.is_empty() and people != "":
		return _pick_village("", water)
	if best.is_empty():
		return Vector2(world.width, world.height) / 2.0
	return Vector2(best.x + 0.5, best.y + 0.5)


## The village a war marches on (the first war's first target), else the point.
func _war_target(at: Vector2) -> Vector2:
	var wars: Array = _main._sim.WarTable()
	print("wars: ", wars)
	if wars.is_empty():
		return at
	var name: String = wars[0].target_a if wars[0].target_a != "" else wars[0].target_b
	for v in _main._sim.VillageTable():
		if v.name == name:
			return Vector2(v.x + 0.5, v.y + 0.5)
	return at


## What this tool draws over the game: bolts of lightning, a falling meteor, flashes.
class Effects:
	extends Node2D

	## Screen position of a ground point (tiles) lifted by some tiles.
	var project: Callable
	var _bolts: Array = []
	var _meteors: Array = []
	var _flash := 0.0
	var _flash_color := Color.WHITE

	func bolt(at: Vector2, seed_value: int) -> void:
		_bolts.append({at = at, seed = seed_value, age = 0})
		_flash = 0.55
		_flash_color = Color(0.85, 0.9, 1.0)

	func meteor(at: Vector2, frames: int, landed: Callable) -> void:
		_meteors.append({at = at, frames = frames, age = 0, landed = landed})

	func _draw() -> void:
		if not project.is_valid():
			return
		var size := get_viewport_rect().size
		for b in _bolts:
			var ground: Vector2 = project.call(b.at, 0.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = b.seed
			var top := Vector2(ground.x + rng.randf_range(-140, 140), -20)
			var fade: float = 1.0 - b.age / 7.0
			var points := PackedVector2Array([top])
			for i in range(1, 13):
				var p := top.lerp(ground, i / 12.0)
				if i < 12:
					p.x += rng.randf_range(-38, 38)
				points.append(p)
			draw_polyline(points, Color(0.55, 0.65, 1.0, 0.35 * fade), 22.0)
			draw_polyline(points, Color(0.8, 0.86, 1.0, 0.8 * fade), 8.0)
			draw_polyline(points, Color(1, 1, 1, fade), 3.0)
			var from: Vector2 = points[5]
			var side := 1.0 if b.seed % 2 == 0 else -1.0
			var branch := PackedVector2Array([from])
			for i in range(1, 6):
				branch.append(from + Vector2(rng.randf_range(10, 40) * i * side, i * 35.0))
			draw_polyline(branch, Color(0.85, 0.9, 1.0, 0.7 * fade), 2.0)
			draw_circle(ground, 60.0 * fade, Color(0.8, 0.85, 1.0, 0.25 * fade))
		for m in _meteors:
			var k: float = float(m.age) / m.frames
			if k > 1.0:
				continue
			var ground: Vector2 = project.call(m.at, 0.0)
			var start := ground + Vector2(-size.x * 0.55, -size.y * 0.9)
			var head := start.lerp(ground, k * k)
			var tail := start.lerp(ground, maxf(0.0, k * k - 0.25))
			for i in 6:
				var w := 46.0 - i * 7.0
				draw_line(tail.lerp(head, i / 6.0), head, Color(1.0, 0.45 + i * 0.08, 0.15, 0.25 + i * 0.12), w)
			draw_circle(head, 30.0, Color(1.0, 0.55, 0.2, 0.6))
			draw_circle(head, 18.0, Color(1.0, 0.95, 0.75))
		if _flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_color, _flash))

	func _process(_delta: float) -> void:
		for b in _bolts:
			b.age += 1
		_bolts = _bolts.filter(func(b): return b.age < 7)
		for m in _meteors:
			m.age += 1
			if m.age == m.frames:
				m.landed.call()
				_flash = 0.95
				_flash_color = Color(1.0, 0.85, 0.6)
		_meteors = _meteors.filter(func(m): return m.age <= m.frames)
		_flash = maxf(0.0, _flash - 0.09)
