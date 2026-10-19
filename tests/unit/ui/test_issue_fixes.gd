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
