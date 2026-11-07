// Trees, bushes, rocks: the instance colour (COLOR) on foliage parts; parts tagged in UV.x keep a
// fixed colour (1 trunk, 2 mushroom stem, 3 bare wood). Leafy world-space grain and banded light.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"

uniform vec4 trunk_color : source_color = vec4(0.36, 0.23, 0.14, 1.0);
uniform vec4 stem_color : source_color = vec4(0.93, 0.9, 0.82, 1.0);
uniform vec4 bare_color : source_color = vec4(0.24, 0.18, 0.22, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb;
	if (UV.x > 2.5) {
		base = bare_color.rgb;
	} else if (UV.x > 1.5) {
		base = stem_color.rgb;
	} else if (UV.x > 0.5) {
		base = trunk_color.rgb;
	}
	float n = hash12(floor(world_pos.xz * 6.0 + world_pos.y * 4.0));
	ALBEDO = base * (0.86 + 0.28 * n);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR);
}
