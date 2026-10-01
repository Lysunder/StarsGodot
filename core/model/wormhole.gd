class_name Wormhole
extends ModelObject
## One end of a wormhole (S03; movement S12, events S18). Wormholes have no owner.

var number: int = 0
var x: int = 0
var y: int = 0
## Number of the wormhole at the other end.
var other_end: int = -1
var stability: int = 0
## Player indices that have seen it, sorted.
var seen_by: Array[int] = []
var mod_data: Dictionary = {}


func _schema() -> Array:
	return [
		["number", Kind.INT],
		["x", Kind.INT],
		["y", Kind.INT],
		["other_end", Kind.INT],
		["stability", Kind.INT],
		["seen_by", Kind.INT_LIST],
		["mod_data", Kind.JSON],
	]
