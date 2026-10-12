extends GdUnitTestSuite
## Spec S20: the ship rating, the score and the turn's update (ranks, elimination, victory).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _design(slot: int, parts: Array) -> Design:
	var d := Design.new()
	d.slot = slot
	d.hull = "hull.destroyer"
	var slots: Array[DesignSlot] = [DesignSlot.new("part.engine.long_hump_6", 1)]
	for p: Array in parts:
		slots.append(DesignSlot.new(p[0], p[1]))
	d.parts.assign(slots)
	return d


func test_ship_rating() -> void:
	var lasers := _design(0, [["part.beam.laser", 2]])
	var m := BattleSetup.design_movement(lasers, _content)
	# beams: (1 + 3) × 10 × 2 div 4 = 20, adjusted by the movement
	assert_int(Score.ship_rating(lasers, _content)).is_equal(20 + (m - 4) * 20 / 10)
	var boosted := _design(0, [["part.beam.laser", 2], ["part.electrical.energy_capacitor", 1]])
	var mb := BattleSetup.design_movement(boosted, _content)
	# a 10% capacitor: 1,100 per mille, 110%: 22
	assert_int(Score.ship_rating(boosted, _content)).is_equal(22 + (mb - 4) * 22 / 10)
	var sapper := _design(0, [["part.beam.phased_sapper", 1]])
	var ms := BattleSetup.design_movement(sapper, _content)
	# (3 + 3) × 211 div 4 = 316, a third for a sapper: 105
	assert_int(Score.ship_rating(sapper, _content)).is_equal(105 + (ms - 4) * 105 / 10)
	# torpedoes and bombs ignore movement: (4 - 2) × 5 × 3 div 2 = 15; (6 + 2) × 2 × 2 = 32
	var torps := _design(0, [["part.torpedo.alpha_torpedo", 3], ["part.bomb.lady_finger_bomb", 2]])
	assert_int(Score.ship_rating(torps, _content)).is_equal(15 + 32)
	assert_int(Score.ship_rating(_design(0, []), _content)).is_equal(0)


func test_tech_points_and_packing() -> void:
	assert_array([3, 4, 6, 7, 9, 10, 26].map(Score._tech_points)).is_equal(
		[3, 5, 9, 12, 18, 22, 86]
	)
	assert_int(Score.packed(8191)).is_equal(8191)
	assert_int(Score.packed(8195)).is_equal(8192)


func _world(players: int) -> GameState:
	var s := GameState.new()
	for i in players:
		var p := Player.new()
		p.index = i
		p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
		p.tech_levels.assign([4, 4, 4, 4, 4, 4])
		s.players.append(p)
		var pl := Planet.new()
		pl.id = i
		pl.owner = i
		pl.population = 2500
		s.planets.append(pl)
	TurnMessages.clear(s)
	return s


func _victory(conditions: Dictionary, criteria: int, min_years: int) -> Dictionary:
	var out := {"tech_fields": 2, "criteria": criteria, "min_years": min_years}
	for id in Score.CONDITIONS:
		out[id] = {"on": conditions.has(id), "value": conditions.get(id, 1000000)}
	return out


func test_score_and_capital_ships() -> void:
	var s := _world(1)
	var p := s.player(0)
	p.set_design(_design(0, [["part.beam.laser", 1]]), false)
	var big := _design(1, [["part.beam.phased_sapper", 12], ["part.beam.mega_disruptor", 12]])
	p.set_design(big, false)
	var f := s.add_fleet(0, 512)
	f.add_ships(0, 3)
	f.add_ships(1, 4)
	var r := Score.record(s, _content, 0)
	var resources := PlanetEconomy.resources(s.planet(0), p.race, _content)
	# 3 population points, resources div 30, tech 6 × 5; 3 escorts and 4 capitals with 1 planet
	var expected := 3 + resources / 30 + 30 + 2 * 1 + 1 * 4 * 8 / 5
	assert_int(Score.ship_rating(big, _content)).is_greater_equal(Score.CAPITAL_RATING)
	assert_int(r.score).is_equal(expected)
	assert_array([r.planets, r.escorts, r.capitals, r.tech]).is_equal([1, 3, 4, 24])


func test_single_player_rank_stays() -> void:
	var s := _world(1)
	s.settings.victory = _victory({}, 0, 30)
	Score.update(s, _content)
	assert_int(s.player(0).score.rank).is_equal(1)
	assert_int(s.player(0).rank).is_equal(0)


func test_elimination_and_last_standing() -> void:
	var s := _world(2)
	s.settings.victory = _victory({}, 0, 30)
	s.planet(1).owner = -1
	TurnMessages.add(s, _content, 0, "message.production.queue_empty", {"planet": 0}, [0])
	Score.update(s, _content)
	assert_bool(s.player(1).eliminated).is_true()
	assert_bool(s.player(0).eliminated).is_false()
	# put first: the last one standing, then the elimination, then the turn's other messages
	var types: Array = s.messages[0].map(func(m: Dictionary) -> String: return m.type)
	assert_array(types).is_equal(
		[
			"message.game.last_standing",
			"message.game.player_eliminated",
			"message.production.queue_empty"
		]
	)
	assert_array(s.messages[0][1].params).is_equal([1])
	assert_str(s.messages[1][0].type).is_equal("message.game.dead")


func test_winners_by_conditions() -> void:
	var s := _world(3)
	s.turn = 40
	s.settings.victory = _victory({"score": 1, "owns_planets": 30}, 2, 30)
	s.planet(2).owner = -1
	var third := Planet.new()
	third.id = 3
	third.owner = 2
	third.population = 10
	s.planets.append(third)
	# each owns 1 of 4 planets: MulDiv(4, 30, 100) = 1 planet needed
	Score.update(s, _content)
	assert_array(s.player(0).score.met).contains(["owns_planets", "score"])
	assert_bool(s.player(0).score.winner).is_true()
	assert_bool(s.player(1).score.winner).is_true()
	assert_str(s.messages[0][0].type).is_equal("message.game.won_shared")
	# player 2 meets both too: the others are players 1 and 2
	assert_bool(s.player(2).score.winner).is_true()
	assert_array(s.messages[0][0].params).is_equal([[1, 2]])
	# before the minimum years nobody wins
	var early := _world(2)
	early.turn = 29
	early.settings.victory = _victory({"score": 1}, 1, 30)
	Score.update(early, _content)
	assert_bool(early.player(0).score.winner).is_false()
	assert_array(early.messages[0]).is_empty()


func test_one_winner_and_the_others() -> void:
	var s := _world(2)
	s.turn = 50
	s.settings.victory = _victory({"highest_score": 30}, 1, 30)
	s.planet(0).population = 9000
	Score.update(s, _content)
	assert_int(s.player(0).rank).is_equal(1)
	assert_int(s.player(1).rank).is_equal(2)
	assert_str(s.messages[0][0].type).is_equal("message.game.won")
	assert_str(s.messages[1][0].type).is_equal("message.game.won_by_other")
	assert_array(s.messages[1][0].params).is_equal([[0]])
