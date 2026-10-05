class_name Vis
extends RefCounted
## The single source of the visual scale constants (usable in const expressions, unlike the Game
## autoload, which exposes the same values as Game.VISUAL_SCALE etc.).

## Everything in the world is DRAWN this much bigger (characters, props, walls, effects, telegraphs,
## icons) with matching collision shapes; ranges, speeds and distance constants are untouched.
const VISUAL_SCALE := 1.6
## Base camera zoom: the view shows twice the area (in each direction) of the old one.
const CAM_ZOOM := 0.5
## Screen-aligned enemy overlays (HP bar, ? / ! icons, damage numbers) are drawn this much bigger:
## the camera zoom would otherwise make them unreadable.
const BILLBOARD_SCALE := 2.0
