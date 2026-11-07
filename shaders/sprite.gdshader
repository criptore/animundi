// A 2D pixel-art sprite standing in the 3D world (upright quad facing the fixed camera).
// Lit like the ground it stands on (normal up), so it darkens in the shade of trees and
// shows its exact sheet colours in full sun. Pixels outside the drawing are cut, also in the
// shadow pass, so it casts a shadow of its own shape.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;

varying vec3 world_pos;

void vertex() {
	NORMAL = vec3(0.0, 1.0, 0.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(sprite, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, 0.5);
}
