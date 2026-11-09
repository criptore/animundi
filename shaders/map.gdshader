// The world map: one texel per tile (TEXTURE holds the tile colours, `data` the level, pattern and
// water flag of each tile), drawn on a sprite where a tile is TILE world pixels wide.
//
// Up close, each tile is cut into an 8x8 grid of "pattern pixels" (the pixel size of the sprites):
// a light pattern per ground type (grass tufts, sand ripples, snow sparkles, rock cracks, lava
// specks) and a step edge where a neighbour sits on a lower level (a dark cliff face on the south
// side, a darker line on east and west, a light rim on the north). Zoomed out, patterns fade away
// and a step shows as a darker tile, so the map reads like WorldBox's: flat colours, hard edges.
shader_type canvas_item;

// Size of the map in tiles.
uniform vec2 map_size = vec2(256.0);
// R = level / 4, G = pattern / 8, B = 1 for water.
uniform sampler2D data : filter_nearest;
// Patterns only on the biome layer; data layers show flat colours (edges stay, to read relief).
uniform bool show_patterns = true;

const float SUB = 8.0;
// Pattern ids (same order as WorldMap.Pattern).
const int PLAIN = 0;
const int GRASS = 1;
const int SAND = 2;
const int SNOW = 3;
const int ROCK = 4;
const int LAVA = 5;
const int FOREST = 6;
const int WATER = 7;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec4 tile_data(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(map_size) - 1);
	return texelFetch(data, c, 0);
}

int level_at(ivec2 c) {
	return int(round(tile_data(c).r * 4.0));
}

vec3 pattern(int kind, vec3 base, ivec2 cell, ivec2 sub) {
	vec2 p = vec2(cell) * SUB + vec2(sub);
	float h = hash(p);
	float h2 = hash(p + 17.0);
	switch (kind) {
		case GRASS:
			if (h < 0.07) return base * 1.18;
			if (h > 0.96) return base * 0.84;
			break;
		case FOREST:
			if (h < 0.10) return base * 0.78;
			if (h > 0.95) return base * 1.15;
			break;
		case SAND: {
			// Short ripples: lighter dashes on every fourth row, shifted per tile.
			int row = (sub.y + int(hash(vec2(cell)) * 4.0)) % 4;
			if (row == 0 && h < 0.55) return base * 1.07;
			if (h > 0.97) return base * 0.9;
			break;
		}
		case SNOW:
			if (h < 0.04) return min(base * 1.12, vec3(1.0));
			if (h > 0.97) return base * 0.92;
			break;
		case ROCK:
			if (h < 0.09) return base * 0.78;
			if (h > 0.94) return base * 1.14;
			break;
		case LAVA: {
			float flicker = 0.5 + 0.5 * sin(TIME * 2.0 + h2 * 6.283);
			if (h < 0.12) return mix(base, vec3(1.0, 0.85, 0.35), flicker);
			if (h > 0.9) return base * 0.75;
			break;
		}
		case WATER:
			if (h < 0.025) return base * 1.12;
			break;
	}
	return base;
}

void fragment() {
	vec2 t = UV * map_size;
	ivec2 cell = ivec2(floor(t));
	ivec2 sub = ivec2(floor(fract(t) * SUB));
	vec3 col = texelFetch(TEXTURE, cell, 0).rgb;
	vec4 d = tile_data(cell);
	int level = int(round(d.r * 4.0));
	bool water = d.b > 0.5;

	// Screen pixels covered by one tile: drives the level of detail.
	float tile_px = 1.0 / max(fwidth(t.x), 1e-5);
	float detail = smoothstep(3.0, 7.0, tile_px);

	if (show_patterns && detail > 0.0) {
		int kind = int(round(d.g * 8.0));
		col = mix(col, pattern(kind, col, cell, sub), detail);
	}

	// Step edges toward lower neighbours. Under water they are softer.
	float strength = water ? 0.5 : 1.0;
	bool south = level_at(cell + ivec2(0, 1)) < level;
	bool north = level_at(cell + ivec2(0, -1)) < level;
	bool east = level_at(cell + ivec2(1, 0)) < level;
	bool west = level_at(cell + ivec2(-1, 0)) < level;
	float shade = 1.0;
	if (south && sub.y >= 6) shade = sub.y == 7 ? 0.62 : 0.74;
	else if (east && sub.x == 7) shade = 0.84;
	else if (west && sub.x == 0) shade = 0.84;
	else if (north && sub.y == 0) shade = 1.1;
	// Zoomed out the cliff face is smaller than a screen pixel: darken the whole tile a little.
	float far_shade = south ? 0.82 : 1.0;
	shade = mix(far_shade, shade, smoothstep(2.0, 5.0, tile_px));
	col *= mix(1.0, shade, strength);

	COLOR = vec4(col, 1.0);
}
