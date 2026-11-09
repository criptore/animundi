// Sprites drawn in batches from the sprite atlas (scripts/render2d/sprite_batch.gd): every instance
// is a unit quad (feet at the origin) scaled to the sprite's size; its custom data is the sprite's
// rectangle in the atlas, its colour the sprite's average colour (rgb) and height in world pixels
// (a, divided by 256). Shadows use the same shader on a shadow texture, without custom data.
//
// - Wind: the top of tall sprites sways a little, each with its own phase; the feet stay put.
// - Level of detail: when a sprite would be only a few screen pixels tall, it is drawn as a small
//   dot of its average colour at its feet instead (crisp, readable from far, like WorldBox).
shader_type canvas_item;

uniform bool from_atlas = true;
// Screen pixels per world pixel (the camera zoom), set every frame.
uniform float zoom = 1.0;
// Sway amplitude in world pixels at the top of a sprite (0 = no wind).
uniform float wind = 0.6;
// Sprites shorter than this on screen become dots.
uniform float dot_below = 6.0;

varying vec2 local_uv;
varying vec4 info;
// Width over height of the sprite.
varying float aspect;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	local_uv = UV;
	info = COLOR;
	aspect = 1.0;
	if (from_atlas) {
		UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
		aspect = (INSTANCE_CUSTOM.z / TEXTURE_PIXEL_SIZE.x) / max(INSTANCE_CUSTOM.w / TEXTURE_PIXEL_SIZE.y, 1e-5);
		float height = COLOR.a * 256.0;
		// VERTEX is in the unit quad: y = -1 at the top, 0 at the feet. The sway is given in world
		// pixels, so it is divided by the sprite's width (the instance transform scales it back).
		// Short sprites (grass, rocks) barely move.
		float phase = hash(float(INSTANCE_ID)) * 6.2831;
		float sway = sin(TIME * 1.3 + phase) + 0.35 * sin(TIME * 3.1 + phase * 2.0);
		float width = max(height * aspect, 1.0);
		VERTEX.x += sway * wind * smoothstep(0.0, 1.0, -VERTEX.y) / width * clamp(height / 12.0, 0.0, 1.0);
	}
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (!from_atlas) {
		COLOR = tex;
	} else {
		float height_px = info.a * 256.0 * zoom;
		if (height_px >= dot_below) {
			COLOR = tex;
		} else {
			// A dot of the sprite's average colour, 1 to 3 screen pixels wide, at its feet.
			float dot_px = clamp(height_px * 0.5, 1.0, 3.0);
			float width_px = max(height_px * aspect, 1e-3);
			bool inside = abs(local_uv.x - 0.5) * width_px <= dot_px * 0.5
					&& (1.0 - local_uv.y) * height_px <= dot_px;
			COLOR = inside ? vec4(info.rgb, 1.0) : vec4(0.0);
		}
	}
}
