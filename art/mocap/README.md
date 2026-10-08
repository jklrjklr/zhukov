# Motion capture sources (free licences only)

Both datasets are retargeted to our rig by `tools/cmu_retarget.py` (called from
`tools/reshape_character.py`); the player's clips are then turned into key poses by
`tools/keypose.py`. Not used on purpose: datasets with non-commercial / no-derivatives licences
(e.g. Bandai Namco ND) and Mixamo (needs a login).

## CMU Graphics Lab Motion Capture Database (`cmu/`)

http://mocap.cs.cmu.edu - free to use, including in commercial products; the raw data may not be
resold as a motion database. BVH conversion from github.com/una-dinosauria/cmu-mocap.
"The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with
funding from NSF EIA-0196217."

Used: 82_08 (idle), 16_15 / 16_35 (enemy walk / run), 41_02 (enemy strafe / back), 104_41 (zombie
walk), **127_23 "Run Dive Over Roll Run" (the player's dive: coil, push, extended flight, tumble,
roll, crouch, rise)**. Candidates evaluated but not kept (fetch from the same BVH mirror when
needed): 127_09..14 run side steps, 127_21 run-jump-stop, 128_09 run roll underneath, 136_09 / 136_11
crouched walks, 141_05 / 143_07 jump sideways, 111_06 get up from the floor, 111_21 roll over.
Some takes (e.g. 81_12 jump backwards, 83_x sidesteps, 77_16 getting up) are not in that mirror.

## 100STYLE (`100style/`)

Ian Mason, Sebastian Starke, Taku Komura: "100STYLE Dataset", Zenodo, 2023,
https://zenodo.org/records/8127870 - licence **CC BY 4.0** (checked on the record page and in its
API metadata: `cc-by-4.0`). Attribution: *100STYLE dataset, I. Mason, S. Starke, T. Komura,
CC BY 4.0*; the files here are cut to the time ranges used (8 s .. 40 s of the original takes).

Used: style **Proud** (confident, chest out), `Proud_FW` (forward walk), `Proud_FR` (forward run),
`Proud_BW` (backward walk), `Proud_SW` (sideways walk; the other direction is its mirror) ->
the player's walk_f/b/r/l and run_f sheets. Only these four files were downloaded from the 1.4 GB
archive (HTTP range requests); the other styles (Military does not exist in the set; Heavyset,
Stiff, Neutral, Angry, March ...) can be fetched the same way.
