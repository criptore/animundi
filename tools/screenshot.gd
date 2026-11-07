## Opens the game, waits for the world to be shown, saves a screenshot and quits.
##   godot --path . --script res://tools/screenshot.gd -- <out.png> [seed] [zoom] [volcano]
## With "volcano", the view is centred on the world's first volcano.
## Needs a display (use xvfb-run on a headless machine).
extends SceneTree

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
		_main._camera.zoom_by(_zoom)
		var args := OS.get_cmdline_user_args()
		if args.size() > 3 and args[3] == "volcano" and _main.world.volcanoes.size() > 0:
			var v: int = _main.world.volcanoes[0]
			_main._camera.frame(Vector3(v % _main.world.width, 0, v / _main.world.width), _main._camera.ortho_size)
	if _frames == 12:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
