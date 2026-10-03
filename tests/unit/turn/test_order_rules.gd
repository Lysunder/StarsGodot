extends GdUnitTestSuite
## Spec S11 "Orders": validation and effect of each order type, and the order file format.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _state() -> GameState:
	var s := GameState.new()
	for i in 2:
		var p := Player.new()
		p.index = i
		s.players.append(p)
	for i in 3:
		var pl := Planet.new()
		pl.id = i
		pl.owner = 0 if i == 0 else -1
		s.planets.append(pl)
	return s


static func _item(key: String, count: int, progress := 0) -> Dictionary:
	return {
		"item": "production_item." + key,
		"design": -1,
		"starbase": false,
		"count": count,
		"progress": progress,
	}


func _apply(s: GameState, player: int, order: Dictionary) -> String:
	return OrderRules.apply(s, _content, player, order)


func test_queue_change_keeps_matching_progress_once() -> void:
	var s := _state()
	var pl := s.planets[0]
	var old := QueueItem.new("production_item.factories", 3)
	old.progress = 40
	pl.queue.append(old)
	var order := {
		"type": "production_queue",
		"planet": 0,
		"items": [_item("factories", 5, 40), _item("factories", 2, 40), _item("mines", 1, 10)],
	}
	assert_str(_apply(s, 0, order)).is_empty()
	var got := pl.queue.map(func(q: QueueItem) -> Array: return [q.item, q.count, q.progress])
	(
		assert_array(got)
		. is_equal(
			[
				["production_item.factories", 5, 40],
				["production_item.factories", 2, 0],
				["production_item.mines", 1, 0],
			]
		)
	)


func test_queue_change_is_checked() -> void:
	var s := _state()
	var change := func(player: int, planet: int, items: Array) -> String:
		return _apply(s, player, {"type": "production_queue", "planet": planet, "items": items})
	assert_str(change.call(1, 0, [])).is_equal("not the player's planet")
	assert_str(change.call(0, 1, [])).is_equal("not the player's planet")
	assert_str(change.call(0, 0, [_item("nothing", 1)])).is_equal("no such production item")
	assert_str(change.call(0, 0, [_item("mines", 2000)])).is_equal("bad queue item count")
	var design := _item("mines", 1)
	design["item"] = ""
	design["design"] = 3
	assert_str(change.call(0, 0, [design])).is_equal("no such design")
	assert_bool(s.planets[0].queue.is_empty()).is_true()
	assert_str(change.call(0, 0, [])).is_empty()


func test_research_change() -> void:
	var s := _state()
	assert_str(_apply(s, 1, {"type": "research", "percent": 30, "field": 2, "next": 7})).is_empty()
	var p := s.players[1]
	assert_array([p.research_percent, p.research_field, p.next_research_field]).is_equal([30, 2, 7])
	assert_str(_apply(s, 1, {"type": "research", "percent": 101, "field": 2, "next": 7})).is_equal(
		"research percent must be 0..100"
	)
	assert_str(_apply(s, 1, {"type": "research", "percent": 10, "field": 6, "next": 7})).is_equal(
		"bad research field"
	)


func test_planet_settings_keep_driver_only_with_a_starbase() -> void:
	var s := _state()
	var order := {
		"type": "planet_settings",
		"planet": 0,
		"leftover_to_research": true,
		"mass_driver_target": 2,
		"mass_driver_warp": 8,
		"route": 1,
	}
	assert_str(_apply(s, 0, order)).is_empty()
	var pl := s.planets[0]
	assert_array([pl.leftover_to_research, pl.route]).is_equal([true, 1])
	assert_array([pl.mass_driver_target, pl.mass_driver_warp]).is_equal([-1, 0])
	pl.starbase = Starbase.new()
	assert_str(_apply(s, 0, order)).is_empty()
	assert_array([pl.mass_driver_target, pl.mass_driver_warp]).is_equal([2, 8])
	order["route"] = 9
	assert_str(_apply(s, 0, order)).is_equal("no such planet")


func test_players_apply_in_order_and_rejections_are_reported() -> void:
	var s := _state()
	var later := OrderSet.new(1, 0)
	later.add({"type": "research", "percent": 50, "field": 0, "next": 6})
	later.add({"type": "teleport"})
	var first := OrderSet.new(0, 0)
	first.add({"type": "research", "percent": 20, "field": 1, "next": 6})
	var rejected := OrderRules.apply_all(s, _content, [later, first])
	assert_array(Array(rejected)).is_equal(["player 1 order 1: unknown order type teleport"])
	assert_array([s.players[0].research_percent, s.players[1].research_percent]).is_equal([20, 50])


func test_order_file_round_trip_and_checks() -> void:
	var order_set := OrderSet.new(1, 7)
	order_set.add({"type": "research", "percent": 20, "field": 1, "next": 6})
	var text := OrderFile.encode(order_set, "test")
	var loaded := OrderFile.decode(text)
	assert_bool(loaded.ok()).override_failure_message("\n".join(loaded.errors)).is_true()
	assert_array([loaded.order_set.player, loaded.order_set.turn]).is_equal([1, 7])
	assert_array(loaded.order_set.orders).is_equal(order_set.orders)
	assert_str(OrderFile.encode(loaded.order_set, "test")).is_equal(text)
	var data: Dictionary = JsonReader.parse(text).value
	data["orders"] = [{"percent": 3}]
	var bad := OrderFile.decode(ContentRegistry.canonical(data))
	assert_array(Array(bad.errors)).is_equal(['/orders/0: must be an object with a "type"'])
