extends GdUnitTestSuite
## Spec S16: the battles of fixture turns, fought in the turn's waypoint 1 step, must match the
## original's recordings: place, sides, players, every token as it started (stats,
## square, order, weight jitter) and every move and shot.
## In compat mode (D12), like the golden turns: the original's armor damage (B09).

const CompatContent := preload("res://tests/unit/compat_content.gd")

var _content: ContentRegistry


func before() -> void:
	var r := CompatContent.load_mods()
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _load(game: String, turn: int) -> GameState:
	var path := "res://tests/fixtures/golden/%s/t%03d.json" % [game, turn]
	var result := SaveFile.decode(FileAccess.get_file_as_string(path), _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	return result.state


func _orders(game: String, turn: int, players: int) -> Array[OrderSet]:
	var out: Array[OrderSet] = []
	for p in players:
		var path := "res://tests/fixtures/golden/%s/t%03d.p%d.orders.json" % [game, turn, p]
		if FileAccess.file_exists(path):
			out.append(OrderFile.read(path).order_set)
	return out


## The battles fought while generating `turn` of `game`.
func _setup(game: String, turn: int) -> Array:
	var state := _load(game, turn)
	StandardTurn.generate(state, _content, _orders(game, turn, state.players.size()))
	return state.battles


func _check(game: String, turn: int) -> void:
	var expected: Array = _load(game, turn + 1).battles
	var ours := _setup(game, turn)
	assert_int(expected.size()).is_greater(0)
	assert_int(ours.size()).is_equal(expected.size())
	for i in mini(ours.size(), expected.size()):
		var want: Dictionary = (expected[i] as Dictionary).duplicate(true)
		var diffs := StateDiff.compare_dicts(want, ours[i], PackedStringArray())
		(
			assert_array(diffs)
			. override_failure_message(
				"%s turn %d battle %d:\n%s" % [game, turn, i, StateDiff.format(diffs, 40)]
			)
			. is_empty()
		)


func test_terra1_starbase_battle() -> void:
	_check("terra1", 30)


func test_mine1_patrol_battle() -> void:
	_check("mine1", 69)


func test_no_battle_without_an_armed_attacker() -> void:
	# mine1 turn 68: fleets of both players meet nowhere armed and hostile
	assert_array(_setup("mine1", 68)).is_empty()
