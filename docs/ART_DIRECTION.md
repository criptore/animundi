# Animundi — Art direction

## Direction: flat 2D pixel art, built like WorldBox

The world is shown **from above, flat, in 2D pixel art**, the way WorldBox does it (see [WORLDBOX_ANALYSIS.md](WORLDBOX_ANALYSIS.md)). This keeps rendering almost free, so the machine's power goes to the simulation of thousands of beings and to the AI minds, which are the game's edge.

| Layer | How it is drawn |
|---|---|
| Map | **One texture, one pixel per tile**, scaled up with sharp pixels. Biome colour with slight per-tile variation; height told by colour (the five levels: deep sea, shallow water, plain/beach, hill, mountain) and a one-pixel darker edge where the ground steps down; a light pixel pattern (grass, sand, snow, rock) appears when zoomed in |
| Water | Depth colours from the water sheet, cheap animated glints and shore foam |
| Sprites | The 2D sprites cut from the reference sheets, **drawn in batches** (thousands per draw call), sorted by screen height, each with a small drawn shadow |
| Zoom | Zoomed out: units become dots in their kingdom or species colour, small plants are hidden. Zoomed in: full sprites and patterns |
| Effects | Cheap only: wind sway, water, fire, smoke, magic and weather particles in pixels. **No real-time lighting or shadows** |

## Sprites

All characters, animals, monsters, trees and plants come from the reference sheets in `art/reference/` (trees, small plants, biomes, water, races, roles × races, animals, monsters), cut into `assets/sprites/` by `art/extract_sprites.py`: background and drop shadows removed, each sprite brought back to its true pixel grid. Trees and small plants, drawn coarser in their sheets, are enlarged with Scale2x and given extra painted detail so every sprite shares the same pixel density. Biome ground and water colours come from the biome and water sheets.

**Generated content gets generated sprites.** Objects, buildings, banners and new variants invented by the generators or the AI are assembled from templates, parts and the culture's palette, in the same style as the reference sheets, and change with the age.

## Rules

1. **Cheap to draw.** Every visual choice is checked against the cost of drawing thousands of units: one texture for the map, batched sprites, no per-pixel lighting.
2. **Pixels stay pixels.** Nearest filtering everywhere, whole-pixel positions and steps.
3. **Readable from far, rich up close.** From the world view, biomes, kingdoms and cities read like a map; zoomed in, sprites and patterns show their detail.
4. **Cosy palette.** Soft, warm colours from the reference sheets; nothing neon.
5. **Every visual change ships with a screenshot** compared against the references.

## History: the 3D pixel-art prototype (0.1)

Version 0.1 explored a 3D pixel-art look after David Holland's *3D pixel art rendering* (https://davidholland.netlify.app/articles/3d-pixel-art-rendering) and t3ssel8r: terraced 3D terrain rendered at low resolution, sprites standing in the 3D world lit at their base, cel lighting, cloud shadows, billboard grass, mirrored-camera water reflections, Leo Peltola's outline & highlight pass and a sub-pixel camera (techniques adapted from Robert-K/godot-3d-pixel-art and Leo Peltola, credited in `shaders/vendor/README.md`). It looked good but cost too much for a world with thousands of units (real-time shadows, the scene drawn twice for reflections, post-processing, Forward+ renderer), so the game moves to the flat 2D approach above. The prototype stays in the repository history (merge of pull request #2).
