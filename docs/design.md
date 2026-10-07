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
- **Dodge = dive:** DIVE button (Space / C). Committed lunge in the stick direction
  (3.2 m airborne, invulnerable while airborne), then prone slide and getting up with no
  control and no invulnerability: 0.8 s total, so mistimed dives get punished.

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
- Clips the pack lacks are posed procedurally from keyed bone directions (`tools/poses.gd`):
  - **weapon hold** (`Poses.hold(pitch)`): two-handed rifle hold, counter-rotated by the
    body pitch so the gun stays level. Every pose of an armed character must keep it:
    `idle_aim` / `run_aim` (FBX legs + hold arms) and the dive use it; deaths drop the gun.
  - **dive** (HD2-style, 16 frames, 128 px): crouch + push-off, flat flight with one knee
    kicked up, chest-first landing, slide, separate get-up (left hand pushes off, knee
    under, kneel, stand); gun held level throughout. Mirrored at random in game.
  - **deaths** (10 frames, 160 px, ragdoll-like): back x3, face-down x3, left / right side,
    crumple x2; random elbow / knee bends, spine twist, lolling head, impact overshoot.
    `CharSprite.play_death(push)` picks by hit direction and mirrors at random.
- Weapons are not baked into the sprites: armed clips export per-frame anchors
  (`<clip>.json`: grip offset px, gun angle) and `CharSprite` draws the weapon there, under
  the arms. Any weapon art fits every armed pose without re-baking.
- New characters / clips: add the FBX (same rig) and list the skin / clip in the tool.
  Shooting / hit / death clips will need a source with those animations (same rig).
