// Shared helpers for the 3D pixel-art look (docs/ART_DIRECTION.md). Every lit material uses
// toon_light, so ground, sprites and water are lit the same way.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Light in three soft bands (lit, half, shadow); cast shadows count as the darkest band.
// `dither` (0..1, per pixel) jitters the band edges, giving pixel clusters where light meets shade.
vec3 toon_light(vec3 normal, vec3 light, float attenuation, vec3 light_color, float dither) {
	float ndl = clamp(dot(normal, light), 0.0, 1.0) * attenuation + (dither - 0.5) * 0.16;
	float band = ndl > 0.5 ? 1.0 : (ndl > 0.18 ? 0.74 : 0.5);
	return light_color * band / 3.14159;
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Shade of the clouds drifting over the world at ground point `xz` (1 = clear, < 1 = shaded),
// on a grid of `pixels` cells per tile so cloud edges stay pixel-sharp.
float cloud_shade(vec2 xz, float time, float pixels) {
	vec2 p = floor(xz * pixels) / pixels * 0.03 + vec2(time * 0.012, time * 0.005);
	float n = value_noise(p) * 0.65 + value_noise(p * 2.3 + 17.0) * 0.35;
	return n > 0.62 ? 0.84 : 1.0;
}
