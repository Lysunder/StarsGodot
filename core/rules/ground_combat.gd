class_name GroundCombat
extends RefCounted
## Ground combat (spec S17 "Ground combat", `ResolveGroundCombat@10b0:1e82`): colonists landed on
## planets during a task pass, or dropped by hand with the orders, are recorded per fleet and
## planet, then each planet is colonized or fought for, between the task passes of each pair
## (S02 5c and 16d).

const TROOPS_PCT_DEFAULT := 110
const DEFENSE_PCT_DEFAULT := 100
const PCT := 100
const ARTIFACT_FIELDS := 6
const ARTIFACT_MIN := 100
const ARTIFACT_RANGE := 301
const ARTIFACT_FULL_POPULATION := 10


## Colonists landed on a planet, waiting for ground combat (`RecordTransfer@10b0:2fda`): one
## record per fleet and planet.
class Colonization:
	extends RefCounted
	var fleet: int
	var player: int
	var planet: int
	var colonists: int
	## The planet had an owner when the colonists landed (hand drops record it; tasks always set it).
	var owned: bool

	func _init(
		p_fleet: int, p_player: int, p_planet: int, p_colonists: int, p_owned := true
	) -> void:
		fleet = p_fleet
		player = p_player
		planet = p_planet
		colonists = p_colonists
		owned = p_owned


var _state: GameState
var _content: ContentRegistry
var _rng: StarsRandom
var _pending: Array[Colonization] = []


func _init(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	_state = state
	_content = content
	_rng = rng
	# colonists dropped by hand with this turn's orders come first (S17)
	for d: Dictionary in state.dropped_colonists:
		_pending.append(Colonization.new(d.fleet, d.player, d.planet, d.colonists, d.owned))
	state.dropped_colonists.clear()


func record(fleet: Fleet, planet: Planet, colonists: int) -> void:
	if colonists <= 0:
		return
	var word := fleet.owner * 512 + fleet.number
	for c in _pending:
		if c.fleet == word and c.planet == planet.id:
			c.colonists += colonists
			return
	_pending.append(Colonization.new(word, fleet.owner, planet.id, colonists))


## S02 5c and 16d, `ResolveGroundCombat@10b0:1e82` (S17 "Ground combat"): the colonists landed on
## each planet, in the order of the planet's first record, colonize it or fight for it.
func resolve() -> void:
	var planets: Array[int] = []
	for c in _pending:
		if not planets.has(c.planet):
			planets.append(c.planet)
	for id in planets:
		_ground_combat(_state.planet(id))
	_pending.clear()


func _ground_combat(planet: Planet) -> void:
	var owner := planet.owner
	var through := 1.0
	if owner >= 0:
		through = DefenseCoverage.troops_through(
			DefenseCoverage.uncovered(_state, _content, planet)
		)
	var colonists := {}
	var strength := {}
	var total := 0
	for c in _pending:
		if c.planet != planet.id or _turned_away(c, planet):
			continue
		var race := _state.player(c.player).race
		var pct := RaceMath.trait_param(race, _content, "invasion.troops_pct", TROOPS_PCT_DEFAULT)
		var s := DefenseCoverage.scale_trunc(c.colonists * pct / PCT, through)
		colonists[c.player] = colonists.get(c.player, 0) + c.colonists
		strength[c.player] = strength.get(c.player, 0) + s
		total += s
	var defense := 0
	if owner >= 0:
		var race := _state.player(owner).race
		var pct := RaceMath.trait_param(race, _content, "invasion.defense_pct", DEFENSE_PCT_DEFAULT)
		defense = planet.population * pct / PCT
		if defense > total:
			_invaders_lose(planet, colonists, through, total, defense)
			return
		PlanetEconomy.depopulate(planet, race, _content)
	var best := -1
	var top := -1
	var second := 0
	var tie := false
	var count := 0
	for p in _state.players.size():
		if not colonists.has(p):
			continue
		count += 1
		var s: int = strength[p]
		if s >= top:
			if s == top:
				tie = true
			else:
				tie = false
				second = top
				top = s
				best = p
	if top < 0:
		return
	var at := {"planet": planet.id}
	if tie:
		for p: int in colonists:
			_message_to(p, "planet.invasion_all_died", at, [count, planet.id])
		if owner >= 0:
			_message_to(owner, "planet.invaded_all_died", at, [count, planet.id])
		return
	if owner < 0:
		if count < 2:
			var starter := RaceMath.trait_param(
				_state.player(best).race, _content, "colony.starbase", 0
			)
			_message_to(
				best,
				"planet.colonized_starbase" if starter else "planet.colonized",
				at,
				[planet.id]
			)
		else:
			for p: int in _sorted(colonists):
				if p == best:
					_message_to(p, "planet.colonized_race_won", at, [count, planet.id])
				else:
					_message_to(p, "planet.colonized_race_lost", at, [count, planet.id, best])
	else:
		for p: int in _sorted(colonists):
			if p == best:
				_message_to(p, "planet.invasion_won", at, [owner, planet.id])
			else:
				_message_to(p, "planet.invasion_lost_race", at, [planet.id])
		_message_to(owner, "planet.invaded", at, [best, planet.id, colonists[best]])
		# the winner may learn from the loser's technology (S24)
		var winner := _state.player(best)
		var gained := TechGain.try_bonus(winner, _state.player(owner).tech_levels, _content, _rng)
		if gained < 0:
			TechGain.wreckage_message(_state, _content, best, gained, [-1, planet.id])
		elif gained > 0:
			var field := gained - 1
			var amount := ResearchRules.level_cost(
				winner, field, _content, _state.settings.slow_tech
			)
			_message_to(
				best, "battle.tech_gained", {"research": true}, [-1, planet.id, field, amount]
			)
	var population: int = colonists[best]
	if total != 0 and top != 0:
		var left := (total - defense) * top / total
		population = colonists[best] * left / top
	if second > 0:
		population = (top - second) * population / top
	_found_colony(planet, best, maxi(population, 1))


## The defenders win: every invader is told (in player order), each time with the planet's owner;
## the defenders lose their share.
func _turned_away(c: Colonization, planet: Planet) -> bool:
	var at := {"planet": planet.id}
	var race := _state.player(c.player).race
	if (
		RaceMath.trait_param(race, _content, "colony.starbase", 0)
		and (not c.owned or planet.owner >= 0)
	):
		# a race that lives in space can't land colonists on a planet's surface
		_message_to(c.player, "planet.dropped_colonists_cannot_live", at, [planet.id])
	elif planet.owner < 0 and not c.owned:
		_message_to(c.player, "planet.dropped_colonists_died", at, [c.colonists, planet.id])
	elif planet.owner >= 0 and planet.starbase != null:
		_message_to(c.player, "planet.dropped_colonists_starbase", at, [planet.id])
	else:
		return false
	return true


func _invaders_lose(
	planet: Planet, colonists: Dictionary, through: float, total: int, defense: int
) -> void:
	var owner := planet.owner
	var at := {"planet": planet.id}
	for p: int in _sorted(colonists):
		var landed: int = colonists[p]
		if through == 1.0:
			_message_to(p, "planet.invasion_failed", at, [landed, planet.id, owner])
			_message_to(owner, "planet.invasion_repelled", at, [planet.id, landed, p])
		else:
			var stopped := DefenseCoverage.stopped_basis_points(through)
			var said := [landed, planet.id, stopped, owner]
			_message_to(p, "planet.invasion_failed_defended", at, said)
			_message_to(owner, "planet.invasion_repelled_defended", at, [planet.id, landed, p])
	planet.population -= planet.population * total / defense


func _sorted(players: Dictionary) -> Array:
	var out := players.keys()
	out.sort()
	return out


func _message_to(player: int, type: String, goto: Dictionary, params: Array) -> void:
	TurnMessages.add(_state, _content, player, "message." + type, goto, params)


func _found_colony(planet: Planet, player: int, population: int) -> void:
	var owner := _state.player(player)
	planet.owner = player
	planet.population = population
	planet.leftover_to_research = owner.default_leftover_to_research
	planet.queue.clear()
	for q in owner.default_queue:
		if ProductionTemplates.skips(owner.race, _content, q.item):
			continue
		var copy := q.copy() as QueueItem
		copy.progress = 0
		planet.queue.append(copy)
	if RaceMath.trait_param(owner.race, _content, "colony.starbase", 0):
		planet.starbase = Starbase.new()
		var base := owner.starbase_design(0)
		if base != null:
			base.built += 1
			base.remaining += 1
	if planet.artifact != null:
		planet.artifact = null
		if not _state.settings.no_random_events:
			var field := _rng.random(ARTIFACT_FIELDS)
			var points := ARTIFACT_MIN + _rng.random(ARTIFACT_RANGE)
			if population < ARTIFACT_FULL_POPULATION:
				points = population * points / ARTIFACT_FULL_POPULATION
			_message_to(
				player, "planet.artifact_found", {"research": true}, [planet.id, field, points]
			)
			_state.player(player).research_points[field] += points
