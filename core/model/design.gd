class_name Design
extends ModelObject
## A ship or starbase design (spec S03). Derived values (mass, cost, armor ...) are computed from
## content and tech level (S04), never stored.

var slot: int = 0
var name: String = ""
## Hull content id.
var hull: String = ""
## One entry per hull slot, in the hull's slot order.
var parts: Array[DesignSlot] = []
var turn_designed: int = 0
## Ships of this design ever built, and still existing.
var built: int = 0
var remaining: int = 0
## Cosmetic picture index.
var picture: int = 0
## Came with ships another player transferred (S11); its ships count at a quarter of their cost
## when scrapped or colonizing.
var transferred: bool = false
var mod_data: Dictionary = {}
## Turn-only mark: players who saw this design in full this turn (S15; a minefield hit, a caught
## packet); keys are player indices.
var revealed_to: Dictionary = {}


func _schema() -> Array:
	return [
		["slot", Kind.INT],
		["name", Kind.STRING],
		["hull", Kind.STRING],
		["parts", Kind.OBJECT_LIST, DesignSlot],
		["turn_designed", Kind.INT],
		["built", Kind.INT],
		["remaining", Kind.INT],
		["picture", Kind.INT],
		["transferred", Kind.BOOL],
		["mod_data", Kind.JSON],
	]
