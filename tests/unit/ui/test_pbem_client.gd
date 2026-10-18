extends GdUnitTestSuite
## S27 "Play by email", the player's side (through GameSession, the autoload, and the game screen):
## a turn file opens as that player's game; ending the turn writes the orders beside it for the
## host, and opening the file again goes on with them.

const DIR := "user://test_pbem_client"


func after() -> void:
	for sub in ["done/0", "done"]:
		var d := DIR.path_join(sub)
		if DirAccess.dir_exists_absolute(d):
			for f in DirAccess.get_files_at(d):
				DirAccess.remove_absolute(d.path_join(f))
			DirAccess.remove_absolute(d)
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
		DirAccess.remove_absolute(DIR)


func test_a_turn_file_is_played_and_its_orders_written() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 55
	options.race = RacePresets.make(GameSession.content, "race_preset.default")
	options.opponents = [
		{"human": true, "race": RacePresets.make(GameSession.content, "race_preset.shadow")}
	]
	var made := PbemHost.create(DIR, "pair", options, GameSession.content, "t")
	assert_bool(made.ok()).override_failure_message("\n".join(made.errors)).is_true()
	var turn := DIR.path_join("pair-p2.turn")
	assert_str(GameSession.open_turn_file(turn)).is_empty()
	assert_bool(GameSession.is_pbem()).is_true()
	assert_int(GameSession.player).is_equal(1)
	assert_int(GameSession.view.me().index).is_equal(1)
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	# no hand-off cover: one player per turn file
	assert_bool(screen._handoff.visible).is_false()
	var reason := GameSession.set_order(
		{"type": "research", "percent": 44, "field": 0, "next": Player.NEXT_FIELD_LOWEST}
	)
	assert_str(reason).is_empty()
	screen._on_end_turn()
	assert_bool(FileAccess.file_exists(DIR.path_join("pair-p2.orders"))).is_true()
	assert_array(PbemHost.status(DIR, GameSession.content).submitted).is_equal([1])
	screen.queue_free()
	await get_tree().process_frame
	# opened again, the orders written are there to go on with
	assert_str(GameSession.open_turn_file(turn)).is_empty()
	assert_int(GameSession.orders.orders.size()).is_equal(1)
	# a damaged turn file is refused
	var text := FileAccess.get_file_as_string(turn)
	var f := FileAccess.open(DIR.path_join("bad.turn"), FileAccess.WRITE)
	f.store_string(text.replace('"turn":0', '"turn":7'))
	f.close()
	assert_str(GameSession.open_turn_file(DIR.path_join("bad.turn"))).contains("damaged")
