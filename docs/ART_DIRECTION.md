# Animundi — Art direction

## Main inspiration: David Holland's 3D pixel art

**Reference:** David Holland, *3D pixel art rendering* — https://davidholland.netlify.app/articles/3d-pixel-art-rendering

This is the look Animundi aims for. Every rendering decision is checked against it first. Holland recreates in Godot the 3D pixel art style made popular by t3ssel8r: real 3D scenes rendered at low resolution so they read as hand-made pixel art, with a cosy, soft, lived-in feel.

Techniques described in the article, all to be reproduced:

| Technique | What it does |
|---|---|
| Low-resolution render, nearest-neighbour upscale | the whole scene becomes crisp pixels |
| Stable orthographic camera snapped to the pixel grid | no shimmering when the camera moves |
| Toon lighting in a few bands, shared by every material | ground, grass and trees light the same way, nothing looks pasted on |
| Billboarded grass blades / tufts | soft, swaying grass that is mostly visible at edges of ground shapes |
| Pixel-perfect water: planar reflection (camera rendered to a viewport and projected on the water) + refraction | trees, characters and shores reflected in the water |
| Procedural pixel outlines (depth / normal edges) | dark 1-pixel outlines around trees, rocks and cliffs |
| God rays through trees and rocks | soft light shafts for the cosy mood |

Known limit noted by the author: a perfect outline shader for every model and camera angle is not possible at this resolution, so some edge compromises are expected.

## Shaders in the game

The game renders with Godot's **Forward+** renderer. Its shaders follow the techniques of the t3ssel8r / David Holland style, taken from open-source Godot implementations (credits and licenses in `shaders/vendor/README.md`):

| Technique | Where | From |
|---|---|---|
| Pixel-art outlines (depth edges) and highlights (normal edges), toggle with E | `shaders/vendor/pixelart_stylizer.gdshader` | Leo Peltola (MIT), unmodified |
| Stepped cel lighting shared by ground, sprites and grass | `shaders/cel.gdshaderinc` | Robert-K/godot-3d-pixel-art (MIT) |
| Cloud shadows: the sun ray is followed up to a cloud layer that reads a scrolling noise texture | `shaders/cel.gdshaderinc` | Robert-K/godot-3d-pixel-art (MIT) |
| Sprites and grass lit as one point at their base (`LIGHT_VERTEX`), so each is wholly in sun or shade | `shaders/sprite.gdshader`, `shaders/grass.gdshader` | Robert-K/godot-3d-pixel-art (MIT) |
| Dense billboard grass: 3×3 tuft atlas, ground colour, wind animated at a low frame rate in groups | `shaders/grass.gdshader`, `assets/vendor/grass_atlas.png` | Robert-K/godot-3d-pixel-art (MIT) |
| Texel-snapped camera with sub-pixel display offset (smooth panning, no shimmering) | `scripts/ui/pixel_camera.gd`, `scripts/main.gd` | Robert-K/godot-3d-pixel-art (MIT) |
| Water: depth colours, mirrored-camera reflections with pixel ripple, glints, shore foam | `shaders/water.gdshader` | after David Holland's article |
| Tile-top patterns, cliff strata, glowing lava | `shaders/terrain.gdshader` | Animundi |

Tried and dropped: volumetric godray planes (they washed a beige veil over large parts of a world-sized map; the technique suits close-up scenes).

## Sprites in the 3D world

The camera never rotates, so characters, animals, monsters, trees and plants are **2D pixel-art sprites** standing upright in the 3D world, facing the camera (stretched by 1 / cos(pitch) so they keep their drawn proportions), casting shadows of their own shape on the relief. Their art comes from the reference sheets in `art/reference/` (trees, small plants, biomes, water, races, roles × races, animals, monsters), cut into `assets/sprites/` by `art/extract_sprites.py`. Biome ground and water colours are taken from the biome and water sheets.

Trees and small plants are drawn at a coarser pixel size than the characters in their sheets; the extraction script enlarges them (Scale2x) and paints extra detail (leaf texture, rim light, shading) so every sprite shares the same pixel density in game.

## Secondary references

- **The two reference images given by the project owner** (sunflower pond, stone circle in an autumn glade):
  - warm, soft palette (yellow-greens, light sky, nothing over-saturated);
  - leafy trees made of clustered pixel clumps, dark outlines, a few autumn trees (orange, red, yellow);
  - grass tufts and scattered white flowers;
  - clear water reflecting trees and characters, light horizontal glints;
  - long soft shadows and light shafts;
  - light, rounded rocks.
- **t3ssel8r**: the original creator of this style (YouTube / X videos).
- **Tenkemo** (cozy Godot game): pixelated water, low-resolution shadows — https://80.lv/articles/check-out-water-shaders-in-this-wip-godot-powered-cozy-game
- **Godot forum, replicating t3ssel8r grass**: ground and grass must share identical toon lighting — https://forum.godotengine.org/t/trying-to-replicate-t3ssel8r-grass-shader/123816
- **Free stylized 3D grass shader (CC0, Godot)**: billboard blades, wind from a noise texture, dithered alpha — https://forum.godotengine.org/t/free-stylized-3d-grass-shader-cc0/134880

## Rules

1. **Cosy first.** Soft, warm colours; nothing neon. Calm motion (wind in grass, water glints, drifting light).
2. **Pixels stay pixels.** Everything is rendered at low resolution and upscaled with nearest filtering; effects are computed per render pixel.
3. **One light model.** Terrain, grass, trees, rocks and buildings use the same banded toon lighting.
4. **Readable from far, rich up close.** From the world view, biomes and kingdoms read clearly; zoomed in, the scene looks like the reference images.
5. **Every visual change ships with a screenshot** compared against the references.
