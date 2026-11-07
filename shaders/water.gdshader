// Water: colour from the real depth (water surface minus ground, read from the heightmap),
// reflections of the shores, trees and people (a mirrored camera renders them into `reflection`;
// see main.gd), moving glints, and foam breathing along the shore. Unshaded, in flat colour bands.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/cel.gdshaderinc"

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(256.0, 256.0);
uniform vec4 shallow_color : source_color = vec4(0.36, 0.78, 0.95, 1.0);
uniform vec4 deep_color : source_color = vec4(0.08, 0.27, 0.6, 1.0);
uniform vec4 foam_color : source_color = vec4(0.93, 0.98, 1.0, 1.0);
// Depth (in tiles) at which water reaches its deepest colour.
uniform float full_depth = 1.5;
uniform bool has_reflection = false;
uniform sampler2D reflection : filter_nearest, repeat_disable;
uniform float reflection_strength = 0.45;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz + 0.5) / map_size;
	float ground = texture(heightmap, uv).r;
	float depth = max(world_pos.y - ground, 0.0);
	// Towards and past the map edges the sea becomes open ocean, so the map has no visible border.
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	depth = mix(full_depth * 1.5, depth, smoothstep(0.0, 0.1, edge));
	float band = floor(clamp(depth / full_depth, 0.0, 1.0) * 4.0 + 0.5) / 4.0;
	vec3 c = mix(shallow_color.rgb, deep_color.rgb, band);

	if (has_reflection) {
		// The mirrored camera's image is upside down: read it at the flipped screen position,
		// shifted by a small horizontal ripple in whole render pixels.
		vec2 px = 1.0 / vec2(textureSize(reflection, 0));
		float ripple = floor(sin(world_pos.z * 6.0 + TIME * 2.0) * 1.5 + 0.5);
		vec4 r = texture(reflection, vec2(SCREEN_UV.x + ripple * px.x, 1.0 - SCREEN_UV.y));
		c = mix(c, r.rgb * 0.85 + c * 0.15, r.a * reflection_strength);
	}

	// Glints: short horizontal streaks drifting with the waves.
	vec2 cell = floor(world_pos.xz * vec2(1.5, 4.0));
	float wave = sin(world_pos.x * 0.7 + TIME * 1.4 + sin(world_pos.z * 0.5 + TIME * 0.6) * 2.0)
			* sin(world_pos.z * 1.1 - TIME * 0.9);
	float glint = step(0.93, wave) * step(0.75, hash12(cell + floor(TIME * 2.0)));
	c = mix(c, foam_color.rgb, glint * 0.55 * (1.0 - band * 0.5));

	// Foam: a band along the shore that swells and shrinks.
	float swell = 0.1 + 0.08 * sin(TIME * 1.8 + (world_pos.x + world_pos.z) * 0.6);
	float foam = step(depth, swell);
	c = mix(c, foam_color.rgb, foam * 0.85);

	ALBEDO = c;
}
