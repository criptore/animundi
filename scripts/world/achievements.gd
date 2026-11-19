## Achievements (1.0, docs/POLISH.md): data/achievements.json lists them; each is won once,
## for good, when the world's facts (the simulation's Facts) meet its test, in any world. What was
## won is kept in user://achievements.json with the day it was won.
extends RefCounted

const FILE := "user://achievements.json"

var list: Array = []
## id → the day it was won.
var won := {}
var _file := FILE


func _init(file := FILE) -> void:
	_file = file
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))
	list = data.achievements if data is Dictionary else []
	if FileAccess.file_exists(_file):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(_file))
		if saved is Dictionary:
			won = saved


## Checks the facts; returns the achievements won now (and keeps them).
func check(facts: Dictionary) -> Array:
	var new := []
	for a in list:
		if won.has(a.id) or not facts.has(a.fact):
			continue
		var value = facts[a.fact]
		var goal = a.at_least
		var met: bool = bool(value) if goal is bool else float(value) >= float(goal)
		if met:
			won[a.id] = Time.get_date_string_from_system()
			new.append(a)
	if not new.is_empty():
		_save()
	return new


func _save() -> void:
	var f := FileAccess.open(_file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(won))
		f.close()


## Forgets every achievement won (settings).
func reset() -> void:
	won.clear()
	_save()
