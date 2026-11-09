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
		for k in sim.KingdomTable():
			print("   KINGDOM %s (%s) %s · capital %s · %d villages, %d people, %d soldiers · wars: %s · allies: %s" % [
				k.name, k.people, k.ruler, k.capital, k.villages, k.population, k.soldiers, k.wars, k.allies])
		for p in sim.PlanTable():
			print("   PLAN %s: %s → %s (%d%%)" % [p.kind, p.kingdom, p.target, int(p.progress * 100)])
		print("   trade routes: %d, war deaths %d, conquests %d, landings %d" % [sim.TradeTable().size(), sim.WarDeaths, sim.Conquests, sim.Landings])
		for e in sim.TakeEvents():
			print("   ", e)
	print("inventions (%d, %d rejected):" % [sim.InventionTable().size(), sim.InventionsRejected])
	for inv in sim.InventionTable().slice(0, 25):
		print("   %s %s (%s) by the %s, year %d%s · %s · known in %d villages%s" % [
			inv.kind, inv.name, inv.mind, inv.people, inv.year, (" · improves " + inv.parent) if inv.parent != "" else "",
			inv.effects, inv.villages, " · LOST" if inv.lost else ""])
	print("life: ", sim.LifeStats())
	if sim.has_method("DeathNotes"):
		var notes: Dictionary = sim.DeathNotes()
		var keys := notes.keys()
		keys.sort_custom(func(a, b): return notes[a] > notes[b])
		for k in keys.slice(0, 15):
			print("   ", k, ": ", notes[k])
	quit()
