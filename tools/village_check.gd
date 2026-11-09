## Runs a world with peoples for some years without a window and prints, year by year, each
## village's population, food, wood and houses, and the events (needs Godot .NET):
##   godot --headless --path . --script res://tools/village_check.gd -- [years] [peoples] [seed]
## `peoples` is a comma-separated list of ids from data/races.json (default humans,elves,orcs).
extends SceneTree

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const Flora = preload("res://scripts/world/flora.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 5
	var peoples := (args[1] if args.size() > 1 else "humans,elves,orcs").split(",")
	var s := WorldSettings.new()
	s.seed_text = args[2] if args.size() > 2 else "animundi"
	var world := WorldGenerator.generate(s)
	var sim: Node2D = load("res://sim/Simulation.cs").new()
	root.add_child(sim)
	sim.Start(world, PackedStringArray(Biomes.NAMES))
	var flora := Flora.place(world)
	sim.LoadPlants(flora.id, flora.pos, flora.flip, flora.scale)
	sim.SpawnNatural(world.size() / 300)
	print("villages founded: ", sim.StartPeoples(PackedStringArray(peoples), 12))
	for id in peoples:
		print("  %s: %s  names: %s" % [id, sim.RaceOf(id), ", ".join(sim.SampleNames(id, 6))])
	for y in years:
		sim.RunSteps(60 * 30)
		print("year %d: %d people, %d animals, %.3f ms/step" % [y + 1, sim.PeopleCount(), sim.UnitCount() - sim.PeopleCount(), sim.TakeStepMs()])
		for v in sim.VillageTable():
			print("   %s (%s): %d people / %d homes, food %d wood %d stone %d metal %d gold %d tools %d weapons %d, %d zones, %d fields, building %s %.2f\n      [%s]\n      jobs: %s" % [v.name, v.people, v.population, v.homes, v.food, v.wood, v.stone, v.metal, v.gold, v.tools, v.weapons, v.zones, v.fields, v.building, v.site, v.buildings, v.jobs])
		for e in sim.TakeEvents():
			print("   ", e)
	print("life: ", sim.LifeStats())
	quit()
