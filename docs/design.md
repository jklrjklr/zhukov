# Design direction

Roguelite shooter in the spirit of Enter the Gungeon / Soul Knight, with hardcore,
skill-based player control. Mobile first (budget Android), desktop for testing.

## Decided

- **View:** pure top-down, pixel art (low-res buffer, see `optimization.md`).
- **Camera:** rotating, as now. Right-side swipe turns the camera; screen-up is always
  where the player looks. Body follows at a limited turn rate.
- **Aim:** the look direction (swipe). Options, toggleable in settings:
  - **Auto-fire:** shoots while an enemy is in the aim cone (no fire button needed).
  - **Aim assist:** bends aim / bullets slightly toward the nearest enemy in the cone.
- **Movement:** floating left joystick, screen-relative; light inertia; strafe/back
  speed penalties; sprint (stick at edge) limited by stamina.

## Implications to keep in mind

- Sprites rotate with the world, so art must read from any angle (top-down silhouettes,
  no front-facing characters, light direction baked consistently or not at all).
- Bullet-hell rooms: hundreds of bullets drawn in one batch (MultiMesh / one canvas item),
  collision by circle checks in a spatial grid, not physics bodies.

## Character art pipeline (3D -> pre-rendered sprites)

- Sources: `art/3d/` (Kenney "Animated Characters Survivors", CC0: one rig, skins for
  survivors and zombies, idle / run / jump clips). Excluded from exports.
- `tools/bake_sprites.gd` renders each skin x clip straight down with an orthographic camera
  into `art/sprites/<skin>/<clip>.png` (one row of 64 px frames, facing up):
  - head bone scaled to 0.6 (Kenney models are chibi; from above the head hid the body),
  - light from straight above + ambient (sprites rotate in game, so no side light baked),
  - binary alpha + 1 px ink outline, centred on the idle silhouette.
  - Run: `xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/bake_sprites.gd -- <preview dir>`
- In game `CharSprite` draws the sheet (1 texel = 1 buffer pixel), picks idle / run from
  speed and advances the run cycle by distance travelled (no foot sliding).
- New characters / clips: add the FBX (same rig) and list the skin / clip in the tool.
  Shooting / hit / death clips will need a source with those animations (same rig).
