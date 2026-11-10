// Reflections on water, close up in the tilt view: the simulation's sprite batches drawn once
// more (the same MultiMeshes as shaders/tilt_sprite.gdshader, no second pass over the scene).
// Each sprite is laid upside down on the water, from its feet toward the camera, as long as it
// takes to look as tall on screen as the sprite itself (a standing sprite is a drawing, not a
// volume: a true mirror image of its leaning quad would look squashed). Only what stands in the
// water or on the tiles just north of it reflects; the rest collapses to nothing. The image
// ripples in pattern pixels, takes the water's colour and fades with height.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_draw_never;

#include "tilt_common.gdshaderinc"

uniform sampler2D atlas : filter_nearest_mipmap;
// Tiles of water covered by one tile of sprite height: 1 / sin(camera pitch).
uniform float reach = 1.3;
// 1 close up, 0 when the camera is far (the pass is then hidden).
uniform float strength = 1.0;

const float TILE = 8.0;
// How far south of its feet a sprite may find the water it reflects in, in tiles.
const int REACH = 3;

varying vec3 world_pos;
varying vec3 mask_color;
varying vec4 region;
varying vec2 local_uv;
varying float water_y;

void vertex() {
	vec2 feet = MODEL_MATRIX[3].xy / TILE;
	float sx = MODEL_MATRIX[0].x;
	float sy = MODEL_MATRIX[1].y;
	region = INSTANCE_CUSTOM;
	mask_color = COLOR.rgb;
	local_uv = UV;
	water_y = 1e5;
	for (int i = 0; i < REACH; i++) {
		vec2 t = feet + vec2(0.0, float(i));
		if (tile_data(ivec2(floor(t))).b > 0.5) {
			water_y = tile_height(t);
			break;
		}
	}
	if (water_y > 1e4) {
		// Nothing to reflect in: behind the camera, all four corners together.
		VERTEX = vec3(0.0, 0.0, 10.0);
	} else {
		float up = -VERTEX.y;
		vec3 on_water = vec3(feet.x + VERTEX.x * sx / TILE, water_y + 0.006, feet.y + up * sy / TILE * reach);
		world_pos = on_water;
		VERTEX = (VIEW_MATRIX * vec4(on_water, 1.0)).xyz;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// Only on water at the level the sprite reflects in.
	vec4 d = tile_data(ivec2(floor(world_pos.xz)));
	if (d.b < 0.5 || abs(tile_height(world_pos.xz) - water_y) > 0.05) {
		discard;
	}
	// Ripples: each row of pattern pixels slides sideways, back and forth.
	float row = floor(world_pos.z * 8.0);
	vec2 uv = local_uv;
	uv.x = clamp(uv.x + sin(row * 1.7 + TIME * 2.2) * 0.035 + sin(row * 0.6 - TIME * 1.3) * 0.02, 0.0, 1.0);
	vec4 tex = texture(atlas, region.xy + uv * region.zw);
	if (tex.a < 0.5) {
		discard;
	}
	vec3 col = tex.rgb;
	if (tex.g < 0.02 && abs(tex.r - tex.b) < 0.02 && tex.r > 0.25) {
		float k = tex.r / 0.816;
		col = k <= 1.0 ? mask_color * k : mix(mask_color, vec3(1.0), (k - 1.0) * 1.5);
	}
	col = mix(col, vec3(0.29, 0.80, 0.87), 0.3) * light_at(world_pos);
	ALBEDO = to_linear(col);
	// Strongest at the feet (the bottom of the sprite, UV.y = 1), fading toward the head.
	ALPHA = strength * mix(0.35, 0.7, local_uv.y);
}
