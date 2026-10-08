class_name Packet
extends ModelObject
## A mineral packet or a pile of salvage (S03, S14). They share one kind and one numbering in
## the original; salvage has no destination and warp 0.

## Decay classes: none, 10%, 25%, 50% a year.
const DECAY_CLASSES := 4

var owner: int = 0
var number: int = 0
var x: int = 0
var y: int = 0
## kT of ironium, boranium, germanium.
var minerals: Array[int] = [0, 0, 0]
var salvage: bool = false
## Destination planet id, -1 for salvage.
var destination: int = -1
## The packet's speed (5..13); 0 for salvage.
var warp: int = 0
## The decay class (0 none, 1 10%, 2 25%, 3 50% a year).
var decay: int = 0
## The mass the original shows, in tens of kT, kept as S14 describes.
var mass_tenths: int = 0
## A packet: it has moved at least once. Salvage: dropped this year (it skips one decay).
var fresh: bool = false
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
		["decay", Kind.INT],
		["mass_tenths", Kind.INT],
		["fresh", Kind.BOOL],
		["mod_data", Kind.JSON],
	]
