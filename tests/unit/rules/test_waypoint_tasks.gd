extends GdUnitTestSuite
## Spec S11 waypoint tasks: merge with fleet, scrap and transfer fleet.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _game() -> GameState:
	var s := GameState.new()
	for i in 2:
		var p := Player.new()
		p.index = i
		p.relations.assign(["neutral", "neutral"])
		for slot in 2:
			var d := Design.new()
			d.slot = slot
			d.hull = "hull.colony_ship" if slot == 0 else "hull.scout"
			d.parts.assign([DesignSlot.new("part.engine.long_hump_6", 1)])
			d.remaining = 5
			d.built = 5
			p.set_design(d, false)
		s.players.append(p)
	var pl := Planet.new()
	pl.id = 0
	pl.x = 100
	pl.y = 100
	pl.owner = 0
	pl.population = 100
	s.planets.append(pl)
	return s


func _fleet(s: GameState, owner := 0, ships := 2, task := "none") -> Fleet:
	var f := s.add_fleet(owner, 512)
	f.x = 100
	f.y = 100
	f.planet = 0
	f.add_ships(0, ships)
	var wp := Waypoint.new(100, 100)
	wp.target = "planet"
	wp.target_id = 0
	wp.task = task
	f.waypoints.append(wp)
	return f


func _tasks(s: GameState) -> WaypointTasks:
	return WaypointTasks.new(s, _content, StarsRandom.new())


func _cost(s: GameState, player := 0, slot := 0) -> Array[int]:
	var p := s.player(player)
	return ProductionCosts.design_cost(p.ship_design(slot), p, _content)


func test_merge_task_moves_ships_into_the_target() -> void:
	var s := _game()
	var target := _fleet(s, 0, 1)
	var f := _fleet(s, 0, 2, "merge")
	f.waypoints[0].target = "fleet"
	f.waypoints[0].target_owner = 0
	f.waypoints[0].target_id = target.number
	f.cargo[Fleet.CARGO_FUEL] = 90
	_tasks(s).run_pass(1)
	assert_int(s.fleets.size()).is_equal(2)
	_tasks(s).run_pass(2)
	assert_int(s.fleets.size()).is_equal(1)
	assert_array([target.ship_count(), target.cargo[Fleet.CARGO_FUEL]]).is_equal([3, 90])


func test_merge_task_needs_the_same_owner_and_place() -> void:
	var s := _game()
	var other := _fleet(s, 1, 1)
	var f := _fleet(s, 0, 2, "merge")
	f.waypoints[0].target = "fleet"
	f.waypoints[0].target_owner = 1
	f.waypoints[0].target_id = other.number
	_tasks(s).run_pass(2)
	assert_int(s.fleets.size()).is_equal(2)
	var mine := _fleet(s, 0, 1)
	mine.x = 300
	f.waypoints[0].target_owner = 0
	f.waypoints[0].target_id = mine.number
	_tasks(s).run_pass(2)
	assert_int(s.fleets.size()).is_equal(3)


func test_scrap_at_a_planet_without_a_starbase() -> void:
	var s := _game()
	var f := _fleet(s, 0, 2, "scrap")
	f.cargo.assign([7, 0, 0, 20, 50])
	var cost := _cost(s)
	_tasks(s).run_pass(3)
	assert_int(s.fleets.size()).is_equal(1)
	_tasks(s).run_pass(1)
	var pl := s.planets[0]
	assert_int(s.fleets.size()).is_equal(0)
	assert_array(pl.surface).is_equal([2 * cost[0] / 3 + 7, 2 * cost[1] / 3, 2 * cost[2] / 3])
	assert_int(pl.population).is_equal(120)
	assert_int(s.players[0].ship_design(0).remaining).is_equal(3)


func test_scrap_at_a_starbase_and_transferred_designs() -> void:
	var s := _game()
	s.planets[0].starbase = Starbase.new()
	s.planets[0].owner = 1
	s.players[0].ship_design(0).transferred = true
	var f := _fleet(s, 0, 4, "scrap")
	f.cargo.assign([0, 0, 0, 20, 0])
	var cost := _cost(s)
	_tasks(s).run_pass(1)
	var pl := s.planets[0]
	var worth := 4 * cost[0] / 4
	assert_int(pl.surface[0]).is_equal(worth * 4 / 5)
	# colonists are lost on another player's planet
	assert_int(pl.population).is_equal(100)


func test_transfer_copies_designs_into_free_slots() -> void:
	var s := _game()
	var f := _fleet(s, 0, 2, "transfer")
	f.add_ships(1, 1)
	f.stacks[0].damaged_percent = 50
	f.stacks[0].damage = 30
	f.cargo.assign([5, 0, 0, 0, 80])
	f.waypoints[0].task_data = {"raw": [0, 0, 0, 0, 0]}
	_tasks(s).run_pass(2)
	assert_int(s.fleets_of(1).size()).is_equal(0)
	_tasks(s).run_pass(4)
	assert_int(s.fleets_of(0).size()).is_equal(0)
	var got := s.fleets_of(1)
	assert_int(got.size()).is_equal(1)
	var receiver := s.players[1]
	var copied := receiver.ship_design(2)
	assert_bool(copied.transferred).is_true()
	assert_str(copied.hull).is_equal("hull.colony_ship")
	assert_array([copied.built, copied.remaining]).is_equal([2, 2])
	assert_str(receiver.ship_design(3).hull).is_equal("hull.scout")
	assert_array([got[0].stacks[0].design, got[0].stacks[0].count]).is_equal([2, 2])
	assert_array([got[0].stacks[0].damaged_percent, got[0].stacks[0].damage]).is_equal([50, 30])
	assert_array(got[0].cargo).is_equal([5, 0, 0, 0, 80])
	assert_int(s.players[0].ship_design(0).remaining).is_equal(3)
	# the same design again goes into the same transferred slot
	var again := _fleet(s, 0, 1, "transfer")
	again.waypoints[0].task_data = {"raw": [0, 0, 0, 0, 0]}
	_tasks(s).run_pass(4)
	assert_array([receiver.ship_designs.size(), copied.remaining]).is_equal([4, 3])


func test_transfer_is_refused() -> void:
	var s := _game()
	var f := _fleet(s, 0, 1, "transfer")
	f.waypoints[0].task_data = {"raw": [0, 0, 0, 0, 0]}
	s.players[1].relations[0] = "enemy"
	_tasks(s).run_pass(4)
	assert_int(s.fleets_of(1).size()).is_equal(0)
	s.players[1].relations[0] = "neutral"
	f.cargo[Fleet.CARGO_COLONISTS] = 1
	_tasks(s).run_pass(4)
	assert_int(s.fleets_of(1).size()).is_equal(0)
	f.cargo[Fleet.CARGO_COLONISTS] = 0
	_tasks(s).run_pass(4)
	assert_int(s.fleets_of(1).size()).is_equal(1)


func test_tech_bonus_once_per_turn() -> void:
	var p := Player.new()
	p.race.research_costs.assign([1, 1, 1, 1, 1, 1])
	var rng := StarsRandom.new()
	var none: Array[int] = [0, 0, 0, 0, 0, 0]
	for i in 20:
		assert_int(TechGain.try_bonus(p, none, _content, rng)).is_equal(0)
	var need: Array[int] = [26, 26, 26, 26, 26, 26]
	var gained := 0
	for i in 20:
		var cost := []
		for f in 6:
			cost.append(ResearchRules.level_cost(p, f, _content, false))
		var got := TechGain.try_bonus(p, need, _content, rng)
		if got > 0:
			assert_int(gained).is_equal(0)
			gained = got
			assert_int(p.research_points[got - 1]).is_equal(cost[got - 1])
	assert_int(gained).is_greater(0)
	assert_bool(p.tech_bonus_taken).is_true()


func _transport(f: Fleet, actions: Dictionary) -> void:
	var cargo := []
	for c in 5:
		var a: Array = actions.get(c, ["none", 0])
		cargo.append({"action": a[0], "amount": a[1]})
	f.waypoints[0].task = "transport"
	f.waypoints[0].task_data = {"cargo": cargo}


func test_unload_at_another_players_planet() -> void:
	var s := _game()
	s.planets[0].owner = 1
	var f := _fleet(s, 0, 1)
	f.cargo.assign([10, 0, 0, 20, 0])
	_transport(f, {0: ["unload_all", 0], 3: ["unload", 5]})
	_tasks(s).run_pass(1)
	# minerals land; colonists become an invasion (ground combat, S17) and leave the fleet
	assert_array([s.planets[0].surface[0], f.cargo[0], f.cargo[3]]).is_equal([10, 0, 15])
	assert_str(f.waypoints[0].task_data["cargo"][3]["action"]).is_equal("none")
	assert_int(s.planets[0].population).is_equal(100)


func test_colonist_unload_refused_cancels_the_task() -> void:
	for case in ["starbase", "unowned", "space_race"]:
		var s := _game()
		s.planets[0].owner = 1 if case != "unowned" else -1
		if case == "starbase":
			s.planets[0].starbase = Starbase.new()
		if case == "space_race":
			s.players[0].race.primary_trait = "trait.prt.AR"
		var f := _fleet(s, 0, 1)
		f.cargo.assign([0, 0, 0, 20, 0])
		_transport(f, {3: ["unload_all", 0], 4: ["unload_all", 0]})
		_tasks(s).run_pass(1)
		assert_array([f.cargo[3], f.waypoints[0].task]).is_equal([20, "none"])


func test_load_from_what_the_player_does_not_control_is_skipped() -> void:
	var s := _game()
	s.planets[0].owner = 1
	s.planets[0].surface.assign([50, 0, 0])
	var f := _fleet(s, 0, 1)
	_transport(f, {0: ["load_all", 0]})
	_tasks(s).run_pass(2)
	# fix B26: the impossible load is a no-op and the task completes
	assert_array([f.cargo[0], f.waypoints[0].task]).is_equal([0, "none"])


func test_transport_between_fleets() -> void:
	var s := _game()
	var mine := _fleet(s, 0, 1)
	var theirs := _fleet(s, 1, 1)
	var f := _fleet(s, 0, 1)
	f.cargo.assign([20, 0, 0, 0, 100])
	mine.cargo.assign([0, 7, 0, 0, 0])
	_transport(f, {0: ["unload", 12], 1: ["load_all", 0], 4: ["unload", 40]})
	f.waypoints[0].target = "fleet"
	f.waypoints[0].target_owner = 0
	f.waypoints[0].target_id = mine.number
	_tasks(s).run_pass(1)
	_tasks(s).run_pass(2)
	assert_array(f.cargo).is_equal([8, 7, 0, 0, 60])
	assert_array(mine.cargo).is_equal([12, 0, 0, 0, 40])
	# another player's fleet gets fuel, never minerals (fix B20) or colonists
	_transport(f, {0: ["unload_all", 0], 4: ["unload", 10]})
	f.waypoints[0].target_owner = 1
	f.waypoints[0].target_id = theirs.number
	_tasks(s).run_pass(1)
	assert_array([f.cargo[0], f.cargo[4], theirs.cargo[0], theirs.cargo[4]]).is_equal(
		[8, 50, 0, 10]
	)
	f.cargo[3] = 5
	_transport(f, {3: ["unload_all", 0]})
	f.waypoints[0].target_owner = 1
	_tasks(s).run_pass(1)
	assert_array([f.cargo[3], f.waypoints[0].task]).is_equal([5, "none"])


func test_fill_and_wait_percent() -> void:
	var s := _game()
	s.planets[0].surface.assign([50, 6, 0])
	var f := _fleet(s, 0, 1)
	f.cargo.assign([5, 0, 0, 0, 0])
	# 40% of the 25 kT hold is 10 kT, loaded on top of what is aboard (as the original does)
	_transport(f, {0: ["fill_percent", 40]})
	_tasks(s).run_pass(2)
	assert_array([f.cargo[0], f.waypoints[0].task]).is_equal([15, "none"])
	# waiting for 80% (capped by the 10 kT left in the hold) with only 6 kT of boranium there
	_transport(f, {1: ["wait_percent", 80]})
	_tasks(s).run_pass(2)
	assert_array([f.cargo[1], f.waypoints[0].task]).is_equal([6, "transport"])


func test_set_amount_and_set_waypoint() -> void:
	var s := _game()
	var f := _fleet(s, 0, 1)
	f.cargo.assign([0, 0, 0, 20, 0])
	_transport(f, {3: ["set_amount", 12]})
	_tasks(s).run_pass(1)
	assert_array([f.cargo[3], s.planets[0].population]).is_equal([12, 108])
	assert_str(f.waypoints[0].task_data["cargo"][3]["action"]).is_equal("none")
	f.cargo[3] = 3
	_transport(f, {3: ["set_amount", 12]})
	_tasks(s).run_pass(2)
	assert_array([f.cargo[3], f.waypoints[0].task]).is_equal([12, "none"])
	s.planets[0].population = 2
	f.cargo[3] = 0
	_transport(f, {3: ["set_amount", 12]})
	_tasks(s).run_pass(2)
	assert_array([f.cargo[3], f.waypoints[0].task]).is_equal([2, "transport"])
	# set waypoint: the planet keeps 30 kT of ironium
	f.cargo.assign([0, 0, 0, 0, 0])
	s.planets[0].surface.assign([50, 0, 0])
	_transport(f, {0: ["set_waypoint", 30]})
	_tasks(s).run_pass(2)
	assert_array([f.cargo[0], s.planets[0].surface[0]]).is_equal([20, 30])
	s.planets[0].surface[0] = 10
	_transport(f, {0: ["set_waypoint", 30]})
	_tasks(s).run_pass(1)
	assert_array([f.cargo[0], s.planets[0].surface[0]]).is_equal([0, 30])
