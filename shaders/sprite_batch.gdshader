// Sprites drawn in batches from the sprite atlas (scripts/render2d/sprite_batch.gd): every instance
// is a unit quad (feet at the origin) scaled to the sprite's size; its custom data is the sprite's
// rectangle in the atlas. Shadows use the same shader on a shadow texture, without custom data.
shader_type canvas_item;

uniform bool from_atlas = true;

void vertex() {
	if (from_atlas) {
		UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
	}
}
