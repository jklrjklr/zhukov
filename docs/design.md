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
- Bodies: `tools/reshape_character.py` (Blender, `apt install blender`) reshapes Kenney's
  chibi body to stylised ~5-heads proportions (anime/VRoid-like reference: long legs ~47%
  of height, short torso, smaller head), sculpts the torso profile (male V-taper / female
  narrow waist + hips), subdivides for curves and re-exports the clips on the new rest pose
  -> `characterHuman.glb` / `characterHumanF.glb`:
  `blender -b --python tools/reshape_character.py -- <in.fbx> <out.glb> male|female`.
  `tools/model_preview.gd` renders front T-poses (original vs reshaped) to check.
- Look: narrowed head; faceless (front of the head below the hairline takes the skin tone);
  survivors wear a black formal suit (white shirt, collar, cuffs, black tie, lighter lapels)
  painted per face into the mesh colours with crease shading; `tools/char_bake.gdshader`
  mixes it over the skin texture with fabric grain, a soft sheen and rim. Zombies keep rags.
- `tools/bake_sprites.gd` renders each skin x clip straight down with an orthographic camera
  into `art/sprites/<skin>/<clip>.png` (one row of 64 px frames, facing up):
  - light from straight above + ambient (sprites rotate in game, so no side light baked),
  - binary alpha + 1 px ink outline, centred on the idle silhouette.
  - Run: `xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/bake_sprites.gd -- <preview dir>`
- In game `CharSprite` draws the sheet (1 texel = 1 buffer pixel), picks idle / run from
  speed and advances the run cycle by distance travelled (no foot sliding).
- Realistic motion: CMU Graphics Lab mocap (BVH), retargeted to the rig in Blender (Mixamo
  list kept in `docs/mixamo_clips.md` for later); keyed clips are stand-ins until replaced.
- Clips the pack lacks are posed procedurally from keyed bone directions (`tools/poses.gd`):
  - **weapon hold** (`Poses.hold(pitch)`): shouldered rifle solved with 2-bone IK (stock in
    the right shoulder pocket, gun beside the right cheek, right hand on the grip with the
    elbow out, left arm forward on the foregrip), counter-rotated by the body pitch so the
    gun stays level. Every pose of an armed character must keep it:
    `idle_aim` / `run_aim` (FBX legs + hold arms) and the dive use it; deaths drop the gun.
  - **dive** (HD2-style, 16 frames, 128 px): crouch + push-off, flat flight with one knee
    kicked up, chest-first landing, slide, separate get-up (left hand pushes off, knee
    under, kneel, stand); gun held level throughout. Mirrored at random in game.
  - **deaths** (physics ragdoll, `tools/ragdoll.gd`, Jolt at 240 Hz): the body starts from
    its stance (gun hold), takes a hit impulse and falls limp; 8 push directions (45 deg) x 3
    seeded variants (force, lift, spin) = `death_d<dir>_<v>`, 10 frames over 1.5 s. Sheets
    are cropped to the area the fall uses (rect in the clip's .json).
    `CharSprite.play_death(push)` picks the nearest direction and a random variant.
- Weapons are not baked into the sprites: armed clips export per-frame anchors
  (`<clip>.json`: grip offset px, gun angle) and `CharSprite` draws the weapon there, under
  the arms. Any weapon art fits every armed pose without re-baking.
- After a bake run `godot --headless --import` so the game picks up the new PNGs.
- New characters / clips: add the FBX (same rig) and list the skin / clip in the tool.
  Shooting / hit / death clips will need a source with those animations (same rig).
