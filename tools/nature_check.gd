## Runs a history without a window and reports what nature did in it (0.7, docs/NATURE.md):
## spirits and their moods, disasters, sicknesses, monsters and lairs, and the last events told.
##   godot --headless --path . --script res://tools/nature_check.gd -- [years] [size] [peoples] [seed]
## Defaults: 100 years, size 192, humans,elves,orcs, seed "animundi".
extends SceneTree

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const Flora = preload("res://scripts/world/flora.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 100
	var s := WorldSettings.new()
	s.set_size(int(args[1]) if args.size() > 1 else 192)
	var peoples := (args[2] if args.size() > 2 else "humans,elves,orcs").split(",")
	s.seed_text = args[3] if args.size() > 3 else "animundi"
	var world := WorldGenerator.generate(s)
	var sim: Node2D = load("res://sim/Simulation.cs").new()
	root.add_child(sim)
	sim.Start(world, PackedStringArray(Biomes.NAMES))
	var flora := Flora.place(world)
	sim.LoadPlants(flora.id, flora.pos, flora.flip, flora.scale)
	sim.SpawnNatural(world.size() / 300)
	sim.SetMindEndpoint("")
	sim.StartPeoples(peoples, 12)
	var told := {"nature": [], "disasters": []}
	var counts := {}
	var done := 0
	while done < years:
		sim.RunYears(10.0, 6)
		done += 10
		var events: PackedStringArray = sim.TakeTaggedEvents()
		for n in range(0, events.size(), 2):
			counts[events[n]] = counts.get(events[n], 0) + 1
			if told.has(events[n]) and not String(events[n + 1]).contains("lightning sets"):
				told[events[n]].append(events[n + 1])
	var nature: Dictionary = sim.NatureTable()
	print("after %d years: %d people, %d villages, %d animals; events %s" % [years, sim.PeopleCount(), sim.VillageCount(), sim.UnitCount() - sim.PeopleCount(), counts])
	print("deaths: %s" % sim.LifeStats())
	print("\nSPIRITS")
	for sp in nature.spirits:
		print("  %s: %s (%.2f), %d tiles, last act %s%s" % [sp.full_name, sp.mood_word, sp.mood, sp.tiles, sp.act, " | " + String(sp.deeds).replace("\n", "; ") if sp.deeds != "" else ""])
	print("\nSICKNESSES")
	for d in nature.diseases:
		print("  %s (%s, %s, cure %s) year %d-%d: %d caught, %d dead (%d people), %d recovered" % [d.name, d.symptom, d.carrier, d.cure, d.year, d.ended, d.caught, d.dead, d.people_dead, d.recovered])
	print("\nMONSTERS")
	for m in nature.strains:
		print("  %s: %d alive, %d lairs, generation %d | %s" % [m.name, m.population, m.lairs, m.generation, String(m.lineage).replace("\n", "; ")])
	for l in nature.lairs:
		print("  %s %s, year %d, size %.1f, %d born%s" % [l.name, l.place, l.year, l.size, l.born, "" if l.alive else " | " + l.end])
	for cat in told:
		print("\n%s (%d told, the last 25)" % [cat.to_upper(), told[cat].size()])
		for line in told[cat].slice(-25):
			print("  " + line)
	sim.queue_free()
	quit()
