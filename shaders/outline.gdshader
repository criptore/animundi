// Pixel outline for trees, bushes and rocks (inverted hull): the model's back faces, pushed out
// along the normals by about one render pixel and drawn in a dark shade of the object's colour.
// Used as the next pass of the foliage materials; `width` is updated by main.gd from the zoom.
shader_type spatial;
render_mode unshaded, cull_front;

uniform float width = 0.05;
uniform vec4 ink : source_color = vec4(0.16, 0.17, 0.15, 1.0);

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = mix(ink.rgb, COLOR.rgb * 0.35, 0.45);
}
