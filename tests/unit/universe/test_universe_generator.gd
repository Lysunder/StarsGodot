extends GdUnitTestSuite
## Spec S07 against the original: universes generated from each fixture's seed must match the
## turn-0 files the original wrote for the same definition (tests/fixtures/golden).

## Fixture -> [game seed, players given as random computer players (`#0 0`)].
const GAMES := {
	"tiny2": [4242, []],
	"tiny3ai": [4242, []],
	"medium_clump": [1002, [1, 2, 3]],
	"small_maxmin": [1003, []],
	"tiny_accel": [1004, []],
	"small_sparse": [1005, []],
	"tiny_random_ai": [1009, [1]],
	"small_it": [1011, []],
	"medium_it_two_humans": [1012, [2]],
	"tiny_it": [1013, []],
	"tiny_random_race": [1014, []],
	"small_two_random_races": [1015, []],
	"tiny_random_races_only": [1017, []],
	"small_random_race_accel": [1018, []],
	"tiny_random_race_packed": [1019, []],
}

## The race file of the race wizard's "Random" preset uses this logo.
const RANDOM_PRESET_LOGO := 31

## Everything except names (the fixtures have neutral ones) and the random streams (a fixture
## holds the state at the start of the next turn's generation, S01).
const IGNORE := [
	"/rng",
	"/planets/*/name",
	"/players/*/race/name",
	"/players/*/race/plural_name",
	"/players/*/ship_designs*/name",
	"/players/*/starbase_designs*/name",
	"/players/*/battle_plans/*/name",
]

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _fixture(game: String) -> GameState:
	var path := "res://tests/fixtures/golden/%s/t000.json" % game
	var result := SaveFile.decode(FileAccess.get_file_as_string(path), _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	return result.state


## The players as the definition file gave them: the fixture's races, with the name and logo
## each race had before the setup draws. Human race files: logo 1 and one name per file (the
## fixtures use one race file per primary trait). Built-in computer races: no name, logo 0.
## Random computer players get their level and personality drawn again. A random race (S06) was
## the "Random" preset before the game was created (its name is drawn, so ours is empty).
func _input_players(game: String, state: GameState) -> Array[Player]:
	var randoms: Array = GAMES[game][1]
	var out: Array[Player] = []
	for original in state.players:
		var p := Player.new()
		p.index = original.index
		p.race = original.race.copy() as Race
		p.ai = original.ai
		p.ai_level = original.ai_level
		if p.race.random:
			p.race = _random_preset()
		elif p.is_human():
			p.race.name = "Testers " + p.race.primary_trait
			p.race.logo = 1
		else:
			p.race.name = ""
			p.race.logo = 0
			if p.index in randoms:
				p.ai = UniverseGenerator.AI_RANDOM
				p.ai_level = -1
		out.append(p)
	return out


func _random_preset() -> Race:
	var race := RacePresets.make(_content, "race_preset.random")
	race.logo = RANDOM_PRESET_LOGO
	return race


func _generate(game: String) -> Array:
	var state := _fixture(game)
	var gen := UniverseGenerator.new(
		_content, state.settings, _input_players(game, state), GAMES[game][0]
	)
	gen.generate_universe()
	return [gen, state]


func _check_universe(game: String) -> void:
	var pair := _generate(game)
	var gen: UniverseGenerator = pair[0]
	var real: GameState = pair[1]
	assert_int(gen.planets.size()).is_equal(real.planets.size())
	var homeworlds: Array[int] = []
	for p in real.players:
		homeworlds.append(p.homeworld)
	assert_array(gen.homeworlds).override_failure_message("%s homeworlds" % game).is_equal(
		homeworlds
	)
	for pl in gen.planets:
		var other := real.planet(pl.id)
		assert_array([pl.x, pl.y]).is_equal([other.x, other.y])
		if other.owner >= 0:
			continue
		var where := "%s planet %d" % [game, pl.id]
		assert_array(pl.environment).override_failure_message(where).is_equal(other.environment)
		assert_array(pl.concentration).override_failure_message(where).is_equal(other.concentration)
		assert_bool(pl.artifact != null).override_failure_message(where).is_equal(
			other.artifact != null
		)
	var logos: Array[int] = []
	for p in real.players:
		logos.append(p.race.logo)
	var got: Array[int] = []
	for p in gen.players:
		got.append(p.race.logo)
	assert_array(got).override_failure_message("%s logos" % game).is_equal(logos)


func test_two_humans_universe() -> void:
	_check_universe("tiny2")


func test_human_and_computers_universe() -> void:
	_check_universe("tiny3ai")


func test_planet_count() -> void:
	var settings := GameSettings.new()
	var gen := UniverseGenerator.new(_content, settings, [], 1)
	var cases := [
		[400, "normal", 32],
		[800, "normal", 128],
		[800, "sparse", 96],
		[1200, "dense", 360],
		[2000, "packed", 999],
	]
	for c: Array in cases:
		settings.universe_width = c[0]
		settings.density = c[1]
		gen.width = c[0]
		assert_int(gen.planet_count()).is_equal(c[2])


func test_sort_keeps_the_originals_order_of_equal_x() -> void:
	# Three equal x values: the original's quicksort leaves them in this order.
	var a := [[5, 1], [3, 0], [5, 2], [1, 0], [5, 3]]
	UniverseGenerator.sort_by_x(a)
	assert_array(a.map(func(p: Array) -> int: return p[0])).is_equal([1, 3, 5, 5, 5])
	var ys := a.slice(2).map(func(p: Array) -> int: return p[1])
	assert_array(ys).is_equal(_reference_order())


## Expected order of the y values of the three x = 5 entries after the original's sort
## (computed with the harness reference implementation of the same routine).
static func _reference_order() -> Array:
	return [2, 1, 3]


func _check_whole_game(game: String) -> void:
	var real := _fixture(game)
	var gen := UniverseGenerator.new(
		_content, real.settings, _input_players(game, real), GAMES[game][0]
	)
	var state := gen.generate()
	var diffs := StateDiff.compare(real, state, PackedStringArray(IGNORE))
	(
		assert_array(diffs)
		. override_failure_message(
			"%s: %d differences\n%s" % [game, diffs.size(), StateDiff.format(diffs, 60)]
		)
		. is_empty()
	)
	for checked in [real, state]:
		var errors := StateValidator.validate(checked, _content)
		assert_array(Array(errors)).override_failure_message("\n".join(errors)).is_empty()


## Every fixture game: the whole turn-0 state must match the original's. (gdUnit4 reads
## `test_parameters` itself.)
func test_whole_game(
	game: String,
	# gdlint: ignore=unused-argument
	test_parameters := [
		["tiny2"],
		["tiny3ai"],
		["medium_clump"],
		["small_maxmin"],
		["tiny_accel"],
		["small_sparse"],
		["tiny_random_ai"],
		["small_it"],
		["medium_it_two_humans"],
		["tiny_it"],
		["tiny_random_race"],
		["small_two_random_races"],
		["tiny_random_races_only"],
		["small_random_race_accel"],
		["tiny_random_race_packed"],
	]
) -> void:
	_check_whole_game(game)
