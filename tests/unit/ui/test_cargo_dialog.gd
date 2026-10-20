extends GdUnitTestSuite
## The cargo window's other sides: deep space (Jettison: the cargo is lost) and another player's
## planet (the fleet can only give).


func _new_game() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 99
	options.race = RacePresets.make(GameSession.content, RacePresets.ids(GameSession.content)[0])
	GameSession.new_game(options)


func test_jettison_drops_cargo_into_deep_space() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	# a fleet with a cargo hold, 50 kT of ironium aboard
	var number := -1
	for f in GameSession.view.fleets():
		if GameSession.view.fleet_info(f.number)["cargo_capacity"] >= 50:
			number = f.number
			break
	assert_int(number).is_not_equal(-1)
	GameSession.state.fleet(GameSession.player, number).cargo[0] = 50
	GameSession._refresh()
	var dialog := screen._command._cargo
	dialog.open_deep_space(number)
	assert_str(dialog._right_title.text).is_equal("Deep Space")
	# nothing to take from deep space; 20 kT of ironium thrown out
	dialog.move(0, 10)
	assert_int(dialog._fleet[0]).is_equal(50)
	dialog.move(0, -20)
	dialog._on_ok()
	assert_str(dialog._status.text).is_empty()
	assert_int(GameSession.view.fleet_info(number)["cargo"][0]).is_equal(30)
	screen.queue_free()
	await get_tree().process_frame


func test_another_players_planet_starts_empty() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var number := GameSession.view.fleets()[0].number
	var other := -1
	for pl: Dictionary in GameSession.view.planets():
		if not pl["mine"]:
			other = pl["id"]
			break
	var dialog := screen._command._cargo
	dialog.open_with_planet(number, other)
	assert_array(dialog._other).is_equal([0, 0, 0, 0, 0])
	dialog.move(0, 10)
	assert_int(dialog._fleet[0]).is_equal(GameSession.view.fleet_info(number)["cargo"][0])
	dialog.hide()
	screen.queue_free()
	await get_tree().process_frame
