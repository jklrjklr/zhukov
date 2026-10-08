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
- **Movement:** floating left joystick, screen-relative; light inertia; strafe/back speed
  penalties. The stick direction is **quantised to 8 directions** relative to the look direction
  (forward, forward-right, right, back-right, back, back-left, left, forward-left; 4 degrees of
  hysteresis at sector borders); only its length is analogue. The body and its sprite face the
  look direction at once (no turn lag).
- **Sprint / run:** stick at the edge + stamina, **only in the 3 forward directions** (forward,
  forward-left, forward-right). In the other 5 directions the player walks even with the stick at
  the edge, and no stamina is spent.
- **Dodge = dive:** DIVE button (Space / C). Committed lunge in the stick direction
  (3.2 m airborne, invulnerable while airborne), then prone slide and getting up with no
  control and no invulnerability: 0.8 s total, so mistimed dives are punished. The dive
  **physically moves along the exact stick direction (not quantised)**. Its animation is chosen
  from the same direction **relative to the look direction**, snapped to 8 (`dive_0..7`), and
  the sprite keeps **facing the look direction** the whole time: the body tips toward the dive
  heading (belly-down forward, on the back for back, on the side for left / right) while the gun
  keeps pointing along the aim line.
- **Attacking in a dive:** a **firearm** can be fired during the airborne part of the dive (the
  gun is held level by IK, bullets go along the look direction from the muzzle); a **melee**
  weapon cannot attack during a dive (`Player.weapon_type`, `can_attack()`).

## Implications to keep in mind

- Sprites rotate with the world, so art must read from any angle (top-down silhouettes,
  no front-facing characters, light direction baked consistently or not at all).
- Bullet-hell rooms: hundreds of bullets drawn in one batch (MultiMesh / one canvas item),
  collision by circle checks in a spatial grid, not physics bodies.

## Character art pipeline (3D -> pre-rendered sprites)

- Sources: `art/3d/` (Kenney "Animated Characters Survivors", CC0: one rig, skins for
  survivors and zombies, idle / run / jump clips). Excluded from exports.
- Bodies: `tools/reshape_character.py` (Blender, `apt install blender`) reshapes Kenney's
  chibi body to stylised 5-heads proportions (the script prints the measured height in heads:
  5.0) (anime/VRoid-like reference: long legs ~47%
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
  - Run: `xvfb-run -a gd --path . --rendering-driver opengl3 --script res://tools/bake_sprites.gd -- <preview dir> [only=walk_,dive_] [skin=survivorMaleB]`
- In game `CharSprite` draws the sheet (1 texel = 1 buffer pixel) and plays locomotion by
  distance travelled (no foot sliding).
- Motion is real mocap: CMU Graphics Lab Motion Capture Database (BVH in `art/mocap/cmu/`,
  credit in its README), retargeted in Blender by `tools/cmu_retarget.py` (called from the
  reshape): world-space rotation transfer between the T-pose rests, facing aligned, travel
  removed (sway kept) or hips locked, automatic seamless loops, mirroring, direction
  segments cut from "navigate" takes. Clips: Idle (82_08), Walk (16_15), Run (16_35),
  WalkBack / WalkLeft (mirrored) / WalkRight (41_02), ZombieWalk (104_41). Mixamo list kept in
  `docs/mixamo_clips.md` for later.
- **Player locomotion sheets** (armed skins, `walk_<tag>`, `run_<tag>`, tag = f, fr, r, br, b, bl, l,
  fl = direction relative to the look direction, clockwise): forward / back / left / right
  walks and the forward run are the mocap clips. The **diagonals re-aim the forward / back gait**
  (no suitable diagonal take exists in the CMU takes we have; blending forward and strafe clips
  gives strides that don't match, and a run can't be blended with a side step): each foot's swing
  around its neutral position is turned 45 degrees about the vertical axis and the legs are re-solved
  with 2-bone IK (knee forward, foot orientation kept), so cadence and leg timing stay mocap and the
  planted foot moves in a straight line against the travel direction. Run exists as `run_f`, `run_fr`,
  `run_fl` only. Every loop is phase-aligned (frame 0 = left foot at its leading extreme) so switching
  direction mid-stride doesn't pop, and its **stride is measured from the planted toes** (written to
  `<clip>.json` `stride`; the mocap hips travel overestimates it by ~20-40%). The bake log prints the
  residual slide per clip (`GAIT ...`). `CharSprite.advance_dir(delta, speed, idx, running)` plays them
  by distance travelled (`stride x UNIT_PX` per loop).
- **Player dive sheets** (`dive_0..7`, direction relative to look): hand-keyed, not mocap, per the
  snappy-player rule. `Poses.dive(heading)` gives 12 key poses (coil, kick-off, flight with one knee
  driven up, flat skid, prone, prop, kneel, rise, stand), the whole body tipping toward the heading
  about the hips; the weapon hold IK works in the aim frame (body rotation undone), so the gun stays
  level and pointing ahead. One sprite frame per key pose, held until the next key (`starts` = key
  times), so the fast part is a few hard cuts and the recovery lingers.
- **Pixel-art rendering rules** (bake):
  - Timing is pose-to-pose, not per time: each clip is rendered densely (32 samples per
    loop, 30 for a ragdoll fall) and only key poses are kept, each held
    until the next (frame phase starts in the clip's .json). Loops keep the pose extremes
    (where the visible joints slow down) plus fills for long gaps; one-shots (dive, deaths)
    keep poses at equal amounts of visible change (deaths), or the hand-keyed poses are
    the keys (dives). Keys: idle 5, walk/run 8, strafe 6, dive 12, death 8.
  - Flat before pixelizing: cel shading (`tools/char_bake.gdshader`: light from above in 3
    flat bands, no gradients), rendered at 2x and reduced by majority vote per pixel, then
    the 1 px ink outline.
  - Crowds: each character has its own phase offset and pace, so none move in lockstep.
- Preview tools: `tools/clip_preview.gd` (side-view filmstrips of the model's clips),
  `tools/sheet_preview.gd` (baked top-down sheets with gun anchors).
- Procedural layers (`tools/poses.gd`, keyed bone directions / IK) on top of the mocap:
  - **weapon hold** (`Poses.hold(pitch)`): shouldered rifle solved with 2-bone IK (stock in
    the right shoulder pocket, gun beside the right cheek, right hand on the grip with the
    elbow out, left arm forward on the foregrip), counter-rotated by the body pitch so the
    gun stays level. Every pose of an armed character must keep it:
    `idle_aim`, the walk / run sheets and the dives use it; deaths drop the gun.
  - **deaths** (physics ragdoll, `tools/ragdoll.gd`, Jolt at 240 Hz): the body starts from
    its stance (gun hold), takes a hit impulse and falls limp; 8 push directions (45 deg) x 3
    seeded variants (force, lift, spin) = `death_d<dir>_<v>`, 10 frames over 1.5 s. Sheets
    are cropped to the area the fall uses (rect in the clip's .json).
    `CharSprite.play_death(push)` picks the nearest direction and a random variant.
- Weapons are not baked into the sprites: armed clips export per-frame anchors
  (`<clip>.json`: grip offset px, gun angle) and `CharSprite` draws the weapon there, under
  the arms. Any weapon art fits every armed pose without re-baking.
- Tests: `gd --headless --script res://tools/smoke_test.gd` and `tools/player_test.gd` (movement
  quantisation, run refusal, exact dive direction, dive animation index, facing, firing / melee in a
  dive). Preview video / gif: `sh tools/player_preview.sh` -> `docs/preview/`.
- After a bake run `godot --headless --import` so the game picks up the new PNGs.
- New characters / clips: add the FBX (same rig) and list the skin / clip in the tool.
  Shooting / hit / death clips will need a source with those animations (same rig).

## Art and motion rules

Goal: stylish but heavy — things look like they weigh something and hurt, and the screen stays
readable on a phone.

- **Style:** everything (characters, enemies, props, ground, effects) is 3D models pre-rendered
  top-down into pixel-art sprites per the pipeline above. All art is made beforehand as image files,
  never generated on the phone during play; one atlas per group so draws batch.
- **Outline:** 1 px ink outline on actors and pickups only; ground, walls and rocks have none.
- **Readability:** every enemy type recognisable as a black silhouette at phone size. Value order:
  ground darkest, props mid, enemies mid-light, player and pickups lightest, danger brightest.
  The world is desaturated; saturated colour only where it means something.
- **Colour meanings (fixed):** red = danger and enemy attacks; yellow = player and objectives;
  blue = friendly tech; orange = fire. Never used for decoration.
- **Telegraphs:** every attack that can hurt the player shows its area or line first (≥ 0.4 s).
- **Impacts:** every hit has a flash (1–2 frames), particles, a lasting decal and a sound. Big hits
  add screen shake and 30–80 ms hit-stop. Explosions: flash → fireball → smoke → debris → scorch.
- **Effects never hide threats:** most fade under 0.5 s; smoke is low and semi-transparent.
- **Scale contrast:** small enemies smaller than the player, heavies clearly bigger.
- **Damage shows on the body** (cracks, missing parts, limping); health bars only where the body can't.

### Motion rule: snappy player, real enemies

- **Player is a superhero:** responds in 1–2 frames, short acceleration, no turn lag; dive, reload
  and throws can cancel each other. Weight comes from timing contrast (short wind-up, very fast
  action, held recovery) and exaggerated hand-keyed poses, not from input delay.
- **Enemies are real:** realistic, seamless motion with mass — planted feet (cycles played by
  distance travelled), mass-limited acceleration and turning, lagging secondary motion, blended
  hit flinches, physical slide-and-crumple deaths. Enemy sheets get dense frames so motion stays
  smooth at pixel resolution; mocap is used for enemies.
- **Player deaths** are short and readable: knockback toward the hit, crumple, done.

### Budget

Under 500 draw calls in a big fight, under 200 idle; texture memory under about 200 MB; 60 fps at
1080p on a mid-range phone.
