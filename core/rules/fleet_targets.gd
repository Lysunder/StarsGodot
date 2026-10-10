class_name FleetTargets
extends RefCounted
## Waypoints that target fleets (spec S12 "Waypoint targets", "Following a fleet"): the start of
## the turn (S02 phase 4) sets up following fleets and retargets waypoints whose fleet is gone or
## moved; phase 21 retargets again.

## Rounds of copying a followed fleet's next waypoint (chains of followers).
const FOLLOW_ROUNDS := 8
## Battle-plan primary targets (S16) and the hull classes they prefer when retargeting.
const TARGET_ARMED := 3
const TARGET_BOMBERS_FREIGHTERS := 4
const TARGET_UNARMED := 5
const TARGET_FUEL := 6
const TARGET_FREIGHTERS := 7
const ARMED_CLASSES := [2, 3, 4]


## S02 phase 4: mark following fleets, update waypoint targets, then copy each followed fleet's
## next waypoint to its followers.
static func resolve(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	var any := false
	for fleet in state.fleets:
		fleet.claimed = false
		fleet.following = fleet.waypoints.size() == 1 and fleet.waypoints[0].target == "fleet"
		any = any or fleet.following
	update(state, content, rng)
	if not any:
		return
	var changed := true
	var round := 0
	while changed and round < FOLLOW_ROUNDS:
		changed = false
		round += 1
		for fleet in state.fleets:
			if not fleet.following or fleet.waypoints.size() != 1:
				continue
			var wp := fleet.waypoints[0]
			var target := state.fleet(wp.target_owner, wp.target_id)
			if target != null and target.waypoints.size() > 1:
				var next := target.waypoints[1].copy() as Waypoint
				next.task_data = wp.task_data.duplicate(true)
				fleet.waypoints.append(next)
				changed = true
			elif (
				target != null
				and target.waypoints.size() == 1
				and target.waypoints[0].target == "fleet"
			):
				pass
			else:
				_message(state, content, fleet, "message.fleet.follow_failed")
				fleet.following = false


## `UpdateWaypointTargets`: waypoint 0 becomes where the fleet is (unless it targets a planet, has
## a transport or merge task, or the fleet is following), positions stay inside the universe, and
## waypoints targeting a fleet that is gone or moved are retargeted among the fleets left there.
static func update(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	var low := 1000
	var high := state.settings.universe_width + 1000
	for fleet in state.fleets:
		if fleet.waypoints.is_empty():
			continue
		var wp0 := fleet.waypoints[0]
		if (
			wp0.target != "planet"
			and wp0.task != "transport"
			and wp0.task != "merge"
			and not fleet.following
		):
			wp0.target = "planet" if fleet.planet >= 0 else "none"
			wp0.target_owner = -1
			wp0.target_id = fleet.planet
		if fleet.x != clampi(fleet.x, low, high):
			fleet.x = clampi(fleet.x, low, high)
			wp0.x = fleet.x
		if fleet.y != clampi(fleet.y, low, high):
			fleet.y = clampi(fleet.y, low, high)
			wp0.y = fleet.y
		var first := 0 if fleet.following else 1
		for i in range(first, fleet.waypoints.size()):
			var wp := fleet.waypoints[i]
			if wp.target == "fleet" and not wp.frozen:
				_check_target(state, content, rng, fleet, wp)
			elif wp.target == "wormhole":
				_check_wormhole(state, content, fleet, wp)


## A waypoint's fleet target: still there (claimed), or retargeted among the fleets at the
## waypoint's position owned by the old target's owner.
static func _check_target(
	state: GameState, content: ContentRegistry, rng: StarsRandom, fleet: Fleet, wp: Waypoint
) -> void:
	var target := state.fleet(wp.target_owner, wp.target_id)
	if target != null and target.x == wp.x and target.y == wp.y:
		target.claimed = true
		return
	var plan_target := primary_target(state, fleet)
	var heaviest: Fleet = null
	var heaviest_mass := 0
	var picked: Fleet = null
	var seen := 0
	for other in state.fleets:
		if other.x != wp.x or other.y != wp.y or other.owner != wp.target_owner:
			continue
		if has_class(other, state.player(other.owner), plan_target, content):
			var mass := mass_with_cargo(other, state.player(other.owner), content)
			if mass > heaviest_mass or (mass == heaviest_mass and rng.random(2) == 0):
				heaviest_mass = mass
				heaviest = other
		seen += 1
		if rng.random(seen) == 0 and (seen == 1 or not other.claimed or rng.random(2) != 0):
			picked = other
	var chosen := heaviest if heaviest != null else picked
	if chosen == null:
		return
	wp.target_owner = chosen.owner
	wp.target_id = chosen.number
	wp.x = chosen.x
	wp.y = chosen.y
	chosen.claimed = true


## A waypoint's wormhole: its position is followed while the owner knows where it is; one that
## moved out of sight (S15) leaves the waypoint at its last known position, with a message.
static func _check_wormhole(
	state: GameState, content: ContentRegistry, fleet: Fleet, wp: Waypoint
) -> void:
	var w := state.wormhole(wp.target_id)
	if w != null and (w.tracked_by.has(fleet.owner) or (w.x == wp.x and w.y == wp.y)):
		wp.x = w.x
		wp.y = w.y
		return
	if w != null:
		_message(state, content, fleet, "message.fleet.wormhole_vanished")
	wp.target = "none"
	wp.target_owner = -1
	wp.target_id = -1


## Other players' waypoints that target `fleet` stay where it is now (frozen), when it jumps
## through a stargate or a wormhole (`RetargetFollowers@1078:133e`).
static func freeze_followers(state: GameState, fleet: Fleet) -> void:
	for other in state.fleets:
		if other.owner == fleet.owner:
			continue
		for i in range(1, other.waypoints.size()):
			var wp := other.waypoints[i]
			if (
				wp.target == "fleet"
				and wp.target_owner == fleet.owner
				and wp.target_id == fleet.number
			):
				wp.frozen = true
				wp.x = fleet.x
				wp.y = fleet.y


static func primary_target(state: GameState, fleet: Fleet) -> int:
	var plans: Array = state.player(fleet.owner).battle_plans
	if fleet.battle_plan < 0 or fleet.battle_plan >= plans.size():
		return 0
	return int(plans[fleet.battle_plan].get("primary_target", 0))


## Whether the fleet has a ship of the hull classes a battle plan's primary target prefers
## (`Fleet_HasShipOfTargetClass@1030:411a`): armed (classes 2-4), bombers and freighters (1, 5),
## unarmed (no ship of 2-4), fuel transports (7), freighters (1); other targets give `others`
## (the caller's third argument: patrols pass "match", S15).
static func has_class(
	fleet: Fleet, owner: Player, target: int, content: ContentRegistry, others := false
) -> bool:
	var classes: Array[int] = []
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		if stack.count > 0 and design != null:
			classes.append(int(content.hull(design.hull).get("class", 0)))
	match target:
		TARGET_ARMED:
			return classes.any(func(c: int) -> bool: return c in ARMED_CLASSES)
		TARGET_UNARMED:
			return not classes.any(func(c: int) -> bool: return c in ARMED_CLASSES)
		TARGET_BOMBERS_FREIGHTERS:
			return classes.any(func(c: int) -> bool: return c == 1 or c == 5)
		TARGET_FUEL:
			return classes.has(7)
		TARGET_FREIGHTERS:
			return classes.has(1)
	return others


## Ships' mass plus cargo (not fuel), as `Fleet_GetMass@1030:4c90`.
static func mass_with_cargo(fleet: Fleet, owner: Player, content: ContentRegistry) -> int:
	var total := 0
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		if design != null and stack.count > 0:
			total += stack.count * PartRules.mass(design, content)
	for c in Fleet.CARGO_FUEL:
		total += fleet.cargo[c]
	return total


static func _message(
	state: GameState, content: ContentRegistry, fleet: Fleet, type: String
) -> void:
	TurnMessages.add(
		state,
		content,
		fleet.owner,
		type,
		{"fleet": fleet.number, "owner": fleet.owner},
		[fleet.owner * 512 + fleet.number]
	)
