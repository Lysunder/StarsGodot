extends GdUnitTestSuite
## Spec S08 worked examples (Humanoid race: JoaT).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


static func _planet(env: Array, population: int) -> Planet:
	var pl := Planet.new()
	pl.environment.assign(env)
	pl.population = population
	pl.owner = 0
	return pl


func test_hab_and_max_pop() -> void:
	var race := Race.new()
	assert_int(PlanetEconomy.hab_value(_planet([50, 50, 50], 0), race)).is_equal(100)
	var pl := _planet([30, 60, 85], 0)
	assert_int(PlanetEconomy.hab_value(pl, race)).is_equal(22)
	assert_int(PlanetEconomy.max_pop(pl, race, _content)).is_equal(2640)
	assert_int(PlanetEconomy.hab_value(_planet([10, 50, 50], 0), race)).is_equal(-5)


func test_growth_worked_examples() -> void:
	var race := Race.new()
	var cases := [
		[[30, 60, 85], 250, 825],
		[[30, 60, 85], 1000, 2260],
		[[30, 60, 85], 5000, -18000],
		[[30, 60, 85], 2640, 0],
		[[30, 60, 85], 2645, 0],
		[[50, 50, 50], 250, 3750],
	]
	for c: Array in cases:
		var pl := _planet(c[0], c[1])
		var where := "%s P %d" % [str(c[0]), c[1]]
		var change := PlanetEconomy.grow(pl, race, _content, false)
		assert_int(change).override_failure_message(where).is_equal(c[2])


func test_uninhabitable_loss() -> void:
	var race := Race.new()
	race.hab_low.assign([42, 15, 15])
	race.hab_center.assign([50, 50, 50])
	race.hab_high.assign([58, 85, 85])
	var pl := _planet([30, 50, 50], 1000)
	assert_int(PlanetEconomy.hab_value(pl, race)).is_equal(-12)
	assert_int(PlanetEconomy.grow(pl, race, _content, true)).is_equal(-1200)
	assert_int(pl.population).is_equal(988)


func test_resources_example() -> void:
	var pl := _planet([50, 50, 50], 250)
	pl.factories = 10
	assert_int(PlanetEconomy.resources(pl, Race.new(), _content)).is_equal(35)


func test_add_colonists_borrows() -> void:
	var pl := _planet([50, 50, 50], 10)
	pl.extra_colonists = 20
	PlanetEconomy.add_colonists(pl, -50)
	assert_array([pl.population, pl.extra_colonists]).is_equal([9, 70])


func test_depopulate_keeps_installations() -> void:
	var pl := _planet([50, 50, 50], 0)
	pl.mines = 5
	pl.factories = 6
	pl.defenses = 7
	pl.has_scanner = true
	pl.starbase = Starbase.new()
	var race := Race.new()
	race.primary_trait = "trait.prt.CA"
	pl.environment_original.assign([40, 40, 40])
	PlanetEconomy.depopulate(pl, race, _content)
	assert_int(pl.owner).is_equal(-1)
	assert_array([pl.mines, pl.factories, pl.defenses]).is_equal([5, 6, 0])
	assert_bool(pl.has_scanner).is_false()
	assert_object(pl.starbase).is_null()
	assert_array(pl.environment).is_equal([40, 40, 40])


func test_alternate_reality_miners_in_orbit_mine_the_planet() -> void:
	var s := GameState.new()
	var p := Player.new()
	p.race.primary_trait = "trait.prt.AR"
	var d := Design.new()
	d.slot = 0
	d.hull = "hull.mini_miner"
	d.parts.assign(
		[
			DesignSlot.new("part.engine.long_hump_6", 1),
			DesignSlot.new("part.mining_robot.robo_miner", 1)
		]
	)
	p.set_design(d, false)
	s.players.append(p)
	var pl := _planet([50, 50, 50], 100)
	pl.id = 0
	pl.homeworld = true
	pl.concentration.assign([50, 50, 20])
	s.planets.append(pl)
	var f := s.add_fleet(0, 512)
	f.planet = 0
	f.add_ships(0, 2)
	var wp := Waypoint.new(0, 0)
	wp.task = "remote_mine"
	f.waypoints.append(wp)
	f.did_not_move = true
	var rate := WaypointTasks.mining_rate(f, p, _content)
	assert_int(rate).is_greater(0)
	PlanetEconomy.mine_orbit(s, pl, _content, null, true)
	# raw output C x rate, the homeworld minimum of 30 for germanium
	assert_array(pl.surface.slice(0, 3)).is_equal(
		[50 * rate / 100, 50 * rate / 100, 30 * rate / 100]
	)
	assert_bool(f.did_not_move).is_false()
	# a fleet with somewhere to go, or another race, mines nothing here
	pl.surface.assign([0, 0, 0])
	f.waypoints.append(Waypoint.new(10, 10))
	PlanetEconomy.mine_orbit(s, pl, _content, null, true)
	assert_array(pl.surface.slice(0, 3)).is_equal([0, 0, 0])


func test_lone_colonists_on_an_empty_planet_are_lost_at_the_end_of_the_turn() -> void:
	var s := GameState.new()
	var bare := _planet([50, 50, 50], 0)
	bare.owner = -1
	bare.extra_colonists = 40
	var mined := _planet([50, 50, 50], 0)
	mined.owner = -1
	mined.extra_colonists = 40
	mined.mines = 3
	s.planets.append_array([bare, mined])
	TurnEndPhases.FileDraws.new()._drop_lone_colonists(s)
	assert_array([bare.extra_colonists, mined.extra_colonists]).is_equal([0, 40])
