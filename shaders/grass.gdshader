// Dense billboard grass, adapted from Robert-K/godot-3d-pixel-art (MIT, see shaders/vendor/README.md):
// each instance shows one of 3x3 pixel tufts from an alpha atlas, coloured like the ground under it
// (instance colour), lit as a single point at its base so it blends into the ground, and swaying in
// the wind at a low frame rate, in a few groups, like hand-animated pixel art.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

#include "res://shaders/cel.gdshaderinc"

uniform sampler2D alpha_texture : filter_nearest, repeat_disable;
// Number of wind groups and wind animation frames per second.
uniform int groups = 6;
uniform float fps = 2.0;
uniform float sway = 0.2;

varying vec3 base_world;
varying float r;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

void vertex() {
	base_world = MODEL_MATRIX[3].xyz;
	r = random(base_world.xz);
	float g = floor(r * float(groups)) / float(groups);
	float t = floor((TIME + g * 10.0) * fps) / fps;
	// Sway is stronger at the top (the quad's base is at y = 0).
	VERTEX.x += sin(PI * t) * VERTEX.y * sway;
	NORMAL = vec3(0.0, 1.0, 0.0);
	base_world += vec3(0.0, 0.07, 0.0);
}

void fragment() {
	// One of the 3x3 tufts in the atlas, picked from the instance's random number.
	float x = mod(floor(r * 9.0), 3.0);
	float y = floor(r * 3.0);
	float a = texture(alpha_texture, (UV + vec2(x, y)) / 3.0).a;
	if (a < 0.5) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	LIGHT_VERTEX = (VIEW_MATRIX * vec4(base_world, 1.0)).xyz;
}

void light() {
	float amount = dot(NORMAL, LIGHT) + (ATTENUATION - 1.0) - cloud_shadow(base_world, TIME);
	DIFFUSE_LIGHT += cel_light(amount, LIGHT_COLOR);
}
