extends GdUnitTestSuite
## Every golden-turn fixture (tests/fixtures/golden) loads cleanly with the core content: the
## harness importer's output and our save format agree (specs S03, S23).

const GOLDEN_DIR := "res://tests/fixtures/golden"
const GAMES := ["tiny2", "tiny3ai"]
const TURNS := 6

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _load(game: String, turn: int) -> SaveFile.LoadResult:
	var path := "%s/%s/t%03d.json" % [GOLDEN_DIR, game, turn]
	return SaveFile.decode(FileAccess.get_file_as_string(path), _content)


func test_fixtures_load_and_validate() -> void:
	for game: String in GAMES:
		for turn in TURNS:
			var result := _load(game, turn)
			(
				assert_bool(result.ok())
				. override_failure_message("%s t%03d:\n%s" % [game, turn, "\n".join(result.errors)])
				. is_true()
			)
			assert_int(result.state.turn).is_equal(turn)


func test_turns_change_the_state() -> void:
	for game: String in GAMES:
		var previous := _load(game, 0).state
		for turn in range(1, TURNS):
			var current := _load(game, turn).state
			assert_bool(current.equals(previous)).is_false()
			previous = current


func test_fixture_shape() -> void:
	var tiny2 := _load("tiny2", 0).state
	assert_int(tiny2.players.size()).is_equal(2)
	assert_bool(tiny2.settings.no_random_events).is_true()
	assert_int(tiny2.settings.universe_width).is_equal(400)
	var ai := _load("tiny3ai", 5).state
	assert_int(ai.players.size()).is_equal(3)
	assert_bool(ai.players[0].is_human()).is_true()
	assert_bool(ai.players[1].is_human()).is_false()
	for p in ai.players:
		assert_object(ai.planet(p.homeworld)).is_not_null()
		assert_int(ai.planet(p.homeworld).owner).is_equal(p.index)
