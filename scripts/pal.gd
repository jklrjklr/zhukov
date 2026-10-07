class_name Pal
extends RefCounted
## The colour palette. Everything in the world picks from here so the frame stays coherent:
## cool, dark teal-green ground, violet-grey stone, warm accents (skin, cloak, flowers).

const INK := Color("120e14") # outlines
const SHADOW := Color(0.05, 0.03, 0.09, 0.42) # drop shadows (multiplied over the ground)

const GROUND := [Color("18281f"), Color("1d3025"), Color("22382a"), Color("284030")]
const GRASS := Color("4f7a4a")
const GRASS_LIGHT := Color("7aa25c")
const MOSS := Color("3b5e42")
const FLOWER_A := Color("e8c170")
const FLOWER_B := Color("d9667a")
const FLOWER_C := Color("9fc7e8")
const PEBBLE := Color("4a4555")

const STONE_DARK := Color("3a3346")
const STONE := Color("5b5468")
const STONE_LIGHT := Color("847a92")
const STONE_TOP := Color("b0a6ba")

const LEAF_DARK := Color("1f3b2c")
const LEAF := Color("2f5a3a")
const LEAF_LIGHT := Color("4f8a4e")

const SKIN := Color("f2c49b")
const HAIR := Color("3b2a2a")
const CLOAK := Color("b8333e")
const CLOAK_DARK := Color("7a1f30")
const ARMOR := Color("56658a")
const ARMOR_LIGHT := Color("8597bd")
const BOOT := Color("2d2430")

const GUN := Color("3a3a44")
const GUN_LIGHT := Color("6a6a78")

const STAMINA := Color("6ec6e8")
const STAMINA_LOW := Color("f08a3c")
