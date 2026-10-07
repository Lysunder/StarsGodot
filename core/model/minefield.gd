class_name Minefield
extends ModelObject
## A minefield (S03, S13). Its radius is the square root of the mine count.

const TYPES := ["standard", "heavy", "speed_bump"]

var owner: int = 0
var number: int = 0
var x: int = 0
var y: int = 0
var mines: int = 0
var type: String = "standard"
## Space Demolition detonate order.
var detonate: bool = false
## Player indices that know of this field (its owner, players who hit or swept it, and whom
## scanning shows it, S15), sorted.
var known_by: Array[int] = []
## Player indices that have seen this field this turn, sorted.
var seen_by: Array[int] = []
var mod_data: Dictionary = {}


func _schema() -> Array:
	return [
		["owner", Kind.INT],
		["number", Kind.INT],
		["x", Kind.INT],
		["y", Kind.INT],
		["mines", Kind.INT],
		["type", Kind.ENUM, TYPES],
		["detonate", Kind.BOOL],
		["known_by", Kind.INT_LIST],
		["seen_by", Kind.INT_LIST],
		["mod_data", Kind.JSON],
	]
