// Terrain: biome colour (vertex colour) with a fine world-space pixel grain, lit in soft bands
// with shadows, so the low-resolution render reads as pixel art.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/toon.gdshaderinc"

uniform float grain = 0.08;
// Grain cells per tile: the "pixels" painted on the ground.
uniform float grain_scale = 3.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = hash12(floor(world_pos.xz * grain_scale));
	ALBEDO = COLOR.rgb * (1.0 - grain * 0.5 + grain * n);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float d = hash12(floor(world_pos.xz * grain_scale) + 17.0);
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, d);
}
