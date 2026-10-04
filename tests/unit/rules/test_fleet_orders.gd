extends GdUnitTestSuite
## Spec S11 "Fleet orders": split, ship moves (cargo, fuel, damage with fix B32), merges, deleting
## fleets, and the order checks.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _game() -> GameState:
	var s := GameState.new()
	for i in 2:
		var p := Player.new()
		p.index = i
		p.relations.assign(["neutral", "neutral"])
		var d := Design.new()
		d.slot = 0
		d.hull = "hull.colony_ship"
		(
			d
			. parts
			. assign(
				[
					DesignSlot.new("part.engine.long_hump_6", 1),
					DesignSlot.new("part.mechanical.colonization_module", 1),
				]
			)
		)
		p.set_design(d, false)
		var scout := d.copy() as Design
		scout.slot = 1
		p.set_design(scout, false)
		p.battle_plans = [{}, {}]
		s.players.append(p)
	var pl := Planet.new()
	pl.id = 0
	pl.x = 100
	pl.y = 100
	s.planets.append(pl)
	return s


func _fleet(s: GameState, owner := 0, ships := 3) -> Fleet:
	var f := s.add_fleet(owner, 512)
	f.x = 100
	f.y = 100
	f.planet = 0
	f.add_ships(0, ships)
	var wp := Waypoint.new(100, 100)
	wp.target = "planet"
	wp.target_id = 0
	f.waypoints.append(wp)
	return f


func _apply(s: GameState, player: int, order: Dictionary) -> String:
	return OrderRules.apply(s, _content, player, order)


func _cap(kind: String) -> int:
	var d := _game().players[0].ship_design(0)
	if kind == "fuel":
		return PartRules.fuel_capacity(d, _content)
	return PartRules.cargo_capacity(d, _content)


func test_split_then_move_takes_a_share_of_cargo_and_fuel() -> void:
	var s := _game()
	var a := _fleet(s)
	a.repeat = true
	a.battle_plan = 1
	a.cargo.assign([30, 0, 0, 0, 300])
	var wp := Waypoint.new(200, 200)
	wp.warp = 5
	a.waypoints.append(wp)
	assert_str(_apply(s, 0, {"type": "fleet_split", "owner": 0, "fleet": 0})).is_empty()
	var b := s.fleet(0, 1)
	assert_object(b).is_not_null()
	assert_array([b.planet, b.repeat, b.battle_plan, b.waypoints.size()]).is_equal([0, true, 1, 2])
	assert_int(b.ship_count()).is_equal(0)
	var order := {
		"type": "fleet_move_ships",
		"owner": 0,
		"fleet": 1,
		"other": 0,
		"ships": [{"design": 0, "count": 1}],
	}
	assert_str(_apply(s, 0, order)).is_empty()
	assert_array([a.ship_count(), b.ship_count()]).is_equal([2, 1])
	assert_array(a.cargo).is_equal([20, 0, 0, 0, 200])
	assert_array(b.cargo).is_equal([10, 0, 0, 0, 100])


func test_cargo_leftover_goes_one_unit_per_type() -> void:
	var s := _game()
	var a := _fleet(s, 0, 2)
	var b := _fleet(s, 0, 1)
	a.cargo.assign([1, 1, 1, 0, 0])
	FleetOrders.move_ships(s, _content, b, a, {0: 1}, 0)
	# lost capacity is half of a's, so one of the three units moves: ironium (the leftover pass)
	assert_array(b.cargo).is_equal([1, 0, 0, 0, 0])
	assert_array(a.cargo).is_equal([0, 1, 1, 0, 0])


func test_moving_every_ship_deletes_the_fleet() -> void:
	var s := _game()
	var a := _fleet(s, 0, 2)
	var b := _fleet(s, 0, 1)
	a.cargo.assign([5, 0, 0, 0, 40])
	FleetOrders.move_ships(s, _content, b, a, {0: 9}, 0)
	assert_int(s.fleets.size()).is_equal(1)
	assert_array([b.ship_count(), b.cargo[0], b.cargo[4]]).is_equal([3, 5, 40])


func test_damaged_ships_move_first_and_damage_is_averaged() -> void:
	var s := _game()
	var a := _fleet(s, 0, 4)
	var b := _fleet(s, 0, 2)
	a.stacks[0].damaged_percent = 50
	a.stacks[0].damage = 100
	b.stacks[0].damaged_percent = 50
	b.stacks[0].damage = 200
	FleetOrders.move_ships(s, _content, b, a, {0: 1}, 0)
	# Fix B32: (100 + 200) / 2 damaged ships, not / 3 ships.
	assert_array([b.stacks[0].damage, b.stacks[0].damaged_percent]).is_equal([150, 67])
	assert_array([a.stacks[0].damage, a.stacks[0].damaged_percent]).is_equal([100, 34])
	# Into an undamaged stack: the damage comes along.
	var c := _fleet(s, 0, 1)
	FleetOrders.move_ships(s, _content, c, a, {0: 2}, 0)
	assert_array([c.stacks[0].damage, c.stacks[0].damaged_percent]).is_equal([100, 34])
	assert_array([a.stacks[0].damage, a.stacks[0].damaged_percent]).is_equal([0, 0])


func test_merge_adds_ships_cargo_and_combines_damage() -> void:
	var s := _game()
	var target := _fleet(s, 0, 2)
	var plain := _fleet(s, 0, 2)
	var hurt := _fleet(s, 0, 1)
	hurt.add_ships(1, 1)
	target.stacks[0].damaged_percent = 50
	target.stacks[0].damage = 100
	hurt.stacks[0].damaged_percent = 10
	hurt.stacks[0].damage = 300
	plain.cargo.assign([1, 2, 3, 4, 5])
	hurt.cargo.assign([0, 0, 0, 0, 10])
	(
		assert_str(_apply(s, 0, {"type": "fleet_merge", "owner": 0, "fleet": 0, "fleets": []}))
		. is_empty()
	)
	assert_int(s.fleets.size()).is_equal(1)
	assert_array([target.stacks.size(), target.stacks[0].count]).is_equal([2, 5])
	# 1 + max(1, 10% of 1) = 2 damaged ships with 400 damage over 5 ships
	assert_array([target.stacks[0].damaged_percent, target.stacks[0].damage]).is_equal([40, 200])
	assert_array(target.cargo).is_equal([1, 2, 3, 4, 15])


func test_waypoints_targeting_a_deleted_fleet_are_retargeted() -> void:
	var s := _game()
	var target := _fleet(s, 0, 1)
	var merged := _fleet(s, 0, 1)
	var chaser := _fleet(s, 1, 1)
	chaser.x = 0
	chaser.planet = -1
	var wp := Waypoint.new(100, 100)
	wp.target = "fleet"
	wp.target_owner = 0
	wp.target_id = merged.number
	chaser.waypoints.append(wp)
	FleetOrders.merge(s, target, [merged] as Array[Fleet], 0)
	assert_array([wp.target, wp.target_owner, wp.target_id]).is_equal(["fleet", 0, target.number])
	FleetOrders.delete_fleet(s, target, 0)
	assert_array([wp.target, wp.target_id]).is_equal(["planet", 0])


func test_orders_are_checked() -> void:
	var s := _game()
	_fleet(s, 0, 2)
	var far := _fleet(s, 0, 1)
	far.x = 300
	_fleet(s, 1, 1)
	var move := {
		"type": "fleet_move_ships",
		"owner": 0,
		"fleet": 0,
		"other": 1,
		"ships": [{"design": 0, "count": 1}],
	}
	assert_str(_apply(s, 0, move)).is_equal("fleets are not at the same place")
	assert_str(_apply(s, 1, move)).is_equal("not the player's fleet")
	var o := {"type": "fleet_repeat", "owner": 0, "fleet": 0, "repeat": true}
	assert_str(_apply(s, 0, o)).is_empty()
	assert_bool(s.fleet(0, 0).repeat).is_true()
	o = {"type": "fleet_rename", "owner": 0, "fleet": 0, "name": "Pathfinders"}
	assert_str(_apply(s, 0, o)).is_empty()
	assert_str(s.fleet(0, 0).name).is_equal("Pathfinders")
	o["name"] = "x".repeat(32)
	assert_str(_apply(s, 0, o)).is_equal("bad fleet name")
	o = {"type": "fleet_battle_plan", "owner": 0, "fleet": 0, "plan": 2}
	assert_str(_apply(s, 0, o)).is_equal("no such battle plan")
	o["plan"] = 1
	assert_str(_apply(s, 0, o)).is_empty()
	assert_int(s.fleet(0, 0).battle_plan).is_equal(1)
