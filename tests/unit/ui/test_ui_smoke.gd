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


func test_designer_saves_a_new_design() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var designer := screen._designer
	designer.open()
	var before := GameSession.view.designer.designs(false).size()
	designer._on_new()
	assert_bool(designer.editing).is_true()
	designer._name.text = "Probe"
	designer._on_name("Probe")
	# put the first part the engine slot takes into it
	var hull := GameSession.content.hull(designer.design.hull)
	var engine_slot := -1
	for i in (hull["slots"] as Array).size():
		if (hull["slots"][i]["accepts"] as Array).has("engine"):
			engine_slot = i
			break
	assert_int(engine_slot).is_greater_equal(0)
	designer._slots.select(engine_slot)
	designer._show_parts()
	assert_int(designer._parts.item_count).is_greater(0)
	designer._parts.select(0)
	designer._on_add()
	assert_str(designer.design.parts[engine_slot].part).is_not_empty()
	designer._on_save()
	assert_str(designer._status.text).is_empty()
	assert_bool(designer.editing).is_false()
	var designs := GameSession.view.designer.designs(false)
	assert_int(designs.size()).is_equal(before + 1)
	assert_bool(designs.any(func(d: Design) -> bool: return d.name == "Probe")).is_true()
	# the new design can be queued straight away
	var home := GameSession.view.me().homeworld
	var labels := GameSession.view.production_inventory(home).map(
		func(i: Dictionary) -> String: return i["label"]
	)
	assert_bool(labels.has("Probe")).is_true()
	designer.hide()
	screen.queue_free()
	await get_tree().process_frame


func test_designer_refuses_an_unnamed_design() -> void:
	_new_game()
	var designer := ShipDesigner.new()
	add_child(designer)
	designer.open()
	designer._on_new()
	designer._on_save()
	assert_str(designer._status.text).is_not_empty()
	assert_bool(designer.editing).is_true()
	designer.queue_free()
	await get_tree().process_frame


func test_waypoint_editing() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var map := screen._map
	var fleet := GameSession.view.fleets()[0]
	map.select("fleet", fleet.number)
	map.size = Vector2(800, 600)
	map._fit()
	var planets := GameSession.view.planets()
	var far: Dictionary = planets[0]
	var near: Dictionary = planets[planets.size() - 1]
	# a deep-space spot: no planet or fleet within the pick radius
	var space := Vector2(map.to_screen(far["x"], far["y"]))
	while not (
		GameSession
		. view
		. objects_at(map.to_universe(space).x, map.to_universe(space).y, map.PICK_PIXELS / map.zoom)
		. is_empty()
	):
		space += Vector2(7, 3)
	# two waypoints at the end, then one inserted after waypoint 1
	map.set_waypoint(-1)
	map._add_waypoint(map.to_screen(far["x"], far["y"]))
	assert_int(map.waypoint).is_equal(1)
	map._add_waypoint(map.to_screen(near["x"], near["y"]))
	assert_int(map.waypoint).is_equal(2)
	map.set_waypoint(1)
	map._add_waypoint(space)
	var waypoints: Array = GameSession.view.fleet_info(fleet.number)["waypoints"]
	assert_int(waypoints.size()).is_equal(4)
	assert_str(waypoints[1]["label"]).is_equal(far["name"])
	assert_str(waypoints[2]["target"]).is_equal("none")
	assert_str(waypoints[3]["label"]).is_equal(near["name"])
	for i in range(1, 4):
		assert_bool(waypoints[i].has("short_of_fuel")).is_true()
	# adjusting the same waypoint step by step stays one order
	var before := GameSession.orders.orders.size()
	var pane := screen._command
	pane._waypoint = 3
	for warp in [5, 4, 3]:
		pane._change_waypoint(waypoints[3], warp, "none", {})
	assert_int(GameSession.orders.orders.size()).is_equal(before + 1)
	assert_int(GameSession.view.fleet_info(fleet.number)["waypoints"][3]["warp"]).is_equal(3)
	# dragging waypoint 2 onto a planet retargets it
	map._drag_waypoint = 2
	map._drag_from = map.to_screen(waypoints[2]["x"], waypoints[2]["y"])
	map._release(map.to_screen(far["x"], far["y"]))
	waypoints = GameSession.view.fleet_info(fleet.number)["waypoints"]
	assert_str(waypoints[2]["target"]).is_equal("planet")
	assert_int(waypoints[2]["target_id"]).is_equal(far["id"])
	screen.queue_free()
	await get_tree().process_frame


func test_warp_slider_updates_rows_while_dragging() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var fleet := GameSession.view.fleets()[0]
	screen._map.size = Vector2(800, 600)
	screen._map._fit()
	screen._map.select("fleet", fleet.number)
	var target := GameSession.view.planets()[0]
	screen._map._add_waypoint(screen._map.to_screen(target["x"], target["y"]))
	await get_tree().process_frame
	var pane := screen._command
	var slider: HSlider = pane._tiles.find_children("*", "HSlider", true, false)[0]
	var list := pane._waypoint_list
	var before := GameSession.orders.orders.size()
	slider.drag_started.emit()
	for warp in [3, 4, 5]:
		slider.value = warp
		assert_bool(list.get_item_text(1).contains("warp %d," % warp)).is_true()
		assert_object(pane._waypoint_list).is_same(list)
	slider.drag_ended.emit(true)
	assert_int(GameSession.orders.orders.size()).is_equal(before + 1)
	assert_int(GameSession.view.fleet_info(fleet.number)["waypoints"][1]["warp"]).is_equal(5)
	screen.queue_free()
	await get_tree().process_frame


func test_rename_dialog_renames_the_fleet() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var fleet := GameSession.view.fleets()[0]
	screen._map.select("fleet", fleet.number)
	var dialog := screen._command._rename_dialog
	var current := GameSession.view.fleet_name(fleet)
	dialog.open("Rename Fleet", current, OrderRules.NAME_MAX)
	assert_str(dialog._field.text).is_equal(current)
	assert_str(dialog._field.get_selected_text()).is_equal(current)
	dialog._field.text = "Scouts"
	dialog.get_ok_button().pressed.emit()
	var renamed := GameSession.view.state.fleet(GameSession.PLAYER, fleet.number)
	assert_str(GameSession.view.fleet_name(renamed)).is_equal("Scouts")
	screen.queue_free()
	await get_tree().process_frame


func test_tiles_keep_their_order_and_collapse() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var pane := screen._command
	pane.command("planet", GameSession.view.me().homeworld)
	var keys := func() -> Array:
		var out := []
		for child in pane._tiles.get_children():
			if child is Tile and not child.is_queued_for_deletion():
				out.append(child.key)
		return out
	var before: Array = keys.call()
	assert_str(before[0]).is_equal("planet")
	# drop the Status tile on the first tile, collapse Minerals on Hand
	var first: Tile = pane._tiles.get_child(0)
	first.tile_dropped.emit("Status", "planet")
	pane._collapsed["Minerals on Hand"] = true
	pane._rebuild()
	var after: Array = keys.call()
	assert_str(after[0]).is_equal("Status")
	assert_str(after[1]).is_equal("planet")
	for child in pane._tiles.get_children():
		if child is Tile and child.key == "Minerals on Hand" and not child.is_queued_for_deletion():
			assert_bool(child.collapsed).is_true()
	assert_str(CommandPane.thousands(1234567)).is_equal("1,234,567")
	screen.queue_free()
	await get_tree().process_frame
