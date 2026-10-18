extends GdUnitTestSuite
## M13 single player in the game screen (through GameSession, the autoload): turns with computer
## players, and a player whose race is wiped out told once and still able to watch.


func _new_game() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 99
	options.opponents = [{"ai": "turindrones", "level": 1, "personality": {}}]
	GameSession.new_game(options)


func _wipe_out_the_player() -> void:
	var s := GameSession.state
	for pl in s.planets:
		if pl.owner == GameSession.player:
			pl.owner = -1
			pl.population = 0
			pl.starbase = null
	for f in s.fleets_of(GameSession.player):
		s.remove_fleet(f)
	GameSession._refresh()


func test_a_wiped_out_player_is_told_once_and_can_watch() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	assert_bool(screen._eliminated.visible).is_false()
	screen._on_end_turn()
	assert_bool(screen._eliminated.visible).is_false()
	_wipe_out_the_player()
	screen._on_end_turn()
	assert_bool(GameSession.view.me().eliminated).is_true()
	assert_bool(screen._eliminated.visible).is_true()
	screen._eliminated.hide()
	# the next years go on without the notice
	var year := GameSession.view.year()
	screen._on_end_turn()
	screen._on_end_turn()
	assert_int(GameSession.view.year()).is_equal(year + 2)
	assert_bool(screen._eliminated.visible).is_false()
	screen.queue_free()
	await get_tree().process_frame
	# a game already lost, opened again, says so
	var path := "user://test_lost_game.json"
	assert_int(GameSession.save_game(path)).is_equal(OK)
	assert_str(GameSession.load_game(path)).is_empty()
	screen = GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	assert_bool(screen._eliminated.visible).is_true()
	screen.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".orders")
