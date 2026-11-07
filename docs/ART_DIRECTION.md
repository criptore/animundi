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

## Shader effects in the game (toggle with E)

| Effect | Where |
|---|---|
| Banded toon light with dithered edges, shared by ground, sprites and water | `shaders/toon.gdshaderinc` |
| Sprites lit like the ground, darkened in tree and cloud shadows, swaying in the wind | `shaders/sprite.gdshader` |
| Tile-top patterns, cliff strata, 1-pixel dark outline where the ground drops, glowing lava | `shaders/terrain.gdshader` |
| Water depth colours, mirrored-camera reflections with pixel ripple, glints, shore foam | `shaders/water.gdshader` |
| Drifting cloud shadows over land and sea | `cloud_shade` in `shaders/toon.gdshaderinc` |
| Diagonal light shafts, warm afternoon grade, vignette, per render pixel | `shaders/post.gdshader` |

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
