extends GdUnitTestSuite
## Spec S15 "Orders changed by sight".

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _world() -> GameState:
	var s := GameState.new()
	for i in 2:
		var p := Player.new()
		p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
		p.race.primary_trait = "trait.prt.HE"
		p.race.lesser_traits.assign([])
		p.tech_levels.assign([0, 0, 0, 0, 3, 0])
		p.index = i
		p.relations.assign(["neutral", "enemy"] if i == 0 else ["enemy", "neutral"])
		p.battle_plans = [{"number": 0, "attack": 3, "primary_target": 1}]
		s.players.append(p)
	return s


func _design(slot: int, parts: Array) -> Design:
	var d := Design.new()
	d.slot = slot
	d.hull = "hull.scout"
	var slots: Array[DesignSlot] = []
	for pc: Array in parts:
		slots.append(DesignSlot.new(pc[0], pc[1]))
	d.parts.assign(slots)
	return d


func _fleet(s: GameState, owner: int, parts: Array, x: int, y: int, planet := -1) -> Fleet:
	var p := s.player(owner)
	var slot := p.ship_designs.size()
	p.set_design(_design(slot, parts), false)
	var f := s.add_fleet(owner, 512)
	f.x = x
	f.y = y
	f.planet = planet
	f.add_ships(slot, 1)
	f.waypoints.append(Waypoint.new(x, y))
	return f


func _planet(s: GameState, x: int, y: int) -> Planet:
	var pl := Planet.new()
	pl.id = s.planets.size()
	pl.x = x
	pl.y = y
	s.planets.append(pl)
	return pl


## Scanning then retargeting for player 0, as the end of the turn does.
func _write(s: GameState) -> void:
	s.messages = [[], []]
	s.views.clear()
	var sight := Scanning.record_player(s, _content, 0, null)
	Retargeting.run(s, _content, 0, sight)
	Scanning.finish(s)


func _types(s: GameState) -> Array:
	return s.messages[0].map(func(m: Dictionary) -> String: return m.type)


func test_default_warp() -> void:
	var s := _world()
	var cases := [
		["part.engine.settler_s_delight", 6],
		["part.engine.quick_jump_5", 5],
		["part.engine.fuel_mizer", 4],
		["part.engine.sub_galactic_fuel_scoop", 5],
		["part.engine.trans_galactic_drive", 9],
		["part.engine.interspace_10", 10],
		["part.engine.galaxy_scoop", 10],
	]
	for c: Array in cases:
		var f := _fleet(s, 0, [[c[0], 1]], 1000, 1000)
		(
			assert_int(Retargeting.default_warp(f, s.player(0), _content))
			. override_failure_message(str(c))
			. is_equal(c[1])
		)
	var none := _fleet(s, 0, [], 1000, 1000)
	assert_int(Retargeting.default_warp(none, s.player(0), _content)).is_equal(0)
	# a fleet goes as fast as its slowest design allows
	none.stacks.clear()
	none.add_ships(0, 1)
	none.add_ships(4, 1)
	assert_int(Retargeting.default_warp(none, s.player(0), _content)).is_equal(6)


func test_lost_fleet_targets() -> void:
	var s := _world()
	var pl := _planet(s, 1300, 1000)
	var hunter := _fleet(s, 0, [["part.scanner.rhino_scanner", 1]], 1000, 1000)
	var near := _fleet(s, 1, [], 1020, 1000)
	var far := _fleet(s, 1, [], 1200, 1000)
	var hiding := _fleet(s, 1, [], 1300, 1000, pl.id)
	for target: Fleet in [near, far, hiding]:
		var wp := Waypoint.new(target.x, target.y)
		wp.target = "fleet"
		wp.target_owner = 1
		wp.target_id = target.number
		hunter.waypoints.append(wp)
	var gone := Waypoint.new(1500, 1500)
	gone.target = "fleet"
	gone.target_owner = 1
	gone.target_id = 99
	hunter.waypoints.append(gone)
	_write(s)
	(
		assert_array(_types(s))
		. is_equal(
			[
				"message.fleet.target_out_of_range",
				"message.fleet.target_behind_planet",
				"message.fleet.target_gone",
			]
		)
	)
	assert_array(s.messages[0][1].params).is_equal([0, pl.id])
	assert_array(s.messages[0][2].params).is_equal([0, 512 + 99])
	var targets := hunter.waypoints.map(func(w: Waypoint) -> String: return w.target)
	assert_array(targets).is_equal(["none", "fleet", "none", "planet", "none"])
	# the lost waypoint keeps the place the fleet was last seen
	assert_int(hunter.waypoints[2].x).is_equal(1200)


func test_lost_objects_and_waypoint_zero() -> void:
	var s := _world()
	var pl := _planet(s, 1000, 1000)
	var f := _fleet(s, 0, [], 1000, 1000, pl.id)
	f.waypoints[0].target = "fleet"
	f.waypoints[0].target_owner = 1
	f.waypoints[0].target_id = 0
	var field := s.add_minefield(1, 512)
	field.x = 1500
	field.y = 1500
	var w := s.add_wormhole(100)
	w.x = 1800
	w.y = 1800
	for obj: Array in [["minefield", 1, field.number], ["wormhole", -1, w.number]]:
		var wp := Waypoint.new(1500, 1500)
		wp.target = obj[0]
		wp.target_owner = obj[1]
		wp.target_id = obj[2]
		f.waypoints.append(wp)
	_write(s)
	assert_str(f.waypoints[0].target).is_equal("planet")
	assert_int(f.waypoints[0].target_id).is_equal(pl.id)
	assert_array(_types(s)).is_equal(
		["message.fleet.minefield_vanished", "message.fleet.wormhole_vanished"]
	)
	assert_str(f.waypoints[1].target).is_equal("none")
	assert_str(f.waypoints[2].target).is_equal("none")


func test_patrol_intercepts_the_nearest_fleet_in_range() -> void:
	var s := _world()
	var patrol := _fleet(
		s, 0, [["part.engine.settler_s_delight", 1], ["part.scanner.rhino_scanner", 1]], 1000, 1000
	)
	patrol.waypoints[0].task = "patrol"
	# automatic speed, range 50 ly
	patrol.waypoints[0].task_data = {"raw": [0, 0, 0, 0, 0]}
	patrol.repeat = true
	var close := _fleet(s, 1, [], 1030, 1000)
	_fleet(s, 1, [], 1010, 1030)
	_write(s)
	assert_array(_types(s)).is_equal(["message.fleet.patrol_intercept"])
	assert_array(s.messages[0][0].params).is_equal([0, 512 + close.number])
	assert_int(patrol.waypoints.size()).is_equal(3)
	var wp1 := patrol.waypoints[1]
	assert_str(wp1.target).is_equal("fleet")
	assert_int(wp1.target_id).is_equal(close.number)
	assert_str(wp1.task).is_equal("patrol")
	assert_int(wp1.warp).is_equal(6)
	# a repeating patrol comes back to its post
	assert_int(patrol.waypoints[2].x).is_equal(1000)
	assert_str(patrol.waypoints[2].task).is_equal("patrol")


func test_patrol_needs_a_target_in_range_and_attacked() -> void:
	var s := _world()
	var patrol := _fleet(s, 0, [["part.scanner.dolphin_scanner", 1]], 1000, 1000)
	patrol.waypoints[0].task = "patrol"
	patrol.waypoints[0].task_data = {"raw": [7, 0, 0, 0, 0]}
	# in view, but 54 ly away: beyond a 50 ly patrol range
	_fleet(s, 1, [], 1045, 1030)
	_write(s)
	assert_int(patrol.waypoints.size()).is_equal(1)
	# range 100 ly reaches it; a plan that attacks nobody doesn't
	patrol.waypoints[0].task_data = {"raw": [7, 1, 0, 0, 0]}
	s.player(0).battle_plans = [{"number": 0, "attack": 0, "primary_target": 1}]
	_write(s)
	assert_int(patrol.waypoints.size()).is_equal(1)
	s.player(0).battle_plans = [{"number": 0, "attack": 1, "primary_target": 1}]
	_write(s)
	assert_int(patrol.waypoints.size()).is_equal(2)
	assert_int(patrol.waypoints[1].warp).is_equal(7)
