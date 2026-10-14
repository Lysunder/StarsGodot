extends GdUnitTestSuite
## M11 step 7: the score report's table, victory conditions and history graph (S20 "What a player
## sees", "History"), on the rand1 fixtures (two players, private scores).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _state(turn: int) -> GameState:
	var path := "res://tests/fixtures/golden/rand1/t%03d.json" % turn
	var result := SaveFile.decode(FileAccess.get_file_as_string(path), _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	return result.state


func _row(t: Dictionary, field: String) -> Dictionary:
	for row: Dictionary in t["rows"]:
		if row["field"] == field:
			return row
	return {}


func test_private_scores_show_only_the_players_own() -> void:
	var state := _state(104)
	var t := ScoreView.table(PlayerView.new(state, _content, 0))
	assert_bool(t["players"][0]["known"]).is_true()
	assert_bool(t["players"][1]["known"]).is_false()
	var score := _row(t, "score")
	assert_int(score["values"][0]).is_equal(int(state.player(0).score.score))
	assert_int(score["values"][1]).is_equal(-1)
	assert_int(_row(t, "rank")["values"][0]).is_equal(1)


func test_public_scores_show_everyone_after_turn_19() -> void:
	var state := _state(104)
	state.settings.public_scores = true
	var view := PlayerView.new(state, _content, 1)
	var t := ScoreView.table(view)
	assert_bool(t["players"][0]["known"]).is_true()
	var score := _row(t, "score")
	assert_int(score["best"]).is_equal(int(state.player(0).score.score))
	# the best rank is the lowest
	assert_int(_row(t, "rank")["best"]).is_equal(1)
	assert_bool(ScoreView.can_see(view, 0, 19)).is_false()
	assert_bool(ScoreView.can_see(view, 0, 20)).is_true()
	assert_bool(ScoreView.can_see(view, 1, 3)).is_true()


func test_conditions_follow_the_settings_and_records() -> void:
	var state := _state(104)
	var view := PlayerView.new(state, _content, 0)
	var conditions := ScoreView.conditions(view)
	var by_id := {}
	for c in conditions:
		by_id[c["id"]] = c
	assert_bool(by_id["owns_planets"]["on"]).is_true()
	assert_int(by_id["owns_planets"]["value"]).is_equal(20)
	assert_bool(by_id["score"]["on"]).is_false()
	assert_int(by_id["tech_level"]["fields"]).is_equal(2)
	assert_int(by_id["criteria"]["value"]).is_equal(1)
	# player 0 met owns_planets (its record); player 1's record is private
	assert_that(by_id["owns_planets"]["met"][0]).is_equal(true)
	assert_that(by_id["owns_planets"]["met"][1]).is_null()
	assert_array(ScoreView.winners(view)).is_equal([0])


func test_turns_add_to_the_history() -> void:
	var state := _state(103)
	assert_array(state.history).is_empty()
	StandardTurn.generate(state, _content, [])
	assert_int(state.history.size()).is_equal(1)
	var entry: Dictionary = state.history[0]
	assert_int(entry["turn"]).is_equal(state.turn)
	assert_int(entry["records"][0]["score"]).is_equal(int(state.player(0).score.score))
	assert_int(entry["records"][1]["rank"]).is_equal(int(state.player(1).score.rank))
	var view := PlayerView.new(state, _content, 0)
	var lines := ScoreView.series(view, "score")
	assert_int(lines.size()).is_equal(1)
	assert_int(lines[0]["player"]).is_equal(0)
	assert_that(lines[0]["points"][0]).is_equal(
		Vector2i(2400 + state.turn, entry["records"][0]["score"])
	)
	# the history survives saving
	var again := SaveFile.decode(SaveFile.encode(state, "0.1.0"), _content).state
	assert_int(ScoreView.series(PlayerView.new(again, _content, 0), "score").size()).is_equal(1)


func test_graph_scale() -> void:
	assert_int(ScoreGraph.scale_top(1)).is_equal(5)
	assert_int(ScoreGraph.scale_top(7)).is_equal(10)
	assert_int(ScoreGraph.scale_top(509)).is_equal(1000)
	assert_int(ScoreGraph.scale_top(120000)).is_equal(150000)
