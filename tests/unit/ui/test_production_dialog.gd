extends GdUnitTestSuite
## The production window: no more factories, mines or defenses than the planet can use (issue
## #16), and the completion years follow the leftover box (issue #12).


func _new_game() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 99
	options.race = RacePresets.make(GameSession.content, RacePresets.ids(GameSession.content)[0])
	GameSession.new_game(options)


func _dialog() -> Array:
	_new_game()
	var screen := GameScreen.new()
	add_child(screen)
	return [screen, screen._command._production]


func _pick(dialog: ProductionDialog, item_id: String) -> void:
	for i in dialog._inventory_items.size():
		if dialog._inventory_items[i]["item"] == item_id:
			dialog._inventory.select(i)
			return
	assert_bool(false).override_failure_message("%s not offered" % item_id).is_true()


func test_adding_stops_at_what_the_planet_can_use() -> void:
	var made := _dialog()
	var screen: GameScreen = made[0]
	var dialog: ProductionDialog = made[1]
	await get_tree().process_frame
	var home := GameSession.view.me().homeworld
	var pl := GameSession.preview.state.planet(home)
	var me := GameSession.preview.state.player(pl.owner)
	pl.defenses = PlanetEconomy.max_defenses(pl, me.race, GameSession.content) - 2
	dialog.open(home)
	_pick(dialog, "production_item.defenses")
	for i in 3:
		dialog._on_add()
	assert_int(dialog._items.size()).is_equal(1)
	assert_int(dialog._items[0]["count"]).is_equal(2)
	assert_str(dialog._status.text).is_not_empty()
	# taking one off the queue makes room for one more
	dialog._queue.selected = 1
	dialog._on_remove()
	_pick(dialog, "production_item.defenses")
	dialog._queue.selected = 1
	dialog._on_add()
	assert_int(dialog._items[0]["count"]).is_equal(2)
	assert_str(dialog._status.text).is_empty()
	dialog.hide()
	screen.queue_free()
	await get_tree().process_frame


func test_the_leftover_box_changes_the_completion_years() -> void:
	var made := _dialog()
	var screen: GameScreen = made[0]
	var dialog: ProductionDialog = made[1]
	await get_tree().process_frame
	var home := GameSession.view.me().homeworld
	dialog.open(home)
	# alchemy costs resources only, so the resources kept from research shorten it
	dialog._items = [
		{"item": "production_item.alchemy", "design": -1, "starbase": false, "count": 60},
	]
	dialog._items[0]["progress"] = 0
	dialog._leftover.button_pressed = false
	dialog._show_queue()
	var sharing: int = dialog._estimate["last"][0]
	dialog._leftover.button_pressed = true
	var leftover_only: int = dialog._estimate["last"][0]
	assert_int(leftover_only).is_greater(0)
	assert_int(leftover_only).is_less(sharing)
	dialog._leftover.button_pressed = false
	assert_int(dialog._estimate["last"][0]).is_equal(sharing)
	dialog.hide()
	screen.queue_free()
	await get_tree().process_frame
