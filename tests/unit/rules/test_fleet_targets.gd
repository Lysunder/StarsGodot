extends GdUnitTestSuite
## Spec S12 "Waypoint targets", "Following a fleet" and "Chasing a fleet". The follow set-up's
## "didn't move" message is also checked against the original by terra1 turn 29.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _design(hull := "hull.colony_ship", engine := "part.engine.long_hump_6") -> Design:
	var d := Design.new()
	d.slot = 0
	d.hull = hull
	d.parts.assign([DesignSlot.new(engine, 1)])
	return d


func _game() -> GameState:
	var s := GameState.new()
	s.settings.universe_width = 400
	var p := Player.new()
	p.relations.assign(["neutral"])
	p.set_design(_design(), false)
	p.battle_plans = [{"name": "Default", "primary_target": FleetTargets.TARGET_ARMED}]
	s.players.append(p)
	var pl := Planet.new()
	pl.x = 1200
	pl.y = 1200
	pl.owner = 0
	s.planets.append(pl)
	return s


func _fleet(s: GameState, x := 1200, y := 1200) -> Fleet:
	var f := s.add_fleet(0, 512)
	f.x = x
	f.y = y
	f.planet = 0 if x == 1200 and y == 1200 else -1
	f.add_ships(0, 1)
	f.cargo[Fleet.CARGO_FUEL] = 200
	var wp := Waypoint.new(x, y)
	wp.target = "planet" if f.planet == 0 else "none"
	wp.target_id = f.planet
	f.waypoints.append(wp)
	return f


func _to(f: Fleet, x: int, y: int, warp: int) -> Waypoint:
	var wp := Waypoint.new(x, y)
	wp.warp = warp
	f.waypoints.append(wp)
	return wp


func _target(wp: Waypoint, other: Fleet) -> void:
	wp.target = "fleet"
	wp.target_owner = other.owner
	wp.target_id = other.number


func _types(s: GameState) -> Array:
	return (s.messages[0] as Array).map(func(m: Dictionary) -> String: return m["type"])


func test_a_follower_copies_its_targets_next_waypoint_for_one_turn() -> void:
	var s := _game()
	var leader := _fleet(s)
	_to(leader, 1230, 1240, 5)
	var follower := _fleet(s)
	_target(follower.waypoints[0], leader)
	follower.waypoints[0].task_data = {"raw": [1, 2, 3, 4, 5]}
	TurnMessages.clear(s)
	FleetTargets.resolve(s, _content, StarsRandom.new())
	assert_bool(follower.following).is_true()
	assert_int(follower.waypoints.size()).is_equal(2)
	assert_int(follower.waypoints[1].x).is_equal(1230)
	assert_int(follower.waypoints[1].warp).is_equal(5)
	assert_dict(follower.waypoints[1].task_data).is_equal({"raw": [1, 2, 3, 4, 5]})
	Movement.move_all(s, _content, StarsRandom.new())
	assert_int(follower.x).is_equal(leader.x)
	assert_int(follower.waypoints.size()).is_equal(1)
	assert_str(follower.waypoints[0].target).is_equal("none")
	assert_array(_types(s)).contains(["message.fleet.follow_done"])


func test_following_a_fleet_going_nowhere_fails() -> void:
	var s := _game()
	var leader := _fleet(s)
	var follower := _fleet(s)
	_target(follower.waypoints[0], leader)
	TurnMessages.clear(s)
	FleetTargets.resolve(s, _content, StarsRandom.new())
	assert_bool(follower.following).is_false()
	assert_array(_types(s)).is_equal(["message.fleet.follow_failed"])
	assert_array(s.messages[0][0]["params"]).is_equal([follower.number])


func test_a_chaser_closes_in_on_a_moving_target() -> void:
	var s := _game()
	var target := _fleet(s)
	_to(target, 1200, 1225, 5)
	var chaser := _fleet(s, 1200, 1170)
	_target(_to(chaser, 1200, 1200, 9), target)
	TurnMessages.clear(s)
	Movement.move_all(s, _content, StarsRandom.new())
	# the target moves its 25 ly first; the chaser's 81 ly reach it where it stopped
	assert_int(target.y).is_equal(1225)
	assert_int(chaser.y).is_equal(1225)
	assert_int(chaser.waypoints.size()).is_equal(1)
	assert_int(chaser.cargo[Fleet.CARGO_FUEL]).is_less(200)


func test_a_chaser_of_a_fleet_that_has_moved_uses_its_whole_budget() -> void:
	var s := _game()
	var target := _fleet(s)
	_to(target, 1200, 1400, 4)
	var chaser := _fleet(s, 1200, 1100)
	_target(_to(chaser, 1200, 1200, 5), target)
	Movement.move_all(s, _content, StarsRandom.new())
	assert_int(target.y).is_equal(1216)
	assert_int(chaser.y).is_equal(1125)
	var straight := _fleet(s, 1200, 1100)
	_to(straight, 1200, 1125, 5)
	var fuel := Movement.fuel_needed(straight, s.players[0], 5, 25, _content)
	assert_int(chaser.cargo[Fleet.CARGO_FUEL]).is_equal(200 - fuel)


func test_a_waypoint_whose_fleet_is_gone_takes_one_left_there() -> void:
	var s := _game()
	var chaser := _fleet(s, 1100, 1100)
	var wp := _to(chaser, 1250, 1250, 5)
	wp.target = "fleet"
	wp.target_owner = 0
	wp.target_id = 77
	var left := _fleet(s, 1250, 1250)
	FleetTargets.update(s, _content, StarsRandom.new())
	assert_int(wp.target_id).is_equal(left.number)
	assert_bool(left.claimed).is_true()


func test_hull_classes_for_battle_plan_targets() -> void:
	var s := _game()
	var colony := _fleet(s)
	var owner := s.players[0]
	(
		assert_bool(FleetTargets.has_class(colony, owner, FleetTargets.TARGET_UNARMED, _content))
		. is_true()
	)
	(
		assert_bool(FleetTargets.has_class(colony, owner, FleetTargets.TARGET_ARMED, _content))
		. is_false()
	)
	var warship := _design("hull.destroyer")
	warship.slot = 1
	owner.set_design(warship, false)
	colony.add_ships(1, 1)
	(
		assert_bool(FleetTargets.has_class(colony, owner, FleetTargets.TARGET_ARMED, _content))
		. is_true()
	)
	assert_bool(FleetTargets.has_class(colony, owner, 1, _content)).is_false()


func _wormholes(s: GameState) -> Array[Wormhole]:
	var near := s.add_wormhole(100)
	near.x = 1220
	near.y = 1200
	var far := s.add_wormhole(100)
	far.x = 1500
	far.y = 1500
	near.other_end = far.number
	far.other_end = near.number
	return [near, far]


func test_a_fleet_arriving_on_its_wormhole_comes_out_at_the_far_end() -> void:
	var s := _game()
	var ends := _wormholes(s)
	var f := _fleet(s)
	var wp := _to(f, 1220, 1200, 5)
	wp.target = "wormhole"
	wp.target_id = ends[0].number
	TurnMessages.clear(s)
	Movement.move_all(s, _content, StarsRandom.new())
	assert_int(f.x).is_equal(1500)
	assert_int(f.y).is_equal(1500)
	assert_int(f.waypoints.size()).is_equal(1)
	assert_array(ends[0].seen_by).is_equal([0])
	assert_array(ends[1].seen_by).is_equal([0])
	assert_array(ends[0].tracked_by).is_empty()
	assert_array(ends[1].tracked_by).is_equal([0])


func test_a_wormhole_that_moved_out_of_sight_leaves_its_waypoint_behind() -> void:
	var s := _game()
	var ends := _wormholes(s)
	var f := _fleet(s)
	var wp := _to(f, 1220, 1200, 5)
	wp.target = "wormhole"
	wp.target_id = ends[0].number
	ends[0].x = 1230
	TurnMessages.clear(s)
	FleetTargets.update(s, _content, StarsRandom.new())
	assert_str(wp.target).is_equal("none")
	assert_int(wp.x).is_equal(1220)
	assert_array(_types(s)).is_equal(["message.fleet.wormhole_vanished"])
	# a wormhole the owner keeps track of is followed
	wp.target = "wormhole"
	wp.target_id = ends[0].number
	ends[0].tracked_by.assign([0])
	FleetTargets.update(s, _content, StarsRandom.new())
	assert_int(wp.x).is_equal(1230)
