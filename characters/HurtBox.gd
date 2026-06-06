class_name HurtBox
extends Area2D

enum HitType { BODY = 0, HEAD = 1 }

@export var hit_type: HitType = HitType.BODY

# Returns the owning character (convention: HurtBox is a direct child of the character node).
func get_character() -> Node:
	return get_parent()
