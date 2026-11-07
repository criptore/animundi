// Grass tufts and flowers: camera-facing quads (the camera never rotates) cut into a few pixel
// blades, or a stem and a flower head. They sway in the wind and are lit like the ground (normal
// pointing up), so they blend into it.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"

uniform bool flower = false;
uniform vec4 stem_color : source_color = vec4(0.42, 0.62, 0.3, 1.0);
uniform float wind = 0.07;

varying vec3 world_pos;
varying vec3 origin;

void vertex() {
	origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float top = 1.0 - UV.y;
	VERTEX.x += sin(TIME * 1.6 + origin.x * 0.35 + origin.z * 0.25) * wind * top;
	NORMAL = vec3(0.0, 1.0, 0.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Work on a coarse grid so blades are made of whole pixels.
	vec2 g = (floor(UV * vec2(9.0, 8.0)) + 0.5) / vec2(9.0, 8.0);
	float hgt = 1.0 - g.y;
	if (!flower) {
		bool blade = false;
		for (int i = 0; i < 4; i++) {
			float r = hash12(origin.xz * 13.0 + float(i) * 7.1);
			float cx = 0.14 + 0.24 * float(i) + (r - 0.5) * 0.1 + (r - 0.5) * 0.25 * hgt;
			float w = 0.1 * (1.0 - hgt * 0.75);
			float tall = 0.45 + 0.55 * hash12(origin.xz * 5.0 + float(i));
			if (abs(g.x - cx) < w && hgt < tall) {
				blade = true;
			}
		}
		if (!blade) {
			discard;
		}
		ALBEDO = COLOR.rgb * (0.88 + 0.28 * hgt);
	} else {
		bool head = distance(g, vec2(0.5, 0.24)) < 0.2;
		bool stem = abs(g.x - 0.5) < 0.07 && hgt < 0.72;
		if (!head && !stem) {
			discard;
		}
		ALBEDO = head ? COLOR.rgb : stem_color.rgb;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, hash12(floor(world_pos.xz * 3.0) + 17.0));
}
