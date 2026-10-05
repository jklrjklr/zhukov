# Sound slots

Every sound is a named slot: `audio/<slot>.ogg` (or `.wav`). Variants
`<slot>_1.ogg`, `<slot>_2.ogg` ... are picked at random. A missing slot is silent.
To replace a sound, drop your own file with the same name here and rebuild the APK.

| slot | when |
|---|---|
| rifle_shot | Liberator shot (synthesized) |
| smg_shot | Knight shot (synthesized) |
| rocket_launch | EAT-17 launch (synthesized) |
| dry_fire / mag_out / mag_in / bolt | trigger on empty, reload steps |
| throw / dive / stim | grenade or beacon throw, dive, stim |
| player_hit | Helldiver takes damage |
| bot_blaster / bot_heavy_blaster | Trooper / Devastator bolts |
| hit_metal / hit_armor | bullet hits a bot / bounces off armor |
| bot_death | bot destroyed |
| chainsaw / flamer | Berserker saw, Hulk flamer (looped while active) |
| explosion / explosion_big | small / large blasts |
| hellpod_impact | Hellpod or supply pod lands |
| strat_input / strat_error / strat_ready | stratagem arrow, wrong code, code complete |
| beacon | beacon lands |
| eagle_flyby / orbital_shot | Eagle pass, orbital shell |
| pod_open | take from a supply pod |
| bot_drop | dropship arrives |
| pelican | Pelican-1 engines (looped) |
| objective | mission message |
| ui_click | menu buttons |
| plasma_shot | Overseer plasma (borrows bot_heavy_blaster) |
| hit_flesh / claw | bullet hits a squid or Voteless / Voteless claws (borrow player_hit) |
| voteless_death / illuminate_death | Voteless / other Illuminate killed |
| shield_hit / shield_break | Harvester shield hit / collapses |
| watcher_call | Watcher calls a warp ship (borrows beacon) |
| beam_charge / harvester_beam | Harvester beam charging / firing (looped) |
| warp_ship | warp ship arrives (borrows bot_drop) |
| evac_rocket | evac rocket lift-off (borrows explosion_big) |
| sentry_shot | MG-43 sentry (borrows smg_shot) |

Slots marked "borrows" have no file of their own yet: they use the named slot's sound
until you add `<slot>.ogg`.

## Credits

- Kenney "Sci-Fi Sounds", "Impact Sounds", "Interface Sounds" (www.kenney.nl), CC0 1.0.
- rifle_shot*, smg_shot*, rocket_launch, throw, dive, eagle_flyby: synthesized with ffmpeg for this project, CC0.
