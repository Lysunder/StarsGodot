class_name Starbase
extends ModelObject
## The starbase orbiting a planet (S03): the owner's starbase design slot and its damage.
##
## Unlike ship stacks, the original keeps a starbase's damage as plain armor points (S23).

var design: int = 0
## Armor points of damage, 0..4095.
var damage: int = 0


func _schema() -> Array:
	return [
		["design", Kind.INT],
		["damage", Kind.INT],
	]
