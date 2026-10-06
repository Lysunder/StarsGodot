extends GdUnitTestSuite
## M11 UI support: NewGame, OrderPreview and PlayerView.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _new_game() -> GameState:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 77
	options.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
	return NewGame.create(_content, options)


func test_new_game_has_one_player_with_a_homeworld() -> void:
	var s := _new_game()
	assert_int(s.players.size()).is_equal(1)
	var home := s.player(0).homeworld
	assert_int(home).is_greater_equal(0)
	assert_int(s.planet(home).owner).is_equal(0)
	assert_bool(s.fleets.is_empty()).is_false()
	assert_str(s.settings.ruleset_hash).is_not_empty()
	assert_array(Array(StateValidator.validate(s, _content))).is_empty()


func test_view_of_the_homeworld_and_fleets() -> void:
	var s := _new_game()
	var view := PlayerView.new(s, _content, 0)
	var home := view.planet_info(s.player(0).homeworld)
	assert_bool(home["mine"]).is_true()
	assert_int(home["population"]).is_greater(0)
	assert_int(home["resources"]).is_greater(0)
	assert_bool(view.production_inventory(home["id"]).is_empty()).is_false()
	var fleet := view.fleet_info(view.fleets()[0].number)
	assert_str(fleet["name"]).is_not_empty()
	assert_int(fleet["waypoints"].size()).is_greater(0)
	var picked := view.objects_at(home["x"], home["y"])
	assert_str(picked[0]["kind"]).is_equal("planet")
	assert_int(view.research_info()["fields"].size()).is_equal(6)


func test_preview_applies_orders_without_touching_the_state() -> void:
	var s := _new_game()
	var orders := OrderSet.new(0, s.turn)
	orders.add({"type": "research", "percent": 40, "field": 2, "next": 7})
	orders.add({"type": "research", "percent": 400, "field": 2, "next": 7})
	var preview := OrderPreview.build(s, _content, orders)
	assert_int(preview.state.player(0).research_percent).is_equal(40)
	assert_int(s.player(0).research_percent).is_not_equal(40)
	assert_int(preview.rejected.size()).is_equal(1)


func test_turn_save_and_load() -> void:
	var s := _new_game()
	var orders := OrderSet.new(0, s.turn)
	orders.add({"type": "research", "percent": 30, "field": 0, "next": 7})
	var sets: Array[OrderSet] = [orders]
	assert_array(Array(StandardTurn.generate(s, _content, sets))).is_empty()
	assert_int(s.turn).is_equal(1)
	var text := SaveFile.encode(s, "0.1.0")
	var loaded := SaveFile.decode(text, _content)
	assert_bool(loaded.ok()).override_failure_message("\n".join(loaded.errors)).is_true()
	assert_bool(loaded.state.equals(s)).is_true()


func test_design_range_matches_a_fleet_of_one_ship() -> void:
	var s := _new_game()
	var view := PlayerView.new(s, _content, 0)
	var me := s.player(0)
	for d in me.ship_designs:
		if not PartRules.engine(d, _content)[1]:
			continue
		var fleet := Fleet.new()
		var stack := ShipStack.new()
		stack.design = d.slot
		stack.count = 1
		fleet.stacks.append(stack)
		fleet.cargo[Fleet.CARGO_FUEL] = PartRules.fuel_capacity(d, _content)
		for warp in range(1, 11):
			(
				assert_int(Movement.design_range(d, me, warp, _content))
				. override_failure_message("%s warp %d" % [d.name, warp])
				. is_equal(Movement.fuel_range(fleet, me, warp, _content))
			)
		var stats := view.designer.design_stats(d, false)
		assert_str(stats["problem"]).is_empty()
		assert_int(stats["ranges"].size()).is_equal(10)


func test_designer_lists() -> void:
	var s := _new_game()
	var view := PlayerView.new(s, _content, 0)
	var hulls := view.designer.available_hulls(false)
	assert_bool(hulls.is_empty()).is_false()
	assert_bool(view.designer.available_hulls(true).is_empty()).is_false()
	var blank := view.designer.blank_design(hulls[0])
	assert_int(blank.parts.size()).is_equal((_content.hull(hulls[0])["slots"] as Array).size())
	assert_str(view.designer.design_stats(blank, false)["problem"]).is_equal(
		"the design needs a name"
	)
	assert_bool(view.designer.available_parts(["engine"]).is_empty()).is_false()
	assert_int(view.designer.free_design_slot(false)).is_greater_equal(0)


func test_production_estimate() -> void:
	var s := _new_game()
	var home := s.planet(s.player(0).homeworld)
	home.queue.clear()
	home.queue.append(QueueItem.new("production_item.factories", 2))
	home.queue.append(QueueItem.new("production_item.factories", 20))
	home.queue.append(QueueItem.new("production_item.auto_mines", 5))
	var before := s.copy() as GameState
	var e := ProductionEstimate.estimate(s, _content, home.id)
	assert_bool(s.equals(before)).is_true()
	var when: Array = e["items"]
	assert_int(when.size()).is_equal(3)
	assert_int(when[0]).is_equal(ProductionEstimate.When.THIS_YEAR_ALL)
	assert_int(when[1]).is_not_equal(ProductionEstimate.When.THIS_YEAR_ALL)
	assert_int(e["years"]).is_greater(1)
	home.queue.clear()
	assert_int(ProductionEstimate.estimate(s, _content, home.id)["years"]).is_equal(0)
