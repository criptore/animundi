// A 2D pixel-art sprite standing in the 3D world (upright quad facing the fixed camera).
// Lit like the ground it stands on (normal up), so it darkens in the shade of trees and clouds and
// shows its exact sheet colours in full sun. Pixels outside the drawing are cut, also in the
// shadow pass, so it casts a shadow of its own shape. Plants sway in the wind (`sway`).
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;
uniform bool effects = true;
// Wind sway of the top of the sprite, in world units (0 = none).
uniform float sway = 0.0;

varying vec3 world_pos;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (effects && sway > 0.0) {
		float top = 1.0 - UV.y;
		float gust = sin(TIME * 1.3 + origin.x * 0.4 + origin.z * 0.3) + 0.5 * sin(TIME * 2.9 + origin.x);
		// Whole steps of a fraction of a pixel, so the motion stays pixel-like.
		VERTEX.x += floor(gust * 2.0) / 2.0 * sway * top * top;
	}
	NORMAL = vec3(0.0, 1.0, 0.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(sprite, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * (effects ? cloud_shade(world_pos.xz, TIME, 8.0) : 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, 0.5);
}
