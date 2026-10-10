class_name Retargeting
extends RefCounted
## Orders changed by sight (spec S15 "Orders changed by sight"; `WriteGameFile@1068:35b0`): right
## after a player's scanning, patrolling fleets pick a target, and waypoints aimed at what the
## player no longer sees lose their target.

const WARP_MAX := 10
## The highest warp a default speed may use: fuel use below this (per mille of the table).
const FUEL_LIMIT := 121
const FULL_TAG := "full_default_warp"
const SAFE_TAG := "warp10_safe"
## Patrol range: (data word 1 + 1) × RANGE_STEP ly; ANY_RANGE stands for "any distance".
const RANGE_STEP := 50
const ANY_RANGE := 550
const ANY_DISTANCE := 10000
const NO_CHOICE := 100000000
## Transport actions by their number in the original's task data (S11).
const TRANSPORT_ACTIONS := [
	"none",
	"load_all",
	"unload_all",
	"load",
	"unload",
	"fill_percent",
	"wait_percent",
	"load_optimal",
	"set_amount",
	"set_waypoint",
]


## The player `p`'s fleets, in fleet order; `sight` is the player's scanning pass.
static func run(state: GameState, content: ContentRegistry, p: int, sight: Scanning.Sight) -> void:
	var picked := {}
	for fleet in state.fleets:
		if fleet.owner != p or fleet.ship_count() == 0 or fleet.waypoints.is_empty():
			continue
		var wp0 := fleet.waypoints[0]
		if wp0.target == "fleet":
			_to_place(state, wp0)
		if (
			wp0.task == "none"
			and fleet.waypoints.size() > 1
			and fleet.waypoints[1].task == "patrol"
		):
			wp0.task = "patrol"
			var words := _words(fleet.waypoints[1])
			wp0.task_data = {"raw": [words[0], words[1], 0, 0, 0]}
		if (
			wp0.task == "patrol"
			and (fleet.waypoints.size() < 2 or fleet.waypoints[1].target != "fleet")
		):
			_patrol(state, content, fleet, sight, picked)
		if wp0.task != "transport":
			_lost_targets(state, content, fleet, sight)


## Step 3: the nearest suitable fleet in view within the patrol range gets intercepted.
static func _patrol(
	state: GameState,
	content: ContentRegistry,
	fleet: Fleet,
	sight: Scanning.Sight,
	picked: Dictionary
) -> void:
	var owner := state.player(fleet.owner)
	var wp0 := fleet.waypoints[0]
	var x := fleet.x
	var y := fleet.y
	if fleet.planet < 0 and fleet.waypoints.size() > 1 and fleet.repeat:
		x = fleet.waypoints[1].x
		y = fleet.waypoints[1].y
	var target_class := FleetTargets.primary_target(state, fleet)
	var best: Fleet = null
	var best_d2 := NO_CHOICE
	var unpicked := false
	for other in state.fleets:
		if other.owner == fleet.owner or not sight.fleets.has(other):
			continue
		var d2 := (other.x - x) * (other.x - x) + (other.y - y) * (other.y - y)
		var free := not picked.has(other)
		if not ((not unpicked and free) or (d2 < best_d2 and (not unpicked or free))):
			continue
		var other_owner := state.player(other.owner)
		if not FleetTargets.has_class(other, other_owner, target_class, content, true):
			continue
		if not BattlePlans.attacks(state, fleet, other.owner):
			continue
		best = other
		best_d2 = d2
		if free:
			unpicked = true
	if unpicked:
		picked[best] = true
	var range := (_words(wp0)[1] + 1) * RANGE_STEP
	if range == ANY_RANGE:
		range = ANY_DISTANCE
	if best == null or best_d2 == 0 or best_d2 > range * range:
		return
	var added: Waypoint
	if fleet.waypoints.size() == 1:
		added = Waypoint.new()
		added.task = "patrol"
		var words := _words(wp0)
		added.task_data = {"raw": [words[0], words[1], 0, 0, 0]}
		added.warp = words[0] if words[0] != 0 else default_warp(fleet, owner, content)
		fleet.waypoints.append(added)
		if fleet.repeat:
			var back := wp0.copy() as Waypoint
			back.warp = default_warp(fleet, owner, content)
			fleet.waypoints.append(back)
	else:
		added = fleet.waypoints[1].copy() as Waypoint
		var word0 := _words(added)[0]
		added.warp = word0 & 15 if word0 != 0 else default_warp(fleet, owner, content)
		fleet.waypoints.insert(1, added)
	added.x = best.x
	added.y = best.y
	added.target = "fleet"
	added.target_owner = best.owner
	added.target_id = best.number
	TurnMessages.add(
		state,
		content,
		fleet.owner,
		"message.fleet.patrol_intercept",
		{"fleet": fleet.number, "owner": fleet.owner},
		[fleet.owner * 512 + fleet.number, best.owner * 512 + best.number]
	)


## Step 4: waypoints 1 and later aimed at a fleet or object out of sight lose their target.
static func _lost_targets(
	state: GameState, content: ContentRegistry, fleet: Fleet, sight: Scanning.Sight
) -> void:
	var word := fleet.owner * 512 + fleet.number
	var goto := {"fleet": fleet.number, "owner": fleet.owner}
	for i in range(1, fleet.waypoints.size()):
		var wp := fleet.waypoints[i]
		match wp.target:
			"fleet":
				var stopped := wp.frozen
				wp.frozen = false
				var target := state.fleet(wp.target_owner, wp.target_id)
				var type := ""
				var params := [word]
				if target == null or target.ship_count() == 0:
					type = "message.fleet.target_gone"
					params.append(wp.target_owner * 512 + wp.target_id)
				elif sight.fleets.has(target):
					continue
				elif target.planet < 0 or stopped:
					type = "message.fleet.target_out_of_range"
				else:
					type = "message.fleet.target_behind_planet"
					params.append(target.planet)
				TurnMessages.add(state, content, fleet.owner, type, goto, params)
				_to_place(state, wp)
			"minefield", "wormhole", "trader":
				var type := _lost_object(state, wp, sight)
				if type == "keep":
					continue
				if not type.is_empty():
					TurnMessages.add(state, content, fleet.owner, type, goto, [word])
				wp.target = "none"
				wp.target_owner = -1
				wp.target_id = -1


## "keep" when the waypoint's object is in view; otherwise the message to give ("" when the
## object no longer exists).
static func _lost_object(state: GameState, wp: Waypoint, sight: Scanning.Sight) -> String:
	match wp.target:
		"minefield":
			for field in state.minefields:
				if field.owner == wp.target_owner and field.number == wp.target_id:
					return (
						"keep" if field.seen_by.has(sight.p) else "message.fleet.minefield_vanished"
					)
		"wormhole":
			var w := state.wormhole(wp.target_id)
			if w != null:
				return "keep" if sight.tracked.has(w) else "message.fleet.wormhole_vanished"
		"trader":
			for trader in state.traders:
				if trader.number == wp.target_id:
					return "keep"
	return ""


## The waypoint targets the planet at its position, or deep space.
static func _to_place(state: GameState, wp: Waypoint) -> void:
	wp.target = "none"
	wp.target_owner = -1
	wp.target_id = -1
	for planet in state.planets:
		if planet.x == wp.x and planet.y == wp.y:
			wp.target = "planet"
			wp.target_id = planet.id
			return


## A waypoint's task data as the original's words (S11): the raw words, or a transport's
## action and amount per cargo type.
static func _words(wp: Waypoint) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0, 0]
	if wp.task_data.has("raw"):
		var raw: Array = wp.task_data.raw
		for i in mini(raw.size(), out.size()):
			out[i] = int(raw[i])
	elif wp.task_data.has("cargo"):
		var cargo: Array = wp.task_data.cargo
		for i in mini(cargo.size(), out.size()):
			var c: Dictionary = cargo[i]
			out[i] = maxi(TRANSPORT_ACTIONS.find(c.get("action", "none")), 0) << 12
			out[i] |= int(c.get("amount", 0))
	return out


## The fleet's default warp (`Fleet_CalcWarp@1048:678c`): the fastest speed every engine runs
## below 121 per mille fuel use, eased down to a nearby free speed; 0 when a design has no engine.
static func default_warp(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var warp := WARP_MAX
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var engine := PartRules.engine(owner.ship_design(stack.design), content)
		if (engine[0] as String).is_empty():
			return 0
		var part := content.part(engine[0])
		var table: Array = part.get("fuel_table", [])
		var tags: Array = part.get("tags", [])
		while warp > 0:
			if int(table[warp]) < FUEL_LIMIT:
				if int(table[warp]) > 0 and not tags.has(FULL_TAG):
					if warp >= 5 and int(table[warp - 1]) == 0:
						warp -= 1
					elif warp >= 6 and int(table[warp - 2]) == 0:
						warp -= 2
					elif warp > 6 and int(table[warp - 3]) == 0:
						warp -= 3
				if warp == WARP_MAX and not tags.has(SAFE_TAG):
					warp = WARP_MAX - 1
				break
			warp -= 1
	return warp
