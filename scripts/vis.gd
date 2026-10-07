class_name Vis
extends RefCounted
## Visual scale constants.

## Characters and props are DRAWN this much bigger (with matching collision shapes);
## speeds and distances are untouched.
const VISUAL_SCALE := 1.6
## The world is rendered into a buffer this many pixels tall (width follows the screen
## aspect), then upscaled to the screen: the pixel look, and ~9x fewer fragments than
## native 1080p on phones.
const PIXEL_HEIGHT := 360
## Base camera zoom: buffer pixels per world px (0.4 = 1 pixel covers 2.5 world px,
## so the view is 900 world px = 15 m tall).
const CAM_ZOOM := 0.4
