// The simulation's sprite batches shown in the tilt view. The MultiMeshes are the very ones the
// flat view draws (sim/Draw.cs, 2D transforms in world pixels: x scale, y scale, feet position;
// custom data = rectangle in the atlas; colour = mask colour and packed height + sway phase). Here
// each quad is stood up on the ground at its feet, leaning back by `lean` toward the camera's line
// of sight and stretched so the tilted camera sees it at its true proportions. The depth buffer
// sorts them: no order to keep. Lit once at the feet (a sticker, as in Cult of the Lamb).
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

#include "tilt_common.gdshaderinc"

uniform sampler2D atlas : filter_nearest_mipmap;
// Angle from upright, in radians, and the vertical stretch that makes up for the camera's tilt.
uniform float lean = 0.4;
uniform float stretch = 1.1;
// Sway amplitude in world pixels at the top of a plant.
uniform float wind = 0.6;

const float TILE = 8.0;

varying vec3 lit;
varying vec3 mask_color;
varying float dist;

void vertex() {
	vec2 feet = MODEL_MATRIX[3].xy / TILE;
	float sx = MODEL_MATRIX[0].x;
	float sy = MODEL_MATRIX[1].y;
	vec4 region = INSTANCE_CUSTOM;
	mask_color = COLOR.rgb;
	// Alpha = (height in whole world pixels + sway phase) / 256; a phase of 0 never sways.
	float packed = COLOR.a * 256.0;
	float height = floor(packed + 0.02);
	float sway_phase = packed - height;
	float phase = sway_phase * 6.2831;
	float sway = (sin(TIME * 1.3 + phase) + 0.35 * sin(TIME * 3.1 + phase * 2.0)) * step(0.03, sway_phase);
	// The unit quad: x from -0.5 to 0.5, y from -1 (top) to 0 (feet).
	float up = -VERTEX.y;
	float side = VERTEX.x * sx + sway * wind * smoothstep(0.0, 1.0, up) * clamp(height / 12.0, 0.0, 1.0);
	float rise = up * sy / TILE * stretch;
	float ground_y = tile_height(feet);
	// A hair higher toward the south, so sprites lying almost flat keep the flat view's order.
	vec3 w = vec3(feet.x + side / TILE, ground_y + 0.02 + feet.y * 0.00005 + rise * cos(lean), feet.y - rise * sin(lean));
	lit = light_at(vec3(feet.x, ground_y + 0.3, feet.y));
	UV = region.xy + UV * region.zw;
	vec4 view = VIEW_MATRIX * vec4(w, 1.0);
	VERTEX = view.xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	dist = -view.z;
}

void fragment() {
	vec4 tex = texture(atlas, UV);
	vec3 col = tex.rgb;
	// The colour mask (magenta shades: roofs, banners), painted in the instance's colour.
	if (tex.g < 0.02 && abs(tex.r - tex.b) < 0.02 && tex.r > 0.25) {
		float k = tex.r / 0.816;
		col = k <= 1.0 ? mask_color * k : mix(mask_color, vec3(1.0), (k - 1.0) * 1.5);
	}
	ALBEDO = to_linear(haze(col * lit, dist));
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
