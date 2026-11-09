// The world map: one texel per tile (TEXTURE holds the tile colours, `data` the level, pattern and
// water flag of each tile), drawn on a sprite where a tile is TILE world pixels wide.
//
// Up close, each tile is cut into an 8x8 grid of "pattern pixels" (one world pixel):
// a light pattern per ground type (grass tufts, sand ripples, snow sparkles, rock cracks, lava
// specks) and a step edge where a neighbour sits on a lower level (a dark cliff face on the south
// side, a darker line on east and west, a light rim on the north). Zoomed out, patterns fade away
// and a step shows as a darker tile, so the map reads like WorldBox's: flat colours, hard edges.
// Water moves: a slow swell of light, twinkling glints and foam that comes and goes on the shore.
shader_type canvas_item;

// Size of the map in tiles.
uniform vec2 map_size = vec2(256.0);
// R = level / 4, G = pattern / 8, B = 1 for water, A = ash left by fire.
uniform sampler2D data : filter_nearest;
// Patterns only on the biome layer; data layers show flat colours (edges stay, to read relief).
uniform bool show_patterns = true;
// Winter: frost whitens the land towards the poles (0 = none, 1 = midwinter).
uniform float frost = 0.0;
// Villages: territory (RGB = owner colour, A = owner key, 0 = no one's) and ground made by people
// (R * 255: 0 nothing, 1 road, 2 bare field, 3 young wheat, 4 growing wheat, 5 ripe wheat).
uniform sampler2D territory : filter_nearest;
uniform sampler2D ground : filter_nearest;
uniform bool show_territory = true;

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
const int MEADOW = 8;

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

// A flower colour: red, yellow, white, blue, pink or orange.
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
	switch (kind) {
		case GRASS:
		case MEADOW: {
			// Flowers are single pixels of colour on the grass, as in WorldBox: a few on
			// grassland, many on flower meadows.
			float flowers = kind == MEADOW ? 0.06 : 0.006;
			if (h2 < flowers) return flower_color(hash(p + 91.0));
			if (h < 0.07) return base * 1.18;
			if (h > 0.96) return base * 0.84;
			break;
		}
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
		case WATER: {
			// Glints that twinkle in and out.
			float twinkle = sin(TIME * 2.2 + h2 * 6.2831);
			if (h < 0.03 && twinkle > 0.4) return base * (1.0 + 0.18 * (twinkle - 0.4) / 0.6);
			break;
		}
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

	if (water && show_patterns) {
		// Slow swell: broad bands of light drift across the water, visible at every zoom.
		float swell = sin(dot(t, vec2(0.35, 0.22)) - TIME * 0.6) * 0.5 + 0.5;
		col *= 0.97 + 0.06 * swell;
		// Foam along the shore: the pattern pixels next to land come and go like small waves.
		float wave = sin(TIME * 1.6 + hash(vec2(cell)) * 6.2831) * 0.5 + 0.5;
		bool shore = (tile_data(cell + ivec2(0, -1)).b < 0.5 && sub.y == 0)
				|| (tile_data(cell + ivec2(0, 1)).b < 0.5 && sub.y == 7)
				|| (tile_data(cell + ivec2(-1, 0)).b < 0.5 && sub.x == 0)
				|| (tile_data(cell + ivec2(1, 0)).b < 0.5 && sub.x == 7);
		if (shore && hash(vec2(cell) * 8.0 + vec2(sub)) < 0.35 + 0.5 * wave) {
			col = mix(col, vec3(0.92, 0.97, 1.0), 0.55 * detail);
		}
	}

	if (!water && show_patterns) {
		// Roads and fields, drawn by the villages.
		int g = int(round(texelFetch(ground, cell, 0).r * 255.0));
		if (g == 1) {
			// A dirt road with pebbles.
			float hr = hash(vec2(cell) * 8.0 + vec2(sub) + 11.0);
			vec3 dirt = vec3(0.62, 0.50, 0.34) * (hr > 0.9 ? 0.85 : (hr < 0.08 ? 1.12 : 1.0));
			col = mix(col, dirt, mix(0.75, 0.95, detail));
		} else if (g >= 2) {
			// A field: furrows of soil, wheat on every other row once sown, green then gold.
			bool furrow = sub.y % 2 == 1;
			vec3 soil = vec3(0.45, 0.33, 0.21) * (furrow ? 0.82 : 1.0);
			vec3 wheat = g == 3 ? vec3(0.45, 0.70, 0.30) : (g == 4 ? vec3(0.66, 0.74, 0.30) : vec3(0.93, 0.80, 0.33));
			float hf = hash(vec2(cell) * 8.0 + vec2(sub) + 23.0);
			bool plant = g >= 3 && !furrow && (g >= 4 || hf < 0.6);
			vec3 field = plant ? wheat * (hf > 0.85 ? 0.88 : 1.0) : soil;
			vec3 far_field = g == 2 ? soil : mix(soil, wheat, 0.6);
			col = mix(col, mix(far_field, field, detail), 0.9);
		}
		// Ash: burned ground turns dark grey, with lighter cinders, and fades as it heals.
		float ash = d.a;
		if (ash > 0.0) {
			vec3 burnt = vec3(0.17, 0.15, 0.14) + (hash(vec2(cell) * 8.0 + vec2(sub) + 7.0) > 0.85 ? 0.12 : 0.0) * detail;
			col = mix(col, burnt, clamp(ash * 1.2, 0.0, 0.9));
		}
		// Frost in winter: from the poles towards the middle, speckled up close.
		float lat = abs((float(cell.y) + 0.5) / map_size.y - 0.5) * 2.0;
		float cover = frost * smoothstep(0.3, 0.75, lat + (hash(vec2(cell)) - 0.5) * 0.1);
		if (cover > 0.0) {
			float speck = hash(vec2(cell) * 8.0 + vec2(sub) + 3.0);
			col = mix(col, vec3(0.93, 0.96, 1.0), clamp(cover * (0.75 + 0.25 * speck), 0.0, 0.85));
		}
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

	// Territory: a light tint of the owner's colour and a solid border where it ends.
	vec4 own = texelFetch(territory, cell, 0);
	if (show_territory && show_patterns && own.a > 0.0) {
		col = mix(col, own.rgb, 0.10);
		vec2 ms = map_size - 1.0;
		bool e = texelFetch(territory, ivec2(clamp(vec2(cell + ivec2(1, 0)), vec2(0.0), ms)), 0).a != own.a;
		bool w = texelFetch(territory, ivec2(clamp(vec2(cell + ivec2(-1, 0)), vec2(0.0), ms)), 0).a != own.a;
		bool s = texelFetch(territory, ivec2(clamp(vec2(cell + ivec2(0, 1)), vec2(0.0), ms)), 0).a != own.a;
		bool n = texelFetch(territory, ivec2(clamp(vec2(cell + ivec2(0, -1)), vec2(0.0), ms)), 0).a != own.a;
		bool edge = (e && sub.x == 7) || (w && sub.x == 0) || (s && sub.y == 7) || (n && sub.y == 0);
		// Up close a line one world pixel wide; far away the whole border tile is tinted.
		float border = edge ? 0.85 : 0.0;
		float far_border = (e || w || s || n) ? 0.6 : 0.0;
		col = mix(col, own.rgb * 1.1, mix(far_border, border, smoothstep(2.0, 6.0, tile_px)));
	}

	COLOR = vec4(col, 1.0);
}
