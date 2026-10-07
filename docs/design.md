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
