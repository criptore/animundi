## Weather over the screen (1.0): rain in rainy eras, snow in cold ones and in a nuclear winter
## (grey ash), drifting motes of light in magical eras. Particles on a canvas layer under the
## interface; the settings switch them off.
extends CanvasLayer

var enabled := true
var kind := ""
var _particles := CPUParticles2D.new()


func _init() -> void:
	layer = 0
	_particles.emitting = false
	_particles.amount = 220
	_particles.lifetime = 2.5
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.local_coords = false
	add_child(_particles)


## The weather to show: "rain", "snow", "ash", "motes" or "" (none).
func set_weather(what: String) -> void:
	if not enabled:
		what = ""
	if what == kind:
		return
	kind = what
	_particles.emitting = what != ""
	if what == "":
		return
	var size := Vector2(1920, 1080)
	if is_inside_tree():
		size = get_viewport().get_visible_rect().size
	_particles.position = Vector2(size.x / 2.0, -20.0)
	_particles.emission_rect_extents = Vector2(size.x * 0.6, 10.0)
	match what:
		"rain":
			_particles.amount = 260
			_particles.lifetime = 1.1
			_particles.direction = Vector2(-0.15, 1.0)
			_particles.spread = 2.0
			_particles.initial_velocity_min = 700.0
			_particles.initial_velocity_max = 900.0
			_particles.gravity = Vector2(0, 300)
			_particles.scale_amount_min = 1.0
			_particles.scale_amount_max = 2.0
			_particles.color = Color(0.7, 0.8, 1.0, 0.45)
		"snow", "ash":
			_particles.amount = 180
			_particles.lifetime = 6.0
			_particles.direction = Vector2(0.2, 1.0)
			_particles.spread = 25.0
			_particles.initial_velocity_min = 60.0
			_particles.initial_velocity_max = 140.0
			_particles.gravity = Vector2(10, 30)
			_particles.scale_amount_min = 2.0
			_particles.scale_amount_max = 4.0
			_particles.color = Color(0.95, 0.97, 1.0, 0.75) if what == "snow" else Color(0.45, 0.43, 0.42, 0.7)
		"motes":
			_particles.amount = 70
			_particles.lifetime = 7.0
			_particles.direction = Vector2(0, 1)
			_particles.spread = 180.0
			_particles.initial_velocity_min = 15.0
			_particles.initial_velocity_max = 50.0
			_particles.gravity = Vector2(0, 8)
			_particles.scale_amount_min = 2.0
			_particles.scale_amount_max = 3.0
			_particles.color = Color(0.85, 0.7, 1.0, 0.8)
			_particles.emission_rect_extents = Vector2(size.x * 0.6, size.y * 0.5)
			_particles.position = Vector2(size.x / 2.0, size.y / 2.0)
	_particles.restart()
