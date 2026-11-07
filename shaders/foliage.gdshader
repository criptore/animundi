// Trees, bushes, rocks: the instance colour (COLOR) on foliage parts; parts tagged in UV.x keep a
// fixed colour (1 trunk, 2 mushroom stem, 3 bare wood). With `leafy`, foliage edges break up into
// pixel leaves and light/shade boundaries are dithered into leaf clusters.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"

uniform bool leafy = true;
uniform vec4 trunk_color : source_color = vec4(0.42, 0.29, 0.2, 1.0);
uniform vec4 stem_color : source_color = vec4(0.95, 0.92, 0.84, 1.0);
uniform vec4 bare_color : source_color = vec4(0.34, 0.27, 0.3, 1.0);
// Leaf cells per world unit.
uniform float leaf_scale = 9.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float leaf_noise() {
	vec3 c = floor(world_pos * leaf_scale);
	return hash12(c.xy + c.z * 31.7);
}

void fragment() {
	vec3 base = COLOR.rgb;
	bool foliage = UV.x < 0.5;
	if (UV.x > 2.5) {
		base = bare_color.rgb;
	} else if (UV.x > 1.5) {
		base = stem_color.rgb;
	} else if (UV.x > 0.5) {
		base = trunk_color.rgb;
	}
	float n = leaf_noise();
	if (leafy && foliage) {
		// Ragged silhouette: pixels near the edge of a clump drop out at random.
		float facing = abs(dot(NORMAL, VIEW));
		if (facing < 0.42 && n > facing * 2.0) {
			discard;
		}
	}
	ALBEDO = base * (foliage && leafy ? 0.9 + 0.2 * n : 0.95 + 0.1 * n);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float d = leafy ? leaf_noise() : 0.5;
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, d);
}
