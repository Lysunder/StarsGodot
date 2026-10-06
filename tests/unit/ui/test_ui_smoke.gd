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
	designer._set_mode(ShipDesigner.MODE_HULLS)
	assert_object(designer.design).is_not_null()
	designer._on_copy()
	assert_bool(designer.editing).is_true()
	designer._name.text = "Probe"
	designer._on_name("Probe")
	# an engine in the slot that takes one, through the schematic
	var hull := GameSession.content.hull(designer.design.hull)
	var engine_slot := -1
	for i in (hull["slots"] as Array).size():
		if (hull["slots"][i]["accepts"] as Array).has("engine"):
			engine_slot = i
			break
	assert_int(engine_slot).is_greater_equal(0)
	var engine := GameSession.view.designer.available_parts(["engine"])[0]
	assert_bool(designer._schematic.add_part(engine_slot, engine, 1)).is_true()
	assert_str(designer.design.parts[engine_slot].part).is_equal(engine)
	designer._on_done()
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
	designer._set_mode(ShipDesigner.MODE_HULLS)
	designer._on_copy()
	designer._on_done()
	assert_str(designer._status.text).is_not_empty()
	assert_bool(designer.editing).is_true()
	# a part dragged back to the list leaves its slot
	var slot := 0
	var part := (
		GameSession
		. view
		. designer
		. available_parts(GameSession.content.hull(designer.design.hull)["slots"][0]["accepts"])[0]
	)
	designer._schematic.add_part(slot, part, 1)
	designer._take_back({"from_slot": slot})
	assert_str(designer.design.parts[slot].part).is_empty()
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


func test_warp_gauge_updates_the_leg_while_dragging() -> void:
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
	var gauge: WarpGauge = pane._tiles.find_children("*", "WarpGauge", true, false)[0]
	var before := GameSession.orders.orders.size()
	var times := []
	for warp in [2, 5, 9]:
		gauge.set_value(warp)
		gauge.value_dragged.emit(warp)
		assert_object(pane._tiles.find_children("*", "WarpGauge", true, false)[0]).is_same(gauge)
		times.append((pane._leg_fields["time"] as Label).text)
	assert_str(times[0]).is_not_equal(times[2])
	gauge.value_set.emit(9)
	assert_int(GameSession.orders.orders.size()).is_equal(before + 1)
	assert_int(GameSession.view.fleet_info(fleet.number)["waypoints"][1]["warp"]).is_equal(9)
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


func test_route_is_picked_on_the_map() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var map := screen._map
	map.size = Vector2(800, 600)
	map._fit()
	var home := GameSession.view.me().homeworld
	map.select("planet", home)
	var info := GameSession.view.planet_info(home)
	screen._command._pick_route(info)
	assert_bool(map.is_picking()).is_true()
	var target: Dictionary = GameSession.view.planets()[0]
	map._press(map.to_screen(target["x"], target["y"]))
	assert_bool(map.is_picking()).is_false()
	assert_int(GameSession.view.planet_info(home)["route"]).is_equal(target["id"])
	screen.queue_free()
	await get_tree().process_frame


func test_production_window_applies_on_ok() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var home := GameSession.view.me().homeworld
	var dialog := screen._command._production
	dialog.open(home)
	var before := GameSession.orders.orders.size()
	dialog._inventory.select(0)
	dialog._on_add()
	dialog._on_add()
	assert_int(dialog._items.size()).is_equal(1)
	assert_int(GameSession.orders.orders.size()).is_equal(before)
	dialog._on_cancel_like()
	assert_int(GameSession.view.planet_info(home)["queue"].size()).is_equal(0)
	dialog.open(home)
	dialog._inventory.select(0)
	dialog._on_add()
	assert_bool(dialog._commit()).is_true()
	assert_int(GameSession.view.planet_info(home)["queue"].size()).is_equal(1)
	dialog.hide()
	screen.queue_free()
	await get_tree().process_frame


func test_research_window_sends_the_field() -> void:
	_new_game()
	var dialog := ResearchDialog.new()
	add_child(dialog)
	dialog.open()
	dialog._fields[3].button_pressed = true
	assert_int(GameSession.view.research_info()["field"]).is_equal(3)
	assert_str(dialog._title.text).contains(GameSession.view.research_info()["fields"][3]["name"])
	dialog.queue_free()
	await get_tree().process_frame


func test_new_game_window_starts_a_game() -> void:
	var dialog := NewGameDialog.new()
	add_child(dialog)
	var chosen: Array = []
	dialog.game_chosen.connect(func(o: NewGame.Options) -> void: chosen.append(o))
	(dialog._size_group.get_buttons()[0] as CheckBox).button_pressed = true
	dialog._flags[1].button_pressed = true
	dialog._on_ok()
	assert_int(chosen.size()).is_equal(1)
	var options: NewGame.Options = chosen[0]
	assert_int(options.size).is_equal(0)
	assert_array(options.flags).contains(["slow_tech"])
	GameSession.new_game(options)
	assert_bool(GameSession.state.settings.slow_tech).is_true()
	dialog.queue_free()
	await get_tree().process_frame


func test_scanner_views_and_status_bar() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var map := screen._map
	map.size = Vector2(800, 600)
	map._fit()
	for v in GalaxyMap.View.values():
		map.set_view(v)
		map.queue_redraw()
		await get_tree().process_frame
	var home := GameSession.view.planet_info(GameSession.view.me().homeworld)
	screen._on_hovered(home["x"], home["y"], {"kind": "planet", "id": home["id"]})
	assert_str(screen._status._name.text).is_equal(home["name"])
	assert_str(screen._status._distance.text).contains("light years from")
	screen.queue_free()
	await get_tree().process_frame


func test_cargo_window_moves_cargo() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var home := GameSession.view.me().homeworld
	var hauler := -1
	var most := 0
	for f in GameSession.view.fleets():
		var info := GameSession.view.fleet_info(f.number)
		if info["cargo_capacity"] > most and info["planet"] == home:
			hauler = f.number
			most = info["cargo_capacity"]
	assert_int(hauler).is_greater_equal(0)
	var dialog := screen._command._cargo
	dialog.open_with_planet(hauler, home)
	var surface: int = GameSession.view.planet_info(home)["surface"][0]
	dialog.move(Fleet.CARGO_IRONIUM, 50)
	dialog.move(Fleet.CARGO_FUEL, 10)
	# a planet takes no fuel
	assert_int(dialog._fleet[Fleet.CARGO_FUEL]).is_equal(dialog._start[Fleet.CARGO_FUEL])
	dialog.move(Fleet.CARGO_BORANIUM, 1 << 20)
	var capacity: int = GameSession.view.fleet_info(hauler)["cargo_capacity"]
	assert_int(dialog._fleet[0] + dialog._fleet[1]).is_equal(capacity)
	dialog._on_ok()
	var after := GameSession.view.fleet_info(hauler)
	assert_int(after["cargo"][0]).is_equal(50)
	assert_int(after["cargo"][1]).is_equal(capacity - 50)
	assert_int(GameSession.view.planet_info(home)["surface"][0]).is_equal(surface - 50)
	screen.queue_free()
	await get_tree().process_frame


func test_clicking_the_cargo_gauge_opens_the_transfer_window() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var fleet := GameSession.view.fleets()[0]
	screen._map.select("fleet", fleet.number)
	var pane := screen._command
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	pane._on_cargo_gauge_input(click, GameSession.view.fleet_info(fleet.number))
	assert_bool(pane._cargo.visible).is_true()
	assert_int(pane._cargo.fleet_number).is_equal(fleet.number)
	assert_bool(pane._cargo.other.has("planet")).is_true()
	pane._cargo.hide()
	screen.queue_free()
	await get_tree().process_frame


func test_messages_pane_shows_the_turn_messages() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var pane := screen._messages
	assert_int(pane.messages().size()).is_equal(5)
	assert_str(pane._text.text).contains("Tip")
	screen._on_end_turn()
	var texts := pane.messages().map(func(m: Dictionary) -> String: return m["text"])
	assert_bool(texts.is_empty()).is_false()
	assert_bool(texts.any(func(t: String) -> bool: return t.contains("{"))).is_false()
	screen.queue_free()
	await get_tree().process_frame


func test_message_filters_hide_a_type_until_shown() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var pane := screen._messages
	var count := pane.messages().size()
	var type: String = pane.messages()[0]["type"]
	assert_int(pane.current).is_equal(0)
	assert_bool(pane._glass.visible).is_false()
	pane._toggle_filter()
	assert_array(pane.filters()).contains([type])
	assert_int(pane.current).is_equal(0)
	assert_str(pane._text.text).is_equal(MessagesPane.FILTERED_TEXT)
	assert_bool(pane._goto.disabled).is_true()
	assert_bool(pane._glass.visible).is_true()
	pane._step(1)
	assert_int(pane.current).is_equal(1)
	assert_bool(pane._prev.disabled).is_true()
	pane.new_year()
	assert_int(pane.current).is_equal(1)
	pane.toggle_show_all()
	assert_int(pane.current).is_equal(0)
	assert_bool(pane._prev.disabled).is_true()
	assert_str(pane._text.text).is_not_equal(MessagesPane.FILTERED_TEXT)
	pane.toggle_show_all()
	assert_int(pane.current).is_equal(1)
	pane.current = 0
	pane.show_all = true
	pane._toggle_filter()
	assert_array(pane.filters()).is_empty()
	assert_bool(pane._glass.visible).is_false()
	assert_int(pane.messages().size()).is_equal(count)
	screen.queue_free()
	await get_tree().process_frame


func test_summary_fleet_popups_show_while_held() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var fleet := GameSession.view.fleets()[0]
	screen._map.select("fleet", fleet.number)
	var summary := screen._summary
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var press := InputEventMouseButton.new()
		press.button_index = button
		press.pressed = true
		summary._on_icon_input(press)
		assert_bool(summary._popup.visible).is_true()
		assert_int(summary._popup.get_child_count()).is_greater(0)
		var release := InputEventMouseButton.new()
		release.button_index = button
		release.pressed = false
		summary._on_icon_input(release)
		assert_bool(summary._popup.visible).is_false()
	screen.queue_free()
	await get_tree().process_frame
