# Tilt view prototype — implementation plan

**Goal:** show the running game from a tilted perspective camera (Cult of the Lamb style: upright pixel-art sprites, stepped terrain, warm lights, tilt-shift) and measure what it costs next to the flat 2D view, on the same world.

**Architecture:** nothing changes in the C# simulation. It already fills 2D-format MultiMesh buffers (plants per strip, units every frame, shadows). `TiltView` shows those same MultiMesh resources through `MultiMeshInstance3D` nodes with a spatial shader that stands each quad up on the ground, so depth sorting comes from the depth buffer. The terrain is a stepped mesh (one height per level) that reads the map's existing colour, data and ground textures. One canvas pass adds blur, vignette and tint.

**Tech stack:** Godot 4.3 .NET, GDScript, Forward+, unshaded spatial shaders.

**Spec:** the mock-up (https://claude.ai/artifact/2TghYCCD2FdegWR4bLzxoE) and `docs/ART_DIRECTION.md`.

## Global constraints

- No change to `sim/`, `scripts/main.gd`, `scripts/render2d/`, `shaders/map.gdshader` or `tests/test_world.gd` (another branch is adding the god powers there).
- No real-time shadows, no second scene pass, no outline pass (what made 0.1 too costly).
- Nearest filtering on every game texture; sprites keep their pixels.
- Heights: sea −0.35, plain 0, hill 0.75, mountain 1.5 tiles; water on land sits 0.15 lower. The same rule in `tilt_terrain.gd` and `shaders/tilt_common.gdshaderinc`.

## Review focus

- A world regenerated after `TiltView.setup` keeps the old terrain mesh and textures (set up again).
- Terrain powers that change a tile's level do not move the mesh yet.
- Mouse picking and village banners still use the 2D camera.
- The simulation is kept in its "far" drawing mode: every unit is written and sorted each frame, which the 3D view does not need.
- Sprites lying flat (camera near 90°) rely on a small height bias for their order.

## Tasks

### 1. Stepped terrain mesh
- Create `scripts/render_tilt/tilt_terrain.gd`: `heights(world) -> PackedFloat32Array`, `chunk_arrays(h, w, hgt, cx, cy) -> Array`, `build(world) -> Array[ArrayMesh]` (chunks of 32 tiles, runs of equal height merged).
- Test `tests/test_tilt.gd`: height rule per level and water; top area of all chunks = width × height; wall area = sum of height drops between neighbours (map border counts as sea).
- Run: `godot --headless --path . --script res://tests/test_tilt.gd` → `0 failed`.

### 2. Shaders
- Create `shaders/tilt_common.gdshaderinc` (tile height, lights, cloud shadows, fog), `tilt_terrain.gdshader` (ground patterns, water, roads, fields, ash, frost, cliff faces), `tilt_sprite.gdshader` (stands a 2D-format instance up, sway, colour mask), `tilt_shadow.gdshader`, `tilt_post.gdshader`.

### 3. View and camera
- Create `scripts/render_tilt/tilt_camera.gd` (perspective, 30° FOV, 52° pitch rising to 82° when far, pan and zoom) and `scripts/render_tilt/tilt_view.gd` (`setup(main)`, `set_enabled(on)`, `set_time(t)`; village lights from `VillageTable`).

### 4. Preview and measure
- Create `tools/tilt_preview.gd`: modes `shot` (tilt and flat screenshots of the same village), `perf` (frame, CPU and GPU render time, draw calls, both views), `play`.
- Run `shot` and look at the image; run `perf` on a 512 world with about 5,000 creatures and record the numbers.
