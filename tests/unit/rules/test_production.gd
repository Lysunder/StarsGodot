extends GdUnitTestSuite
## Spec S09: production costs and the queue. Expectations are worked by hand from the spec.
## Humanoid race (JoaT); the test planet (environment 50/50/50, 250 units, 10 factories) makes
## 35 resources a year (S08 worked example).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _player(levels: Array = [0, 0, 0, 0, 0, 0]) -> Player:
	var p := Player.new()
	p.tech_levels.assign(levels)
	p.research_percent = 0
	return p


func _game(queue: Array, research_percent := 0) -> GameState:
	var s := GameState.new()
	var p := _player()
	p.research_percent = research_percent
	p.relations.assign(["neutral"])
	s.players.append(p)
	var pl := Planet.new()
	pl.owner = 0
	pl.population = 250
	pl.factories = 10
	pl.mines = 10
	pl.surface.assign([0, 0, 100])
	for q: QueueItem in queue:
		pl.queue.append(q)
	s.planets.append(pl)
	return s


func _item(key: String, count: int, progress := 0) -> QueueItem:
	var q := QueueItem.new("production_item." + key, count)
	q.progress = progress
	return q


func _run(s: GameState) -> Array[int]:
	var research: Array[int] = [0]
	Production.new(s, _content, StarsRandom.new()).run_planet(s.planets[0], research)
	return research


static func _queue(pl: Planet) -> Array:
	return pl.queue.map(func(q: QueueItem) -> Array: return [q.item, q.count, q.progress])


# --- Costs -------------------------------------------------------------------------------------


func test_miniaturization() -> void:
	var hump := _content.part("part.engine.long_hump_6")
	var p := _player([0, 0, 10, 0, 0, 0])
	assert_array(ProductionCosts.part_cost(hump, p, _content)).is_equal([4, 0, 1, 4])
	var jump := _content.part("part.engine.quick_jump_5")
	assert_array(ProductionCosts.part_cost(jump, _player([3, 3, 3, 3, 3, 3]), _content)).is_equal(
		[3, 0, 1, 3]
	)
	var at_ten := _player([10, 10, 10, 10, 10, 10])
	assert_array(ProductionCosts.part_cost(jump, at_ten, _content)).is_equal([2, 0, 1, 2])
	at_ten.race.lesser_traits.assign(["trait.lrt.CE"])
	assert_array(ProductionCosts.part_cost(jump, at_ten, _content)).is_equal([1, 0, 1, 1])


func test_bleeding_edge_doubles_at_the_tech_level() -> void:
	var p := _player([0, 0, 3, 0, 0, 0])
	p.race.lesser_traits.assign(["trait.lrt.BET"])
	var hump := _content.part("part.engine.long_hump_6")
	assert_array(ProductionCosts.part_cost(hump, p, _content)).is_equal([10, 0, 2, 12])


func test_weapon_prices_by_trait() -> void:
	var laser := _content.part("part.beam.laser")
	var p := _player()
	p.race.primary_trait = "trait.prt.WM"
	assert_array(ProductionCosts.part_cost(laser, p, _content)).is_equal([0, 5, 0, 4])
	p.race.primary_trait = "trait.prt.IS"
	assert_array(ProductionCosts.part_cost(laser, p, _content)).is_equal([0, 7, 0, 6])


func test_standard_item_costs() -> void:
	var s := _game([])
	var pl := s.planets[0]
	var p := s.players[0]
	var cost := func(key: String) -> Array[int]:
		return ProductionCosts.unit_cost(pl, _item(key, 1), p, _content)
	assert_array(cost.call("mines")).is_equal([0, 0, 0, 5])
	assert_array(cost.call("factories")).is_equal([0, 0, 4, 10])
	p.race.cheap_factories = true
	assert_array(cost.call("factories")).is_equal([0, 0, 3, 10])
	assert_array(cost.call("alchemy")).is_equal([0, 0, 0, 100])
	assert_array(cost.call("defenses")).is_equal([5, 5, 5, 15])
	p.race.primary_trait = "trait.prt.IS"
	assert_array(cost.call("defenses")).is_equal([3, 3, 3, 9])
	p.race.lesser_traits.assign(["trait.lrt.MA"])
	assert_array(cost.call("alchemy")).is_equal([0, 0, 0, 25])


func _design(slot: int, hull: String, parts: Array) -> Design:
	var d := Design.new()
	d.slot = slot
	d.hull = hull
	var count: int = _content.hull(hull)["slots"].size()
	for i in count:
		d.parts.append(
			DesignSlot.new(parts[i][0], parts[i][1]) if i < parts.size() else DesignSlot.new()
		)
	return d


func test_design_and_starbase_prices() -> void:
	var p := _player()
	var scout := _design(
		0, "hull.scout", [["part.engine.quick_jump_5", 1], ["part.scanner.bat_scanner", 1]]
	)
	assert_array(ProductionCosts.design_cost(scout, p, _content)).is_equal([8, 2, 6, 14])
	var fort := _design(0, "hull.orbital_fort", [])
	var station := _design(1, "hull.space_station", [])
	p.set_design(fort, true)
	p.set_design(station, true)
	var pl := Planet.new()
	pl.owner = 0
	var build := QueueItem.of_design(1, true, 1)
	assert_array(ProductionCosts.unit_cost(pl, build, p, _content)).is_equal([120, 80, 250, 600])
	pl.starbase = Starbase.new()
	pl.starbase.design = 0
	assert_array(ProductionCosts.unit_cost(pl, build, p, _content)).is_equal([114, 80, 242, 580])
	pl.starbase.design = 1
	assert_array(ProductionCosts.unit_cost(pl, build, p, _content)).is_equal([0, 0, 0, 0])


# --- The queue ---------------------------------------------------------------------------------


func test_empty_queue_puts_everything_into_research() -> void:
	assert_array(_run(_game([], 15))).is_equal([35])


func test_unfinished_item_stops_the_queue() -> void:
	var s := _game([_item("factories", 5), _item("mines", 1)], 15)
	var research := _run(s)
	var pl := s.planets[0]
	assert_int(pl.factories).is_equal(13)
	assert_int(pl.mines).is_equal(10)
	assert_array(_queue(pl)).is_equal(
		[["production_item.factories", 2, 9], ["production_item.mines", 1, 0]]
	)
	assert_array(pl.surface).is_equal([0, 0, 88])
	assert_array(research).is_equal([5])


func test_auto_item_builds_its_share_and_carries_progress() -> void:
	var s := _game([_item("auto_mines", 50)], 15)
	var research := _run(s)
	var pl := s.planets[0]
	# operable mines next year: 287 units -> 28; room 18; 30 resources buy 6
	assert_int(pl.mines).is_equal(16)
	assert_array(_queue(pl)).is_equal(
		[["production_item.mines", 1, 19], ["production_item.auto_mines", 50, 0]]
	)
	assert_array(research).is_equal([5])


func test_auto_item_short_of_minerals_lets_the_next_item_build() -> void:
	var s := _game([_item("auto_factories", 5), _item("mines", 2)], 15)
	s.planets[0].surface.assign([0, 0, 0])
	var research := _run(s)
	var pl := s.planets[0]
	assert_int(pl.factories).is_equal(10)
	assert_int(pl.mines).is_equal(12)
	assert_array(_queue(pl)).is_equal([["production_item.auto_factories", 5, 0]])
	assert_array(research).is_equal([25])


func test_alchemy_above_and_leftover_alchemy() -> void:
	var s := _game([_item("auto_alchemy", 1), _item("factories", 1)])
	s.planets[0].surface.assign([0, 0, 0])
	var research := _run(s)
	(
		assert_array(_queue(s.planets[0]))
		. is_equal(
			[
				["production_item.alchemy", 1, 33],
				["production_item.auto_alchemy", 1, 0],
				["production_item.factories", 1, 24],
			]
		)
	)
	assert_array(research).is_equal([0])


func test_only_leftover_to_research() -> void:
	var s := _game([_item("mines", 2)], 15)
	s.planets[0].leftover_to_research = true
	assert_array(_run(s)).is_equal([25])
	assert_bool(s.planets[0].queue.is_empty()).is_true()


func test_items_beyond_the_maximum_are_removed() -> void:
	var s := _game([_item("factories", 5)], 0)
	s.planets[0].factories = 1200
	assert_array(_run(s)).is_equal([PlanetEconomy.resources(s.planets[0], Race.new(), _content)])
	assert_bool(s.planets[0].queue.is_empty()).is_true()


func test_ships_need_a_starbase() -> void:
	var s := _game([QueueItem.of_design(0, false, 2)])
	var p := s.players[0]
	p.set_design(
		_design(
			0, "hull.scout", [["part.engine.quick_jump_5", 1], ["part.scanner.bat_scanner", 1]]
		),
		false
	)
	var pl := s.planets[0]
	pl.surface.assign([100, 100, 100])
	_run(s)
	assert_int(s.fleets.size()).is_equal(0)
	assert_bool(pl.queue.is_empty()).is_true()
	s = _game([QueueItem.of_design(0, false, 2)])
	p = s.players[0]
	var scout := _design(
		0, "hull.scout", [["part.engine.quick_jump_5", 1], ["part.scanner.bat_scanner", 1]]
	)
	p.set_design(scout, false)
	p.set_design(_design(0, "hull.orbital_fort", []), true)
	pl = s.planets[0]
	pl.surface.assign([100, 100, 100])
	pl.starbase = Starbase.new()
	var research := _run(s)
	assert_int(s.fleets.size()).is_equal(1)
	var fleet := s.fleets[0]
	assert_int(fleet.ship_count()).is_equal(2)
	assert_int(fleet.cargo[Fleet.CARGO_FUEL]).is_equal(2 * PartRules.fuel_capacity(scout, _content))
	assert_array([scout.built, scout.remaining]).is_equal([2, 2])
	assert_array(pl.surface).is_equal([84, 96, 88])
	assert_array(research).is_equal([7])


func test_starbase_is_built() -> void:
	var s := _game([QueueItem.of_design(0, true, 1)])
	var p := s.players[0]
	var fort := _design(0, "hull.orbital_fort", [])
	p.set_design(fort, true)
	var pl := s.planets[0]
	pl.population = 1000
	pl.factories = 0
	pl.surface.assign([100, 100, 100])
	var research := _run(s)
	assert_object(pl.starbase).is_not_null()
	assert_int(pl.starbase.design).is_equal(0)
	assert_int(fort.built).is_equal(1)
	assert_array(pl.surface).is_equal([88, 100, 83])
	assert_array(research).is_equal([60])


func test_genesis_device_draws_twelve_times() -> void:
	var s := _game([])
	var pl := s.planets[0]
	var rng := StarsRandom.new()
	var expected := rng.duplicate_stream()
	var production := Production.new(s, _content, rng)
	assert_bool(production._complete(pl, s.players[0], _item("genesis", 1), 1)).is_true()
	var draws: Array[int] = []
	for i in 12:
		draws.append(expected.random(50 if i % 4 < 2 else 40))
	assert_array(pl.environment).is_equal(
		[draws[0] + draws[1] + 1, draws[4] + draws[5] + 1, draws[8] + draws[9] + 1]
	)
	assert_array(pl.concentration).is_equal(
		[draws[2] + draws[3] + 25, draws[6] + draws[7] + 25, draws[10] + draws[11] + 25]
	)
	assert_array([pl.mines, pl.factories, pl.surface[2]]).is_equal([0, 0, 0])
