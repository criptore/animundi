## Runs a history without a window and reports how the peoples climbed the ages (0.8,
## docs/AGES.md): each kingdom's age every `step` years, its things, the air and the climate, the
## bombs, the rockets, the moods of the world, and the last events of the ages.
##   godot --headless --path . --script res://tools/ages_check.gd -- [years] [size] [peoples] [seed] [step]
## Defaults: 200 years, size 192, humans,elves,orcs, seed "animundi", a line every 20 years.
extends SceneTree

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const Flora = preload("res://scripts/world/flora.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 200
	var s := WorldSettings.new()
	s.set_size(int(args[1]) if args.size() > 1 else 192)
	var peoples := (args[2] if args.size() > 2 else "humans,elves,orcs").split(",")
	s.seed_text = args[3] if args.size() > 3 else "animundi"
	var step := int(args[4]) if args.size() > 4 else 20
	var world := WorldGenerator.generate(s)
	var sim: Node2D = load("res://sim/Simulation.cs").new()
	root.add_child(sim)
	sim.Start(world, PackedStringArray(Biomes.NAMES))
	var flora := Flora.place(world)
	sim.LoadPlants(flora.id, flora.pos, flora.flip, flora.scale)
	sim.SpawnNatural(world.size() / 300)
	sim.SetMindEndpoint("")
	sim.StartPeoples(peoples, 12)
	var told: Array = []
	var done := 0
	var started := Time.get_ticks_msec()
	while done < years:
		sim.RunYears(float(step), 6)
		done += step
		var events: PackedStringArray = sim.TakeTaggedEvents()
		for n in range(0, events.size(), 2):
			if events[n] == "ages" or String(events[n + 1]).contains("bomb") or String(events[n + 1]).contains(" era begins"):
				told.append(events[n + 1])
		var line := PackedStringArray()
		for k in sim.ProgressTable():
			line.append("%s %s %d%%" % [k.name, k.age_name, int(k.knowledge * 100.0)])
		var air: Dictionary = sim.WorldAges()
		print("year %d (%ds): %d people, %d kingdoms | %s | %.1f°, smog %d zones, %d bombs, %d rockets, %s" % [sim.Year(),
				(Time.get_ticks_msec() - started) / 1000, sim.PeopleCount(), sim.KingdomCount(), "; ".join(line), air.warming,
				air.smoggy_zones, air.nukes, air.rockets, air.era.name])
	print("\nPEOPLES")
	for k in sim.ProgressTable():
		print("  %s (%s): %s, +%d a year, peak %s" % [k.name, k.people, k.age_name, int(k.gain), k.peak_name])
		for kind in k.lineage:
			print("    %s: %s" % [kind, k.lineage[kind]])
		if k.feats != "":
			print("    " + String(k.feats).replace("\n", "\n    "))
	print("\nAGES (%d told, the last 40)" % told.size())
	for line in told.slice(-40):
		print("  " + line)
	sim.queue_free()
	quit()
