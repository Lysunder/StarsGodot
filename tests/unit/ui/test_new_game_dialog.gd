extends GdUnitTestSuite
## S22 "Computer players in a new game": the New Game window's difficulty level and Advanced
## Game's computer player list (through GameSession, the autoload, for the content).


func test_the_difficulty_picks_the_computer_players() -> void:
	var dialog := NewGameDialog.new()
	add_child(dialog)
	var chosen: Array = []
	dialog.game_chosen.connect(func(o: NewGame.Options) -> void: chosen.append(o))
	(dialog._size_group.get_buttons()[2] as CheckBox).button_pressed = true
	(dialog._difficulty_group.get_buttons()[0] as CheckBox).button_pressed = true
	dialog._on_ok()
	var options: NewGame.Options = chosen[0]
	# a medium universe at Easy: six computer players at the easy level
	assert_int(options.opponents.size()).is_equal(6)
	for o in options.opponents:
		assert_int(o["level"]).is_equal(0)
	dialog.queue_free()
	await get_tree().process_frame


func test_advanced_game_chooses_the_computer_players() -> void:
	var folder := "user://test_new_game_personalities"
	PersonalityStore.dir = folder
	var own := PersonalityFile.make("Settler", AiBrains.BASELINE)
	PersonalityStore.save(own)
	var dialog := NewGameDialog.new()
	add_child(dialog)
	var chosen: Array = []
	dialog.game_chosen.connect(func(o: NewGame.Options) -> void: chosen.append(o))
	(dialog._size_group.get_buttons()[0] as CheckBox).button_pressed = true
	dialog._open_advanced()
	assert_bool(dialog._opponent_kind.disabled).is_true()
	dialog._choose.button_pressed = true
	# the game's six, the player's own, then Random
	assert_int(dialog._kinds.size()).is_equal(8)
	assert_str(dialog._kinds[6]["name"]).is_equal("Settler")
	dialog._opponent_kind.select(5)
	dialog._opponent_level.select(3)
	dialog._on_add_opponent()
	dialog._opponent_kind.select(6)
	dialog._opponent_level.select(4)
	dialog._on_add_opponent()
	assert_str(dialog._opponent_list.get_item_text(1)).is_equal("Settler, Random")
	dialog._advanced.hide()
	dialog._on_ok()
	var options: NewGame.Options = chosen[0]
	assert_int(options.opponents.size()).is_equal(2)
	assert_str(options.opponents[0]["ai"]).is_equal("macinti")
	assert_int(options.opponents[0]["level"]).is_equal(3)
	assert_int(options.opponents[1]["level"]).is_equal(-1)
	assert_dict(options.opponents[1]["personality"]).is_equal(own)
	GameSession.new_game(options)
	assert_int(GameSession.state.players.size()).is_equal(3)
	assert_str(GameSession.state.player(1).race.primary_trait).is_equal("trait.prt.AR")
	PersonalityStore.delete("Settler")
	PersonalityStore.dir = PersonalityStore.DIR
	dialog.queue_free()
	await get_tree().process_frame
