## The tilt view (prototype): the running game seen from a tilted perspective camera, in the
## spirit of Cult of the Lamb, without changing the simulation.
##
## - Ground: a stepped mesh (tilt_terrain.gd) that reads the flat map's own textures.
## - Sprites: the simulation already fills MultiMeshes for the flat view (sim/Draw.cs). The same
##   MultiMesh resources are shown here through MultiMeshInstance3D nodes, with a shader that
##   stands each quad up on the ground (shaders/tilt_sprite.gdshader). Nothing is copied.
## - Light: no engine light. A tint for the hour, cloud shadows, the villages' fires and the
##   windows of their homes (BuildingTable, the nearest ones to the camera), computed
##   in the shaders. The 3D world is drawn in its own viewport, shown on screen through one
##   shader that adds the miniature blur, the vignette and the tint (reading the screen back
##   instead cost 4 ms of GPU: the copy of the whole frame).
##
## - Zoom: the closer the camera, the more tilted the view and the richer the picture (lights,
##   reflections on water, blur); the further, the more it looks straight down at the plain map,
##   and the passes that no longer show are switched off (TiltCamera.closeness).
##
## Add it to the main scene and call setup(main) once the world exists; set_enabled(false) gives
## the flat view back. Limits of the prototype: a regenerated world or a tile changing level needs
## setup again; picking and village banners still belong to the flat view.
extends Node3D

const TiltTerrain = preload("res://scripts/render_tilt/tilt_terrain.gd")
const TiltCamera = preload("res://scripts/render_tilt/tilt_camera.gd")
const SpriteAtlas = preload("res://scripts/render2d/sprite_atlas.gd")
const SpriteBatch = preload("res://scripts/render2d/sprite_batch.gd")
const Biomes = preload("res://scripts/world/biomes.gd")

const MAX_LIGHTS := 32
## Lights further than this from the centre of the view are left out, in tiles.
const LIGHTS_WITHIN := 70.0
## Reach (tiles) and brightness of what glows: the bonfire, and the windows of finished homes
## and great buildings (ids of data/buildings.json). A burning building glows like a big fire.
const GLOWS := {
	"bonfire": Vector2(11.0, 0.9), "hut": Vector2(3.0, 0.4), "house": Vector2(3.4, 0.45), "stone_house": Vector2(3.4, 0.45),
	"big_house": Vector2(4.0, 0.5), "town_hall": Vector2(5.0, 0.55), "temple": Vector2(5.0, 0.55), "library": Vector2(4.2, 0.5),
	"barracks": Vector2(4.2, 0.45),
}
const BLAZE := Vector2(9.0, 1.4)
## The hours of the day: tint of the light, strength of the fires, vignette, haze colour, tint of
## the final image, strength of the shadows and of the cloud shadows.
const HOURS := [
	{t = 0.00, name = "dawn", ambient = Vector3(0.96, 0.80, 0.80), fires = 0.35, vignette = 0.36, haze = Vector3(0.98, 0.78, 0.72), tint = Vector3(1.03, 0.99, 0.98), shadow = 0.7, cloud = 0.5},
	{t = 0.30, name = "noon", ambient = Vector3(1.04, 1.02, 0.96), fires = 0.0, vignette = 0.22, haze = Vector3(0.74, 0.90, 0.98), tint = Vector3(1.0, 1.0, 1.0), shadow = 1.0, cloud = 1.0},
	{t = 0.58, name = "afternoon", ambient = Vector3(1.06, 0.88, 0.68), fires = 0.2, vignette = 0.32, haze = Vector3(1.0, 0.80, 0.56), tint = Vector3(1.04, 1.0, 0.95), shadow = 0.95, cloud = 0.9},
	{t = 0.80, name = "dusk", ambient = Vector3(0.82, 0.70, 0.84), fires = 0.9, vignette = 0.40, haze = Vector3(0.42, 0.32, 0.58), tint = Vector3(1.04, 0.98, 1.02), shadow = 0.6, cloud = 0.4},
	{t = 1.00, name = "night", ambient = Vector3(0.34, 0.38, 0.62), fires = 1.15, vignette = 0.56, haze = Vector3(0.10, 0.12, 0.28), tint = Vector3(1.0, 1.0, 1.05), shadow = 0.45, cloud = 0.2},
]

var camera := TiltCamera.new()
## 0 = dawn, 0.3 = noon, 0.8 = dusk, 1 = night (see HOURS).
var time_of_day := 0.78
var enabled := true
## The miniature blur, the vignette and the tint (off: the raw 3D image).
var effects := true

var _main: Node
var _terrain := ShaderMaterial.new()
var _sprites := ShaderMaterial.new()
var _shadows := ShaderMaterial.new()
var _post := ShaderMaterial.new()
var _reflections := ShaderMaterial.new()
var _reflection_nodes: Array[MultiMeshInstance3D] = []
## The look of the current hour (see HOURS), before the camera's distance tones it down.
var _look := {}
var _post_layer := CanvasLayer.new()
var _container := SubViewportContainer.new()
var _viewport := SubViewport.new()
var _environment := Environment.new()
var _lights_wait := 0.0


func _init() -> void:
	_terrain.shader = preload("res://shaders/tilt_terrain.gdshader")
	_sprites.shader = preload("res://shaders/tilt_sprite.gdshader")
	_shadows.shader = preload("res://shaders/tilt_shadow.gdshader")
	_post.shader = preload("res://shaders/tilt_post.gdshader")
	_reflections.shader = preload("res://shaders/tilt_reflection.gdshader")


## Builds the view over `main` (scripts/main.gd), which must already hold a world.
func setup(main: Node) -> void:
	_main = main
	for child in get_children():
		child.queue_free()
	# The 3D world lives in its own viewport, under a canvas layer behind the flat view's.
	_post_layer = CanvasLayer.new()
	_post_layer.layer = -1
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_viewport = SubViewport.new()
	_viewport.handle_input_locally = false
	_container.add_child(_viewport)
	_post_layer.add_child(_container)
	add_child(_post_layer)
	var space := Node3D.new()
	_viewport.add_child(space)
	var world = main.world
	var map = main._map
	var size := Vector2(world.width, world.height)
	for m in [_terrain, _sprites, _shadows, _reflections]:
		m.set_shader_parameter("map_size", size)
		m.set_shader_parameter("data", map._data_tex)
	_reflections.set_shader_parameter("atlas", SpriteAtlas.shared().texture)
	_reflection_nodes.clear()
	_terrain.set_shader_parameter("colors", map.texture)
	_terrain.set_shader_parameter("ground", map._ground_tex)
	_sprites.set_shader_parameter("atlas", SpriteAtlas.shared().texture)
	_shadows.set_shader_parameter("shadow_texture", SpriteBatch.shadow_texture())

	for mesh in TiltTerrain.build(world):
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = _terrain
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		space.add_child(inst)
	# A sea bed all around the map, so the horizon is water.
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size * 6.0
	sea.mesh = plane
	sea.position = Vector3(size.x / 2.0, TiltTerrain.SEA - 0.02, size.y / 2.0)
	sea.material_override = _terrain
	space.add_child(sea)

	# The simulation's batches, shadows first.
	var everywhere := AABB(Vector3(-20, -5, -20), Vector3(size.x + 40, 40, size.y + 40))
	var atlas: Texture2D = SpriteAtlas.shared().texture
	var batches: Array[MultiMeshInstance2D] = []
	for child in main._sim.get_children():
		if child is MultiMeshInstance2D:
			batches.append(child)
		else:
			for grandchild in child.get_children():
				if grandchild is MultiMeshInstance2D:
					batches.append(grandchild)
	for pass_shadows in [true, false]:
		for batch in batches:
			if (batch.texture != atlas) != pass_shadows:
				continue
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = batch.multimesh
			inst.material_override = _shadows if pass_shadows else _sprites
			inst.custom_aabb = everywhere
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			space.add_child(inst)
			if not pass_shadows:
				# The same batch once more, mirrored on the water (shown close up only).
				var mirror := MultiMeshInstance3D.new()
				mirror.multimesh = batch.multimesh
				mirror.material_override = _reflections
				mirror.custom_aabb = everywhere
				mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				space.add_child(mirror)
				_reflection_nodes.append(mirror)

	_environment.background_mode = Environment.BG_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var env := WorldEnvironment.new()
	env.environment = _environment
	space.add_child(env)
	camera = TiltCamera.new()
	camera.bounds = size
	space.add_child(camera)
	camera.look_at_tile(size / 2.0, 34.0)

	# Right after the main scene in the tree: its _process runs first, then this one, then the
	# simulation's (which fills the batches).
	if get_parent() == main:
		main.move_child(self, 0)
	set_enabled(enabled)
	set_time(time_of_day)


## Shows the tilt view, or gives the flat view back.
func set_enabled(on: bool) -> void:
	enabled = on
	_post_layer.visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if _main == null:
		return
	_main._map.visible = not on
	_main._sim.visible = not on
	if on:
		camera.make_current()
		_container.material = _post if effects else null
		# Village banners follow the flat camera: far enough away, the flat view draws none.
		_main._camera.zoom = Vector2(0.05, 0.05)


## The viewport the 3D world is drawn in (tools: measuring its render time).
func viewport_rid() -> RID:
	return _viewport.get_viewport_rid()


## Sets the hour (0 dawn, 0.3 noon, 0.8 dusk, 1 night). Returns the name of the nearest hour.
func set_time(t: float) -> String:
	time_of_day = clampf(t, 0.0, 1.0)
	var i := 0
	while i < HOURS.size() - 2 and time_of_day > HOURS[i + 1].t:
		i += 1
	var a: Dictionary = HOURS[i]
	var b: Dictionary = HOURS[i + 1]
	var k := smoothstep(a.t, b.t, time_of_day)
	_look = {
		ambient = a.ambient.lerp(b.ambient, k), haze = a.haze.lerp(b.haze, k), tint = a.tint.lerp(b.tint, k),
		fires = lerpf(a.fires, b.fires, k), cloud = lerpf(a.cloud, b.cloud, k), shadow = lerpf(a.shadow, b.shadow, k),
		vignette = lerpf(a.vignette, b.vignette, k),
	}
	_apply_look()
	return a.name if k < 0.5 else b.name


## Sends the hour's look to the shaders, toned down by the camera's distance: far away, the plain
## colours of the flat map (no tint, no fires, no clouds, no haze) and nothing over the image.
func _apply_look() -> void:
	if _look.is_empty():
		return
	var near := camera.closeness()
	var plain := Vector3.ONE
	var sea := Biomes.COLORS[Biomes.DEEP_WATER].darkened(0.4)
	var haze: Vector3 = Vector3(sea.r, sea.g, sea.b).lerp(_look.haze, near)
	# The haze starts beyond the place looked at, and moves out of sight as the camera rises.
	var haze_from: float = camera.distance * 1.4 + 14.0 + (1.0 - near) * 5000.0
	for m in [_terrain, _sprites, _shadows, _reflections]:
		m.set_shader_parameter("ambient", plain.lerp(_look.ambient, near))
		m.set_shader_parameter("fog_color", haze)
		m.set_shader_parameter("fog_range", Vector2(haze_from, haze_from + 60.0 + camera.distance * 1.5))
		m.set_shader_parameter("light_power", _look.fires * near)
		m.set_shader_parameter("cloud", _look.cloud * near)
	_shadows.set_shader_parameter("strength", lerpf(1.0, _look.shadow, near))
	_reflections.set_shader_parameter("strength", near)
	for node in _reflection_nodes:
		node.visible = near > 0.03
	# The blur belongs to the close, tilted view; far away the image is shown as it is.
	_post.set_shader_parameter("blur", near * minf(1.3, 30.0 / camera.distance))
	_post.set_shader_parameter("vignette", _look.vignette * near)
	_post.set_shader_parameter("tint", plain.lerp(_look.tint, near))
	_post.set_shader_parameter("saturation", lerpf(1.0, 1.12, near))
	_container.material = _post if effects and near > 0.03 else null
	_environment.background_color = Color(haze.x, haze.y, haze.z)


func _input(event: InputEvent) -> void:
	if enabled and camera.handle_input(event):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not enabled or _main == null:
		return
	var sim = _main._sim
	# Keep the simulation in its "far" drawing mode: plants in their strips (rebuilt only when
	# they change), every creature and building in the unit batch. The 2D shader's dots and its
	# view culling are the flat view's business.
	sim.SetZoom(1.0)
	sim.SetView(camera.target * 8.0, Vector2(1e7, 1e7))
	_terrain.set_shader_parameter("frost", sim.Coldness())
	_sprites.set_shader_parameter("lean", camera.sprite_lean())
	_sprites.set_shader_parameter("stretch", camera.sprite_stretch())
	_reflections.set_shader_parameter("reach", 1.0 / sin(deg_to_rad(camera.pitch())))
	_apply_look()
	_lights_wait -= delta
	if _lights_wait <= 0.0:
		_lights_wait = 1.0
		_update_lights()


## The warm lights near the centre of the view: fires and the windows of finished homes, the
## nearest first when there are too many. None when the camera is too far for them to show.
func _update_lights() -> void:
	var found := []
	if camera.closeness() > 0.03 and _look.get("fires", 0.0) > 0.0:
		for b in _main._sim.BuildingTable():
			var glow: Vector2 = BLAZE if b.burning else GLOWS.get(b.id, Vector2.ZERO)
			if glow.x == 0.0 or not (b.done or b.burning):
				continue
			var at := Vector2(b.x + 0.5, b.y + 0.5)
			var far := camera.target.distance_squared_to(at)
			if far < LIGHTS_WITHIN * LIGHTS_WITHIN:
				found.append([far, at, glow])
		found.sort_custom(func(p, q): return p[0] < q[0])
	var world = _main.world
	var lights: Array[Vector4] = []
	var gains := PackedFloat32Array()
	for entry in found.slice(0, MAX_LIGHTS):
		var at: Vector2 = entry[1]
		var glow: Vector2 = entry[2]
		var i: int = world.index(clampi(int(at.x), 0, world.width - 1), clampi(int(at.y), 0, world.height - 1))
		var ground: float = maxf(0.0, (world.level[i] - 2) * TiltTerrain.STEP)
		# A fire burns at the middle of its tile; a home lights the ground before its door.
		lights.append(Vector4(at.x, ground + 0.6, at.y + (0.0 if glow.x > 8.0 else 0.6), glow.x))
		gains.append(glow.y)
	var count := lights.size()
	while lights.size() < MAX_LIGHTS:
		lights.append(Vector4(0, -999, 0, 1))
		gains.append(0.0)
	for m in [_terrain, _sprites, _shadows, _reflections]:
		m.set_shader_parameter("light_count", count)
		m.set_shader_parameter("lights", lights)
		m.set_shader_parameter("light_gain", gains)
