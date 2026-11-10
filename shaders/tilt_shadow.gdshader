// The simulation's shadow batches in the tilt view: the same small ellipses as in the flat view
// (sim/Draw.cs, 2D transforms in world pixels), laid flat on the ground under each sprite.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_draw_never;

#include "tilt_common.gdshaderinc"

uniform sampler2D shadow_texture : filter_nearest;
uniform float strength = 1.0;

const float TILE = 8.0;

void vertex() {
	vec2 origin = MODEL_MATRIX[3].xy;
	vec2 size = vec2(MODEL_MATRIX[0].x, MODEL_MATRIX[1].y);
	// The ellipse is centred a little above its origin (see WriteShadow): the sprite's feet.
	float ground_y = tile_height((origin - vec2(0.0, size.y * 0.45)) / TILE);
	vec2 p = (origin + VERTEX.xy * size) / TILE;
	VERTEX = (VIEW_MATRIX * vec4(p.x, ground_y + 0.012, p.y, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	ALBEDO = vec3(0.004, 0.006, 0.02);
	ALPHA = texture(shadow_texture, UV).a * strength;
}
