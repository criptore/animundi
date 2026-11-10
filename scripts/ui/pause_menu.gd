## The pause menu (Esc): the world stops while it is open.
extends "res://scripts/ui/window.gd"

## One of: "resume", "save", "load", "settings", "new_world", "title", "quit".
signal chosen(what: String)

const ENTRIES := [
	["resume", "Resume", "play", "Primary"],
	["save", "Save the world", "save", ""],
	["load", "Load a world", "load", ""],
	["settings", "Settings", "gear", ""],
	["new_world", "New world", "globe", ""],
	["title", "Back to the title", "door", ""],
	["quit", "Quit the game", "close", ""],
]


func _init() -> void:
	build("The world waits", "pause", 320)
	for entry in ENTRIES:
		var b := UI.button(entry[1], entry[2], "", entry[3])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 40
		b.pressed.connect(func(): chosen.emit(entry[0]))
		body.add_child(b)
