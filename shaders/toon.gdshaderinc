// Shared helpers for the 3D pixel-art look.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Light in three hard bands (lit, half, shadow); shadows count as the darkest band.
vec3 toon_light(vec3 normal, vec3 light, float attenuation, vec3 light_color) {
	float ndl = clamp(dot(normal, light), 0.0, 1.0) * attenuation;
	float band = ndl > 0.55 ? 1.0 : (ndl > 0.2 ? 0.62 : 0.3);
	return light_color * band / 3.14159;
}
