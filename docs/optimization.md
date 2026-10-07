# Rendering and performance rules (budget Android)

Target: steady 60 fps (30 fps fallback) on budget phones (Mali-G52 / Adreno 610 class,
2-3 GB RAM), Godot 4.6 GL Compatibility renderer.

## Pixel look = low-res render (already in place)

- The world renders into a SubViewport `Vis.PIXEL_HEIGHT` (360) px tall, width from the
  screen aspect (~800 on 20:9), then one full-screen quad upscales it (`PixelView`).
  A post-process "pixelate" shader on a full-res frame would cost MORE (full-res render +
  a screen-read pass); rendering small is both the look and the main saving:
  ~0.3 M fragments instead of ~2.6 M at 2400x1080.
- Upscale shader `shaders/pixel_upscale.gdshader`: sharp bilinear, one texture tap.
  Square pixels, no shimmer at non-integer scale or while the camera rotates.
- Camera transform snapped to whole buffer pixels; the remainder shifts the upscaled quad
  (`PixelView`), so scrolling is smooth without pixel wobble.
- UI is NOT in the buffer: it draws at native resolution on the root viewport.
- Tunables: `Vis.PIXEL_HEIGHT` (chunkiness and fill cost), `Vis.CAM_ZOOM` (how much world
  fits; at 0.4 one buffer pixel = 2.5 world px).
- Dead Cells reference: 3D models rendered at tiny size to pixel sprites (+ normal maps for
  lighting). Same idea is available to us later: author/bake sprites at buffer scale
  (1 sprite texel = 1 buffer pixel) so art never gets resampled.

## Fill rate / GPU (tile-based mobile GPUs)

- Everything world-side is drawn at buffer resolution, so overdraw is cheap but still
  avoid big transparent layers stacked over the whole screen.
- No `SCREEN_TEXTURE` / `BackBufferCopy` / `hint_screen_texture`: forces a resolve on
  tile GPUs. Effects that need the scene go into the upscale shader (one pass) instead.
- No Light2D / shadows / occluders in Compatibility: each light re-draws every lit item.
  Fake lighting with additive sprites, baked gradients, or a palette/light term in the
  upscale shader.
- Keep shaders short: no loops, few texture taps, `lowp`-friendly math.
- Disable 3D on 2D viewports, no MSAA (pixel art does not need it).

## Draw calls / CPU

- Budget: under ~100 draw calls in a fight on budget phones (measured in the old build:
  2200 -> 15 by baking static ground into textures).
- 2D batching only merges items with the same texture + material + no state change:
  use texture atlases, one shared material per layer, avoid per-node unique materials.
- Static stuff (ground, decals, props): bake into textures once (render to a SubViewport
  once, `UPDATE_ONCE`) instead of redrawing with `_draw()` every frame.
- Many similar things (enemies, bullets, particles): MultiMeshInstance2D or one node that
  draws them all; never one node per bullet.
- MultiMesh: don't change `visible_instance_count` every frame (measured ~20 ms/frame
  hit before); hide unused instances by zero-scaling them instead.
- `queue_redraw()` only when something changed; `_draw()` with hundreds of primitives
  per frame is CPU-heavy in GDScript.
- GPUParticles2D are fine in Compatibility (transform feedback), but warm them up
  at load (first emit compiles the shader -> hitch). Same for every new shader/material:
  draw it once off-screen during loading.

## Physics / scripts

- `physics_ticks_per_second` 60 now; if CPU-bound, drop to 30 and turn on
  `physics/common/physics_interpolation`.
- Throttle AI (raycasts, path queries) to a few Hz and stagger across frames.
- Avoid allocations in hot loops (new Arrays/Dictionaries per frame), `get_nodes_in_group`
  per frame, and string building per frame.

## Memory / loading

- Pixel-art textures: lossless (no VRAM compression artifacts), small, atlased;
  nearest filter, no mipmaps.
- Audio: Ogg for music (streamed), short WAV for frequent SFX (no decode cost).
- Preload per level, not everything at boot.

## Frame pacing / battery

- `run/max_fps=60`, vsync, Android frame pacing (Swappy) are on. Offer a 30 fps
  option: thermals on cheap phones throttle after a few minutes.

## Measuring

- `tools/smoke_test.gd` (headless logic checks).
- `tools/capture.gd` (real renderer screenshots under xvfb).
- On device: `Performance.get_monitor(RENDER_TOTAL_DRAW_CALLS_IN_FRAME)` and frame time;
  a perf overlay should come back once there is content to measure.

## Sources

- Dead Cells pipeline: https://80.lv/articles/case-study-dead-cells-character-art-pipeline/
- Godot viewports: https://docs.godotengine.org/en/4.4/tutorials/rendering/viewports.html
- Godot renderers: https://docs.godotengine.org/en/4.4/tutorials/rendering/renderers.html
- Sharp linear upscale: https://godotshaders.com/shader/adjustable-strength-sharp-linear-interpolation/
