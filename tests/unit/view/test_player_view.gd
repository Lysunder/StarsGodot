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
