extends GdUnitTestSuite
## Golden turns (plan M4/M6): from each fixture turn, our turn generation must give the
## original's next turn exactly. Only the random streams are ignored (a fixture holds the state
## at the start of the next turn's generation, S01).

const IGNORE := ["/rng"]

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _load(game: String, turn: int) -> GameState:
	var path := "res://tests/fixtures/golden/%s/t%03d.json" % [game, turn]
	var result := SaveFile.decode(FileAccess.get_file_as_string(path), _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	return result.state


func _check_turn(game: String, turn: int) -> void:
	var state := _load(game, turn)
	StandardTurn.generate(state, _content)
	var expected := _load(game, turn + 1)
	var diffs := StateDiff.compare(expected, state, PackedStringArray(IGNORE))
	(
		assert_array(diffs)
		. override_failure_message(
			(
				"%s turn %d -> %d: %d differences\n%s"
				% [game, turn, turn + 1, diffs.size(), StateDiff.format(diffs, 40)]
			)
		)
		. is_empty()
	)


## Two human players without orders, no random events: mining, research, growth.
# gdlint: ignore=unused-argument
func test_tiny2(turn: int, test_parameters := [[0], [1], [2], [3], [4]]) -> void:
	_check_turn("tiny2", turn)
