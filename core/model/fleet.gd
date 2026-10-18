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
## Turn-only mark: a ship move or merge order this turn named the fleet (S11); other players'
## waypoints on it pick their fleet again (S12 "Waypoint targets"). The first task pass clears it.
var reorganized: bool = false
## Turn-only mark: the fleet went through a stargate this turn (S12; no repair, S19).
var gated: bool = false
## Turn-only mark: a minefield hit or damaged the fleet this turn (S13; no repair, S19).
var mine_hit: bool = false
## Turn-only mark: the fleet was in a battle this turn (S16; no repair, S19).
var fought: bool = false
## Turn-only mark: the fleet orbits a planet its owner's fleets there would bomb this turn
## (`DoBombing@10e8:6e2a`); it sees that planet (S15).
var at_bombing: bool = false


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


## Field by field (the hot path of copying a game; test_model_copies checks it holds every
## schema field).
func _copy_into(out: ModelObject) -> void:
	var o := out as Fleet
	o.owner = owner
	o.number = number
	o.name = name
	o.x = x
	o.y = y
	o.planet = planet
	for s in stacks:
		o.stacks.append(s.copy() as ShipStack)
	o.cargo.assign(cargo)
	o.battle_plan = battle_plan
	for w in waypoints:
		o.waypoints.append(w.copy() as Waypoint)
	o.repeat = repeat
	o.mod_data = mod_data.duplicate(true)


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
