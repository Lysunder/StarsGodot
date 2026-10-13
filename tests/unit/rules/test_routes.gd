extends GdUnitTestSuite
## Spec S11 "Route": following a planet's route, default orders, and new ships on a route (S09).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## Player 0 owns planet 0 (100, 100) with a route to planet 1 (100 + d, 100). Design 0 is a colony
## ship with a Long Hump 6 (default warp 6), design 1 a scout with a mining robot.
func _game(d := 100) -> GameState:
	var s := GameState.new()
	var p := Player.new()
	p.index = 0
	p.relations.assign(["neutral"])
	p.tech_levels.assign([26, 26, 26, 26, 26, 26])
	for slot in 2:
		var design := Design.new()
		design.slot = slot
		design.hull = "hull.colony_ship" if slot == 0 else "hull.scout"
		design.parts.assign([DesignSlot.new("part.engine.long_hump_6", 1)])
		if slot == 1:
			design.parts.append(DesignSlot.new("part.mining_robot.robo_mini_miner", 1))
		p.set_design(design, false)
	var base := Design.new()
	base.slot = 0
	base.hull = "hull.space_station"
	base.parts.assign([DesignSlot.new("part.orbital.stargate_any_any", 1)])
	p.set_design(base, true)
	s.players.append(p)
	for i in 2:
		var pl := Planet.new()
		pl.id = i
		pl.x = 100 + d * i
		pl.y = 100
		pl.owner = 0
		pl.population = 100
		s.planets.append(pl)
	s.planets[0].route = 1
	return s


func _fleet(s: GameState, slot := 0, at := 0, task := "route") -> Fleet:
	var pl := s.planets[at]
	var f := s.add_fleet(0, 512)
	f.x = pl.x
	f.y = pl.y
	f.planet = pl.id
	f.add_ships(slot, 1)
	f.cargo[Fleet.CARGO_FUEL] = 1000
	var wp := Waypoint.new(pl.x, pl.y)
	wp.target = "planet"
	wp.target_id = pl.id
	wp.task = task
	f.waypoints.append(wp)
	return f


func test_follow_takes_the_default_warp_eased_off() -> void:
	var s := _game()
	var f := _fleet(s)
	assert_int(Routes.follow(s, _content, f, s.planets[0])).is_equal(6)
	var wp := f.waypoints[1]
	assert_array([wp.x, wp.y, wp.target, wp.target_id, wp.task]).is_equal(
		[200, 100, "planet", 1, "route"]
	)
	# 20 ly: (20 div 6) div 6 = 0 = (20 div 5) div 5, but (20 div 4) div 4 = 1
	s = _game(20)
	f = _fleet(s)
	assert_int(Routes.follow(s, _content, f, s.planets[0])).is_equal(5)
	# no fuel: down to the warp that uses none
	f = _fleet(s)
	f.cargo[Fleet.CARGO_FUEL] = 0
	assert_int(Routes.follow(s, _content, f, s.planets[0])).is_equal(1)


func test_follow_uses_a_safe_stargate_when_empty() -> void:
	var s := _game()
	for pl in s.planets:
		pl.starbase = Starbase.new()
	var f := _fleet(s)
	assert_int(Routes.follow(s, _content, f, s.planets[0])).is_equal(Waypoint.WARP_STARGATE)
	# with cargo aboard: the dock picks the warp by fuel range instead
	f = _fleet(s)
	f.cargo[0] = 1
	var warp := Routes.follow(s, _content, f, s.planets[0])
	assert_bool(warp > 0 and warp < Waypoint.WARP_STARGATE).is_true()


func test_route_task_reroutes_an_idle_fleet() -> void:
	var s := _game()
	var f := _fleet(s)
	TurnMessages.clear(s)
	WaypointTasks.new(s, _content, StarsRandom.new()).run_pass(1)
	assert_int(f.waypoints.size()).is_equal(2)
	var m: Dictionary = s.messages[0][0]
	assert_str(m.type).is_equal("message.fleet.rerouted")
	assert_array(m.params).is_equal([f.number, 0, 1])
	# a fleet with somewhere to go is left alone
	WaypointTasks.new(s, _content, StarsRandom.new()).run_pass(2)
	assert_int((s.messages[0] as Array).size()).is_equal(1)


func test_default_orders_merge_miners_then_mine() -> void:
	var s := _game()
	s.planets[1].owner = -1
	var first := _fleet(s, 1, 1)
	var second := _fleet(s, 1, 1)
	first.battle_plan = 2
	var tasks := WaypointTasks.new(s, _content, StarsRandom.new())
	tasks.run_pass(3)
	assert_int(s.fleets.size()).is_equal(2)
	tasks.run_pass(4)
	# the first merges into the second at once; the second, alone, remote-mines
	assert_int(s.fleets.size()).is_equal(1)
	assert_int(second.ship_count()).is_equal(2)
	assert_str(second.waypoints[0].task).is_equal("remote_mine")
	# no mining robots, or an owned planet: only the battle plan changes
	var plain := _fleet(s, 0, 1)
	plain.battle_plan = 3
	tasks.run_pass(4)
	assert_array([plain.waypoints[0].task, plain.battle_plan]).is_equal(["route", 0])


func test_new_ships_follow_the_planet_route() -> void:
	var s := _game()
	var pl := s.planets[0]
	pl.starbase = Starbase.new()
	pl.population = 10000
	pl.factories = 1000
	pl.surface.assign([10000, 10000, 10000])
	pl.queue.append(QueueItem.of_design(0, false, 2))
	TurnMessages.clear(s)
	var research: Array[int] = [0]
	Production.new(s, _content, StarsRandom.new()).run_planet(pl, research)
	assert_int(s.fleets.size()).is_equal(1)
	var f := s.fleets[0]
	assert_int(f.waypoints.size()).is_equal(2)
	assert_int(f.waypoints[1].target_id).is_equal(1)
	var types := (s.messages[0] as Array).map(func(m: Dictionary) -> String: return m.type)
	assert_array(types).contains(["message.production.ships_routed"])
