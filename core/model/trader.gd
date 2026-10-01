class_name Trader
extends ModelObject
## The Mystery Trader's ship (S03, S18). It has no owner.

var number: int = 0
var x: int = 0
var y: int = 0
var destination_x: int = 0
var destination_y: int = 0
var warp: int = 0
## The item it carries (content id), "" when none.
var item: String = ""
## Player indices it has met, sorted.
var met: Array[int] = []
var mod_data: Dictionary = {}


func _schema() -> Array:
	return [
		["number", Kind.INT],
		["x", Kind.INT],
		["y", Kind.INT],
		["destination_x", Kind.INT],
		["destination_y", Kind.INT],
		["warp", Kind.INT],
		["item", Kind.STRING],
		["met", Kind.INT_LIST],
		["mod_data", Kind.JSON],
	]
