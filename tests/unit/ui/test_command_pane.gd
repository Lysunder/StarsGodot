extends GdUnitTestSuite
## The Command pane: tiles in two columns that keep where the player puts them (issue #11), Delete
## in the Fleet Waypoints list (issue #9), the Starbase tile's design popup (issue #10).

## The tile layout goes to a file of its own, so the player's never matters.
const TILE_SETTINGS := "user://test_tile_settings.cfg"


func before() -> void:
	TileLayout.path = TILE_SETTINGS
	DirAccess.remove_absolute(TILE_SETTINGS)


func after() -> void:
	DirAccess.remove_absolute(TILE_SETTINGS)
	TileLayout.path = UiSettings.PATH


func _new_game() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 99
	options.race = RacePresets.make(GameSession.content, RacePresets.ids(GameSession.content)[0])
	GameSession.new_game(options)


func test_delete_key_removes_the_selected_waypoint() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var map := screen._map
	var fleet := GameSession.view.fleets()[0]
	map.size = Vector2(800, 600)
	map._fit()
	map.select("fleet", fleet.number)
	var planets := GameSession.view.planets()
	for pl: Dictionary in [planets[0], planets[planets.size() - 1]]:
		map._add_waypoint(map.to_screen(pl["x"], pl["y"]))
	await get_tree().process_frame
	var count := func() -> int: return GameSession.view.fleet_info(fleet.number)["waypoints"].size()
	assert_int(count.call()).is_equal(3)
	# clicking a row rebuilds the pane (issue #9): the new list keeps the focus for Delete
	var pane := screen._command
	pane._waypoint_list.focus_rows()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(4, pane._waypoint_list.row_height() + 2)
	pane._waypoint_list.rows_input(click)
	await get_tree().process_frame
	assert_bool(pane._waypoint_list.rows_have_focus()).is_true()
	var delete := InputEventKey.new()
	delete.keycode = KEY_DELETE
	delete.pressed = true
	pane._waypoint_list.rows_input(delete)
	await get_tree().process_frame
	assert_int(count.call()).is_equal(2)
	assert_bool(pane._waypoint_list.rows_have_focus()).is_true()
	screen.queue_free()
	await get_tree().process_frame


func test_tiles_keep_their_columns_order_and_collapse() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var pane := screen._command
	pane.command("planet", GameSession.view.me().homeworld)
	# the tiles column by column, as shown (the columns being freed left out)
	var tiles := func() -> Array:
		var out := []
		for columns in pane._tiles.get_children():
			if columns is HBoxContainer and not columns.is_queued_for_deletion():
				for column in columns.get_children():
					out.append(
						column.get_children().filter(func(n: Node) -> bool: return n is Tile)
					)
		return out
	var shown := func() -> Array:
		return tiles.call().map(
			func(c: Array) -> Array: return c.map(func(t: Tile) -> String: return t.key)
		)
	# the original's default: two columns
	assert_array(shown.call()).is_equal(TileLayout.DEFAULTS["planet"])
	# Status dropped on the Planet tile goes above it; Production below the first column's tiles
	var planet_tile: Tile = tiles.call()[0][0]
	planet_tile._drop_data(Vector2.ZERO, {"tile": "Status"})
	var first_end: Control = planet_tile.get_parent().get_child(-1)
	assert_bool(first_end._can_drop_data(Vector2.ZERO, {"tile": "Production"})).is_true()
	first_end._drop_data(Vector2.ZERO, {"tile": "Production"})
	TileLayout.set_collapsed("Minerals on Hand", true)
	pane._rebuild()
	var later: Array = shown.call()
	assert_array(later[0]).is_equal(["Status", "planet", "Minerals on Hand", "Production"])
	assert_array(later[1]).is_equal(["Fleets in Orbit", "starbase"])
	for column: Array in tiles.call():
		for t: Tile in column:
			assert_bool(t.collapsed).is_equal(t.key == "Minerals on Hand")
	# the layout lasts: it is in the settings file
	assert_array(TileLayout.columns("planet")).is_equal(later)
	assert_array(TileLayout.columns("fleet")).is_equal(TileLayout.DEFAULTS["fleet"])
	assert_str(CommandPane.thousands(1234567)).is_equal("1,234,567")
	screen.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(TILE_SETTINGS)


## Real mouse input: press on `from`, move in steps to `to`, let go there.
func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	get_viewport().push_input(press)
	await get_tree().process_frame
	for i in range(1, 9):
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = from.lerp(to, i / 8.0)
		motion.global_position = motion.position
		motion.relative = (to - from) / 8.0
		get_viewport().push_input(motion)
		await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	release.global_position = to
	get_viewport().push_input(release)
	await get_tree().process_frame
	await get_tree().process_frame


func test_tiles_move_when_dragged_by_the_mouse() -> void:
	# a headless run's window is tiny: make room for the screen
	var window_size := get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var pane := screen._command
	pane.command("fleet", GameSession.view.fleets()[0].number)
	await get_tree().process_frame
	await get_tree().process_frame
	var tile := func(key: String) -> Tile:
		for t: Tile in pane._tiles.find_children("*", "Tile", true, false):
			if t.key == key:
				return t
		return null
	var bar_of := func(t: Tile) -> Vector2: return t.get_child(0).get_global_rect().get_center()
	# the Waypoint Task tile's title bar onto the middle of the Fuel & Cargo tile (over its gauges)
	var task: Tile = tile.call("Waypoint Task")
	var cargo: Tile = tile.call("Fuel & Cargo")
	await _drag(bar_of.call(task), cargo.get_global_rect().get_center())
	assert_array(TileLayout.columns("fleet")[0]).is_equal(
		["fleet", "location", "Waypoint Task", "Fuel & Cargo", "Fleet Composition"]
	)
	# and below the second column's tiles, to its bottom
	task = tile.call("Waypoint Task")
	var others: Tile = tile.call("Other Fleets Here")
	var below := others.get_global_rect().end + Vector2(-20, 12)
	await _drag(bar_of.call(task), below)
	assert_array(TileLayout.columns("fleet")[1]).is_equal(
		["Fleet Waypoints", "Other Fleets Here", "Waypoint Task"]
	)
	# a drag let go over the map moves nothing, and the tiles' buttons take clicks again
	var earlier := TileLayout.columns("fleet")
	await _drag(bar_of.call(tile.call("Fuel & Cargo")), screen._map.get_global_rect().get_center())
	assert_array(TileLayout.columns("fleet")).is_equal(earlier)
	for b: Button in pane._tiles.find_children("*", "Button", true, false):
		assert_int(b.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	screen.queue_free()
	await get_tree().process_frame
	get_tree().root.size = window_size
	DirAccess.remove_absolute(TILE_SETTINGS)


func test_starbase_tile_shows_the_design_while_held() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var pane := screen._command
	pane.command("planet", GameSession.view.me().homeworld)
	var tile: Tile = null
	for t: Tile in pane._tiles.find_children("*", "Tile", true, false):
		if t.key == "starbase" and not t.is_queued_for_deletion():
			tile = t
	assert_object(tile).is_not_null()
	var frame := tile.body.get_parent() as Control
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	frame.gui_input.emit(press)
	assert_bool(pane._popup.visible).is_true()
	var base := GameSession.view.state.planet(GameSession.view.me().homeworld).starbase
	var design := GameSession.view.me().starbase_design(base.design).name
	var labels := pane._popup.find_children("*", "Label", true, false)
	assert_bool(labels.any(func(l: Label) -> bool: return l.text.begins_with(design))).is_true()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	frame.gui_input.emit(release)
	assert_bool(pane._popup.visible).is_false()
	screen.queue_free()
	await get_tree().process_frame


## The Waypoint Task tile's OptionButtons after the task one, and its warp gauges.
func _task_controls(pane: CommandPane) -> Dictionary:
	for t: Tile in pane._tiles.find_children("*", "Tile", true, false):
		if t.key == "Waypoint Task" and t.is_inside_tree():
			return {
				"lists": t.find_children("*", "OptionButton", true, false).slice(1),
				"gauges": t.find_children("*", "WarpGauge", true, false),
			}
	return {}


func test_lay_mines_and_patrol_tasks_have_their_settings() -> void:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var map := screen._map
	var fleet := GameSession.view.fleets()[0]
	map.size = Vector2(800, 600)
	map._fit()
	map.select("fleet", fleet.number)
	var target: Dictionary = GameSession.view.planets()[0]
	map._add_waypoint(map.to_screen(target["x"], target["y"]))
	await get_tree().process_frame
	var pane := screen._command
	var wp := func() -> Dictionary: return GameSession.view.fleet_info(fleet.number)["waypoints"][1]
	# lay mines: for 1 to 5 years or indefinitely (word 0: 0 to 5)
	pane._change_waypoint(wp.call(), wp.call()["warp"], "lay_mines", {"raw": [0, 0, 0, 0, 0]})
	await get_tree().process_frame
	var lists: Array = _task_controls(pane)["lists"]
	assert_int(lists.size()).is_equal(1)
	var years: OptionButton = lists[0]
	assert_int(years.item_count).is_equal(6)
	years.item_selected.emit(5)
	await get_tree().process_frame
	assert_int(wp.call()["task_data"]["raw"][0]).is_equal(5)
	# patrol: 50 to 550 ly or any enemy (word 1), and the intercept speed (word 0)
	pane._change_waypoint(wp.call(), wp.call()["warp"], "patrol", {"raw": [0, 0, 0, 0, 0]})
	await get_tree().process_frame
	var controls := _task_controls(pane)
	var reach: OptionButton = controls["lists"][0]
	assert_int(reach.item_count).is_equal(Retargeting.ANY_ENEMY + 1)
	reach.item_selected.emit(Retargeting.ANY_ENEMY)
	await get_tree().process_frame
	var speed: WarpGauge = _task_controls(pane)["gauges"].back()
	assert_str(speed.zero_text).is_equal("Automatic")
	speed.value_set.emit(6)
	await get_tree().process_frame
	var raw: Array = wp.call()["task_data"]["raw"]
	assert_int(raw[0]).is_equal(6)
	assert_int(raw[1]).is_equal(Retargeting.ANY_ENEMY)
	screen.queue_free()
	await get_tree().process_frame
