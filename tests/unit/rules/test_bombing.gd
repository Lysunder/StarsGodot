extends GdUnitTestSuite
## Spec S17 "Bombing": the defense coverage arithmetic (exact, as the original's x87 products of
## an integer and a 32-bit float are) and what bombs do to a planet.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func test_coverage_arithmetic() -> void:
	assert_int(DefenseCoverage.scale_round(7, 0.75)).is_equal(5)
	assert_int(DefenseCoverage.scale_round(2, 0.75)).is_equal(2)
	assert_int(DefenseCoverage.halved_round(10, 0.5)).is_equal(8)
	assert_int(DefenseCoverage.halved_round(9, 0.5)).is_equal(7)
	assert_int(DefenseCoverage.stopped_basis_points(0.75)).is_equal(2500)
	assert_int(DefenseCoverage.retro_left(10, 0.5)).is_equal(8)
	assert_int(DefenseCoverage.retro_left(9, 0.5)).is_equal(7)
	assert_int(DefenseCoverage.retro_left(10, 1.0)).is_equal(10)
	# against plain double arithmetic, exact while x × mantissa stays within 53 bits
	for n in [1, 7, 30, 100, 400]:
		var f: float = PackedFloat32Array([pow(1.0 - 38 * 0.001, n)])[0]
		for x in [1, 3, 250, 999, 12345]:
			assert_int(DefenseCoverage.scale_round(x, f)).is_equal(int(floor(x * f + 0.5)))
			var halved := int(floor(x * (1.0 - (1.0 - f) * 0.5) + 0.5))
			assert_int(DefenseCoverage.halved_round(x, f)).is_equal(halved)
			assert_int(DefenseCoverage.retro_left(x, f)).is_equal(x - int((1.0 - f) * x * 0.5))
		assert_int(DefenseCoverage.stopped_basis_points(f)).is_equal(int((1.0 - f) * 10000.0))


func _world() -> GameState:
	var s := GameState.new()
	for i in 2:
		var p := Player.new()
		p.index = i
		p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
		p.tech_levels.assign([3, 3, 3, 3, 3, 3])
		p.relations.assign(["neutral", "enemy"] if i == 0 else ["enemy", "neutral"])
		p.battle_plans = [{"number": 0, "attack": 3, "primary_target": 1}]
		s.players.append(p)
	TurnMessages.clear(s)
	return s


func _bomber(s: GameState, planet: Planet, bombs: Array) -> Fleet:
	var d := Design.new()
	d.hull = "hull.mini_bomber"
	var slots: Array[DesignSlot] = []
	for b: Array in bombs:
		slots.append(DesignSlot.new(b[0], b[1]))
	d.parts.assign(slots)
	d.slot = 0
	s.player(0).set_design(d, false)
	var f := s.add_fleet(0, 512)
	f.x = planet.x
	f.y = planet.y
	f.planet = planet.id
	f.add_ships(0, 1)
	return f


func _planet(s: GameState, population: int) -> Planet:
	var pl := Planet.new()
	pl.id = 0
	pl.owner = 1
	pl.x = 100
	pl.y = 100
	pl.population = population
	s.planets.append(pl)
	return pl


func test_normal_bombs_kill_colonists_and_installations() -> void:
	var s := _world()
	var pl := _planet(s, 1000)
	pl.factories = 100
	pl.mines = 50
	var f := _bomber(s, pl, [["part.bomb.cherry_bomb", 10]])
	var rng := StarsRandom.new(5, 673)
	var probe := StarsRandom.new(5, 673)
	# 100 installations: factories get 100 × 100 / 150 = 66 r 100, rounded by random(150)
	var factories := 66 + (1 if probe.random(150) < 100 else 0)
	Bombing.bomb_all(s, _content, rng)
	assert_int(pl.population).is_equal(1000 - 250)
	assert_int(pl.factories).is_equal(100 - factories)
	assert_int(pl.mines).is_equal(50 - (100 - factories))
	assert_int(rng.s1).is_equal(probe.s1)
	assert_bool(f.at_bombing).is_true()
	var word := f.owner * 512 + f.number
	var mine: Dictionary = s.messages[0][0]
	assert_str(mine.type).is_equal("message.bombing.killed_installations")
	assert_array(mine.params).is_equal([word, 0, 250, 100])
	var theirs: Dictionary = s.messages[1][0]
	assert_str(theirs.type).is_equal("message.bombed.killed_installations")
	assert_dict(theirs.goto).is_equal({"planet": 0})


func test_minimum_kill_bombs_out_a_small_colony() -> void:
	var s := _world()
	var pl := _planet(s, 2)
	_bomber(s, pl, [["part.bomb.lady_finger_bomb", 2]])
	Bombing.bomb_all(s, _content, StarsRandom.new(5, 673))
	assert_int(pl.owner).is_equal(-1)
	assert_int(pl.population).is_equal(0)
	assert_str(s.messages[0][0].type).is_equal("message.bombing.wiped_out")
	assert_array(s.messages[0][0].params).is_equal([0, 0])


func test_smart_bombs_and_retro_bombs() -> void:
	var s := _world()
	var pl := _planet(s, 1000)
	pl.environment.assign([60, 40, 50])
	pl.environment_original.assign([50, 50, 50])
	_bomber(s, pl, [["part.bomb.smart_bomb", 10], ["part.bomb.retro_bomb", 4]])
	Bombing.bomb_all(s, _content, StarsRandom.new(5, 673))
	# smart: 1 - 0.987^10 = 0.1225... -> 123 per mille of 1000
	assert_int(pl.population).is_equal(1000 - 123)
	assert_array(pl.environment).is_equal([56, 44, 50])
	assert_str(s.messages[0][0].type).is_equal("message.bombing.retro")
	assert_array(s.messages[0][0].params).is_equal([0, 0, 8])


func test_bombed_out_by_several_fleets_is_seen() -> void:
	# fix B37: the original shows the planet only when one fleet bombed it out
	var s := _world()
	var pl := _planet(s, 2)
	var a := _bomber(s, pl, [["part.bomb.lady_finger_bomb", 2]])
	var b := s.add_fleet(0, 512)
	b.x = pl.x
	b.y = pl.y
	b.planet = pl.id
	b.add_ships(0, 1)
	Bombing.bomb_all(s, _content, StarsRandom.new(5, 673))
	assert_str(s.messages[0][0].type).is_equal("message.bombing.fleets_wiped_out")
	# every bomber leaves before scanning (scrapped there): only the mark shows the planet
	s.remove_fleet(a)
	s.remove_fleet(b)
	Scanning.record_all(s, _content, StarsRandom.new())
	assert_dict(s.views[0].planets).is_equal({str(pl.id): 3})
	assert_dict(pl.bombed_out_by).is_empty()
