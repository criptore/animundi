## Generates a world and saves its maps as PNG files, without opening a window.
##   godot --headless --path . --script res://tools/render_preview.gd -- <seed> <size> <out_dir>
## Writes <out_dir>/<seed>_biomes.png and one PNG per data layer, and prints biome shares.
extends SceneTree

const WorldSettings = preload("res://scripts/world/world_settings.gd")
const WorldGenerator = preload("res://scripts/world/world_generator.gd")
const Biomes = preload("res://scripts/world/biomes.gd")
const MapRenderer = preload("res://scripts/render/map_renderer.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var s := WorldSettings.new()
	s.seed_text = args[0] if args.size() > 0 else "animundi"
	s.set_size(int(args[1]) if args.size() > 1 else 256)
	var out_dir: String = args[2] if args.size() > 2 else "user://previews"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var world := WorldGenerator.generate(s)
	print("stages (ms): ", world.stage_ms)
	var counts := {}
	for i in world.size():
		counts[world.biome[i]] = counts.get(world.biome[i], 0) + 1
	for b in Biomes.COUNT:
		if counts.has(b):
			print("  %-14s %5.1f%%" % [Biomes.NAMES[b], 100.0 * counts[b] / world.size()])

	var r := MapRenderer.new()
	r.render_biomes(world).save_png("%s/%s_biomes.png" % [out_dir, s.seed_text])
	for layer in MapRenderer.LAYERS:
		if layer != "Biomes":
			var img := r.render_layer(world, layer)
			img.resize(world.width * 2, world.height * 2, Image.INTERPOLATE_NEAREST)
			img.save_png("%s/%s_%s.png" % [out_dir, s.seed_text, layer.to_lower()])
	quit()
