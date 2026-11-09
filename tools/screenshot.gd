## Opens the game, waits for the world to be shown, saves a screenshot and quits.
##   godot --path . --script res://tools/screenshot.gd -- <out.png> [seed] [zoom] [volcano]
## `zoom` is in screen pixels per world pixel (a tile is 8 world pixels; 0 = whole map).
## With "volcano", the view is centred on the world's first volcano, else on the map centre.
## Needs a display (use xvfb-run on a headless machine).
extends SceneTree

const WorldMap = preload("res://scripts/render2d/world_map.gd")

var _frames := 0
var _out := "user://screenshot.png"
var _zoom := 0.0
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
	_main = main
	root.add_child(main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2 and _zoom > 0.0:
		var world = _main.world
		var point := Vector2(world.width, world.height) * WorldMap.TILE / 2.0
		var args := OS.get_cmdline_user_args()
		if args.size() > 3 and args[3] == "volcano" and world.volcanoes.size() > 0:
			var v: int = world.volcanoes[0]
			point = (Vector2(v % world.width, v / world.width) + Vector2(0.5, 0.5)) * WorldMap.TILE
		_main._camera.look_at_point(point, _zoom)
	if _frames == 12:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
