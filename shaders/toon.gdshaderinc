// Shared helpers for the 3D pixel-art look (docs/ART_DIRECTION.md). Every lit material uses
// toon_light, so ground, grass, trees and rocks are lit the same way.

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
