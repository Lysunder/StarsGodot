class_name Bombing
extends RefCounted
## Bombing (spec S17, `DoBombing@10e8:6e2a`), right after the battles of the waypoint 1 step
## (S02): a player's fleets orbiting another player's planet without a starbase, when one of them
## has a battle plan that attacks that player, drop their bombs together.

## Bomb kill rates are in tenths of a percent.
const PER_MILLE := 1000
## Retro bombs undo at most this many clicks per axis.
const RETRO_MAX := 500
const FLEET_WORD := 512
const RETRO_TAG := "retro"
const SMART_TAG := "smart"


## Fleets that would bomb: when one of a player's fleets orbits another player's planet without a
## starbase and its battle plan attacks that player, every fleet of the player at that planet is
## marked (`Bombing_SumFleetBombs@1030:0d6a` marks them all, bombers or not). Scanning reads the
## marks (S15).
static func mark_fleets(state: GameState) -> void:
	for fleet in state.fleets:
		if fleet.at_bombing or not _bombs_here(state, fleet):
			continue
		for other in state.fleets:
			if other.owner == fleet.owner and other.planet == fleet.planet:
				other.at_bombing = true


## S17 "Bombing": every planet bombed this turn, in fleet order of the first fleet that attacks
## it; marks the fleets as `mark_fleets` does.
static func bomb_all(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	var group_of := {}
	for group in BattleSetup.places(state):
		for fleet: Fleet in group:
			group_of[fleet] = group
	for fleet in state.fleets:
		if fleet.at_bombing or not _bombs_here(state, fleet):
			continue
		var bombers := _bombers(group_of[fleet], fleet)
		for other in bombers:
			other.at_bombing = true
		var bombs := _sum_bombs(state, content, bombers)
		if not bombs.is_empty():
			_bomb(state, content, rng, state.planet(fleet.planet), fleet, bombers.size() > 1, bombs)


static func _bombs_here(state: GameState, fleet: Fleet) -> bool:
	if fleet.ship_count() == 0 or fleet.planet < 0:
		return false
	var planet := state.planet(fleet.planet)
	if planet.owner < 0 or planet.owner == fleet.owner or planet.starbase != null:
		return false
	return BattlePlans.attacks(state, fleet, planet.owner)


## The fleet's owner's fleets at its planet, starting with it and going round the place's fleets
## in their order (S16 "Places"; the original's list of fleets at a place is circular).
static func _bombers(group: Array, first: Fleet) -> Array[Fleet]:
	var out: Array[Fleet] = []
	var at := group.find(first)
	for i in group.size():
		var f: Fleet = group[(at + i) % group.size()]
		if f.owner == first.owner and f.planet == first.planet:
			out.append(f)
	return out


## `Bombing_SumFleetBombs@1030:0d6a`: the bombs of all the fleets, per bomb times ships:
## `normal` kill rate (per mille), `minimum` kill (hundreds of colonists), `installations`
## destroyed, `smart` kill rate (per mille: 1 - Π (1 - rate)^bombs, at most 1000) and `retro`
## bombs. Empty when there are none.
static func _sum_bombs(
	state: GameState, content: ContentRegistry, fleets: Array[Fleet]
) -> Dictionary:
	var out := {"normal": 0, "minimum": 0, "installations": 0, "smart": 0, "retro": 0}
	var left := 1.0
	for fleet in fleets:
		var owner := state.player(fleet.owner)
		for stack in fleet.stacks:
			if stack.count <= 0:
				continue
			for slot in owner.ship_design(stack.design).parts:
				if slot.part.is_empty() or slot.count <= 0:
					continue
				var part := content.part(slot.part)
				var stats: Dictionary = part.get("stats", {})
				var tags: Array = part.get("tags", [])
				var n := slot.count * stack.count
				if tags.has(RETRO_TAG):
					out.retro += n
				elif tags.has(SMART_TAG):
					var factor := 1.0 + int(stats.get("kill_rate", 0)) * -(1.0 / PER_MILLE)
					for i in n:
						left *= factor
				else:
					out.normal += int(stats.get("kill_rate", 0)) * n
					out.installations += int(stats.get("installations", 0)) * n
					out.minimum += int(stats.get("min_kill", 0)) * n
	out.smart = mini(int(left * -PER_MILLE + PER_MILLE + 0.5), PER_MILLE)
	for key: String in out:
		if out[key] != 0:
			return out
	return {}


## `DoBombing@10e8:6e2a`: one planet bombed by `fleet` (and its owner's other fleets there).
static func _bomb(
	state: GameState,
	content: ContentRegistry,
	rng: StarsRandom,
	planet: Planet,
	fleet: Fleet,
	several: bool,
	bombs: Dictionary
) -> void:
	var through := DefenseCoverage.uncovered(state, content, planet)
	var smart_through := DefenseCoverage.uncovered(state, content, planet, true)
	var normal: int = bombs.normal
	var minimum: int = bombs.minimum
	var smart: int = bombs.smart
	var installations: int = bombs.installations
	if through < 1.0:
		normal = DefenseCoverage.scale_round(normal, through)
		minimum = DefenseCoverage.scale_round(minimum, through)
		smart = DefenseCoverage.scale_round(smart, smart_through)
		installations = DefenseCoverage.halved_round(installations, through)
	# installations, shared out by kind; a remainder draw rounds factories, then defenses
	var total := planet.factories + planet.mines + planet.defenses
	var factories := 0
	var defenses := 0
	var mines := 0
	if installations > 0 and total > 0:
		factories = mini(
			_share(rng, planet.factories * installations, total, false), planet.factories
		)
		defenses = mini(_share(rng, planet.defenses * installations, total, false), planet.defenses)
		mines = mini(installations - defenses - factories, planet.mines)
	# colonists: smart bombs first, then normal bombs on the rest
	var killed := 0
	var pop := planet.population
	if (normal > 0 or minimum > 0 or smart > 0) and pop > 0:
		var by_smart := pop * smart / PER_MILLE
		if by_smart >= pop:
			by_smart = pop - 1
		killed = _share(rng, (pop - by_smart) * normal, PER_MILLE, true) + by_smart
		if normal > 0 and killed < 1:
			killed = 1
		killed = mini(maxi(killed, minimum), pop)
	planet.population -= maxi(killed, 0)
	planet.factories -= maxi(factories, 0)
	planet.mines -= maxi(mines, 0)
	planet.defenses -= maxi(defenses, 0)
	var defender := planet.owner
	var word := fleet.owner * FLEET_WORD + fleet.number
	var goto := {"fleet": fleet.number, "owner": fleet.owner}
	if bombs.retro > 0:
		var retro := mini(DefenseCoverage.retro_left(bombs.retro, through), RETRO_MAX)
		var undone := 0
		for axis in 3:
			var d := planet.environment[axis] - planet.environment_original[axis]
			var step := mini(absi(d), retro)
			planet.environment[axis] -= step * signi(d)
			undone += step
		if undone > 0:
			var mine := "message.bombing.fleets_retro" if several else "message.bombing.retro"
			var theirs := "message.bombed.fleets_retro" if several else "message.bombing.retro"
			_send(state, content, fleet.owner, mine, goto, [word, planet.id, undone])
			_send(
				state, content, defender, theirs, {"planet": planet.id}, [word, planet.id, undone]
			)
	# (the original's total counts a negative mines share as it is)
	var destroyed := defenses + factories + mines
	_messages(state, content, planet, defender, fleet, several, through, killed, destroyed)
	if planet.population == 0:
		PlanetEconomy.depopulate(planet, state.player(defender).race, content)


## (n div d), plus 1 when a `random(d)` falls below the remainder (or at it, `at_or_below`).
static func _share(rng: StarsRandom, n: int, d: int, at_or_below: bool) -> int:
	var out := n / d
	var r := n % d
	if r > 0:
		var roll := rng.random(d)
		if roll < r or (at_or_below and roll == r):
			out += 1
	return out


## The bombing messages to the bombers' owner (goto the first fleet) and the planet's owner (goto
## the planet), S17 "Messages".
static func _messages(
	state: GameState,
	content: ContentRegistry,
	planet: Planet,
	defender: int,
	fleet: Fleet,
	several: bool,
	through: float,
	killed: int,
	destroyed: int
) -> void:
	if destroyed < 1 and killed < 1:
		return
	var kind := ""
	var params := []
	var defended := ""
	if planet.population < 1:
		kind = "wiped_out"
	elif destroyed < 1:
		kind = "killed"
		params = [killed]
	else:
		var what := "installations" if destroyed > 1 else "one_installation"
		kind = "killed_" + what if killed > 0 else what
		params = [killed, destroyed] if killed > 0 else [destroyed]
		if through != 1.0:
			defended = "_defended"
			params.append(DefenseCoverage.stopped_basis_points(through))
	if kind == "wiped_out":
		params = []
	if kind == "wiped_out" and several:
		# fix B37: the original's "fleets" form of the message shows the bombers nothing
		planet.bombed_out_by[fleet.owner] = true
	var prefix := "fleets_" if several else ""
	var word := fleet.owner * FLEET_WORD + fleet.number
	var said := [word, planet.id] + params
	var goto := {"fleet": fleet.number, "owner": fleet.owner}
	var type := "%s%s%s" % [prefix, kind, defended]
	_send(state, content, fleet.owner, "message.bombing." + type, goto, said)
	_send(state, content, defender, "message.bombed." + type, {"planet": planet.id}, said)


## Sends a message with as many of `params` as its type takes (the original passes the same
## values to every type and each keeps its own number of them).
static func _send(
	state: GameState,
	content: ContentRegistry,
	player: int,
	type: String,
	goto: Dictionary,
	params: Array
) -> void:
	var kinds: Array = content.get_def("message", type).get("params", [])
	TurnMessages.add(state, content, player, type, goto, params.slice(0, kinds.size()))
