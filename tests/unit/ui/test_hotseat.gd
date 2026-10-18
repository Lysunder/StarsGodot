extends GdUnitTestSuite
## S27 hotseat (through GameSession, the autoload, and the game screen): two human players and a
## computer player take their turns in order behind the hand-off cover; the year is generated
## after the last human, with everyone's orders; a save in mid-round keeps who has played.

const PATH := "user://test_hotseat.json"


func after() -> void:
	for suffix in ["", ".orders", ".p1.orders", ".round"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _new_game() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 77
	options.race = RacePresets.make(GameSession.content, "race_preset.default")
	options.opponents = [
		{"human": true, "race": RacePresets.make(GameSession.content, "race_preset.warrior")},
		{"ai": "rototills", "level": 1, "personality": {}},
	]
	GameSession.new_game(options)


func _research(percent: int) -> void:
	var reason := GameSession.set_order(
		{"type": "research", "percent": percent, "field": 0, "next": Player.NEXT_FIELD_LOWEST}
	)
	assert_str(reason).is_empty()


func test_humans_take_turns_and_the_year_comes_after_the_last() -> void:
	_new_game()
	assert_bool(GameSession.is_hotseat()).is_true()
	assert_array(GameSession.humans()).is_equal([0, 1])
	# two humans: no one starts as anyone's enemy (S07)
	assert_str(GameSession.state.player(0).relations[1]).is_equal("neutral")
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	assert_bool(screen._handoff.visible).is_true()
	assert_str(screen._handoff_text.text).contains("player 1")
	screen._begin_turn()
	assert_bool(screen._handoff.visible).is_false()
	var year := GameSession.view.year()
	_research(30)
	screen._on_end_turn()
	# the second human is up, the year not generated yet
	assert_int(GameSession.player).is_equal(1)
	assert_int(GameSession.view.year()).is_equal(year)
	assert_bool(screen._handoff.visible).is_true()
	assert_str(screen._handoff_text.text).contains("player 2")
	screen._begin_turn()
	assert_array(GameSession.orders.orders).is_empty()
	assert_int(GameSession.view.me().index).is_equal(1)
	_research(40)
	screen._on_end_turn()
	# the year came, with both players' orders; the first human is up again
	assert_int(GameSession.view.year()).is_equal(year + 1)
	assert_int(GameSession.player).is_equal(0)
	assert_bool(screen._handoff.visible).is_true()
	assert_int(GameSession.state.player(0).research_percent).is_equal(30)
	assert_int(GameSession.state.player(1).research_percent).is_equal(40)
	screen.queue_free()
	await get_tree().process_frame


func test_a_save_in_mid_round_keeps_who_has_played() -> void:
	_new_game()
	_research(25)
	assert_bool(GameSession.end_turn()).is_false()
	assert_int(GameSession.player).is_equal(1)
	_research(35)
	assert_int(GameSession.save_game(PATH)).is_equal(OK)
	_new_game()
	assert_str(GameSession.load_game(PATH)).is_empty()
	# the second human is still at the controls, with their orders; the first has played
	assert_int(GameSession.player).is_equal(1)
	assert_int(GameSession.orders.orders.size()).is_equal(1)
	assert_bool(GameSession.end_turn()).is_true()
	assert_int(GameSession.state.player(0).research_percent).is_equal(25)
	assert_int(GameSession.state.player(1).research_percent).is_equal(35)
