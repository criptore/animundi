// Cel shading and cloud shadows shared by every lit material (ground, sprites, grass),
// so everything is lit the same way.
// Adapted from Robert-K/godot-3d-pixel-art (MIT, see shaders/vendor/README.md), itself inspired by
// t3ssel8r: diffuse light stepped into `cel_cuts` bands, cloud shadows found by following the sun
// ray from the surface up to a cloud layer and reading a scrolling noise texture there.

uniform int cel_cuts : hint_range(1, 8, 1) = 3;
uniform sampler2D cloud_texture : filter_linear, repeat_enable;
// World units -> cloud texture UV, cloud drift per second, how dark clouds make the ground.
uniform float cloud_scale = 0.012;
uniform vec2 cloud_speed = vec2(0.004, 0.0015);
uniform float cloud_strength = 0.6;
uniform float cloud_height = 12.0;
// Direction the sunlight travels, in world space (set from the sun by SceneStyle).
uniform vec3 sun_direction = vec3(0.4, -0.7, -0.5);
uniform bool clouds_enabled = true;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Cloud cover (0 = clear, 1 = full shade) over the world point `p`.
float cloud_shadow(vec3 p, float time) {
	if (!clouds_enabled) {
		return 0.0;
	}
	vec3 to_sun = -normalize(sun_direction);
	vec3 at_layer = p + to_sun * ((cloud_height - p.y) / max(to_sun.y, 0.05));
	float c = texture(cloud_texture, at_layer.xz * cloud_scale + time * cloud_speed).r;
	return smoothstep(0.2, 1.0, (1.0 - c) * cloud_strength);
}

// Stepped diffuse light: `amount` (n.l, minus shadow and cloud) snapped up to the next of
// `cel_cuts` bands. Returned without albedo (Godot multiplies it in).
vec3 cel_light(float amount, vec3 light_color) {
	float cuts_inv = 1.0 / float(cel_cuts);
	float stepped = clamp(amount + mod(1.0 - amount, cuts_inv), 0.0, 1.0);
	return light_color * stepped / 3.14159;
}
