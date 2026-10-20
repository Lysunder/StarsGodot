extends GdUnitTestSuite
## Map objects as waypoint targets (issues #13, #15) and as what a message's Goto shows (issue #14),
## on a game where a player sees the Mystery Trader and a wormhole.

const GAME := "res://tests/fixtures/golden/cyber1/t072.json"
## The player who sees them.
const PLAYER := 4


func _screen() -> GameScreen:
	GameSession._start(
		SaveFile.decode(FileAccess.get_file_as_string(GAME), GameSession.content).state
	)
	GameSession.player = PLAYER
	GameSession.orders = GameSession._orders_of(PLAYER)
	GameSession._refresh()
	var screen := GameScreen.new()
	add_child(screen)
	return screen


## The map at a size of its own (a headless run's window is tiny), fitted.
func _size_map(screen: GameScreen) -> void:
	screen._map.size = Vector2(800, 600)
	screen._map._fit()


## A waypoint added on object `o` of `kind`: it targets the object and is named after it.
func _waypoint_on(screen: GameScreen, kind: String, o: Variant) -> void:
	var map := screen._map
	var fleet := GameSession.view.fleets()[0]
	map.select("fleet", fleet.number)
	map.set_waypoint(-1)
	var at := map.to_screen(o.x, o.y)
	var target := map._target_at(at)
	assert_str(target["target"]).is_equal(kind)
	assert_int(target["target_id"]).is_equal(o.number)
	map._add_waypoint(at)
	var waypoints: Array = GameSession.view.fleet_info(fleet.number)["waypoints"]
	var last: Dictionary = waypoints[waypoints.size() - 1]
	assert_str(last["target"]).is_equal(kind)
	assert_str(last["label"]).is_equal(MapObjects.object_name(GameSession.view, kind, o))


func test_wormholes_and_the_trader_are_waypoint_targets() -> void:
	var screen := _screen()
	await get_tree().process_frame
	_size_map(screen)
	var wormholes := MapObjects.wormholes(GameSession.view)
	var traders := MapObjects.traders(GameSession.view)
	assert_bool(wormholes.is_empty()).is_false()
	assert_bool(traders.is_empty()).is_false()
	_waypoint_on(screen, "wormhole", wormholes[0])
	_waypoint_on(screen, "trader", traders[0])
	screen.queue_free()
	await get_tree().process_frame


func test_goto_shows_the_trader_and_other_objects() -> void:
	var screen := _screen()
	await get_tree().process_frame
	_size_map(screen)
	var map := screen._map
	var trader: Trader = MapObjects.traders(GameSession.view)[0]
	# zoomed in elsewhere: the Goto selects the trader and scrolls the scanner to it
	map.zoom_by(8.0)
	map.offset += Vector2(5000, 5000)
	screen._on_message_goto({"trader": trader.number})
	assert_str(map.selection_kind).is_equal("trader")
	assert_int(map.selection_id).is_equal(trader.number)
	(
		assert_bool(Rect2(Vector2.ZERO, map.size).has_point(map.to_screen(trader.x, trader.y)))
		. is_true()
	)
	var wormhole: Wormhole = MapObjects.wormholes(GameSession.view)[0]
	screen._on_message_goto({"wormhole": wormhole.number})
	assert_str(map.selection_kind).is_equal("wormhole")
	# another player's fleet, while it is seen
	for f in MapObjects.seen_fleets(GameSession.view):
		screen._on_message_goto({"fleet": f.number, "owner": f.owner})
		assert_str(map.selection_kind).is_equal("seen_fleet")
		assert_int(map.selection_id).is_equal(MapObjects.fleet_key(f))
		break
	screen.queue_free()
	await get_tree().process_frame
