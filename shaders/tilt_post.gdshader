// Shows the tilt view's viewport on screen (a SubViewportContainer's material), in one pass: a
// blur that grows toward the top and bottom of the screen (the look of a photographed miniature),
// a tint and saturation for the hour, a vignette. The sharp band in the middle costs one sample.
shader_type canvas_item;

uniform float blur = 1.0;
uniform float vignette = 0.4;
uniform float saturation = 1.12;
uniform vec3 tint = vec3(1.0);

void fragment() {
	float d = abs(UV.y - 0.54);
	float radius = blur * smoothstep(0.17, 0.52, d) * 0.011 / TEXTURE_PIXEL_SIZE.y;
	vec3 c = vec3(0.0);
	if (radius < 0.5) {
		c = texture(TEXTURE, UV).rgb;
	} else {
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 2.39996;
			float r = sqrt((float(i) + 0.5) / 12.0) * radius;
			c += texture(TEXTURE, UV + vec2(cos(a), sin(a)) * r * TEXTURE_PIXEL_SIZE).rgb;
		}
		c /= 12.0;
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * tint;
	vec2 q = (UV - 0.5) * vec2(1.0, 0.9);
	c *= 1.0 - vignette * smoothstep(0.32, 0.82, length(q));
	COLOR = vec4(c, 1.0);
}
