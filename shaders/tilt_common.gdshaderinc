// Shared by the tilt view's shaders (scripts/render_tilt/tilt_view.gd sets the same values on
// each material): the height of a tile, the cheap lighting (one ambient tint for the hour, cloud
// shadows, and a few warm point lights computed here, no engine light) and the distance haze.
// Colours are worked on as they are stored (sRGB) and turned linear at the very end, so a tint of
// 1 leaves the palette untouched.

// Size of the map in tiles.
uniform vec2 map_size = vec2(256.0);
// The map's data texture: R = level / 4, G = pattern / 8, B = 1 for water, A = ash.
uniform sampler2D data : filter_nearest;
// Tint of the hour (may exceed 1).
uniform vec3 ambient = vec3(1.0);
uniform vec3 fog_color = vec3(0.7, 0.85, 0.95);
// Distance from the camera where the haze starts and where it is full.
uniform vec2 fog_range = vec2(60.0, 140.0);
// Warm lights (fires, the windows of homes): xyz in world space, w = reach in tiles; and how
// bright each one is.
uniform int light_count = 0;
uniform vec4 lights[32];
uniform float light_gain[32];
uniform float light_power = 0.0;
// Strength of the drifting cloud shadows (0 = none).
uniform float cloud = 1.0;

// The same values as scripts/render_tilt/tilt_terrain.gd.
const float STEP = 0.75;
const float SEA = -0.35;
const float WATER_DIP = 0.15;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec4 tile_data(ivec2 c) {
	return texelFetch(data, clamp(c, ivec2(0), ivec2(map_size) - 1), 0);
}

// Height of the ground at a point given in tiles.
float tile_height(vec2 tile) {
	vec4 d = tile_data(ivec2(floor(tile)));
	float level = round(d.r * 4.0);
	if (level < 2.0) {
		return SEA;
	}
	return (level - 2.0) * STEP - (d.b > 0.5 ? WATER_DIP : 0.0);
}

// Light reaching a point of the world.
vec3 light_at(vec3 w) {
	vec3 l = ambient;
	float c = value_noise(w.xz * 0.07 + vec2(TIME * 0.035, TIME * 0.012)) * 0.65 + value_noise(w.xz * 0.19 - TIME * 0.02) * 0.35;
	l *= mix(1.0, 0.76, smoothstep(0.5, 0.66, c) * cloud);
	for (int i = 0; i < light_count; i++) {
		vec3 d = w - lights[i].xyz;
		d.y *= 0.5;
		float a = max(0.0, 1.0 - length(d) / lights[i].w);
		float flicker = 1.0 + 0.07 * sin(TIME * 11.0 + float(i) * 2.1) + 0.05 * sin(TIME * 23.7 + float(i));
		l += vec3(1.0, 0.60, 0.27) * a * a * light_power * light_gain[i] * flicker;
	}
	return l;
}

vec3 haze(vec3 c, float dist) {
	return mix(c, fog_color, smoothstep(fog_range.x, fog_range.y, dist) * 0.85);
}

vec3 to_linear(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}
