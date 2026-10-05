extends GdUnitTestSuite
## M11 UI smoke tests: the game screen on a new game, selecting, queueing, waypoints, end turn,
## save and load, all through GameSession (the autoload).


func _new_game() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 99
	options.race = RacePresets.make(GameSession.content, RacePresets.ids(GameSession.content)[0])
	GameSession.new_game(options)


func test_game_screen_plays_a_turn() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var home := GameSession.view.me().homeworld
	# queue an auto item through the planet pane's order
	var reason := (
		GameSession
		. set_order(
			{
				"type": "production_queue",
				"planet": home,
				"items":
				[
					{
						"item": "production_item.auto_mines",
						"design": -1,
						"starbase": false,
						"count": 5,
						"progress": 0,
					}
				],
			}
		)
	)
	assert_str(reason).is_empty()
	assert_int(GameSession.view.planet_info(home)["queue"].size()).is_equal(1)
	# a waypoint for the first fleet through the map's Shift+click order
	var fleet := GameSession.view.fleets()[0]
	screen._map.select("fleet", fleet.number)
	var target := GameSession.view.planets()[0]
	screen._map._add_waypoint(screen._map.to_screen(target["x"], target["y"]))
	assert_int(GameSession.view.fleet_info(fleet.number)["waypoints"].size()).is_equal(2)
	# a second queue order replaces the first
	(
		assert_str(GameSession.set_order({"type": "production_queue", "planet": home, "items": []}))
		. is_empty()
	)
	assert_int(GameSession.orders.orders.size()).is_equal(2)
	var year := GameSession.view.year()
	screen._on_end_turn()
	assert_int(GameSession.view.year()).is_equal(year + 1)
	screen.queue_free()
	await get_tree().process_frame


func test_rejected_orders_are_not_kept() -> void:
	_new_game()
	var reason := GameSession.add_order({"type": "research", "percent": 500, "field": 0, "next": 7})
	assert_str(reason).is_not_empty()
	assert_int(GameSession.orders.orders.size()).is_equal(0)


func test_save_and_load_keep_pending_orders() -> void:
	_new_game()
	(
		assert_str(
			GameSession.set_order({"type": "research", "percent": 33, "field": 1, "next": 7})
		)
		. is_empty()
	)
	var path := "user://test_saves/smoke.json"
	assert_int(GameSession.save_game(path)).is_equal(OK)
	var before := GameSession.state.copy() as GameState
	assert_str(GameSession.load_game(path)).is_empty()
	assert_bool(GameSession.state.equals(before)).is_true()
	assert_int(GameSession.view.me().research_percent).is_equal(33)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".orders")
