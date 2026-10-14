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
	# the first item is done this year; the second's first factory may come this year, its last later
	assert_int(e["first"][0]).is_equal(1)
	assert_int(e["last"][0]).is_equal(1)
	assert_int(e["first"][1]).is_between(1, e["last"][1])
	assert_int(e["last"][1]).is_equal(e["years"])
	assert_str(ProductionDialog.completion_text(e, 0, false)).is_equal("1 year")
	assert_array(["As needed", "Skipped"]).contains([ProductionDialog.completion_text(e, 2, true)])
	home.queue.clear()
	assert_int(ProductionEstimate.estimate(s, _content, home.id)["years"]).is_equal(0)


func test_completion_text() -> void:
	var e := {"items": [2, 2, 2, 3], "first": [3, 2, 4, 0], "last": [3, 5, 0, 0]}
	assert_str(ProductionDialog.completion_text(e, 0, false)).is_equal("3 years")
	assert_str(ProductionDialog.completion_text(e, 1, false)).is_equal("2 - 5 years")
	assert_str(ProductionDialog.completion_text(e, 2, false)).is_equal("4 - ? years")
	assert_str(ProductionDialog.completion_text(e, 3, false)).is_equal("Never")
	e["items"][0] = ProductionEstimate.When.SKIPPED
	assert_str(ProductionDialog.completion_text(e, 0, true)).is_equal("Skipped")


## The map's right-click menu: the homeworld, then the fleets the game starts with there.
func test_objects_here() -> void:
	var s := _new_game()
	var view := PlayerView.new(s, _content, 0)
	var home := s.planet(s.player(0).homeworld)
	var here := view.objects_here(home.x + 2, home.y + 1, 10.0)
	assert_str(here[0]["kind"]).is_equal("planet")
	assert_int(here[0]["id"]).is_equal(home.id)
	var orbiting := s.fleets_of(0).filter(
		func(f: Fleet) -> bool: return f.x == home.x and f.y == home.y
	)
	assert_int(here.size()).is_equal(1 + orbiting.size())
	for i in orbiting.size():
		assert_str(here[i + 1]["kind"]).is_equal("fleet")
		assert_int(here[i + 1]["id"]).is_equal(orbiting[i].number)
		assert_str(here[i + 1]["name"]).is_equal(view.fleet_name(orbiting[i]))
	assert_array(view.objects_here(-500, -500, 10.0)).is_empty()


## Other planets as the player last saw them (S15 "Planet history"): one planet scanned this turn,
## the others never seen.
func test_other_planets_come_from_the_players_records() -> void:
	var s := _new_game()
	var view := PlayerView.new(s, _content, 0)
	var others := s.planets.filter(func(pl: Planet) -> bool: return pl.owner != 0)
	var scanned: int = others[0].id
	var unseen: int = others[1].id
	s.views[0]["planets"][str(scanned)] = 3
	PlanetHistory.note(s, 0)
	var info := view.planet_info(scanned)
	assert_bool(info["known"]).is_true()
	assert_int(info["report_age"]).is_equal(0)
	assert_bool(info["population_estimated"]).is_true()
	assert_bool(info["surface_known"]).is_false()
	assert_array(info["environment"]).is_equal(Array(s.planet(scanned).environment))
	# a year later, without a new sighting, the report is a year old and keeps the old values
	s.turn += 1
	s.planet(scanned).environment[0] += 1
	info = view.planet_info(scanned)
	assert_int(info["report_age"]).is_equal(1)
	assert_int(info["environment"][0]).is_equal(s.planet(scanned).environment[0] - 1)
	var never := view.planet_info(unseen)
	assert_bool(never["known"]).is_false()
	assert_int(never["report_age"]).is_equal(-1)
	view.reveal_all = true
	assert_bool(view.planet_info(unseen)["known"]).is_true()
