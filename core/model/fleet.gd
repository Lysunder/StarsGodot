class_name Fleet
extends ModelObject
## A fleet (S03). Identity is (owner, number). Cargo is ironium, boranium, germanium, colonists
## (kT; 1 kT = 100 colonists) and fuel (mg).

const CARGO_IRONIUM := 0
const CARGO_BORANIUM := 1
const CARGO_GERMANIUM := 2
const CARGO_COLONISTS := 3
const CARGO_FUEL := 4

var owner: int = 0
var number: int = 0
## "" = the default name.
var name: String = ""
var x: int = 0
var y: int = 0
## Planet id when in orbit, else -1.
var planet: int = -1
## Sorted by design slot, at most one stack per design.
var stacks: Array[ShipStack] = []
var cargo: Array[int] = [0, 0, 0, 0, 0]
## Index into the owner's battle plans.
var battle_plan: int = 0
## The first is where the fleet is now, the second its next destination.
var waypoints: Array[Waypoint] = []
var repeat: bool = false
var mod_data: Dictionary = {}

## Turn-only mark: the fleet didn't move this turn (S12).
var did_not_move: bool = false
## Turn-only mark: the fleet is following a fleet this turn (S12 "Following a fleet").
var following: bool = false
## Turn-only mark: a waypoint targets this fleet (S12 "Waypoint targets").
var claimed: bool = false
## Turn-only mark: the fleet went through a stargate this turn (S12; no repair, S19).
var gated: bool = false


func _schema() -> Array:
	return [
		["owner", Kind.INT],
		["number", Kind.INT],
		["name", Kind.STRING],
		["x", Kind.INT],
		["y", Kind.INT],
		["planet", Kind.INT],
		["stacks", Kind.OBJECT_LIST, ShipStack],
		["cargo", Kind.INT_LIST],
		["battle_plan", Kind.INT],
		["waypoints", Kind.OBJECT_LIST, Waypoint],
		["repeat", Kind.BOOL],
		["mod_data", Kind.JSON],
	]


func ship_count() -> int:
	var total := 0
	for stack in stacks:
		total += stack.count
	return total


func stack_for(design: int) -> ShipStack:
	for stack in stacks:
		if stack.design == design:
			return stack
	return null


## Adds ships of a design, creating its stack in slot order when needed. Returns the stack.
func add_ships(design: int, count: int) -> ShipStack:
	var stack := stack_for(design)
	if stack == null:
		stack = ShipStack.new(design, 0)
		var at := 0
		while at < stacks.size() and stacks[at].design < design:
			at += 1
		stacks.insert(at, stack)
	stack.count += count
	return stack
