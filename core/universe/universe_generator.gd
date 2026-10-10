class_name UniverseGenerator
extends RefCounted
## Creates a new game (spec S07), drawing from the classic stream in exactly the original's order,
## so the same seed and settings give the same universe.
##
## Input: settings (size from universe_width, density, positions, options) and one Player per
## slot, with its race filled in. Computer players set `ai` to a personality id, or to AI_RANDOM
## (and ai_level -1 for a random level); built-in computer races have no name and logo 0.
## Human races whose advantage points are negative are replaced by `default_race`. Races with
## the random setting are rolled after their shuffle draw (S06); an empty name is drawn then.
##
## generate() runs everything. Steps 0-9 (setup draws, planets, homeworld choice) are here;
## steps 9.5-12 (starting tech, homeworlds, designs, fleets, wormholes) are in StartingSetup.

## The tips every player gets at the start (S21).
const WELCOME_TIPS := [
	"message.game.tip_filters",
	"message.game.tip_waypoints",
	"message.game.tip_designs",
	"message.game.tip_details",
]
const AI_PERSONALITIES := [
	"robotoids", "turindrones", "automitrons", "rototills", "cybertrons", "macinti"
]
const AI_RANDOM := "random"
const PLANET_NAMES := "name_list.planets"
const RACE_NAMES := "name_list.races"
const LOGOS := 32
const MIN_SPACING := 12
const MAX_PLANETS := 999
## Name ids are drawn from 0..998 (S07 step 6).
const PLANET_NAME_DRAW := 999
const SCATTER_MARGIN := 1010
const REMOVED := -100
const DENSITIES := ["sparse", "normal", "dense", "packed"]
const POSITIONS := ["close", "moderate", "farther", "distant"]

var content: ContentRegistry
var settings: GameSettings
var players: Array[Player] = []
var default_race: Race

## Results of the steps run so far.
var width: int
var positions: Array = []  # [x, y] per planet, in planet id order
var planets: Array[Planet] = []
## Homeworld surface minerals template (step 8).
var template: Array[int] = []
## Homeworld planet id per player, after the shuffle.
var homeworlds: Array[int] = []

var _rng: StarsRandom
var _streams: RngStreams


func _init(
	p_content: ContentRegistry,
	p_settings: GameSettings,
	p_players: Array[Player],
	game_seed: int,
	p_default_race: Race = null
) -> void:
	content = p_content
	settings = p_settings
	players = p_players
	default_race = p_default_race
	width = settings.universe_width
	_streams = RngStreams.new(game_seed, true)
	_rng = _streams.get_stream(RngStreams.CLASSIC)


## The whole new game (S07).
func generate() -> GameState:
	generate_universe()
	var state := GameState.new()
	state.settings = settings.copy() as GameSettings
	state.rng = _streams
	state.players.assign(players)
	state.planets.assign(planets)
	StartingSetup.new(self, state).run()
	_welcome(state)
	Scanning.record_all(state, content, _rng)
	return state


## S21: each player's first messages: four tips, then the home planet.
func _welcome(state: GameState) -> void:
	TurnMessages.clear(state)
	for p in state.players:
		for tip in WELCOME_TIPS:
			TurnMessages.add(state, content, p.index, tip, {}, [])
		if p.homeworld >= 0:
			TurnMessages.add(
				state,
				content,
				p.index,
				"message.game.home_planet",
				{"planet": p.homeworld},
				[p.homeworld]
			)


## The classic stream, for StartingSetup.
func rng() -> StarsRandom:
	return _rng


## Universe size index 0 (tiny) .. 4 (huge).
func size_index() -> int:
	return width / 400 - 1


## Steps 0-9: setup draws, planets and homeworld choice.
func generate_universe() -> void:
	_setup_draws()
	_scatter_planets()
	_roll_planets()
	_roll_template()
	_choose_homeworlds()


## The random streams after the steps run so far.
func streams() -> RngStreams:
	return _streams


# --- Step 0: setup draws ---------------------------------------------------------------------


func _setup_draws() -> void:
	for p in players:
		if p.ai.is_empty():
			continue
		if p.ai_level < 0:
			p.ai_level = _rng.random(4)
		if p.ai == AI_RANDOM:
			p.ai = AI_PERSONALITIES[_rng.random(AI_PERSONALITIES.size())]
	var race_names := content.name_list(RACE_NAMES)
	for p in players:
		if p.ai.is_empty() and default_race != null:
			if RaceMath.advantage_points(p.race, content) < 0:
				p.race = default_race.copy() as Race
		if p.race.name.is_empty() and not p.race.random:
			p.race.name = race_names[_rng.random(race_names.size())]
	for i in range(1, players.size()):
		if not _name_used(players[i].race.name, i, false):
			continue
		var r := _rng.random(race_names.size())
		while _name_used(race_names[r], -1, true):
			r = (r + 1) % race_names.size()
		players[i].race.name = race_names[r]
	_resolve_logos()


## Whether a name is used by an earlier player (before `upto`), or by any player when `everyone`.
func _name_used(name: String, upto: int, everyone: bool) -> bool:
	var last := players.size() if everyone else upto
	for j in last:
		if players[j].race.name == name:
			return true
	return false


func _resolve_logos() -> void:
	var logos: Array[int] = []
	for p in players:
		logos.append(p.race.logo if p.race.logo >= 0 and p.race.logo < LOGOS else -1)
	for i in range(1, logos.size()):
		if logos[i] < 0:
			continue
		var j := logos.slice(0, i).find(logos[i])
		if j < 0:
			continue
		if _rng.random(2) != 0:
			logos[i] = -1
		else:
			logos[j] = -1
	for i in logos.size():
		if logos[i] >= 0:
			continue
		var v := _rng.random(LOGOS)
		while _logo_taken(logos, v, i):
			v = (v + 1) % LOGOS
		logos[i] = v
	for i in players.size():
		players[i].race.logo = logos[i]


static func _logo_taken(logos: Array[int], v: int, except: int) -> bool:
	for k in logos.size():
		if k != except and logos[k] == v:
			return true
	return false


# --- Steps 1-5: positions --------------------------------------------------------------------


func planet_count() -> int:
	var d := DENSITIES.find(settings.density)
	var n := width * width / 5000
	n += (n / 4) * (d - 1)
	if d > 2:
		n += n / 4
	return mini(n, MAX_PLANETS)


func _scatter_planets() -> void:
	var n := planet_count()
	var m := mini(n + n / 7, MAX_PLANETS)
	var pos := []
	for k in m:
		var x := SCATTER_MARGIN + _rng.random(width - 19)
		var y := SCATTER_MARGIN + _rng.random(width - 19)
		pos.append([x, y])
	sort_by_x(pos)
	var removed := 0
	for k in m:
		if pos[k][1] < 0:
			continue
		var q := k + 1
		while q < m and pos[q][0] <= pos[k][0] + MIN_SPACING:
			var dy: int = absi(pos[k][1] - pos[q][1])
			var dx: int = pos[k][0] - pos[q][0]
			if dy <= MIN_SPACING and dx * dx + dy * dy <= MIN_SPACING * MIN_SPACING:
				pos[q][1] = REMOVED
				removed += 1
			q += 1
	while removed < m - n:
		var k := _rng.random(m)
		if pos[k][1] >= 0:
			pos[k][1] = REMOVED
			removed += 1
	positions = pos.filter(func(p: Array) -> bool: return p[1] >= 0)
	if settings.galaxy_clumping:
		_clump()


func _clump() -> void:
	var count := positions.size()
	for step in count:
		var j := _rng.random(count)
		var best := -1
		var best_d2 := 10000000
		for c in count:
			if c == j:
				continue
			var dx: int = positions[j][0] - positions[c][0]
			var dy: int = positions[j][1] - positions[c][1]
			var d2 := dx * dx + dy * dy
			if d2 < best_d2:
				best_d2 = d2
				best = c
		if best_d2 <= 144:
			continue
		for axis in 2:
			var a: int = positions[j][axis]
			var b: int = positions[best][axis]
			if best_d2 < 325:
				positions[j][axis] = (4 * a + b) / 5
			elif best_d2 < 626:
				positions[j][axis] = (2 * a + b) / 3
			elif best_d2 < 1601:
				positions[j][axis] = (a + b) / 2
			else:
				positions[j][axis] = (a + 2 * b) / 3
	sort_by_x(positions)


## Sorts [x, y] pairs by x with the original's sort routine (S07 step 3), so that equal x values
## end up in the same order as in the original.
static func sort_by_x(a: Array) -> void:
	var n := a.size()
	if n < 2:
		return
	var sorted := true
	for k in n - 1:
		if a[k + 1][0] < a[k][0]:
			sorted = false
			break
	if sorted:
		return
	var stack: Array = [[0, n - 1]]
	while not stack.is_empty():
		var lo: int = stack[-1][0]
		var hi: int = stack[-1][1]
		if lo >= hi:
			stack.pop_back()
			continue
		var bounds := _partition(a, lo, hi)
		stack.pop_back()
		var left: int = bounds[0]
		var right: int = bounds[1]
		if hi - right >= left - lo:
			stack.append([right, hi])
			stack.append([lo, left])
		else:
			stack.append([lo, left])
			stack.append([right, hi])


## One partition step around a[lo]; returns [left, right], the bounds of the two parts.
static func _partition(a: Array, lo: int, hi: int) -> Array:
	var left := lo
	var right := hi
	var i := lo
	var j := hi + 1
	while true:
		while true:
			i += 1
			if i == hi:
				break
			var c: int = a[i][0] - a[lo][0]
			if c > 0:
				break
			if c < 0:
				left = i
		while true:
			j -= 1
			var c: int = a[lo][0] - a[j][0]
			if c > 0:
				break
			if c == 0:
				if j == lo:
					break
				continue
			right = j
		if j > i:
			var t: Variant = a[i]
			a[i] = a[j]
			a[j] = t
			right = j
			left = i
			continue
		var t2: Variant = a[lo]
		a[lo] = a[j]
		a[j] = t2
		break
	return [left, right]


# --- Steps 6-8: names, environment, minerals, template ---------------------------------------


func _roll_planets() -> void:
	var names := content.name_list(PLANET_NAMES)
	var name_count := names.size() - 1 if not settings.tutorial else names.size()
	var used := {}
	planets.clear()
	for id in positions.size():
		var r := _rng.random(PLANET_NAME_DRAW)
		while used.has(r):
			r += 1
			if r >= name_count:
				r = 0
		used[r] = true
		var pl := Planet.new()
		pl.id = id
		pl.name = names[r]
		pl.x = positions[id][0]
		pl.y = positions[id][1]
		planets.append(pl)
	for pl in planets:
		_roll_environment(pl)


func _roll_environment(pl: Planet) -> void:
	if not settings.no_random_events:
		pl.artifact = true if _rng.random(3) == 0 else null
	var gravity := _rng.random(90) + 1
	gravity += _rng.random(10)
	var temperature := _rng.random(90) + 1
	temperature += _rng.random(10)
	var radiation := _rng.random(99) + 1
	pl.environment.assign([gravity, temperature, radiation])
	if settings.tutorial:
		if pl.id == 5:
			for axis in 3:
				pl.environment[axis] -= 5
		elif pl.id == 11:
			pl.environment[0] += 20
	pl.environment_original.assign(pl.environment)
	for k in 3:
		var c := 100
		if not settings.max_minerals:
			c = 31 + _rng.random(45)
			c += _rng.random(45)
			if radiation > 89:
				c += _rng.random(99 - c) / 2
		if settings.accelerated_start and c < 40:
			c += 5
		pl.concentration[k] = c
	if settings.max_minerals:
		return
	var t := _rng.random(27)
	if t < 9:
		var v := t + 1
		while v < 16:
			_scarcity_cut(pl)
			v <<= 1
	elif t < 18:
		_scarcity_cut(pl)


func _scarcity_cut(pl: Planet) -> void:
	var a := _rng.random(30)
	var k := _rng.random(3)
	pl.concentration[k] = a + 1


func _roll_template() -> void:
	template.clear()
	for k in 3:
		var s := 10 + _rng.random(10 * planets[0].concentration[k])
		if s < 200:
			s += 155 + _rng.random(150)
		if settings.accelerated_start:
			s += s / 4
		template.append(s)


# --- Step 9: homeworlds ----------------------------------------------------------------------


func _choose_homeworlds() -> void:
	var count := players.size()
	var a := 6 * width
	var b := width * width / count - a
	var d := 0 if b < 0 else 9 * b / 10
	var base := POSITIONS.find(settings.player_positions) * d / 3 + a
	var min_d2 := 9 * base / 10
	var near_d2 := 7 * base / 6
	var box := _homeworld_box(count)
	var chosen: Array[int] = []
	while true:
		chosen = _try_homeworlds(count, box, min_d2, near_d2)
		if not chosen.is_empty():
			break
		min_d2 -= base / 35
		near_d2 += base / 35
	var random_race: RandomRace = null
	for i in count:
		var r := i + _rng.random(count - i)
		var t := chosen[i]
		chosen[i] = chosen[r]
		chosen[r] = t
		if players[i].race.random:
			if random_race == null:
				random_race = RandomRace.new(content, _rng, default_race)
			random_race.roll(players[i].race)
	homeworlds = chosen


func _homeworld_box(count: int) -> Array[int]:
	if count < 3:
		return [width * 3 / 20 + 1000, width * 17 / 20 + 1000]
	if count < 5:
		return [width / 10 + 1000, width * 9 / 10 + 1000]
	return [width / 20 + 1000, width * 19 / 20 + 1000]


## One attempt at choosing all homeworlds; empty when it fails.
func _try_homeworlds(count: int, box: Array[int], min_d2: int, near_d2: int) -> Array[int]:
	var n := positions.size()
	var chosen: Array[int] = [_first_homeworld()]
	for p in range(1, count):
		var cand := -1
		var found := false
		for attempt in 50:
			cand = _rng.random(n)
			if _homeworld_ok(cand, chosen, box, min_d2, near_d2):
				found = true
				break
		if not found:
			var start := cand
			while true:
				cand += 1
				if cand >= n:
					cand = 0
					if start == 0:
						return []
				if cand == start:
					return []
				if _homeworld_ok(cand, chosen, box, min_d2, near_d2):
					break
		chosen.append(cand)
	return chosen


func _first_homeworld() -> int:
	var lo := width / 4 + 1000
	var hi := width * 3 / 4 + 1000
	var best := -1
	var best_d2 := 100000000
	for attempt in 50:
		var c := _rng.random(positions.size())
		var dx := _outside(positions[c][0], lo, hi)
		var dy := _outside(positions[c][1], lo, hi)
		if dx == 0 and dy == 0:
			return c
		if dx * dx + dy * dy < best_d2:
			best_d2 = dx * dx + dy * dy
			best = c
	return best


static func _outside(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo - v
	return v - hi if v > hi else 0


func _homeworld_ok(c: int, chosen: Array[int], box: Array[int], min_d2: int, near_d2: int) -> bool:
	var x: int = positions[c][0]
	var y: int = positions[c][1]
	if x < box[0] or x > box[1] or y < box[0] or y > box[1]:
		return false
	var near := false
	for h in chosen:
		var dx: int = x - positions[h][0]
		var dy: int = y - positions[h][1]
		var d2 := dx * dx + dy * dy
		if d2 < 1 or d2 < min_d2:
			return false
		if d2 <= near_d2:
			near = true
	return near
