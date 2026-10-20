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
	# the game's six, the player's own, Random, then a human player for each race
	assert_int(dialog._kinds.size()).is_equal(8 + dialog._races.size())
	assert_str(dialog._kinds[7]["name"]).is_equal("Random")
	assert_bool(dialog._kinds[8].get("human", false)).is_true()
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


func test_begin_tutorial_and_public_scores_are_offered() -> void:
	var dialog := NewGameDialog.new()
	add_child(dialog)
	var tutorial := []
	dialog.tutorial_chosen.connect(func() -> void: tutorial.append(true))
	for b: Button in dialog.find_children("*", "Button", true, false):
		if b.text == "Begin Tutorial":
			assert_bool(b.disabled).is_false()
			b.pressed.emit()
	assert_array(tutorial).has_size(1)
	# every game option can be picked, public scores too, and reaches the game's settings
	var chosen: Array = []
	dialog.game_chosen.connect(func(o: NewGame.Options) -> void: chosen.append(o))
	for i in NewGameDialog.FLAGS.size():
		assert_bool(dialog._flags[i].disabled).is_false()
		if NewGameDialog.FLAGS[i][0] == "public_scores":
			dialog._flags[i].button_pressed = true
	dialog._on_ok()
	var options: NewGame.Options = chosen[0]
	assert_bool(options.flags.has("public_scores")).is_true()
	options.race = Race.new()
	assert_bool(NewGame.create(GameSession.content, options).settings.public_scores).is_true()
	dialog.queue_free()
	await get_tree().process_frame
