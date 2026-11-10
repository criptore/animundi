// The stepped ground of the tilt view (scripts/render_tilt/tilt_terrain.gd): tops show what
// shaders/map.gdshader shows on the flat map (tile colour, 8x8 pattern pixels, water, roads,
// fields, ash, frost), read from the same textures by world position; cliff faces are earth or
// rock in strata, with a lip of the ground's colour at the top. Lit by tilt_common.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "tilt_common.gdshaderinc"

// The map's colour texture, one texel per tile.
uniform sampler2D colors : filter_nearest;
// Ground made by people (R * 255: 0 nothing, 1 road, 2 bare field, 3-5 wheat growing to ripe).
uniform sampler2D ground : filter_nearest;
uniform float frost = 0.0;
// Off for the data layers (height, temperature...): the tops show the layer's colours alone.
uniform bool show_patterns = true;

const float SUB = 8.0;
const int GRASS = 1;
const int SAND = 2;
const int SNOW = 3;
const int ROCK = 4;
const int LAVA = 5;
const int FOREST = 6;
const int WATER = 7;
const int MEADOW = 8;

varying vec3 world_pos;
varying vec3 world_normal;
varying float depth_under_top;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
	depth_under_top = COLOR.r * 2.0;
}

vec3 flower_color(float h) {
	if (h < 0.2) return vec3(0.89, 0.25, 0.27);
	if (h < 0.4) return vec3(0.98, 0.84, 0.30);
	if (h < 0.58) return vec3(0.96, 0.96, 0.92);
	if (h < 0.74) return vec3(0.40, 0.58, 0.95);
	if (h < 0.88) return vec3(0.95, 0.55, 0.78);
	return vec3(0.98, 0.60, 0.25);
}

vec3 pattern(int kind, vec3 base, ivec2 cell, ivec2 sub) {
	vec2 p = vec2(cell) * SUB + vec2(sub);
	float h = hash(p);
	float h2 = hash(p + 17.0);
	if (kind == GRASS || kind == MEADOW) {
		float flowers = kind == MEADOW ? 0.06 : 0.006;
		if (h2 < flowers) return flower_color(hash(p + 91.0));
		if (h < 0.07) return base * 1.18;
		if (h > 0.96) return base * 0.84;
	} else if (kind == FOREST) {
		if (h < 0.10) return base * 0.78;
		if (h > 0.95) return base * 1.15;
	} else if (kind == SAND) {
		int row = (sub.y + int(hash(vec2(cell)) * 4.0)) % 4;
		if (row == 0 && h < 0.55) return base * 1.07;
		if (h > 0.97) return base * 0.9;
	} else if (kind == SNOW) {
		if (h < 0.04) return min(base * 1.12, vec3(1.0));
		if (h > 0.97) return base * 0.92;
	} else if (kind == ROCK) {
		if (h < 0.09) return base * 0.78;
		if (h > 0.94) return base * 1.14;
	} else if (kind == LAVA) {
		float flicker = 0.5 + 0.5 * sin(TIME * 2.0 + h2 * 6.283);
		if (h < 0.12) return mix(base, vec3(1.0, 0.85, 0.35), flicker);
		if (h > 0.9) return base * 0.75;
	} else if (kind == WATER) {
		float twinkle = sin(TIME * 2.2 + h2 * 6.2831);
		if (h < 0.03 && twinkle > 0.4) return base * (1.0 + 0.18 * (twinkle - 0.4) / 0.6);
	}
	return base;
}

void fragment() {
	bool top = world_normal.y > 0.5;
	// A cliff face belongs to the tile behind it.
	vec2 t = top ? world_pos.xz : world_pos.xz - world_normal.xz * 0.01;
	ivec2 cell = clamp(ivec2(floor(t)), ivec2(0), ivec2(map_size) - 1);
	ivec2 sub = ivec2(floor(fract(t) * SUB));
	vec3 col = texelFetch(colors, cell, 0).rgb;
	vec4 d = tile_data(cell);
	int kind = int(round(d.g * 8.0));
	bool water = d.b > 0.5;
	float dist = -VERTEX.z;
	// Screen pixels covered by one tile: patterns fade when they would shimmer.
	float tile_px = 1.0 / max(length(fwidth(world_pos.xz)), 1e-5);
	float detail = smoothstep(3.0, 7.0, tile_px);

	if (top && !show_patterns) {
		// A data layer: the colour of the tile, nothing over it.
	} else if (top) {
		col = mix(col, pattern(kind, col, cell, sub), detail);
		if (water) {
			float swell = sin(dot(t, vec2(0.35, 0.22)) - TIME * 0.6) * 0.5 + 0.5;
			col *= 0.97 + 0.06 * swell;
			float wave = sin(TIME * 1.6 + hash(vec2(cell)) * 6.2831) * 0.5 + 0.5;
			bool shore = (tile_data(cell + ivec2(0, -1)).b < 0.5 && sub.y == 0)
					|| (tile_data(cell + ivec2(0, 1)).b < 0.5 && sub.y == 7)
					|| (tile_data(cell + ivec2(-1, 0)).b < 0.5 && sub.x == 0)
					|| (tile_data(cell + ivec2(1, 0)).b < 0.5 && sub.x == 7);
			if (shore && hash(vec2(cell) * 8.0 + vec2(sub)) < 0.35 + 0.5 * wave) {
				col = mix(col, vec3(0.92, 0.97, 1.0), 0.55 * detail);
			}
		} else {
			int g = int(round(texelFetch(ground, cell, 0).r * 255.0));
			if (g == 1) {
				float hr = hash(vec2(cell) * 8.0 + vec2(sub) + 11.0);
				vec3 dirt = vec3(0.62, 0.50, 0.34) * (hr > 0.9 ? 0.85 : (hr < 0.08 ? 1.12 : 1.0));
				col = mix(col, dirt, mix(0.75, 0.95, detail));
			} else if (g >= 2) {
				bool furrow = sub.y % 2 == 1;
				vec3 soil = vec3(0.45, 0.33, 0.21) * (furrow ? 0.82 : 1.0);
				vec3 wheat = g == 3 ? vec3(0.45, 0.70, 0.30) : (g == 4 ? vec3(0.66, 0.74, 0.30) : vec3(0.93, 0.80, 0.33));
				float hf = hash(vec2(cell) * 8.0 + vec2(sub) + 23.0);
				bool plant = g >= 3 && !furrow && (g >= 4 || hf < 0.6);
				vec3 field = plant ? wheat * (hf > 0.85 ? 0.88 : 1.0) : soil;
				vec3 far_field = g == 2 ? soil : mix(soil, wheat, 0.6);
				col = mix(col, mix(far_field, field, detail), 0.9);
			}
			if (d.a > 0.0) {
				vec3 burnt = vec3(0.17, 0.15, 0.14) + (hash(vec2(cell) * 8.0 + vec2(sub) + 7.0) > 0.85 ? 0.12 : 0.0) * detail;
				col = mix(col, burnt, clamp(d.a * 1.2, 0.0, 0.9));
			}
			float lat = abs((float(cell.y) + 0.5) / map_size.y - 0.5) * 2.0;
			float cover = frost * smoothstep(0.3, 0.75, lat + (hash(vec2(cell)) - 0.5) * 0.1);
			if (cover > 0.0) {
				float speck = hash(vec2(cell) * 8.0 + vec2(sub) + 3.0);
				col = mix(col, vec3(0.93, 0.96, 1.0), clamp(cover * (0.75 + 0.25 * speck), 0.0, 0.85));
			}
			// The foot of a cliff rising to the north sits in its shade.
			if (tile_height(vec2(cell) + vec2(0.5, -0.5)) > world_pos.y + 0.3 && sub.y == 0) {
				col *= mix(1.0, 0.8, detail);
			}
		}
	} else {
		// A cliff face, in pattern pixels along the face and down it.
		vec2 q = floor(vec2(world_pos.x + world_pos.z, world_pos.y) * SUB + 0.01);
		float r = hash(q);
		vec3 face = (kind == ROCK || kind == SNOW || kind == LAVA) ? vec3(0.47, 0.47, 0.53)
				: (kind == SAND ? col * 0.80 : vec3(0.55, 0.38, 0.26));
		if (water) {
			face = vec3(0.50, 0.40, 0.30);
		}
		face *= 0.88 + 0.22 * r;
		if (mod(q.y, 3.0) < 0.5) {
			face *= 0.88;
		}
		// The lip: the ground's own colour hangs over the edge, one or two pixels deep.
		float lip = 0.125 + 0.125 * step(0.55, hash(vec2(q.x, 7.0)));
		if (!water && depth_under_top < lip) {
			face = col * (0.70 + 0.12 * r);
		}
		float shade = world_normal.z > 0.5 ? 0.84 : (world_normal.z < -0.5 ? 0.5 : 0.64);
		// On a data layer the face keeps its tile's colour, shaded.
		col = show_patterns ? mix(col * shade, face * shade * (1.0 - 0.18 * smoothstep(0.2, 0.75, depth_under_top)), smoothstep(1.5, 4.0, tile_px)) : col * shade;
	}

	// Light falls in pattern pixels on the ground.
	vec3 lit_at = vec3((floor(world_pos.x * SUB) + 0.5) / SUB, world_pos.y, (floor(world_pos.z * SUB) + 0.5) / SUB);
	col *= light_at(lit_at);
	ALBEDO = to_linear(haze(col, dist));
}
