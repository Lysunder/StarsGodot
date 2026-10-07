class_name Stargates
extends RefCounted
## Stargate travel (spec S12 "Stargates"): a fleet whose next waypoint has warp 11 jumps from a
## stargate (or with Jump Gates on every ship) to a planet with a stargate; designs beyond the
## gates' limits are damaged or lost.

## An unlimited gate range counts as this many light years.
const UNLIMITED_RANGE := 8000
## A gate takes up to this many times its limits, with damage beyond 1x.
const OVER_LIMIT := 5
const SURVIVAL := 10000
const FACTOR_SCALE := 2500
const ALL_LOST := 100
const LOSS_DIVISOR := 3
const DAMAGE_SCALE := 500
const PERCENT := 100
## A position given where a planet could be: the first word is -1 for a planet (S21 "object").
const NO_X := -1


## Jumps the fleet through the gates to its next waypoint. Returns the fleet's fate: "stayed" (the
## jump was refused), "jumped", or "lost" (every ship destroyed; the caller deletes the fleet).
static func jump(
	state: GameState, content: ContentRegistry, rng: StarsRandom, fleet: Fleet
) -> String:
	var owner := state.player(fleet.owner)
	var here := fleet.waypoints[0]
	var next := fleet.waypoints[1]
	var source: Planet = state.planet(here.target_id) if here.target == "planet" else null
	var source_gate := _gate(state, content, source)
	if not source_gate.is_empty():
		if not _ours_or_friend(state, source, fleet.owner):
			_refuse(state, content, fleet, "gate_source_not_ours", [source.id, source.id])
			return "stayed"
	elif not _all_have_jump_gate(fleet, owner, content):
		var where := [NO_X, source.id] if source != null else [here.x, here.y]
		_refuse(state, content, fleet, "gate_none_here", where)
		return "stayed"
	var destination: Planet = null
	if next.target == "planet":
		destination = state.planet(next.target_id)
	else:
		for pl in state.planets:
			if pl.x == next.x and pl.y == next.y:
				destination = pl
				break
	if destination == null:
		_refuse(state, content, fleet, "gate_no_destination", [next.x, next.y])
		return "stayed"
	var destination_gate := _gate(state, content, destination)
	if destination_gate.is_empty():
		_refuse(state, content, fleet, "gate_none_there", [destination.id, NO_X, destination.id])
		return "stayed"
	if not _ours_or_friend(state, destination, fleet.owner):
		var d := destination.id
		_refuse(state, content, fleet, "gate_blocked", [d, d, d])
		return "stayed"
	var jump_gates := source_gate.is_empty()
	if jump_gates:
		source_gate = destination_gate
	var traveler := RaceMath.trait_param(owner.race, content, "movement.gate_cargo", 0) != 0
	if not jump_gates and not traveler:
		if fleet.cargo[Fleet.CARGO_COLONISTS] > 0 and source.owner != fleet.owner:
			_refuse(state, content, fleet, "gate_colonists", [source.id])
			return "stayed"
		_unload(state, content, fleet, source)
	var dx := next.x - fleet.x
	var dy := next.y - fleet.y
	var distance := int(sqrt(float(dx * dx + dy * dy)))
	var source_id := source.id if source != null else -1
	# per design slot: damage percent; the first design over five times a limit stops the jump
	var damages := {}
	for stack in fleet.stacks:
		if stack.count <= 0:
			continue
		var mass := PartRules.mass(owner.ship_design(stack.design), content)
		var result := _damage(source_gate, destination_gate, distance, mass)
		if result == -1:
			_refuse(state, content, fleet, "gate_out_of_range", [source_id, destination.id])
			return "stayed"
		if result == -2:
			_refuse(
				state, content, fleet, "gate_too_massive", [source_id, destination.id, stack.design]
			)
			return "stayed"
		damages[stack.design] = result
	var lost := _apply_damage(content, rng, fleet, owner, damages, traveler)
	if fleet.ship_count() == 0:
		_message(state, content, fleet, "gate_lost", [source_id, destination.id])
		return "lost"
	var total := 0
	for n: int in lost.values():
		total += n
	if total > 0:
		var before := fleet.ship_count() + total
		var type := "gate_lost_some"
		if total < before / 4:
			type = "gate_lost_few"
		elif total > before / 2:
			type = "gate_lost_most"
		_message(state, content, fleet, type, [source_id, destination.id, total])
		FleetOrders.cargo_after_losses(fleet, owner, content, lost)
	FleetTargets.freeze_followers(state, fleet)
	fleet.x = next.x
	fleet.y = next.y
	fleet.planet = destination.id
	fleet.gated = true
	return "jumped"


## The stargate part on a planet's starbase: the first one in its design ({} if none).
static func _gate(state: GameState, content: ContentRegistry, planet: Planet) -> Dictionary:
	if planet == null or planet.starbase == null or planet.owner < 0:
		return {}
	var design := state.player(planet.owner).starbase_design(planet.starbase.design)
	if design == null:
		return {}
	for slot in design.parts:
		if slot.count > 0 and not slot.part.is_empty():
			var stats: Dictionary = content.part(slot.part).get("stats", {})
			if stats.has("gate_mass"):
				return stats
	return {}


## The planet's owner is the fleet's owner, or counts the fleet's owner as a friend.
static func _ours_or_friend(state: GameState, planet: Planet, player: int) -> bool:
	if planet.owner == player:
		return true
	if planet.owner < 0:
		return false
	var relations := state.player(planet.owner).relations
	return player < relations.size() and relations[player] == "friend"


static func _all_have_jump_gate(fleet: Fleet, owner: Player, content: ContentRegistry) -> bool:
	if fleet.stacks.is_empty():
		return false
	for stack in fleet.stacks:
		var design := owner.ship_design(stack.design)
		var has := false
		for slot in design.parts:
			if slot.count > 0 and not slot.part.is_empty():
				has = has or (content.part(slot.part).get("tags", []) as Array).has("jump_gate")
		if not has:
			return false
	return true


## Minerals and colonists go onto the source planet before the jump, with a message to the fleet's
## owner and, for another player's planet, to its owner.
static func _unload(
	state: GameState, content: ContentRegistry, fleet: Fleet, planet: Planet
) -> void:
	var minerals := 0
	for m in 3:
		minerals += fleet.cargo[m]
		planet.surface[m] += fleet.cargo[m]
		fleet.cargo[m] = 0
	var colonists := fleet.cargo[Fleet.CARGO_COLONISTS]
	planet.population += colonists
	fleet.cargo[Fleet.CARGO_COLONISTS] = 0
	var type := ""
	var params := []
	if colonists == 0 and minerals > 0:
		type = "gate_unloaded_minerals"
		params = [minerals, planet.id]
	elif colonists > 0 and minerals == 0:
		type = "gate_unloaded_colonists"
		params = [colonists, planet.id]
	elif colonists > 0:
		type = "gate_unloaded_both"
		params = [colonists, minerals, planet.id]
	if type.is_empty():
		return
	_message(state, content, fleet, type, params)
	if planet.owner >= 0 and planet.owner != fleet.owner:
		TurnMessages.add(
			state,
			content,
			planet.owner,
			"message.fleet." + type,
			{"planet": planet.id},
			[_word(fleet)] + params
		)


## A design's damage percent through the gates (`Fleet_StargateRange`): -1 out of range, -2 too
## massive, else 0 (no damage) to 100 (all lost).
static func _damage(source: Dictionary, destination: Dictionary, distance: int, mass: int) -> int:
	var reach: int = source["gate_range"]
	if reach < 0:
		reach = UNLIMITED_RANGE
	if distance > OVER_LIMIT * reach:
		return -1
	for limit: int in [source["gate_mass"], destination["gate_mass"]]:
		if limit > 0 and mass > OVER_LIMIT * limit:
			return -2
	var survival := SURVIVAL
	if distance > reach:
		survival = (OVER_LIMIT * reach - distance) * FACTOR_SCALE / reach
		if survival < 1:
			return ALL_LOST
	for limit: int in [source["gate_mass"], destination["gate_mass"]]:
		if limit > 0 and mass > limit:
			var factor := (OVER_LIMIT * limit - mass) * FACTOR_SCALE / limit
			if factor < 1:
				return ALL_LOST
			survival = factor * survival / SURVIVAL
	return (SURVIVAL - survival) / PERCENT


## Applies each design's damage percent (S12 step 6); returns the ships lost per design slot.
static func _apply_damage(
	content: ContentRegistry,
	rng: StarsRandom,
	fleet: Fleet,
	owner: Player,
	damages: Dictionary,
	traveler: bool,
) -> Dictionary:
	var lost := {}
	for stack: ShipStack in fleet.stacks.duplicate():
		var percent: int = damages.get(stack.design, 0)
		if percent <= 0:
			continue
		var n := stack.count
		if percent >= ALL_LOST:
			lost[stack.design] = n
			owner.ship_design(stack.design).remaining -= n
			fleet.stacks.erase(stack)
			continue
		var armor := PartRules.armor(owner.ship_design(stack.design), content, owner.race)
		var damaged := 0
		if stack.damaged_percent > 0 or stack.damage > 0:
			damaged = maxi(stack.damaged_percent * n / PERCENT, 1)
		var survivors := n
		var chance := 0 if traveler else percent / LOSS_DIVISOR
		if chance > 0:
			for i in n:
				if rng.random(PERCENT) < chance:
					survivors -= 1
					if damaged != 0 and rng.random(DAMAGE_SCALE) < stack.damage:
						damaged -= 1
		if survivors > 0:
			var old := 0
			if stack.damage > 0:
				old = maxi(stack.damage * armor / DAMAGE_SCALE, 1)
			var hit := maxi(percent * armor / PERCENT, 1)
			if damaged != 0 and armor <= hit + old:
				survivors -= damaged
				# fix B33: the destroyed ships' damage no longer counts
				damaged = 0
			if survivors > 0:
				var average := (hit * survivors + old * damaged) / survivors * DAMAGE_SCALE / armor
				stack.damage = maxi(average, 1)
				stack.damaged_percent = PERCENT
		lost[stack.design] = n - survivors
		# lost ships no longer exist (the design's count of ships in service)
		owner.ship_design(stack.design).remaining -= n - survivors
		for i in stack.paid.size():
			stack.paid[i] -= stack.paid[i] * (n - survivors) / n
		stack.count = survivors
		if survivors == 0:
			fleet.stacks.erase(stack)
	return lost


static func _refuse(
	state: GameState, content: ContentRegistry, fleet: Fleet, type: String, params: Array
) -> void:
	_message(state, content, fleet, type, params)


static func _message(
	state: GameState, content: ContentRegistry, fleet: Fleet, type: String, params: Array
) -> void:
	TurnMessages.add(
		state,
		content,
		fleet.owner,
		"message.fleet." + type,
		{"fleet": fleet.number, "owner": fleet.owner},
		[_word(fleet)] + params
	)


static func _word(fleet: Fleet) -> int:
	return fleet.owner * 512 + fleet.number
