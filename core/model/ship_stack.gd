class_name ShipStack
extends ModelObject
## The ships of one design in a fleet (S03).
##
## Damage uses the original's form: damaged_percent of the ships are damaged, each by
## damage / 500 of the design's armor.

var design: int = 0
var count: int = 0
## 0..100.
var damaged_percent: int = 0
## 0..511, in 1/500 of the design's armor.
var damage: int = 0
## Ironium, boranium, germanium and resources actually paid for these ships (B14 fix, S11).
var paid: Array[int] = [0, 0, 0, 0]


func _init(p_design: int = 0, p_count: int = 0) -> void:
	design = p_design
	count = p_count


func _schema() -> Array:
	return [
		["design", Kind.INT],
		["count", Kind.INT],
		["damaged_percent", Kind.INT],
		["damage", Kind.INT],
		["paid", Kind.INT_LIST],
	]
