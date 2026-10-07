extends GdUnitTestSuite
## Spec S12 "Stargates": the limits, refusals, cargo left behind and losses.

const GATE := "part.orbital.stargate_100_250"

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _ship(slot: int, hull: String, parts: Array) -> Design:
	var d := Design.new()
	d.slot = slot
	d.hull = hull
	d.parts.assign(parts)
	return d


## Two planets 200 ly apart, each with a starbase carrying a 100/250 stargate.
func _game() -> GameState:
	var s := GameState.new()
	s.settings.universe_width = 800
	var p := Player.new()
	p.relations.assign(["neutral"])
	p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
	p.set_design(_ship(0, "hull.scout", [DesignSlot.new("part.engine.long_hump_6", 1)]), false)
	p.set_design(
		_ship(1, "hull.medium_freighter", [DesignSlot.new("part.engine.long_hump_6", 1)]), false
	)
	p.set_design(_ship(0, "hull.orbital_fort", [DesignSlot.new(GATE, 1)]), true)
	s.players.append(p)
	for i in 2:
		var pl := Planet.new()
		pl.id = i
		pl.x = 1200 + 200 * i
		pl.y = 1200
		pl.owner = 0
		pl.population = 100
		pl.starbase = Starbase.new()
		s.planets.append(pl)
	return s


func _fleet(s: GameState, design := 0, count := 1) -> Fleet:
	var f := s.add_fleet(0, 512)
	f.x = 1200
	f.y = 1200
	f.planet = 0
	f.add_ships(design, count)
	f.cargo[Fleet.CARGO_FUEL] = 50
	var here := Waypoint.new(1200, 1200)
	here.target = "planet"
	here.target_id = 0
	f.waypoints.append(here)
	var there := Waypoint.new(1400, 1200)
	there.target = "planet"
	there.target_id = 1
	there.warp = Waypoint.WARP_STARGATE
	f.waypoints.append(there)
	return f


func _types(s: GameState) -> Array:
	return (s.messages[0] as Array).map(func(m: Dictionary) -> String: return m["type"])


func test_damage_matches_the_worked_example() -> void:
	var gate := {"gate_mass": 100, "gate_range": 250}
	assert_int(Stargates._damage(gate, gate, 300, 150)).is_equal(27)
	assert_int(Stargates._damage(gate, gate, 200, 50)).is_equal(0)
	assert_int(Stargates._damage(gate, gate, 1251, 50)).is_equal(-1)
	assert_int(Stargates._damage(gate, gate, 200, 501)).is_equal(-2)
	assert_int(Stargates._damage(gate, gate, 1250, 50)).is_equal(100)
	var unlimited := {"gate_mass": -1, "gate_range": -1}
	assert_int(Stargates._damage(unlimited, unlimited, 5000, 5000)).is_equal(0)


func test_a_jump_within_the_limits_arrives_without_fuel() -> void:
	var s := _game()
	var f := _fleet(s)
	TurnMessages.clear(s)
	Movement.move_all(s, _content, StarsRandom.new())
	assert_int(f.x).is_equal(1400)
	assert_int(f.planet).is_equal(1)
	assert_int(f.cargo[Fleet.CARGO_FUEL]).is_equal(50)
	assert_bool(f.gated).is_true()
	assert_int(f.waypoints.size()).is_equal(1)


func test_cargo_is_left_behind_unless_inter_stellar_traveler() -> void:
	var s := _game()
	var f := _fleet(s, 1)
	f.cargo[Fleet.CARGO_IRONIUM] = 20
	f.cargo[Fleet.CARGO_COLONISTS] = 5
	var before := s.planets[0].surface[0]
	TurnMessages.clear(s)
	Movement.move_all(s, _content, StarsRandom.new())
	assert_int(f.cargo[Fleet.CARGO_IRONIUM]).is_equal(0)
	assert_int(s.planets[0].surface[0]).is_equal(before + 20)
	assert_int(s.planets[0].population).is_equal(105)
	assert_array(_types(s)).contains(["message.fleet.gate_unloaded_both"])
	assert_array(s.messages[0][0]["params"]).is_equal([f.number, 5, 20, 0])


func test_refusals_leave_the_fleet_in_place() -> void:
	var s := _game()
	s.planets[1].starbase = null
	var f := _fleet(s)
	TurnMessages.clear(s)
	Movement.move_all(s, _content, StarsRandom.new())
	assert_int(f.x).is_equal(1200)
	assert_array(_types(s)).is_equal(["message.fleet.gate_none_there"])
	s.planets[1].starbase = Starbase.new()
	var other := Player.new()
	other.index = 1
	other.relations.assign(["neutral", "neutral"])
	other.set_design(_ship(0, "hull.orbital_fort", [DesignSlot.new(GATE, 1)]), true)
	s.players.append(other)
	s.players[0].relations.assign(["neutral", "friend"])
	s.planets[1].owner = 1
	TurnMessages.clear(s)
	Movement.move_all(s, _content, StarsRandom.new())
	assert_array(_types(s)).is_equal(["message.fleet.gate_blocked"])


func test_ships_far_beyond_the_limits_are_lost() -> void:
	var s := _game()
	s.planets[1].x = 1200 + 1250
	var f := _fleet(s, 0, 10)
	f.waypoints[1].x = s.planets[1].x
	TurnMessages.clear(s)
	Movement.move_all(s, _content, StarsRandom.new())
	assert_array(_types(s)).is_equal(["message.fleet.gate_lost"])
	assert_object(s.fleet(0, f.number)).is_null()
