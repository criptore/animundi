// Terrain: biome colour (vertex colour) with a pixel pattern painted in world space, lit in soft
// bands with shadows. Tile tops carry their pattern in UV.x (TerrainBuilder.Pattern): grass tufts,
// forest-floor litter, sand ripples, snow sparkles, rock cracks, moving lava. Cliff faces (UV.y = 1)
// get rock strata. With `effects`: a dark pixel outline along tile tops where the ground drops
// (read from the heightmap), and drifting cloud shadows.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/toon.gdshaderinc"

// Pattern pixels per tile.
uniform float pixels = 8.0;
uniform float grain = 0.06;
uniform bool effects = true;
// Ground height per tile (TerrainBuilder.heightmap_texture), for the cliff-edge outlines.
uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform bool has_heightmap = false;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// True on the outermost pattern pixel of a tile top whose neighbour on that side is lower.
bool cliff_edge(vec3 p) {
	vec2 tile = round(p.xz);
	vec2 f = p.xz - tile;
	float edge = 0.5 - 1.0 / pixels;
	ivec2 t = ivec2(tile);
	ivec2 size = textureSize(heightmap, 0);
	float here = p.y - 0.05;
	if (f.x > edge && t.x + 1 < size.x && texelFetch(heightmap, t + ivec2(1, 0), 0).r < here) return true;
	if (f.x < -edge && t.x > 0 && texelFetch(heightmap, t - ivec2(1, 0), 0).r < here) return true;
	if (f.y > edge && t.y + 1 < size.y && texelFetch(heightmap, t + ivec2(0, 1), 0).r < here) return true;
	if (f.y < -edge && t.y > 0 && texelFetch(heightmap, t - ivec2(0, 1), 0).r < here) return true;
	return false;
}

void fragment() {
	vec3 c = COLOR.rgb;
	vec2 cell = floor(world_pos.xz * pixels);
	float n = hash12(cell);
	c *= 1.0 - grain * 0.5 + grain * hash12(cell + 91.0);
	if (UV.y > 0.5) {
		// Cliff face: horizontal strata and a few stones.
		float y = world_pos.y * pixels * 0.5;
		float strata = step(0.82, fract(y));
		c *= 1.0 - 0.14 * strata;
		vec2 face = floor(vec2(world_pos.x + world_pos.z, world_pos.y) * pixels);
		c *= hash12(face) > 0.93 ? 0.8 : 1.0;
	} else {
		int p = int(UV.x + 0.5);
		if (p == 1) {
			// Grass: light blade tips and dark tufts.
			c *= n > 0.88 ? 1.13 : (n < 0.07 ? 0.84 : 1.0);
		} else if (p == 6) {
			// Forest floor: dark leaf litter, a few lit spots.
			c *= n > 0.86 ? 0.8 : (n < 0.06 ? 1.1 : 1.0);
		} else if (p == 2) {
			// Sand: diagonal ripples, pebbles.
			float r = fract(world_pos.x * 0.9 + world_pos.z * 2.2 + sin(world_pos.x * 0.7) * 0.35);
			c *= step(r, 0.14) > 0.5 ? 0.9 : 1.0;
			c *= n > 0.97 ? 0.8 : 1.0;
		} else if (p == 3) {
			// Snow and ice: sparkles and soft blue hollows.
			c *= n > 0.95 ? 1.12 : (n < 0.08 ? 0.93 : 1.0);
		} else if (p == 4) {
			// Rock: cracks along a coarse grid, light chips.
			vec2 g = world_pos.xz * 3.0;
			bool crack = (fract(g.x) < 0.12 && hash12(floor(g) + 7.0) > 0.55)
					|| (fract(g.y) < 0.12 && hash12(floor(g) + 13.0) > 0.6);
			c *= crack ? 0.74 : (n > 0.92 ? 1.12 : 1.0);
		} else if (p == 5) {
			// Lava: slow bright veins over dark crust, glowing.
			float v = sin(world_pos.x * 2.1 + TIME * 0.9) + sin(world_pos.z * 2.6 - TIME * 1.1)
					+ sin((world_pos.x + world_pos.z) * 1.3 + TIME * 0.5);
			v = floor(v * 2.0) / 2.0;
			c = v > 1.0 ? vec3(1.0, 0.82, 0.3) : (v < -1.0 ? vec3(0.35, 0.1, 0.06) : c);
			EMISSION = c * 0.8;
		}
	}
	if (effects) {
		if (has_heightmap && UV.y < 0.5) {
			c *= cliff_edge(world_pos) ? 0.42 : 1.0;
		}
		c *= cloud_shade(world_pos.xz, TIME, pixels);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float d = hash12(floor(world_pos.xz * pixels) + 17.0);
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, d);
}
