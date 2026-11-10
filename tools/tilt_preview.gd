## Opens the game in the tilt view (scripts/render_tilt/tilt_view.gd), over a village.
##   godot [--disable-vsync] --path . --script res://tools/tilt_preview.gd -- <mode> [out] [seed] [years] [size] [hour] [distance] [animals] [effects]
## `mode`:
## - "shot": saves <out>_tilt.png and <out>_flat.png, the same village in both views;
## - "perf": prints, for both views, the frame time and the CPU and GPU render time averaged
##   over 300 frames, and the draw calls (pass --disable-vsync for a true frame time);
##   "perf-flat-first" measures the flat view first;
## - "play": stays open. Wheel: zoom, drag or WASD: move, T: next hour, V: flat or tilt view,
##   B: effects on or off.
## `out`: path without extension (default user://tilt). `years`: how long the world runs first
## (default 3). `size`: world size in tiles (default 256). `hour`: 0 dawn, 0.3 noon, 0.8 dusk,
## 1 night (default 0.78). `distance`: camera distance in tiles (default 34). `animals`: extra
## animals spawned, to load the view (default 0). `effects`: 0 turns the blur, vignette and tint off. Needs a display and the Godot .NET build.
extends SceneTree

const TiltView = preload("res://scripts/render_tilt/tilt_view.gd")
const WorldMap = preload("res://scripts/render2d/world_map.gd")

const WARMUP := 90
const SAMPLES := 300

var _mode := "shot"
var _out := "user://tilt"
var _years := 3.0
var _hour := 0.78
var _distance := 34.0
var _animals := 0
var _effects := true
var _main: Node
var _view: TiltView
var _village := Vector2.ZERO
var _frames := 0
var _phase := 0
var _sum := {}
var _last_usec := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = args[0]
	if args.size() > 1:
		_out = args[1]
	_main = load("res://scenes/main.tscn").instantiate()
	if args.size() > 2 and args[2] != "":
		_main.settings.seed_text = args[2]
	if args.size() > 3:
		_years = float(args[3])
	if args.size() > 4:
		_main.settings.set_size(int(args[4]))
	if args.size() > 5:
		_hour = float(args[5])
	if args.size() > 6:
		_distance = float(args[6])
	if args.size() > 7:
		_animals = int(args[7])
	if args.size() > 8:
		_effects = args[8] != "0"
	root.add_child(_main)


func _start() -> void:
	var world = _main.world
	_main._hud._setup.visible = false
	# Screenshots show the world alone.
	_main._hud.visible = _mode != "shot"
	_main.start_peoples(PackedStringArray(["humans", "elves", "orcs"]), 12)
	if _years > 0.0:
		_main._sim.RunSteps(int(_years * 60.0 * 30.0))
	if _animals > 0:
		_main._sim.SpawnNatural(_animals)
	_village = Vector2(world.width, world.height) / 2.0
	if _main._sim.VillageCount() > 0:
		var v: Dictionary = _main._sim.VillageTable()[0]
		_village = Vector2(v.x + 0.5, v.y + 0.5)
	var started := Time.get_ticks_msec()
	_view = TiltView.new()
	_view.time_of_day = _hour
	_view.effects = _effects
	_main.add_child(_view)
	_view.setup(_main)
	_view.camera.look_at_tile(_village, _distance)
	print("tilt view built in %d ms: %d units, %d plants, %d villages on a %d² world" % [
		Time.get_ticks_msec() - started, _main._sim.UnitCount(), _main._sim.PlantCount(), _main._sim.VillageCount(), world.width])
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(_view.viewport_rid(), true)
	print("window %s" % root.size)


## The flat view of the same place, covering the same height of the world.
func _show_flat() -> void:
	_view.set_enabled(false)
	var zoom: float = root.get_visible_rect().size.y / (_view.camera.view_height() * WorldMap.TILE)
	_main._camera.look_at_point(_village * WorldMap.TILE, zoom)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_start()
	if _frames < 3:
		return false
	match _mode:
		"shot":
			return _shot()
		"perf", "perf-flat-first":
			if _mode == "perf-flat-first" and _frames == 3:
				_show_flat()
			return _perf()
	if Input.is_key_pressed(KEY_ESCAPE):
		return true
	return false


func _shot() -> bool:
	if _frames == 60:
		_save("%s_tilt.png" % _out)
		_show_flat()
	if _frames == 100:
		_save("%s_flat.png" % _out)
		return _finish()
	return false


## Ends the tool at once: leaving through the scene tree can hang while the C# simulation is
## torn down, and nothing here needs saving.
func _finish() -> bool:
	OS.kill(OS.get_process_id())
	return true


func _save(path: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _perf() -> bool:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	var k := _frames - 3 - _phase * (WARMUP + SAMPLES)
	if k == 0:
		_sum = {frame = 0.0, cpu = 0.0, gpu = 0.0, draws = 0.0, process = 0.0}
		_main._sim.TakeDrawMs()
	elif k > WARMUP:
		var vp := root.get_viewport_rid()
		_sum.frame += frame_ms
		_sum.process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_sum.cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		_sum.gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		if _view.enabled:
			_sum.cpu += RenderingServer.viewport_get_measured_render_time_cpu(_view.viewport_rid())
			_sum.gpu += RenderingServer.viewport_get_measured_render_time_gpu(_view.viewport_rid())
		_sum.draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	elif k == WARMUP:
		_main._sim.TakeDrawMs()
	if k == WARMUP + SAMPLES:
		var n := float(SAMPLES)
		print("%s view: frame %.2f ms (%.0f fps), process %.2f ms, render CPU %.2f ms, render GPU %.2f ms, %.0f draw calls, sim fills its batches in %.2f ms" % [
			"tilt" if _view.enabled else "flat", _sum.frame / n, 1000.0 * n / _sum.frame, _sum.process / n, _sum.cpu / n, _sum.gpu / n, _sum.draws / n, _main._sim.TakeDrawMs()])
		_phase += 1
		if _phase == 2:
			return _finish()
		if _view.enabled:
			_show_flat()
		else:
			_view.set_enabled(true)
	return false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _mode != "play" or _view == null or key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_T:
			var hours := [0.0, 0.3, 0.58, 0.8, 1.0]
			var next := 0
			for i in hours.size():
				if hours[i] <= _view.time_of_day + 0.01:
					next = (i + 1) % hours.size()
			print("hour: ", _view.set_time(hours[next]))
		KEY_V:
			if _view.enabled:
				_show_flat()
			else:
				_view.set_enabled(true)
		KEY_B:
			_view.effects = not _view.effects
