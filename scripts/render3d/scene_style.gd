## The shared look of every 3D view (game and asset sheets): environment, sun and materials,
## following docs/ART_DIRECTION.md. Change the look here and it changes everywhere.
## Palette colours are given to the shaders as they are (no linear conversion): sun and ambient are
## tuned so a lit flat surface shows its palette colour and a shaded one about 60% of it.
extends RefCounted

const TerrainShader = preload("res://shaders/terrain.gdshader")
const WaterShader = preload("res://shaders/water.gdshader")
const FoliageShader = preload("res://shaders/foliage.gdshader")
const OutlineShader = preload("res://shaders/outline.gdshader")
const GrassShader = preload("res://shaders/grass.gdshader")

## Outlines are hidden when a render pixel covers more ground than this (trees are then specks).
const OUTLINE_MAX_PIXEL := 0.16

var terrain := ShaderMaterial.new()
var water := ShaderMaterial.new()
## Trees and bushes: ragged leafy edges, dithered light.
var leafy := ShaderMaterial.new()
## Rocks, cacti, mushrooms, dead trees, people, animals: plain surfaces.
var solid := ShaderMaterial.new()
var outline := ShaderMaterial.new()
var grass := ShaderMaterial.new()
var flower := ShaderMaterial.new()


func _init() -> void:
	terrain.shader = TerrainShader
	water.shader = WaterShader
	leafy.shader = FoliageShader
	solid.shader = FoliageShader
	solid.set_shader_parameter("leafy", false)
	outline.shader = OutlineShader
	leafy.next_pass = outline
	solid.next_pass = outline
	grass.shader = GrassShader
	flower.shader = GrassShader
	flower.set_shader_parameter("flower", true)


## Adds the environment (sky colour, soft bluish ambient) and the warm sun to `parent`.
func add_lighting(parent: Node, background := Color("#2f6fa8")) -> DirectionalLight3D:
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


## Outlines about one render pixel wide for a camera whose pixel covers `world_per_pixel` units.
func update_outline(world_per_pixel: float) -> void:
	outline.set_shader_parameter("width", world_per_pixel * 0.9 if world_per_pixel < OUTLINE_MAX_PIXEL else 0.0)
