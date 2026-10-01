class_name Player
extends ModelObject
## One player (spec S03): the race plus the player's state in this game.

## Values of next_research_field beyond the six field indices (S05).
const NEXT_FIELD_SAME := 6
const NEXT_FIELD_LOWEST := 7
const AI_NONE := ""
const RELATIONS := ["neutral", "friend", "enemy"]

var index: int = 0
var race: Race = Race.new()
## AI personality id, or "" for a human player (S22).
var ai: String = AI_NONE
var ai_level: int = 0
var active: bool = true
## Homeworld planet id, -1 when none.
var homeworld: int = -1
## Per tech field, in field order (energy, weapons, propulsion, construction, electronics, biotech).
var tech_levels: Array[int] = [0, 0, 0, 0, 0, 0]
var research_points: Array[int] = [0, 0, 0, 0, 0, 0]
var research_percent: int = 15
## Field being researched (0..5).
var research_field: int = 0
## A field (0..5), NEXT_FIELD_SAME or NEXT_FIELD_LOWEST.
var next_research_field: int = NEXT_FIELD_LOWEST
## One entry per player index: "neutral", "friend" or "enemy".
var relations: Array[String] = []
## Battle plans (S16).
var battle_plans: Array = []
## Designs, sorted by slot; empty slots are absent.
var ship_designs: Array[Design] = []
var starbase_designs: Array[Design] = []
## Mystery Trader part content ids obtained (S18), sorted.
var trader_parts: Array[String] = []
## What this player knows of objects it does not own (S15).
var knowledge: Dictionary = {}
var mod_data: Dictionary = {}


func _schema() -> Array:
	return [
		["index", Kind.INT],
		["race", Kind.OBJECT, Race],
		["ai", Kind.STRING],
		["ai_level", Kind.INT],
		["active", Kind.BOOL],
		["homeworld", Kind.INT],
		["tech_levels", Kind.INT_LIST],
		["research_points", Kind.INT_LIST],
		["research_percent", Kind.INT],
		["research_field", Kind.INT],
		["next_research_field", Kind.INT],
		["relations", Kind.STRING_LIST],
		["battle_plans", Kind.JSON],
		["ship_designs", Kind.OBJECT_LIST, Design],
		["starbase_designs", Kind.OBJECT_LIST, Design],
		["trader_parts", Kind.STRING_LIST],
		["knowledge", Kind.JSON],
		["mod_data", Kind.JSON],
	]


func is_human() -> bool:
	return ai == AI_NONE


func ship_design(slot: int) -> Design:
	return _find_design(ship_designs, slot)


func starbase_design(slot: int) -> Design:
	return _find_design(starbase_designs, slot)


## Puts a design in its slot (replacing what was there), keeping the list sorted.
func set_design(design: Design, starbase: bool) -> void:
	var list: Array[Design] = starbase_designs if starbase else ship_designs
	var at := 0
	while at < list.size() and list[at].slot < design.slot:
		at += 1
	if at < list.size() and list[at].slot == design.slot:
		list[at] = design
	else:
		list.insert(at, design)


## Empties a slot. Other designs keep their slots.
func remove_design(slot: int, starbase: bool) -> void:
	var list: Array[Design] = starbase_designs if starbase else ship_designs
	for i in list.size():
		if list[i].slot == slot:
			list.remove_at(i)
			return


static func _find_design(list: Array[Design], slot: int) -> Design:
	for design in list:
		if design.slot == slot:
			return design
	return null
