// A 2D pixel-art sprite standing in the 3D world (upright quad facing the fixed camera).
// The whole sprite is lit as the ground point at its base (technique from Robert-K/godot-3d-pixel-art,
// MIT, see shaders/vendor/README.md): it is entirely in sun or entirely in the shade of a tree or a
// cloud, never patchy, and shows its exact sheet colours in full sun. Pixels outside the drawing are
// cut, also in the shadow pass, so it casts a shadow of its own shape.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/cel.gdshaderinc"

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;

varying vec3 base_world;

void vertex() {
	// MODEL_MATRIX includes the MultiMesh instance transform: its origin is the sprite's foot.
	// The light point is moved a little towards the sun, so the sprite never shades itself.
	base_world = MODEL_MATRIX[3].xyz + vec3(0.0, 0.1, 0.0) - normalize(sun_direction) * 0.35;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 c = texture(sprite, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Light (and shadow-map lookups) for the whole sprite happen at its base.
	LIGHT_VERTEX = (VIEW_MATRIX * vec4(base_world, 1.0)).xyz;
}

void light() {
	float amount = dot(NORMAL, LIGHT) + (ATTENUATION - 1.0) - cloud_shadow(base_world, TIME);
	DIFFUSE_LIGHT += cel_light(amount, LIGHT_COLOR);
}
