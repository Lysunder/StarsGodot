extends GdUnitTestSuite
## Spec S07 against the original: universes generated from seed 4242 must match the turn-0 files
## the original wrote for the same definition (tests/fixtures/golden).

const SEED := 4242

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
## each race had before the setup draws (human race files: one name, logo 1; built-in computer
## races: no name, logo 0).
func _input_players(state: GameState) -> Array[Player]:
	var out: Array[Player] = []
	for original in state.players:
		var p := Player.new()
		p.index = original.index
		p.race = original.race.copy() as Race
		p.ai = original.ai
		p.ai_level = original.ai_level
		if p.is_human():
			p.race.name = "Testers"
			p.race.logo = 1
		else:
			p.race.name = ""
			p.race.logo = 0
		out.append(p)
	return out


func _generate(game: String) -> Array:
	var state := _fixture(game)
	var gen := UniverseGenerator.new(_content, state.settings, _input_players(state), SEED)
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
