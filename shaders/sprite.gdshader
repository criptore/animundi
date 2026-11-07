// A 2D pixel-art sprite standing in the 3D world (quad facing the fixed camera). Its colours are
// drawn exactly as in the sprite sheet; pixels outside the drawing are cut, also in the shadow
// pass, so the sprite casts a shadow of its own shape on the relief.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;

void fragment() {
	vec4 c = texture(sprite, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
}
