class_name Wormhole
extends ModelObject
## One end of a wormhole (S03; movement S12, events S18). Wormholes have no owner.

var number: int = 0
var x: int = 0
var y: int = 0
## Number of the wormhole at the other end.
var other_end: int = -1
## Stability roll 0..3, set when the wormhole is created (S07); how likely it is to move (S18).
var stability: int = 0
## Years since the wormhole last moved (S18).
var age: int = 0
## Player indices that have seen it, sorted.
var seen_by: Array[int] = []
## Player indices that know where it is now: their scanners have it in view (S15) or a fleet of
## theirs came out of it (S12); cleared when it jumps. Sorted.
var tracked_by: Array[int] = []
var mod_data: Dictionary = {}


func _schema() -> Array:
	return [
		["number", Kind.INT],
		["x", Kind.INT],
		["y", Kind.INT],
		["other_end", Kind.INT],
		["stability", Kind.INT],
		["age", Kind.INT],
		["seen_by", Kind.INT_LIST],
		["tracked_by", Kind.INT_LIST],
		["mod_data", Kind.JSON],
	]
