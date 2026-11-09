## Runs the living world for some years without a window and prints, year by year, how many
## creatures of each species live, how they died and how many plants grow (needs Godot .NET):
##   godot --headless --path . --script res://tools/life_check.gd -- [years] [seed] [size]
## Use it to tune food chains, breeding and fire: populations should rise and fall, not explode
## or die out at once.
extends SceneTree

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const Flora = preload("res://scripts/world/flora.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 10
	var s := WorldSettings.new()
	s.seed_text = args[1] if args.size() > 1 else "animundi"
	s.set_size(int(args[2]) if args.size() > 2 else 256)
	var world := WorldGenerator.generate(s)
	var sim: Node2D = load("res://sim/Simulation.cs").new()
	root.add_child(sim)
	sim.Start(world, PackedStringArray(Biomes.NAMES))
	var flora := Flora.place(world)
	sim.LoadPlants(flora.id, flora.pos, flora.flip, flora.scale)
	sim.SpawnNatural(world.size() / 300)
	print("start: %d creatures, %d plants" % [sim.UnitCount(), sim.PlantCount()])
	var steps_per_year := int(60.0 * 30.0)
	for y in years:
		sim.RunSteps(steps_per_year)
		print("year %d: %d creatures, %d plants, %.3f ms/step  %s" % [y + 1, sim.UnitCount(), sim.PlantCount(),
				sim.TakeStepMs(), sim.PopulationTable()])
		for e in sim.TakeEvents():
			print("   ", e)
	print("life: ", sim.LifeStats())
	quit()
