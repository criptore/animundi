## Opens the game, waits for the world to be shown, saves a screenshot and quits.
##   godot --path . --script res://tools/screenshot.gd -- <out.png> [seed] [zoom] [where] [years]
## `zoom` is in screen pixels per world pixel (a tile is 8 world pixels; 0 = whole map).
## `where`:
## - "setup": shows the world setup panel, as a new world opens;
## - "village": starts the world with Humans, Elves and Orcs and centres on the first village;
## - "volcano": centres on the world's first volcano (once the terrain tools can place one);
## - anything else: the map centre, peoples started as with "village".
## `years`: how long the world runs before the screenshot (default 0).
## Needs a display (use xvfb-run on a headless machine).
extends SceneTree

const WorldMap = preload("res://scripts/render2d/world_map.gd")

var _frames := 0
var _out := "user://screenshot.png"
var _zoom := 0.0
var _where := ""
var _years := 0.0
var _main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	if args.size() > 1:
		main.settings.seed_text = args[1]
	if args.size() > 2:
		_zoom = float(args[2])
	if args.size() > 3:
		_where = args[3]
	if args.size() > 4:
		_years = float(args[4])
	_main = main
	root.add_child(main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var world = _main.world
		var point := Vector2(world.width, world.height) * WorldMap.TILE / 2.0
		if _where != "setup":
			_main._hud._setup.visible = false
			_main.start_peoples(PackedStringArray(["humans", "elves", "orcs"]), 12)
			if _years > 0.0:
				_main._sim.RunSteps(int(_years * 60.0 * 30.0))
		if _where == "village" and _main._sim.VillageCount() > 0:
			var v: Dictionary = _main._sim.VillageTable()[0]
			point = Vector2(v.x + 0.5, v.y + 0.5) * WorldMap.TILE
		elif _where == "volcano" and world.volcanoes.size() > 0:
			var vol: int = world.volcanoes[0]
			point = (Vector2(vol % world.width, vol / world.width) + Vector2(0.5, 0.5)) * WorldMap.TILE
		if _zoom > 0.0:
			_main._camera.look_at_point(point, _zoom)
	if _frames == 40:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
