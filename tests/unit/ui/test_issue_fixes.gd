extends GdUnitTestSuite
## Fixes for GitHub issues #1-#6 (through GameSession, the autoload, and the game screen).


func _new_game() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 21
	GameSession.new_game(options)


## #1 shortcut keys in the menu item's colour; #4 readable tooltips.
func test_menu_shortcuts_and_tooltips() -> void:
	var t := ClassicTheme.build()
	assert_bool(t.get_color("font_accelerator_color", "PopupMenu") == ClassicTheme.TEXT).is_true()
	var tip := t.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	assert_object(tip).is_not_null()
	assert_bool(tip.bg_color == ClassicTheme.TOOLTIP).is_true()
	assert_bool(t.get_color("font_color", "TooltipLabel") == ClassicTheme.TEXT).is_true()


## #3 the map keeps its zoom and centre when its size changes (a waypoint added grows a pane).
func test_the_map_keeps_its_zoom_when_resized() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var map := screen._map
	map.size = Vector2(800, 600)
	map._fit()
	map.zoom_by(2.0)
	var zoom := map.zoom
	var centre := map.to_universe(map.size / 2.0)
	map.size = Vector2(800, 500)
	await get_tree().process_frame
	assert_float(map.zoom).is_equal(zoom)
	assert_vector(map.to_universe(map.size / 2.0)).is_equal_approx(centre, Vector2(0.01, 0.01))
	screen.queue_free()
	await get_tree().process_frame


## #5 no Terraform Environment where terraforming can change nothing.
func test_terraforming_is_offered_only_where_it_does_something() -> void:
	_new_game()
	var home := GameSession.view.me().homeworld
	var items := GameSession.view.production_inventory(home).map(
		func(i: Dictionary) -> String: return i["item"]
	)
	# a new homeworld is as good as no terraforming tech can make it
	assert_bool(items.has("production_item.terraform")).is_false()
	assert_bool(items.has("production_item.auto_max_terraform")).is_true()
	# with terraforming tech and an environment off the ideal it is offered
	var pl := GameSession.state.planet(home)
	var me := GameSession.state.player(GameSession.player)
	me.tech_levels.assign([15, 15, 15, 15, 15, 15])
	var ideal: int = me.race.hab_center[0] if me.race.hab_center[0] >= 0 else 50
	pl.environment[0] = clampi(ideal + 20, 0, 100)
	pl.environment_original[0] = pl.environment[0]
	GameSession._refresh()
	items = GameSession.view.production_inventory(home).map(
		func(i: Dictionary) -> String: return i["item"]
	)
	if not me.race.is_immune(0):
		assert_bool(items.has("production_item.terraform")).is_true()


## #6 the transport task's quick options set every cargo type at once.
func test_quick_transport_options() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var fleet := GameSession.view.fleets()[0]
	var info := GameSession.view.fleet_info(fleet.number)
	screen._command.command("fleet", fleet.number)
	screen._command._waypoint = 0
	var first: Dictionary = info["waypoints"][0]
	first["task"] = "transport"
	screen._command._quick_cargo(first, 1)  # Quick Drop
	var cargo: Array = (
		GameSession.view.fleet_info(fleet.number)["waypoints"][0]["task_data"]["cargo"]
	)
	for c in 4:
		assert_str(cargo[c]["action"]).is_equal("unload_all")
	assert_str(cargo[4]["action"]).is_equal("none")
	first = GameSession.view.fleet_info(fleet.number)["waypoints"][0]
	screen._command._quick_cargo(first, 2)  # Wait Load
	cargo = GameSession.view.fleet_info(fleet.number)["waypoints"][0]["task_data"]["cargo"]
	assert_str(cargo[0]["action"]).is_equal("wait_percent")
	assert_int(cargo[0]["amount"]).is_equal(100)
	# the colonists keep their action
	assert_str(cargo[3]["action"]).is_equal("unload_all")
	screen.queue_free()
	await get_tree().process_frame


## #2 the scanner coverage overlay: a toolbar toggle, drawn under the map.
func test_scanner_coverage_overlay() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var scan_buttons := screen.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.text == "Scan"
	)
	assert_int(scan_buttons.size()).is_equal(1)
	(scan_buttons[0] as Button).button_pressed = true
	assert_bool(screen._map.show_scanners).is_true()
	screen._map.queue_redraw()
	await get_tree().process_frame
	screen.queue_free()
	await get_tree().process_frame


## #7 other players' fleets seen on the map can be picked: clicked, in the right-click menu, in
## the summary pane (owner, ships, mass), and as a waypoint target; they are never commanded.
func test_rival_fleets_can_be_selected() -> void:
	var path := "res://tests/fixtures/golden/mine1/t040.json"
	GameSession._start(
		SaveFile.decode(FileAccess.get_file_as_string(path), GameSession.content).state
	)
	var view := GameSession.view
	var seen := MapObjects.seen_fleets(view)
	assert_bool(seen.is_empty()).is_false()
	var rival: Fleet = seen[0]
	var key := MapObjects.fleet_key(rival)
	var hits := view.objects_at(rival.x, rival.y, 1.0)
	assert_bool(hits.has({"kind": "seen_fleet", "id": key})).is_true()
	var menu := view.objects_here(rival.x, rival.y, 1.0).map(
		func(o: Dictionary) -> int: return o["id"] if o["kind"] == "seen_fleet" else -1
	)
	assert_bool(menu.has(key)).is_true()
	var info := MapObjects.seen_fleet_info(view, key)
	assert_int(info["owner"]).is_equal(rival.owner)
	assert_int((info["ships"] as Array).size()).is_equal(rival.stacks.size())
	# a fleet the player doesn't see isn't offered
	for f in view.state.fleets:
		if f.owner != view.player and not seen.has(f):
			assert_object(MapObjects.seen_fleet(view, MapObjects.fleet_key(f))).is_null()
			break
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen._map.select("seen_fleet", key)
	assert_str(screen._summary._title.text).is_equal("%s Summary" % info["name"])
	assert_bool(screen._summary._fleet_box.visible).is_true()
	var ships := screen._summary._ships_view()
	assert_object(ships).is_not_null()
	ships.free()
	assert_str(screen._command.kind).is_not_equal("seen_fleet")
	screen._map.queue_redraw()
	await get_tree().process_frame
	# a rival fleet under the mouse is a fleet waypoint target with its owner
	var target := screen._map._target_at(screen._map.to_screen(rival.x, rival.y))
	if target["target"] == "fleet":
		assert_int(target["target_owner"]).is_equal(rival.owner)
	screen.queue_free()
	await get_tree().process_frame
