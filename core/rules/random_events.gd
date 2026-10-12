class_name RandomEvents
extends RefCounted
## Random events (spec S18), right after the production step's tech update unless random events are
## off (`DoRandomEvents@10b0:1c1a`): a comet strike, an environment change, a mineral deposit and a
## Mystery Trader's arrival, in that order.

const SIZES := ["small", "medium", "large", "huge"]
const HUGE := 3
## Young colonies are spared environment changes before this year (population below 51 hundred).
const YOUNG_YEARS := 19
const YOUNG_POPULATION := 51
const FIRST_YEAR := 9
const ENV_MIN := 1
const ENV_MAX := 99
const CONCENTRATION_MAX := 200
const DEPOSIT_LIMIT := 180
const UNIVERSE_STEP := 400


static func run(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	comet(state, content, rng)
	environment_change(state, content, rng)
	mineral_deposit(state, content, rng)
	MysteryTrader.arrive(state, content, rng)


## The universe size: 0 tiny … 4 huge.
static func universe_size(state: GameState) -> int:
	return state.settings.universe_width / UNIVERSE_STEP - 1


## `RandomEvent_CometStrike@10b0:33aa`.
static func comet(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	if rng.random(20) != 0:
		return
	var planet := state.planets[rng.random(state.planets.size())]
	var t := state.turn
	if t <= FIRST_YEAR or not _changeable(planet, t):
		return
	var k := rng.random(4)
	var axes := [0, 1, 2]
	for i in 3:
		var j := rng.random(3)
		var swap: int = axes[i]
		axes[i] = axes[j]
		axes[j] = swap
	var amount: Array[int] = []
	for m in 3:
		amount.append(rng.random(250) + 50)
	var order := [0, 1, 2]
	for i in 2:
		var j := i + rng.random(3 - i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	var changed := mini(k, 2) + 1
	for p in state.players.size():
		if planet.owner == p and not _lives_in_starbase(state, content, p):
			var params := [planet.id]
			params.append_array(axes.slice(0, changed))
			_send(state, content, p, "message.event.comet_hit_yours_" + SIZES[k], planet, params)
		else:
			_send(state, content, p, "message.event.comet_hit_" + SIZES[k], planet, [planet.id])
	if planet.owner >= 0 and not _lives_in_starbase(state, content, planet.owner):
		planet.population -= planet.population * (25 + 20 * k) / 100
	for i in changed:
		var m: int = order[i]
		amount[m] += rng.random(17000) + 3000
		var c := planet.concentration[m] + rng.random(50) + 50
		if k == HUGE:
			c += rng.random(15) + 15
		planet.concentration[m] = mini(c, CONCENTRATION_MAX)
	for m in 3:
		planet.surface[m] += amount[m] >> 4
	for i in changed:
		var d := rng.random(3) + 3
		if k == HUGE:
			d += rng.random(3) + 3
		if rng.random(2) != 0:
			d = -d
		# fix B38: the axes the messages name (the original changes axes 0, 1, 2 in order)
		_shift(planet, axes[i], d)
	_clear_queue(planet, content)


## `RandomEvent_EnvironmentChange@10b0:3784`.
static func environment_change(
	state: GameState, content: ContentRegistry, rng: StarsRandom
) -> void:
	if rng.random(20) != 0:
		return
	var planet := state.planets[rng.random(state.planets.size())]
	if not _changeable(planet, state.turn):
		return
	var axis := rng.random(3)
	if planet.owner >= 0:
		_send(
			state,
			content,
			planet.owner,
			"message.event.environment_changed",
			planet,
			[planet.id, axis]
		)
	var d := rng.random(3) + 3
	if d == 3:
		d = rng.random(3) + 6
	if rng.random(2) != 0:
		d = -d
	_shift(planet, axis, d)
	_clear_queue(planet, content)


## `RandomEvent_MineralDeposit@10b0:3898`.
static func mineral_deposit(state: GameState, content: ContentRegistry, rng: StarsRandom) -> void:
	if rng.random(15 - universe_size(state)) != 0:
		return
	var planet := state.planets[rng.random(state.planets.size())]
	if state.turn <= FIRST_YEAR:
		return
	var m := rng.random(3)
	if planet.owner >= 0:
		_send(state, content, planet.owner, "message.event.mineral_deposit", planet, [planet.id, m])
	if planet.concentration[m] < DEPOSIT_LIMIT:
		planet.concentration[m] += rng.random(15) + 5


## Unowned, a young colony, or past the first years.
static func _changeable(planet: Planet, t: int) -> bool:
	return planet.owner < 0 or planet.population < YOUNG_POPULATION or t > YOUNG_YEARS


## An Alternate Reality race: its colonists live in the starbase.
static func _lives_in_starbase(state: GameState, content: ContentRegistry, p: int) -> bool:
	return RaceMath.trait_param(state.player(p).race, content, "colony.starbase", 0) != 0


static func _shift(planet: Planet, axis: int, d: int) -> void:
	planet.environment[axis] = clampi(planet.environment[axis] + d, ENV_MIN, ENV_MAX)
	planet.environment_original[axis] = clampi(
		planet.environment_original[axis] + d, ENV_MIN, ENV_MAX
	)


## `Planet_FreeQueue@10b0:36d6`: the queue keeps only its auto items.
static func _clear_queue(planet: Planet, content: ContentRegistry) -> void:
	var kept: Array[QueueItem] = []
	for q in planet.queue:
		if not q.is_design() and content.get_def("production_item", q.item).get("auto", false):
			kept.append(q)
	planet.queue = kept


static func _send(
	state: GameState,
	content: ContentRegistry,
	player: int,
	type: String,
	planet: Planet,
	params: Array
) -> void:
	TurnMessages.add(state, content, player, type, {"planet": planet.id}, params)
