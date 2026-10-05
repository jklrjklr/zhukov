# Vertical slice v0.5 — spec

Goal: one playable Terminid planet of the roguelite (design doc: https://claude.ai/code/artifact/04601c50-13f3-4227-93a1-1bc13aec5ccf), built on the existing Godot 4.6 code (player, firearms, terminids, stratagems, Sfx, touch controls, vision). Mobile (Android) + Web. Top-down.

## Mission flow
- Chain: Insertion zone → passage → Middle zone → passage → Extraction zone.
- Zone = shrunk HD2 map, about 120 × 120 m (use Firearm.PX_PER_M for scale). Contents per zone:
  - 1 main objective (insertion: "Destroy bug nest" = 3 holes to grenade/explode; middle: "Upload data" = terminal hold 8 s while bugs attack; extraction zone: none).
  - 0–1 optional objective (e.g. "Kill elite": a Charger).
  - 1 outpost (bug holes spawning small bugs while alive), 2 POIs (sample pickup, ammo crate).
  - Patrols walk in from the edges; alerted bugs can call a breach (existing system).
- Passage: 20 m corridor, roofed (Eagle/orbital beacons inside are refused with strat_error), no spawns. Crossing its midline seals it behind (rockslide / door animation + sound); the zone's uncleared objectives fail (HUD warns at the entrance listing them). Bugs already inside come along. Next zone's enemies start unaware.
- Extraction zone: terminal. Using it calls Pelican-1, which lands 3–5 s later (animation), player boards → mission complete screen. Uncleared objectives = failed. No defend phase.

## Timer (two stages)
- Main timer starts at 8:00. Each zone clear (that zone's main objective done) adds 1:30, capped at 10:00.
- At 2:00 left: departure warning. Announcement "Super Destroyer preparing to leave low orbit." Meter fill and Eagle rearm stop; held charges usable. A zone clear in this stage adds time and returns to the main stage.
- At 0:00: departed. "Super Destroyer has left orbit." All stratagems lock. Reinforcements escalate. Any death after departure = run over regardless of reinforcements left. Pelican still answers the terminal.
- Warnings at 5:00 and 1:00.

## Stratagems (meter)
- Each stratagem has charges and a points meter. Cost = HD2 cooldown × 10 points (EAT-17 70 s → 700). Meter fills 10 points/s passively, + points on kills (light 10, medium 30, heavy 150) and objectives (main 300, optional 150). Full meter = +1 charge (cap shown on the HUD).
- Slice loadout: Resupply (1 box, not refilling by meter more than once per zone), EAT-17, Eagle Airstrike (Eagle rearm meter after Eagle Rearm is called; keep simple: 2 uses, then rearm meter 1500 pts), Orbital 120mm HE Barrage (centre-weighted Gaussian σ=0.45 R, R=27 m, redraw outside R), MG-43 Sentry (existing sentry.gd).
- Input (no arrow entry any more): the Helldiver types the HD2 code automatically, 0.1 s per arrow (Orbital Precision 0.3 s, Eagle Airstrike 0.4 s, EAT-17 0.5 s, 120mm 0.6 s). While typing: arm-raised pose, small arrow glyphs tick above the head, one `strat_input` per arrow, `strat_ready` at the end. Walking is allowed (no sprint); a dive or a stagger/knock-down interrupts and typing must restart (a quick throw is dropped, in aim mode typing starts over). Then the beacon is thrown with the existing meter / charge / beacon / landing logic. Code: `scripts/stratagems.gd`; UI: `scripts/ui/strat_menu.gd` (radial, list, aim overlay), input in `scripts/touch_controls.gd`.
  - Touch, two ways on the STRAT button: (1) press-and-swipe: a radial menu of the loadout opens around the thumb (unavailable ones greyed with charges / meter %), swipe toward one and release = selected, auto-typed, thrown in the current aim direction at 12 m (shorter if a wall blocks it); release in the centre dead-zone cancels. (2) tap: list menu (large rows, locked rows show the reason) -> tap one -> aim mode: throw arc + landing marker with the effect footprint (barrage circle R 27 m, Eagle line perpendicular to the throw, 500 kg / orbital circle, pod / sentry footprint); drag anywhere on the right half moves the landing point (max 20 m, camera eases toward it), THROW button or releasing the drag throws (waits for the code to finish), CANCEL exits.
  - Desktop / web: hold Q (or middle mouse) = radial, move the mouse toward a stratagem and release; tap Q = menu, then click one or press 1-5 (also straight from the game) = aim mode with the mouse as landing point, left click throws, right click / Q cancels. (Keyboard turning moved to the Left / Right arrows.)
  - Locked stratagems cannot be picked and say why (menu text, `strat_error`, banner): after departure ("offline"), no charge (meter %), re-use lockout, Eagle / orbital in a roofed passage ("no sky access"; also checked at the landing point).
- Reinforce: 5 lives; death respawns by hellpod near the player's last position after 3 s (not after departure).

## Lives and run end
- Start 5 reinforcements. 0 left and dead = run lost screen. Extraction = mission complete screen with objectives done/failed, kills, samples, time.

## Audio (must be complete — "silent most of the time" was the complaint)
- Every gameplay event has a sound: player gun shots/reload/empty, footsteps (player + big bugs), every bug: idle chitter, alert screech, attack, hurt, death, burrow/breach; explosions, stratagem input/complete/beacon/hellpod/eagle/orbital whistle+impact, sentry, passage seal, objective progress/complete/fail, terminal beeps, Pelican approach/land/takeoff, timer warnings, UI.
- Ambience loop per zone (wind + distant insects) and music: calm bed, combat layer that fades in when enemies are alerted, extraction stinger.
- Announcements: radio-style voice lines are not available; use a short radio chirp + on-screen text banner.
- All sounds are CC0 (Kenney packs) or synthesized with ffmpeg. A headless test lists every Sfx slot used in code and fails if any slot has no file.

## Graphics (keep style, add information and detail)
- Ground: tiled noise texture per biome with decals (cracks, rocks, grass tufts), props with drop shadows, height-shaded walls.
- Persistent decals: blood (bug goo green/orange), scorch, bile, shell casings, bullet impacts.
- Effects: muzzle flash, tracers, hit sparks vs. armor (yellow) / flesh (goo), explosion with shockwave ring + debris + smoke, beacon light pillar, hellpod streak, Eagle shadow pass, orbital shell whistle marker.
- Enemy readability: visible body parts; armored parts drawn with plating; hit flash; "armor bounce" ricochet icon; small HP bar only on heavies and after being damaged; awareness icon (? / !) above bugs.
- Player: aim laser/cone, reload ring, stamina bar, stim count.
- HUD: top-left objectives list (main/optional, status), top-centre mission timer with stage colour, top-right minimap of the current zone (fog, objectives, POIs, exit), bottom: stratagem bar (icon, charges, meter fill), ammo/mags, grenades, stims, reinforcements, samples; banners for announcements; damage direction indicator.
- Must stay 60 fps on mid Android; draw with _draw() / MultiMesh, no heavy shaders.

## Shared sound slot names (audio agent makes the files; code agents call Sfx with these)
Player: footstep, footstep_run, dive, stim, player_hit, player_death, rifle_shot, smg_shot, shotgun_shot, rocket_launch, dry_fire, mag_out, mag_in, bolt, throw, grenade_bounce, pickup_ammo, pickup_sample.
Bugs: bug_chitter (idle, small), bug_alert (screech), bug_attack, bug_hurt, bug_death, bug_big_step (Charger), charger_roar, charger_charge, bile_spit, bile_splash, burrow, breach (bug breach rumble), nest_hole_destroyed.
Hits: hit_flesh, hit_armor (ricochet), hit_ground, hit_metal.
Explosions: explosion, explosion_big, debris.
Stratagems: strat_open, strat_input, strat_error, strat_ready, beacon, hellpod_streak, hellpod_impact, eagle_flyby, eagle_bomb, orbital_whistle, orbital_shot, sentry_shot, sentry_deploy, resupply_open.
Mission: passage_seal, objective_progress, objective_complete, objective_failed, terminal_beep, upload_loop, radio_chirp, timer_warning, departure_alarm, pelican_approach, pelican_land, pelican_takeoff, mission_complete, mission_failed, reinforce.
UI: ui_click, ui_back.
Loops (Sfx.hold / music API): amb_wind, amb_insects, music_calm, music_combat, music_extract (stinger), upload_loop, pelican (engine).
