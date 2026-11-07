// Map effects on top of the 8x8 tile art: relief lighting, animated water and drifting cloud shadows.
// Every effect is computed per art pixel and quantised, so the result stays pixel art.
shader_type canvas_item;

// One pixel per tile, see MapRenderer.render_shader_data(): R land height, G sea depth, B open water.
uniform sampler2D data_tex : filter_linear, repeat_disable;
uniform sampler2D cloud_noise : filter_linear, repeat_enable;
uniform vec2 world_tiles = vec2(256.0, 256.0);
uniform float tile_pixels = 8.0;

uniform bool effects = true;
uniform float relief_strength = 2.0;
uniform vec3 light_dir = vec3(-1.0, -1.2, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.25, 0.62, 0.92, 1.0);
uniform vec4 deep_color : source_color = vec4(0.07, 0.2, 0.48, 1.0);
uniform vec4 foam_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);
uniform float cloud_amount = 0.42;
uniform float cloud_speed = 0.006;

// Rounds a value to steps, for the banded, pixel-art look.
float steps(float v, float n) {
	return floor(v * n + 0.5) / n;
}

void fragment() {
	vec4 art = texture(TEXTURE, UV);
	if (!effects) {
		COLOR = art;
	} else {
		vec2 map_px = world_tiles * tile_pixels;
		// Centre of the art pixel this fragment belongs to: effects are constant inside it.
		vec2 px = floor(UV * map_px) + 0.5;
		vec2 uv = px / map_px;
		vec2 tile = 1.0 / world_tiles;
		vec4 data = texture(data_tex, uv);
		float water = step(0.5, data.b);

		vec3 col = art.rgb;

		// Relief: light the heightmap from the north-west, in a few bands.
		float hx = texture(data_tex, uv + vec2(tile.x, 0.0)).r - texture(data_tex, uv - vec2(tile.x, 0.0)).r;
		float hy = texture(data_tex, uv + vec2(0.0, tile.y)).r - texture(data_tex, uv - vec2(0.0, tile.y)).r;
		vec3 n = normalize(vec3(-hx * relief_strength * 8.0, -hy * relief_strength * 8.0, 1.0));
		float lit = dot(n, normalize(light_dir)) - dot(vec3(0.0, 0.0, 1.0), normalize(light_dir));
		// Three crisp bands (shadow / flat / lit) keep it pixel art instead of a smooth gradient.
		float relief = steps(clamp(lit * 1.6, -0.3, 0.2), 5.0) * 0.8;
		col *= 1.0 + relief * (1.0 - water);

		if (water > 0.5) {
			// Depth colour in bands, then the tile art on top of it, faintly.
			float depth = steps(clamp(data.g * 1.8, 0.0, 1.0), 5.0);
			vec3 sea = mix(shallow_color.rgb, deep_color.rgb, depth);
			col = mix(sea, art.rgb, 0.18);
			// Waves: thin moving crests on a pixel grid.
			float wave = sin(px.x * 0.21 + px.y * 0.07 + TIME * 1.3 + sin(px.y * 0.11 + TIME * 0.5) * 3.0);
			float crest = step(0.94, wave) * (1.0 - depth * 0.6);
			col = mix(col, foam_color.rgb, crest * 0.35);
			// Foam where the sea meets the land, breathing in and out.
			float shore = 1.0 - smoothstep(0.0, 0.035, data.g);
			float land_near = max(max(texture(data_tex, uv + vec2(tile.x, 0.0)).r, texture(data_tex, uv - vec2(tile.x, 0.0)).r),
					max(texture(data_tex, uv + vec2(0.0, tile.y)).r, texture(data_tex, uv - vec2(0.0, tile.y)).r));
			float pulse = 0.5 + 0.5 * sin(TIME * 1.6 + px.x * 0.05 + px.y * 0.05);
			float foam = step(0.55, shore * step(0.0001, land_near) * (0.6 + 0.4 * pulse)
					+ 0.25 * step(0.85, fract(sin(dot(px, vec2(12.9898, 78.233))) * 43758.5453)));
			col = mix(col, foam_color.rgb, foam * shore * 0.7);
		}

		// Cloud shadows drifting slowly over everything.
		float cloud = texture(cloud_noise, uv * 2.2 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4)).r;
		float shadow = step(1.0 - cloud_amount, cloud) * 0.16;
		col *= 1.0 - shadow;

		COLOR = vec4(col, art.a);
	}
}
