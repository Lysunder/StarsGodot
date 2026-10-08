extends GdUnitTestSuite
## Spec S13 (and S11 "Lay mines"): laying, merging into a field, the years count and decay.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _game() -> GameState:
	var s := GameState.new()
	s.settings.universe_width = 400
	var p := Player.new()
	p.relations.assign(["neutral"])
	p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
	var d := Design.new()
	d.slot = 0
	d.hull = "hull.mini_mine_layer"
	(
		d
		. parts
		. assign(
			[
				DesignSlot.new("part.engine.long_hump_6", 1),
				DesignSlot.new("part.mine_layer.mine_dispenser_40", 2),
			]
		)
	)
	p.set_design(d, false)
	s.players.append(p)
	var pl := Planet.new()
	pl.x = 1300
	pl.y = 1300
	s.planets.append(pl)
	return s


func _layer(s: GameState, years: int) -> Fleet:
	var f := s.add_fleet(0, 512)
	f.x = 1200
	f.y = 1200
	f.add_ships(0, 2)
	var wp := Waypoint.new(1200, 1200)
	wp.task = "lay_mines"
	wp.task_data = {"raw": [years, 0, 0, 0, 0]}
	f.waypoints.append(wp)
	f.did_not_move = true
	return f


func test_rate_doubles_on_mine_layer_hulls() -> void:
	var s := _game()
	var f := _layer(s, 0)
	# 2 ships x 2 dispensers x 40, doubled on the Mini Mine Layer
	assert_int(Minefields.lay_rate(f, s.players[0], "standard", _content)).is_equal(320)
	assert_int(Minefields.lay_rate(f, s.players[0], "heavy", _content)).is_equal(0)


func test_laying_makes_a_field_then_adds_to_it() -> void:
	var s := _game()
	var f := _layer(s, 2)
	TurnMessages.clear(s)
	Minefields.lay(s, _content, f, f.waypoints[0], false)
	assert_int(s.minefields.size()).is_equal(1)
	var field := s.minefields[0]
	assert_int(field.mines).is_equal(320)
	assert_int(field.x).is_equal(1200)
	assert_array(f.waypoints[0].task_data["raw"]).is_equal([1, 0, 0, 0, 0])
	# moved inside the field: the new mines join it and its center moves toward the fleet
	f.x = 1210
	Minefields.lay(s, _content, f, f.waypoints[0], false)
	assert_int(s.minefields.size()).is_equal(1)
	assert_int(field.mines).is_equal(640)
	assert_int(field.x).is_equal(1205)
	assert_array(f.waypoints[0].task_data["raw"]).is_equal([0, 0, 0, 0, 0])
	# with 0 years left it lays once more and the task ends
	Minefields.lay(s, _content, f, f.waypoints[0], false)
	assert_str(f.waypoints[0].task).is_equal("none")
	var types := (s.messages[0] as Array).map(func(m: Dictionary) -> String: return m["type"])
	assert_array(types).is_equal(
		["message.fleet.mines_laid", "message.fleet.mines_added", "message.fleet.mines_added"]
	)


func test_decay_grows_with_planets_inside_and_removes_empty_fields() -> void:
	var s := _game()
	var field := s.add_minefield(0, 512)
	field.x = 1300
	field.y = 1300
	field.mines = 2500
	# one planet inside: 4 + 2 = 6%
	Minefields.decay_all(s, _content)
	assert_int(field.mines).is_equal(2350)
	var small := s.add_minefield(0, 512)
	small.x = 1000
	small.y = 1000
	small.mines = 10
	Minefields.decay_all(s, _content)
	assert_bool(s.minefields.has(small)).is_false()


func _field(s: GameState, owner: int, x: int, y: int, mines: int, type := "standard") -> Minefield:
	var f := s.add_minefield(owner, 512)
	f.x = x
	f.y = y
	f.mines = mines
	f.type = type
	return f


func test_crossing_a_field_and_merging_stretches() -> void:
	var s := _game()
	var field := _field(s, 1, 1250, 1200, 400)
	# along the x axis: the field (radius 20) is crossed from 30 to 70 ly, cut at the move
	assert_array(Minefields._crossing(1200, 1200, 1400, 1200, field, 100)).is_equal([30, 70])
	assert_array(Minefields._crossing(1200, 1200, 1400, 1200, field, 50)).is_equal([30, 50])
	assert_array(Minefields._crossing(1200, 1200, 1000, 1200, field, 100)).is_empty()
	# fix B01: a straight vertical path still finds a field ahead of it
	var north := _field(s, 1, 1200, 1250, 400)
	assert_array(Minefields._crossing(1200, 1200, 1200, 1400, north, 100)).is_equal([30, 70])
	var list := []
	Minefields._add_stretch(list, 30, 50)
	Minefields._add_stretch(list, 80, 90)
	Minefields._add_stretch(list, 10, 40)
	assert_array(list).is_equal([[10, 50], [80, 90]])
	Minefields._add_stretch(list, 45, 85)
	assert_array(list).is_equal([[10, 50], [45, 90]])


func test_a_speed_bump_stops_a_fast_fleet() -> void:
	var s := _game()
	var other := Player.new()
	other.index = 1
	other.relations.assign(["neutral", "neutral"])
	s.players.append(other)
	s.players[0].relations.assign(["neutral", "neutral"])
	_field(s, 1, 1240, 1200, 900, "speed_bump")
	var f := _layer(s, 0)
	f.waypoints[0].task = "none"
	var wp := Waypoint.new(1300, 1200)
	wp.warp = 10
	f.waypoints.append(wp)
	f.cargo[Fleet.CARGO_FUEL] = 500
	TurnMessages.clear(s)
	Movement.move_all(s, _content, StarsRandom.new())
	# speed 10 against a safe 5: 175 in 1000 per light year inside (10 to 70)
	assert_int(f.x).is_less(1270)
	assert_int(f.ship_count()).is_equal(2)
	var types := (s.messages[0] as Array).map(func(m: Dictionary) -> String: return m["type"])
	assert_array(types).contains(["message.fleet.mine_stopped"])
	(
		assert_array((s.messages[1] as Array).map(func(m: Dictionary) -> String: return m["type"]))
		. is_equal(["message.fleet.mine_stopped_yours"])
	)


func test_damage_matches_the_worked_example() -> void:
	var s := _game()
	var other := Player.new()
	other.index = 1
	other.relations.assign(["neutral", "neutral"])
	s.players.append(other)
	var field := _field(s, 1, 1200, 1200, 10000)
	var f := _layer(s, 0)
	var wp := Waypoint.new(1300, 1200)
	f.waypoints.append(wp)
	TurnMessages.clear(s)
	# 2 ships with 1 engine: (2 x 100 + 300) x 1 = 500, 250 a ship: more than a Mini Mine
	# Layer's armor, so the stack is destroyed and the fleet with it
	Minefields._hit(s, _content, f, 0, 10)
	assert_bool(f.stacks.is_empty()).is_true()
	assert_str(s.messages[0][0]["type"]).is_equal("message.fleet.mine_annihilated")
	assert_int(s.players[0].ship_design(0).remaining).is_equal(-2)
	# the field loses 10000 div 100 = 100 mines
	assert_int(field.mines).is_equal(9900)


func _laser_design(slot: int, hull: String, lasers: int) -> Design:
	var d := Design.new()
	d.slot = slot
	d.hull = hull
	d.parts.assign([DesignSlot.new("part.beam.laser", lasers)])
	return d


## Player 1 with a fleet of 2 ships carrying 2 lasers each (sweep rate 40) at (1200, 1210), and a
## battle plan attacking `attack`.
func _sweeper(s: GameState, attack: int) -> Fleet:
	var other := Player.new()
	other.index = 1
	other.relations.assign(["neutral", "neutral"])
	other.battle_plans = [{"number": 0, "name": "Plan 0", "attack": attack}]
	other.set_design(_laser_design(0, "hull.scout", 2), false)
	s.players.append(other)
	s.players[0].relations.assign(["neutral", "neutral"])
	var f := s.add_fleet(1, 512)
	f.x = 1200
	f.y = 1210
	f.add_ships(0, 2)
	f.waypoints.append(Waypoint.new(1200, 1210))
	return f


func test_sweep_rates() -> void:
	# count x power x range squared; starbases count one more range; gatlings range 4
	assert_int(PartRules.sweep_rate(_laser_design(0, "hull.scout", 2), _content)).is_equal(20)
	assert_int(PartRules.sweep_rate(_laser_design(0, "hull.space_station", 2), _content)).is_equal(
		80
	)
	var gun := _laser_design(0, "hull.scout", 0)
	gun.parts.assign(
		[DesignSlot.new("part.beam.mini_gun", 1), DesignSlot.new("part.beam.pulsed_sapper", 1)]
	)
	assert_int(PartRules.sweep_rate(gun, _content)).is_equal(13 * 16)


func test_a_fleet_sweeps_a_field_its_plan_attacks() -> void:
	var s := _game()
	var f := _sweeper(s, BattlePlans.ATTACK_NOT_FRIENDS)
	var field := _field(s, 0, 1200, 1200, 1000)
	TurnMessages.clear(s)
	Minefields.sweep_all(s, _content)
	assert_int(field.mines).is_equal(960)
	assert_array(field.known_by).is_equal([1])
	assert_str(s.messages[1][0]["type"]).is_equal("message.fleet.swept_mines")
	assert_array(s.messages[1][0]["params"]).is_equal([512, 40, 0, 0, 1200, 1200])
	assert_str(s.messages[0][0]["type"]).is_equal("message.minefield.swept")
	assert_dict(s.messages[0][0]["goto"]).is_equal({"minefield": 0, "owner": 0})
	# a plan attacking enemies only leaves a neutral's field alone
	s.players[1].battle_plans[0]["attack"] = BattlePlans.ATTACK_ENEMIES
	Minefields.sweep_all(s, _content)
	assert_int(field.mines).is_equal(960)
	s.players[1].relations[0] = "enemy"
	Minefields.sweep_all(s, _content)
	assert_int(field.mines).is_equal(920)
	assert_int(f.ship_count()).is_equal(2)


func test_a_sweep_stops_at_the_sweeper_and_speed_bumps_take_a_third() -> void:
	var s := _game()
	_sweeper(s, BattlePlans.ATTACK_EVERYONE)
	# 10 ly from the center: the field keeps 99 mines, just leaving the fleet outside
	var field := _field(s, 0, 1200, 1200, 120)
	var bump := _field(s, 0, 1200, 1220, 1000, "speed_bump")
	Minefields.sweep_all(s, _content)
	assert_int(field.mines).is_equal(99)
	assert_int(bump.mines).is_equal(1000 - 40 / 3)
	# at the very center a field smaller than the rate goes completely
	field.y = 1210
	field.mines = 30
	Minefields.sweep_all(s, _content)
	assert_bool(s.minefields.has(field)).is_false()


func test_starbases_sweep_fields_of_players_who_are_not_friends() -> void:
	var s := _game()
	_sweeper(s, 0)
	s.players[1].set_design(_laser_design(0, "hull.space_station", 2), true)
	var pl := s.planets[0]
	pl.owner = 1
	pl.starbase = Starbase.new()
	var field := _field(s, 0, 1300, 1290, 1000)
	TurnMessages.clear(s)
	# plan 0 attacks nobody, so only the starbase sweeps: 80 mines
	Minefields.sweep_all(s, _content)
	assert_int(field.mines).is_equal(920)
	assert_array(field.known_by).is_equal([1])
	assert_str(s.messages[1][0]["type"]).is_equal("message.planet.swept_mines")
	assert_dict(s.messages[1][0]["goto"]).is_equal({"planet": pl.id})
	s.players[1].relations[0] = "friend"
	Minefields.sweep_all(s, _content)
	assert_int(field.mines).is_equal(920)


func test_detonation_hits_every_fleet_inside_but_the_owners_layers() -> void:
	var s := _game()
	var f := _sweeper(s, 0)
	s.players[1].ship_design(0).parts.append(DesignSlot.new("part.engine.long_hump_6", 1))
	# a Mini Mine Layer of the field's owner sits inside too: it is spared
	var layer := _layer(s, 0)
	layer.waypoints[0].task = "none"
	var field := _field(s, 0, 1200, 1200, 1000)
	field.detonate = true
	TurnMessages.clear(s)
	Minefields.decay_all(s, _content)
	# player 1's 2 scouts: (2 x 100 + 300) x 1 = 500 raw, 250 a ship, more than a scout's armor
	assert_bool(s.fleets.has(f)).is_false()
	assert_bool(s.fleets.has(layer)).is_true()
	assert_int(layer.stacks[0].damage).is_equal(0)
	assert_str(s.messages[1][0]["type"]).is_equal("message.fleet.mine_annihilated")
	assert_str(s.messages[0][0]["type"]).is_equal("message.minefield.annihilated_yours")
	assert_int(s.messages[0].size()).is_equal(1)
	# decay with the detonation's 25%: 2 + 25 = 27%
	assert_int(field.mines).is_equal(1000 - 270)


func test_a_detonation_can_damage_without_destroying() -> void:
	var s := _game()
	var f := _sweeper(s, 0)
	var d := s.players[1].ship_design(0)
	d.hull = "hull.destroyer"
	d.parts.assign(
		[DesignSlot.new("part.engine.long_hump_6", 1), DesignSlot.new("part.armor.tritanium", 2)]
	)
	var field := _field(s, 0, 1200, 1200, 1000)
	field.detonate = true
	TurnMessages.clear(s)
	Minefields.decay_all(s, _content)
	assert_int(f.ship_count()).is_equal(2)
	assert_int(f.stacks[0].damaged_percent).is_equal(100)
	assert_str(s.messages[1][0]["type"]).is_equal("message.fleet.detonation_damaged")
	assert_array(s.messages[1][0]["params"]).is_equal([33280, 0, 0, 1200, 1200, 500])
	assert_str(s.messages[0][0]["type"]).is_equal("message.fleet.detonation_damaged_yours")
