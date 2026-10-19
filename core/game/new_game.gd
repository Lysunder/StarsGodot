class_name NewGame
extends RefCounted
## Creates a game for the UI (spec S07 through UniverseGenerator): the human player with the given
## race, then the other players chosen (computer players, and more humans for hotseat, S27), in a
## universe of the given size,
## density and player spacing. pick_opponents chooses the computer players from the universe size
## and difficulty level the way the original's simple New Game does (S22 "Computer players in a
## new game").

const SIZES := ["tiny", "small", "medium", "large", "huge"]
const WIDTH_STEP := 400
const MAX_PLAYERS := 16
## The opponents each difficulty level fields, as [personality, level] (personality "random"
## and level -1 are drawn when the game is created), by share of the computer players: each
## entry's share is the numerator of the share bound its slots end at (see _slot_bounds).
const RANDOM := UniverseGenerator.AI_RANDOM
const MIX := [
	[["automitrons", 0], ["rototills", 0], ["turindrones", 0], [RANDOM, 0]],
	[
		["turindrones", 1],
		["robotoids", 1],
		["automitrons", 1],
		["rototills", 1],
		["cybertrons", 1],
		[RANDOM, -1],
	],
	[
		["cybertrons", 2],
		["turindrones", 2],
		["robotoids", 2],
		["macinti", 2],
		[RANDOM, 2],
		[RANDOM, -1],
	],
	[["robotoids", 3], ["macinti", 3], ["cybertrons", 3], [RANDOM, 3]],
]


class Options:
	extends RefCounted
	## Index into SIZES.
	var size: int = 1
	var density: String = "normal"
	var positions: String = "moderate"
	var race: Race = null
	@warning_ignore("shadowed_global_identifier") var seed: int = 1
	## GameSettings flags to turn on (max_minerals, slow_tech, accelerated_start,
	## no_random_events, galaxy_clumping, ...).
	var flags: Array[String] = []
	## The other players, in player order after the first human: a computer player {ai (a
	## personality key, or RANDOM), level (an index into ComputerPlayers.LEVELS, -1 random),
	## personality (the player's own personality, else {} for the content one)}, or another human
	## {human: true, race}.
	var opponents: Array[Dictionary] = []


static func create(content: ContentRegistry, options: Options) -> GameState:
	var settings := GameSettings.new()
	settings.universe_width = (options.size + 1) * WIDTH_STEP
	settings.density = options.density
	settings.player_positions = options.positions
	for flag in options.flags:
		settings.set(flag, true)
	var player := Player.new()
	player.index = 0
	player.race = options.race.copy() as Race if options.race != null else Race.new()
	if player.race.name.is_empty():
		player.race.name = "Humanoids"
		player.race.plural_name = "Humanoids"
	var players: Array[Player] = [player]
	for o: Dictionary in options.opponents:
		if players.size() >= MAX_PLAYERS:
			break
		var p := Player.new()
		p.index = players.size()
		if o.get("human", false):
			p.race = (o["race"] as Race).copy() as Race
			players.append(p)
			continue
		p.ai = str(o.get("ai", RANDOM))
		p.ai_level = int(o.get("level", -1))
		p.ai_personality = (o.get("personality", {}) as Dictionary).duplicate(true)
		p.race = null
		players.append(p)
	var state := UniverseGenerator.new(content, settings, players, options.seed).generate()
	ComputerPlayers.adopt_personalities(state, content)
	SaveFile.stamp(state, content)
	return state


## The key a personality of the player's plays under (Player.ai): its name, made a key.
static func personality_key(p: Dictionary) -> String:
	return "own_" + str(p.get("name", "")).to_snake_case().validate_filename()


## The computer players the simple New Game fields for universe size `size` (index into SIZES)
## at difficulty `difficulty` (index into ComputerPlayers.LEVELS), drawing from `rng`: how many
## players there are, which personalities and levels in what shares, then shuffled.
static func pick_opponents(size: int, difficulty: int, rng: StarsRandom) -> Array[Dictionary]:
	var count := player_count(size, difficulty, rng)
	var slots: Array = []
	slots.resize(count)
	var bounds := _slot_bounds(count, difficulty)
	for i in range(1, count):
		var k := 0
		while k < bounds.size() and i >= bounds[k]:
			k += 1
		slots[i] = MIX[difficulty][k]
	# each slot but the last swaps with a later one
	for i in range(1, count - 1):
		var j := i + 1 + rng.random(count - i - 1)
		var t: Variant = slots[i]
		slots[i] = slots[j]
		slots[j] = t
	var out: Array[Dictionary] = []
	for i in range(1, count):
		out.append({"ai": slots[i][0], "level": slots[i][1], "personality": {}})
	return out


## The players in the game, the human included, by universe size and difficulty.
static func player_count(size: int, d: int, rng: StarsRandom) -> int:
	var expert := d == 3
	match size:
		0:
			return 3 if expert and rng.random(3) == 0 else 2
		1:
			if expert and rng.random(4) == 0:
				return 5
			return 4 if d > 1 and rng.random(6 - d) == 0 else 3
		2:
			if expert and rng.random(10) == 0:
				return 9
			if expert and rng.random(10) == 0:
				return 5
			return _two_tries(d, 7 - d, 8, 6, 7, rng)
		3:
			if expert and rng.random(10) == 0:
				return 14 + rng.random(2)
			if expert and rng.random(10) == 0:
				return 10 - rng.random(2)
			return _two_tries(d, 7 - d, 13, 11, 12, rng)
		_:
			if expert and rng.random(10) == 0:
				return 13 - rng.random(3)
			return _two_tries(d, 9 - d, 14, 15, 16, rng)


## From Harder up, a draw of 1 in `first` gives `a`, then one of 1 in 7 - d gives `b`; else `c`.
static func _two_tries(d: int, first: int, a: int, b: int, c: int, rng: StarsRandom) -> int:
	if d >= 2 and rng.random(first) == 0:
		return a
	if d >= 2 and rng.random(7 - d) == 0:
		return b
	return c


## The first slot index past each share of the computer players (slots 1 .. count-1), for MIX.
static func _slot_bounds(n: int, d: int) -> Array[int]:
	match d:
		0:
			return [(n + 1) / 3 + 1, (n + 1) * 2 / 3 + 1, (n + 1) * 5 / 6 + 1]
		3:
			return [(n + 1) / 3 + 1, (n * 6 + 5) / 12 + 1, n * 5 / 6 + 1]
		_:
			return [
				(n + 5) * 2 / 7 + 1,
				(n + 1) * 3 / 7 + 1,
				(n * 4 + 2) / 7 + 1,
				(n * 5 + 1) / 7 + 1,
				n * 6 / 7 + 1,
			]
