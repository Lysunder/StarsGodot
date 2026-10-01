class_name Starbase
extends ModelObject
## The starbase orbiting a planet: the owner's starbase design slot and its damage, in the same
## form as a ship stack (S03).

var design: int = 0
var damaged_percent: int = 0
var damage: int = 0


func _schema() -> Array:
	return [
		["design", Kind.INT],
		["damaged_percent", Kind.INT],
		["damage", Kind.INT],
	]
