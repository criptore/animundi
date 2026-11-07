## The shared look of every 3D view (game and asset sheets): environment, sun and materials,
## following docs/ART_DIRECTION.md. Change the look here and it changes everywhere.
## Rendered with Forward+: palette colours are sRGB, vertex colours are converted to linear; sun and
## ambient are tuned (measured) so a lit flat surface shows its palette colour.
extends RefCounted

const TerrainShader = preload("res://shaders/terrain.gdshader")
const WaterShader = preload("res://shaders/water.gdshader")
const SpriteShader = preload("res://shaders/sprite.gdshader")
const StylizerShader = preload("res://shaders/vendor/pixelart_stylizer.gdshader")
const GrassShader = preload("res://shaders/grass.gdshader")
const GRASS_ATLAS := preload("res://assets/vendor/grass_atlas.png")

## Sun orientation (front left, warm afternoon): shared by the light and the shaders that need its
## direction (cloud shadows).
const SUN_ROTATION := Vector3(-42.0, -65.0, 0.0)
const SpriteLibrary = preload("res://scripts/render3d/sprite_library.gd")

var terrain := ShaderMaterial.new()
var water := ShaderMaterial.new()
## Leo Peltola's 3D pixel-art outline & highlight pass (shaders/vendor), drawn on a quad just in
## front of the camera: dark outlines where depth jumps, light highlights where surfaces turn.
var stylizer := ShaderMaterial.new()
var grass := ShaderMaterial.new()
## Scrolling noise read by every lit shader for cloud shadows (shaders/cel.gdshaderinc).
var clouds := _cloud_texture()
var _sprites := {}


func _init() -> void:
	terrain.shader = TerrainShader
	water.shader = WaterShader
	water.set_shader_parameter("shallow_color", Color("#49ccdf"))
	water.set_shader_parameter("deep_color", Color("#1b4479"))
	stylizer.shader = StylizerShader
	grass.shader = GrassShader
	grass.set_shader_parameter("alpha_texture", GRASS_ATLAS)
	for m in [terrain, water, grass]:
		_lit(m)


## Direction the sunlight travels, in world space.
static func sun_direction() -> Vector3:
	return -Basis.from_euler(SUN_ROTATION * PI / 180.0).z


## Gives a lit material the shared cloud texture and sun direction.
func _lit(m: ShaderMaterial) -> void:
	m.set_shader_parameter("cloud_texture", clouds)
	m.set_shader_parameter("sun_direction", sun_direction())


## Soft, tileable noise for the clouds (as in Robert-K/godot-3d-pixel-art).
static func _cloud_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.0019
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.525])
	ramp.colors = PackedColorArray([Color(0.26, 0.26, 0.26), Color.WHITE])
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.seamless_blend_skirt = 0.3
	tex.generate_mipmaps = false
	tex.color_ramp = ramp
	tex.noise = noise
	return tex


## Material drawing one sprite (shared by every instance of it).
func sprite(id: String) -> ShaderMaterial:
	if not _sprites.has(id):
		var m := ShaderMaterial.new()
		m.shader = SpriteShader
		m.set_shader_parameter("sprite", SpriteLibrary.texture(id))
		_lit(m)
		_sprites[id] = m
	return _sprites[id]


## Adds the stylizer pass in front of `camera` (it must be kept sized with update_stylizer).
## It sits on its own render layer so other cameras (reflections) can leave it out.
func add_stylizer(camera: Camera3D, layer: int) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	quad.mesh = plane
	quad.material_override = stylizer
	quad.layers = layer
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A plane facing the camera, just past its near plane.
	quad.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, -camera.near - 0.5))
	camera.add_child(quad)
	return quad


## Keeps the stylizer quad covering the whole view of an orthographic camera.
func update_stylizer(quad: MeshInstance3D, camera: Camera3D, aspect: float) -> void:
	(quad.mesh as PlaneMesh).size = Vector2(camera.size * aspect, camera.size) * 1.2


## Adds the environment (sky colour, soft bluish ambient) and the warm sun to `parent`.
func add_lighting(parent: Node, background := Color("#1b4479")) -> DirectionalLight3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Bluish ambient: shadows turn cool and soft instead of black (cosy look).
	env.ambient_light_color = Color(0.78, 0.82, 0.95)
	env.ambient_light_energy = 0.62
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)

	# Warm afternoon sun from the front left: the sides facing the camera are lit, and shadows
	# fall to the right of every tree and rock.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = SUN_ROTATION
	sun.light_energy = 0.85
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
