## Runs some of the tests of tests/test_world.gd:
##   godot --headless --path . --script res://tools/run_test.gd -- test_culture test_kingdoms
extends "res://tests/test_world.gd"


func _initialize() -> void:
	for name in OS.get_cmdline_user_args():
		call(name)
	print("\n%s (%d failed)" % ["FAILED" if _failures else "ALL PASSED", _failures])
	quit(_failures)
