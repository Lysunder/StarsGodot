extends GdUnitTestSuite
## Spec S17 "Ground combat": colonists landed on another player's planet against its defenders.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _world(defender_prt := "") -> GameState:
	var s := GameState.new()
	for i in 2:
		var p := Player.new()
		p.index = i
		p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
		if i == 1 and not defender_prt.is_empty():
			p.race.primary_trait = defender_prt
		p.tech_levels.assign([3, 3, 3, 3, 3, 3])
		p.relations.assign(["neutral", "enemy"] if i == 0 else ["enemy", "neutral"])
		s.players.append(p)
	var pl := Planet.new()
	pl.id = 0
	pl.owner = 1
	s.planets.append(pl)
	var f := s.add_fleet(0, 512)
	f.planet = 0
	TurnMessages.clear(s)
	return s


func _land(s: GameState, colonists: int) -> void:
	var tasks := WaypointTasks.new(s, _content, StarsRandom.new(5, 673))
	tasks._record(s.fleets[0], s.planet(0), colonists)
	tasks.resolve()


func _types(s: GameState, p: int) -> Array:
	return (s.messages[p] as Array).map(func(m: Dictionary) -> String: return m.type)


func test_invaders_take_the_planet() -> void:
	var s := _world()
	s.planet(0).population = 100
	# 200 colonists fight as 220 against 100 defenders: 200 × (220 - 100) / 220 survive
	_land(s, 200)
	assert_int(s.planet(0).owner).is_equal(0)
	assert_int(s.planet(0).population).is_equal(109)
	assert_array(_types(s, 0)).contains(["message.planet.invasion_won"])
	assert_array(s.messages[0][0].params).is_equal([1, 0])
	assert_str(s.messages[1][0].type).is_equal("message.planet.invaded")
	assert_array(s.messages[1][0].params).is_equal([0, 0, 200])


func test_defenders_hold_and_lose_their_share() -> void:
	var s := _world()
	s.planet(0).population = 300
	_land(s, 200)
	assert_int(s.planet(0).owner).is_equal(1)
	assert_int(s.planet(0).population).is_equal(300 - 300 * 220 / 300)
	assert_str(s.messages[0][0].type).is_equal("message.planet.invasion_failed")
	assert_array(s.messages[0][0].params).is_equal([200, 0, 1])
	assert_str(s.messages[1][0].type).is_equal("message.planet.invasion_repelled")
	assert_array(s.messages[1][0].params).is_equal([0, 200, 0])


func test_inner_strength_defenders_count_double() -> void:
	var s := _world("trait.prt.IS")
	s.planet(0).population = 150
	_land(s, 200)
	assert_int(s.planet(0).owner).is_equal(1)
	assert_int(s.planet(0).population).is_equal(150 - 150 * 220 / 300)
