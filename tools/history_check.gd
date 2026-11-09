## Runs a long history without a window, in the ultra-fast mode (coarse steps), and reports how
## far the peoples spread: villages, people, land owned. Saves a map of the territories now and then.
##   godot --headless --path . --script res://tools/history_check.gd -- [years] [size] [peoples] [seed] [step_scale] [report_every] [map_every] [out_dir]
## Defaults: 10000 years, size 512 (Large), humans,elves,orcs,dwarves, seed "animundi", coarse steps of 6,
## a report every 100 years, a map every 1000 years into user://history/.
extends SceneTree

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const Flora = preload("res://scripts/world/flora.gd")
const WorldData = preload("res://scripts/world/world_data.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 10000
	var size := int(args[1]) if args.size() > 1 else 512
	var peoples := (args[2] if args.size() > 2 else "humans,elves,orcs,dwarves").split(",")
	var s := WorldSettings.new()
	s.seed_text = args[3] if args.size() > 3 else "animundi"
	var step_scale := int(args[4]) if args.size() > 4 else 6
	var report_every := int(args[5]) if args.size() > 5 else 100
	var map_every := int(args[6]) if args.size() > 6 else 1000
	var out_dir: String = args[7] if args.size() > 7 else "user://history"
	DirAccess.make_dir_recursive_absolute(out_dir)
	s.set_size(size)
	var world := WorldGenerator.generate(s)
	var sim: Node2D = load("res://sim/Simulation.cs").new()
	root.add_child(sim)
	sim.Start(world, PackedStringArray(Biomes.NAMES))
	var flora := Flora.place(world)
	sim.LoadPlants(flora.id, flora.pos, flora.flip, flora.scale)
	sim.SpawnNatural(world.size() / 300)
	print("world %d×%d, seed %s, villages founded: %d" % [world.width, world.height, s.seed_text, sim.StartPeoples(peoples, 12)])
	var start := Time.get_ticks_msec()
	_save_map(sim, world, "%s/year_%05d.png" % [out_dir, 0])
	var done := 0
	while done < years:
		var chunk := mini(report_every, years - done)
		sim.RunYears(chunk, step_scale)
		done += chunk
		var events: PackedStringArray = sim.TakeEvents()
		var founded := 0
		var abandoned := 0
		for e in events:
			founded += 1 if "settlers leave" in e else 0
			abandoned += 1 if "is abandoned" in e else 0
		var line := "year %5d | %5.0f s | %3d villages (+%d -%d) | %6d people | %5d animals | land owned %4.1f%% |" % [
			done, (Time.get_ticks_msec() - start) / 1000.0, sim.VillageCount(), founded, abandoned,
			sim.PeopleCount(), sim.UnitCount() - sim.PeopleCount(), sim.LandOwned() * 100.0]
		var table: Dictionary = sim.PeopleTable()
		for p in table:
			var r: Dictionary = table[p]
			line += " %s %d v %d p %d z (max %d) |" % [p, r.villages, r.people, r.zones, r.biggest]
		print(line)
		if done % map_every == 0 or done == years:
			_save_map(sim, world, "%s/year_%05d.png" % [out_dir, done])
	print("done in %.0f s" % ((Time.get_ticks_msec() - start) / 1000.0))
	quit()


## The world's biomes, faded, with each village's land in its colour, darker borders and buildings.
func _save_map(sim: Node2D, world: WorldData, path: String) -> void:
	var map: PackedInt32Array = sim.TerritoryMap()
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RGB8)
	for y in world.height:
		for x in world.width:
			var i := world.index(x, y)
			var base: Color = Biomes.COLORS[world.biome[i]]
			if not world.is_water(i):
				base = base.lerp(Color(0.85, 0.85, 0.8), 0.35)
			var c := map[i]
			if c != 0:
				var own := Color8((c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255)
				var border := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if world.in_bounds(nx, ny) and (map[world.index(nx, ny)] & ~255) != (c & ~255):
						border = true
				base = own.darkened(0.45) if border else base.lerp(own, 0.6)
				if (c & 255) == 1:
					base = own.darkened(0.6)
			img.set_pixel(x, y, base)
	img.resize(world.width * 2, world.height * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("  map -> ", ProjectSettings.globalize_path(path))
