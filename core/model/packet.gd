class_name Packet
extends ModelObject
## A mineral packet or a pile of salvage (S03, S14). They share one kind and one numbering in
## the original; salvage has no destination and warp 0.

var owner: int = 0
var number: int = 0
var x: int = 0
var y: int = 0
## kT of ironium, boranium, germanium.
var minerals: Array[int] = [0, 0, 0]
var salvage: bool = false
## Destination planet id, -1 for salvage.
var destination: int = -1
var warp: int = 0
var mod_data: Dictionary = {}


func _schema() -> Array:
	return [
		["owner", Kind.INT],
		["number", Kind.INT],
		["x", Kind.INT],
		["y", Kind.INT],
		["minerals", Kind.INT_LIST],
		["salvage", Kind.BOOL],
		["destination", Kind.INT],
		["warp", Kind.INT],
		["mod_data", Kind.JSON],
	]
