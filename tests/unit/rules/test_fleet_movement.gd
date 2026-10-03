extends GdUnitTestSuite
## Specs S12 (movement, fuel) and S11 (transport, colonize). The fuel and position numbers come from
## the terra1 harness game (a colony ship moving 49 ly at warp 7 burns 95 mg).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _colony_ship(engine := "part.engine.long_hump_6") -> Design:
	var d := Design.new()
	d.slot = 0
	d.hull = "hull.colony_ship"
	d.parts.assign(
		[DesignSlot.new(engine, 1), DesignSlot.new("part.mechanical.colonization_module", 1)]
	)
	return d


func _game(players := 1) -> GameState:
	var s := GameState.new()
	s.settings.universe_width = 400
	for i in players:
		var p := Player.new()
		p.index = i
		p.relations.assign(["neutral", "neutral"].slice(0, players))
		p.set_design(_colony_ship(), false)
		s.players.append(p)
	for i in 2:
		var pl := Planet.new()
		pl.id = i
		s.planets.append(pl)
	s.planets[0].x = 1277
	s.planets[0].y = 1233
	s.planets[0].owner = 0
	s.planets[0].population = 250
	s.planets[1].x = 1241
	s.planets[1].y = 1317
	return s


func _fleet(s: GameState, owner := 0, at := 0) -> Fleet:
	var f := s.add_fleet(owner, 512)
	var pl := s.planets[at]
	f.x = pl.x
	f.y = pl.y
	f.planet = at
	f.add_ships(0, 1)
	f.cargo[Fleet.CARGO_FUEL] = 200
	var wp := Waypoint.new(pl.x, pl.y)
	wp.target = "planet"
	wp.target_id = at
	f.waypoints.append(wp)
	return f


func _goto(f: Fleet, planet: Planet, warp: int, task := "none") -> void:
	var wp := Waypoint.new(planet.x, planet.y)
	wp.target = "planet"
	wp.target_id = planet.id
	wp.warp = warp
	wp.task = task
	f.waypoints.append(wp)


func test_fuel_matches_the_original() -> void:
	var s := _game()
	var f := _fleet(s)
	f.cargo[WaypointTasks.CARGO_COLONISTS] = 25
	assert_int(Movement.fuel_needed(f, s.players[0], 7, 49, _content)).is_equal(95)
	assert_int(Movement.fuel_needed(f, s.players[0], 1, 49, _content)).is_equal(0)


func test_partial_move_and_deep_space_waypoint() -> void:
	var s := _game()
	var f := _fleet(s)
	f.cargo[WaypointTasks.CARGO_COLONISTS] = 25
	_goto(f, s.planets[1], 7, "colonize")
	Movement.move_all(s, _content, StarsRandom.new())
	assert_array([f.x, f.y, f.planet]).is_equal([1258, 1278, -1])
	assert_int(f.cargo[Fleet.CARGO_FUEL]).is_equal(105)
	assert_array([f.waypoints[0].target, f.waypoints[0].task, f.waypoints[0].x]).is_equal(
		["none", "none", 1258]
	)
	Movement.move_all(s, _content, StarsRandom.new())
	assert_array([f.x, f.y, f.planet]).is_equal([1241, 1317, 1])
	assert_int(f.waypoints.size()).is_equal(1)
	assert_str(f.waypoints[0].task).is_equal("colonize")


func test_out_of_fuel_stops_early() -> void:
	var s := _game()
	var f := _fleet(s)
	f.cargo[Fleet.CARGO_FUEL] = 20
	_goto(f, s.planets[1], 9)
	Movement.move_all(s, _content, StarsRandom.new())
	assert_int(f.cargo[Fleet.CARGO_FUEL]).is_equal(0)
	assert_bool(f.x != 1241).is_true()
	assert_int(f.waypoints[1].warp).is_less(9)


func test_load_colonists_and_colonize() -> void:
	var s := _game()
	var f := _fleet(s)
	f.waypoints[0].task = "transport"
	var cargo := []
	for c in 5:
		cargo.append({"action": "load_all" if c == 3 else "none", "amount": 0})
	f.waypoints[0].task_data = {"cargo": cargo}
	_goto(f, s.planets[1], 7, "colonize")
	var tasks := WaypointTasks.new(s, _content, StarsRandom.new())
	tasks.run_pass(1)
	assert_int(f.cargo[3]).is_equal(0)
	tasks.run_pass(2)
	assert_int(f.cargo[3]).is_equal(25)
	assert_int(s.planets[0].population).is_equal(225)
	assert_str(f.waypoints[0].task).is_equal("none")
	f.x = 1241
	f.y = 1317
	f.planet = 1
	f.waypoints.remove_at(0)
	tasks.run_pass(3)
	tasks.resolve()
	var colony := s.planets[1]
	assert_array([colony.owner, colony.population]).is_equal([0, 25])
	assert_int(s.fleets.size()).is_equal(0)
	var cost := ProductionCosts.design_cost(s.players[0].ship_design(0), s.players[0], _content)
	assert_array(colony.surface).is_equal([cost[0] * 3 / 4, cost[1] * 3 / 4, cost[2] * 3 / 4])
	assert_int(s.players[0].ship_design(0).remaining).is_equal(-1)


func test_colonizing_together() -> void:
	var s := _game(2)
	for p in 2:
		var f := _fleet(s, p, 1)
		f.cargo[3] = 25 + 5 * p
		f.waypoints[0].task = "colonize"
	var tasks := WaypointTasks.new(s, _content, StarsRandom.new())
	tasks.run_pass(1)
	tasks.resolve()
	# strengths 27 and 33: player 1 wins with (33 - 27) * 30 / 33 = 5 units
	assert_array([s.planets[1].owner, s.planets[1].population]).is_equal([1, 5])
	var tie := _game(2)
	for p in 2:
		var f := _fleet(tie, p, 1)
		f.cargo[3] = 25
		f.waypoints[0].task = "colonize"
	tasks = WaypointTasks.new(tie, _content, StarsRandom.new())
	tasks.run_pass(1)
	tasks.resolve()
	assert_int(tie.planets[1].owner).is_equal(-1)
