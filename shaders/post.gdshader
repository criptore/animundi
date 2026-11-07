// Final pass over the low-resolution render (on the SubViewportContainer): soft diagonal light
// shafts drifting from the top left, a warm afternoon grade and a light vignette. Computed per
// render pixel so it stays pixel art.
shader_type canvas_item;

uniform bool effects = true;
uniform vec3 warm = vec3(1.05, 1.0, 0.92);
uniform float shaft_strength = 0.07;
uniform float vignette = 0.12;

float hash_band(float x) {
	return fract(sin(x * 91.17) * 43758.5453);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (effects) {
		vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
		vec2 px = floor(UV * size);
		// Light shafts: bands along the sun direction, each with its own brightness, drifting.
		float d = px.x * 0.55 + px.y + TIME * 1.5;
		float band = floor(d / 14.0);
		float lit = step(0.55, hash_band(band)) * step(fract(d / 14.0), 0.6);
		float fade = 1.0 - UV.y * 0.8;
		col.rgb += vec3(1.0, 0.92, 0.7) * lit * shaft_strength * fade;
		col.rgb *= mix(vec3(1.0), warm, 0.6);
		vec2 v = UV - 0.5;
		col.rgb *= 1.0 - vignette * floor(dot(v, v) * 8.0) / 2.0;
	}
	COLOR = col;
}
