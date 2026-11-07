## The shared look of every 3D view (game and asset sheets): environment, sun and materials,
## following docs/ART_DIRECTION.md. Change the look here and it changes everywhere.
## Palette colours are given to the shaders as they are (no linear conversion): sun and ambient are
## tuned so a lit flat surface shows its palette colour and a shaded one about 60% of it.
extends RefCounted

const TerrainShader = preload("res://shaders/terrain.gdshader")
const WaterShader = preload("res://shaders/water.gdshader")
const SpriteShader = preload("res://shaders/sprite.gdshader")
const PostShader = preload("res://shaders/post.gdshader")
const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")

## Wind sway (world units at the top of the sprite) by sprite group; others stand still.
const SWAY := {"trees": 0.05, "plants": 0.03}
const STILL := ["plants/Rock", "plants/Boulder", "plants/Grassy_rock", "plants/Cactus"]

var terrain := ShaderMaterial.new()
var water := ShaderMaterial.new()
## Final pass on the low-resolution render (light shafts, warm grade, vignette).
var post := ShaderMaterial.new()
var effects := true
var _sprites := {}


func _init() -> void:
	terrain.shader = TerrainShader
	water.shader = WaterShader
	water.set_shader_parameter("shallow_color", Color("#49ccdf"))
	water.set_shader_parameter("deep_color", Color("#1b4479"))
	post.shader = PostShader


## Material drawing one sprite (shared by every instance of it).
func sprite(id: String) -> ShaderMaterial:
	if not _sprites.has(id):
		var m := ShaderMaterial.new()
		m.shader = SpriteShader
		m.set_shader_parameter("sprite", SpriteLibrary.texture(id))
		m.set_shader_parameter("sway", 0.0 if id in STILL else SWAY.get(id.get_slice("/", 0), 0.0))
		m.set_shader_parameter("effects", effects)
		_sprites[id] = m
	return _sprites[id]


## Turns the shader effects (wind, clouds, outlines, light shafts, grade) on or off everywhere.
func set_effects(on: bool) -> void:
	effects = on
	for m in [terrain, water, post] + _sprites.values():
		m.set_shader_parameter("effects", on)


## Adds the environment (sky colour, soft bluish ambient) and the warm sun to `parent`.
func add_lighting(parent: Node, background := Color("#1b4479")) -> DirectionalLight3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Bluish ambient: shadows turn cool and soft instead of black (cosy look).
	env.ambient_light_color = Color(0.62, 0.72, 0.95)
	env.ambient_light_energy = 0.21
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)

	# Warm afternoon sun from the front left: the sides facing the camera are lit, and shadows
	# fall to the right of every tree and rock.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -65.0, 0.0)
	sun.light_energy = 0.47
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 700.0
	parent.add_child(sun)
	return sun


## Adds a MultiMesh of one sprite to `parent`.
func add_sprites(parent: Node, id: String, multimesh: MultiMesh, cast_shadow := true) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = multimesh
	mmi.material_override = sprite(id)
	if not cast_shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi
