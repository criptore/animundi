## Opens the game, waits for the world to be shown, saves a screenshot and quits.
##   godot --path . --script res://tools/screenshot.gd -- <out.png> [seed]
## Needs a display (use xvfb-run on a headless machine).
extends SceneTree

var _frames := 0
var _out := "user://screenshot.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	if args.size() > 1:
		main.settings.seed_text = args[1]
	root.add_child(main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
