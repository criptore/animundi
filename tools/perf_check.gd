## Performance check of the C# simulation (needs the Godot .NET build):
##   godot --headless --path . --script res://tools/perf_check.gd -- [units] [size] [steps]
## Generates a world, spawns `units` wandering animals (default 5000), runs `steps` simulation
## steps (default 300 = 10 simulated seconds) and prints the average cost of one step and of
## writing the units into the MultiMesh for a frame. The 0.15 goal is 5,000+ moving units at
## 60 fps: one step plus one frame of drawing must stay well under 16 ms.
extends SceneTree

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const Flora = preload("res://scripts/world/flora.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var units := int(args[0]) if args.size() > 0 else 5000
	var size := int(args[1]) if args.size() > 1 else 256
	var steps := int(args[2]) if args.size() > 2 else 300
	var s := WorldSettings.new()
	s.set_size(size)
	var world := WorldGenerator.generate(s)
	var sim: Node2D = load("res://sim/Simulation.cs").new()
	root.add_child(sim)
	sim.Start(world, PackedStringArray(Biomes.NAMES))
	var flora := Flora.place(world)
	sim.LoadPlants(flora.id, flora.pos, flora.flip, flora.scale)
	# Measure the creatures asked for, not births and deaths along the way.
	for law in ["animal_spawn", "hunger", "old_age", "natural_disasters"]:
		sim.SetLaw(law, false)
	var placed: int = sim.SpawnNatural(units)
	sim.TakeStepMs()
	sim.RunSteps(steps)
	var step_ms: float = sim.TakeStepMs()
	sim.DrawFrames(60)
	var draw_ms: float = sim.TakeDrawMs()
	print("units %d and %d plants on a %d² world: %.3f ms per step, %.3f ms to draw a frame, %d on water" % [
		placed, sim.PlantCount(), size, step_ms, draw_ms, sim.CountOnWater()])
	print("budget at 60 fps: %.1f%% of 16.7 ms" % [100.0 * (step_ms * 2.0 + draw_ms) / 16.7])
	# Up close, plants are sorted with the creatures every frame (only what the camera sees).
	for zoom in [0.5, 2.0]:
		var centre := Vector2(size, size) * 4.0
		sim.SetZoom(zoom)
		sim.SetView(centre, Vector2(1920, 1080) / zoom)
		sim.DrawFrames(60)
		print("close-up at zoom %.1f (1920×1080 screen): %.3f ms to draw a frame" % [zoom, sim.TakeDrawMs()])
	quit()
