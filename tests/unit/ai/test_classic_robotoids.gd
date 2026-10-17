extends GdUnitTestSuite
## M12: the original's Robotoids (S22 "Robotoids"): designs by tech, this turn's thresholds, the
## target score, invasions, colony ships, and whole games of tiny3ai's two computer players.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _load(turn: int) -> GameState:
	var path := "res://tests/fixtures/golden/tiny3ai/t%03d.json" % turn
	var result := SaveFile.decode(FileAccess.get_file_as_string(path), _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	return result.state


func _state() -> GameState:
	var s := _load(1)
	s.views.clear()
	for p in s.players:
		s.views.append({"planets": {}, "fleets": {}, "designs": {}, "starbase_designs": {}})
		p.knowledge = {}
	return s


func _world(s: GameState = null, level: int = 0) -> ClassicWorld:
	if s == null:
		s = _state()
	s.player(1).ai_level = level
	return ClassicWorld.build(s, _content, 1, StarsRandom.new(3, 9), ClassicWorld.ROBOTOIDS)


func _robotoids(w: ClassicWorld) -> ClassicRobotoids:
	var r := ClassicRobotoids.new()
	r.w = w
	r.turn = w.state.turn
	r.level = w.me().ai_level
	r._thresholds()
	return r


func _set_tech(w: ClassicWorld, level: int) -> void:
	w.me().tech_levels.assign([level, level, level, level, level, level])


func _hull(w: ClassicWorld, slot: int) -> String:
	var d := w.me().ship_design(slot)
	return "" if d == null else d.hull


## Player 1 gets player 0's destroyer design in the slots of `ships`, and its fleet 1 those ships
## instead of its colony ship.
func _warships(s: GameState, ships: Dictionary) -> Fleet:
	var me := s.player(1)
	var slots := ships.keys()
	slots.sort()
	for slot: int in slots:
		var d := s.player(0).ship_design(4).copy() as Design
		d.slot = slot
		me.ship_designs.append(d)
	var f := s.fleet(1, 1)
	f.stacks.clear()
	for slot: int in slots:
		var stack := ShipStack.new()
		stack.design = slot
		stack.count = ships[slot]
		f.stacks.append(stack)
	return f


## Moves player 1's fleet 1 to planet `id`.
func _move_to(s: GameState, id: int) -> Fleet:
	var f := s.fleet(1, 1)
	var p := s.planet(id)
	f.x = p.x
	f.y = p.y
	f.planet = id
	f.waypoints.resize(1)
	f.waypoints[0].x = p.x
	f.waypoints[0].y = p.y
	f.waypoints[0].target = "planet"
	f.waypoints[0].target_id = id
	return f


func _orders(w: ClassicWorld, type: String) -> Array:
	return w.orders.orders.filter(func(o: Dictionary) -> bool: return o["type"] == type)


# --- Designs -----------------------------------------------------------------------------------


func test_designs_follow_the_tech() -> void:
	var w := _world()
	_set_tech(w, 8)
	ClassicRobotoids.designs(w)
	# a privateer freighter, and a destroyer where the Nubian's hull is out of reach
	assert_str(_hull(w, 11)).is_equal("hull.privateer")
	assert_str(_hull(w, 12)).is_empty()
	assert_str(_hull(w, 14)).is_equal("hull.destroyer")
	assert_str(_hull(w, 2)).is_empty()
	assert_str(_hull(w, 0)).is_equal("hull.scout")


func test_designs_at_the_top_of_the_tech() -> void:
	var w := _world()
	_set_tech(w, 26)
	ClassicRobotoids.designs(w)
	assert_str(_hull(w, 11)).is_equal("hull.meta_morph")
	assert_str(_hull(w, 14)).is_equal("hull.nubian")
	# slot 15 takes the Nubian too
	assert_str(_hull(w, 15)).is_equal("hull.nubian")
	assert_str(_hull(w, 2)).is_equal("hull.meta_morph")
	assert_str(_hull(w, 6)).is_equal("hull.battleship")
	# the munitions battleship needs the Mystery Trader's part: a B-52
	assert_str(_hull(w, 9)).is_equal("hull.b_52_bomber")
	# each later slot waits for the one before to age
	for slot in [3, 4, 7, 8, 10, 12, 13]:
		assert_str(_hull(w, slot)).is_empty()
	w.state.turn += 13
	ClassicRobotoids.designs(w)
	assert_str(_hull(w, 3)).is_equal("hull.meta_morph")
	assert_str(_hull(w, 12)).is_empty()
	w.state.turn += 2
	ClassicRobotoids.designs(w)
	assert_str(_hull(w, 12)).is_equal("hull.meta_morph")
	assert_str(_hull(w, 10)).is_empty()
	assert_str(_hull(w, 7)).is_empty()


func test_harder_players_replace_the_scout_with_a_mine_layer() -> void:
	var w := _world(null, 2)
	_set_tech(w, 6)
	ClassicRobotoids.designs(w)
	assert_str(_hull(w, 0)).is_equal("hull.frigate")
	var w0 := _world(null, 0)
	_set_tech(w0, 6)
	ClassicRobotoids.designs(w0)
	assert_str(_hull(w0, 0)).is_equal("hull.scout")


# --- Thresholds and targets --------------------------------------------------------------------


func test_thresholds_grow_late() -> void:
	var r := _robotoids(_world())
	var cases := [[1, 4, 6], [115, 4, 6], [122, 4, 7], [140, 5, 7], [400, 18, 12], [2000, 50, 12]]
	for case: Array in cases:
		r.turn = case[0]
		r._thresholds()
		assert_int(r.escort).is_equal(case[1])
		assert_int(r.bombers).is_equal(case[2])


func test_target_score_favours_near_planets() -> void:
	var w := _world()
	var r := _robotoids(w)
	var home := w.state.planet(30)
	var other := w.state.planet(19)
	other.owner = 2
	other.population_estimate = 0
	# not worth anything until marked
	assert_int(r.score(home, other, false)).is_equal(0)
	r._mark_targets()
	assert_int((w.planet_info[19] as PackedByteArray)[9]).is_equal(1)
	# worth 1 (no people seen, no starbase), 149 by 199 light years away: 2 more
	assert_int(r.score(home, other, false)).is_equal(3)
	assert_int(r.score(home, home, false)).is_equal(0)
	# player 2 is a computer player: spared when computer players form alliances
	assert_int(r.score(home, other, true)).is_equal(0)
	# a planet a warship heads for counts on a draw of 1 in 4
	ClassicFleets.info_set(w, 19, 10, 1 | 0x80)
	var seen := {}
	for i in 40:
		seen[r.score(home, other, false)] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([0, 0x83])


# --- Invasions ---------------------------------------------------------------------------------


func test_fleets_gather_at_home_until_strong_enough() -> void:
	var s := _state()
	_warships(s, {2: 3, 9: 6})
	var w := _world(s)
	w.state.planet(19).owner = 2
	var r := _robotoids(w)
	r._mark_targets()
	r.invade(w.state.fleet(1, 1))
	# strength 3, under 4: it stays
	assert_array(w.orders.orders).is_empty()
	w.state.fleet(1, 1).stack_for(2).count = 4
	r.invade(w.state.fleet(1, 1))
	var adds := _orders(w, "waypoint_add")
	assert_int(adds.size()).is_equal(1)
	assert_int(adds[0]["waypoint"]["target_id"]).is_equal(19)
	assert_int(adds[0]["waypoint"]["warp"]).is_equal(4)
	assert_int((w.planet_info[19] as PackedByteArray)[10] & 0x80).is_equal(0x80)


func test_troops_are_dropped_when_they_can_take_the_planet() -> void:
	var s := _state()
	_warships(s, {2: 2, 9: 2})
	_move_to(s, 19)
	var w := _world(s)
	var p := w.state.planet(19)
	p.owner = 2
	p.population_estimate = 10
	p.defense_estimate = 0
	var r := _robotoids(w)
	var fleet := w.state.fleet(1, 1)
	# needed: 10 x 400 / (100 - 4) = 41; with 100 aboard (100 / 5 <= 41) it waits
	fleet.cargo[Fleet.CARGO_COLONISTS] = 100
	r.invade(fleet)
	assert_array(_orders(w, "cargo_transfer")).is_empty()
	# with 300 aboard it drops the larger of half (150) and 41 x 5 / 4
	fleet.cargo[Fleet.CARGO_COLONISTS] = 300
	r.invade(fleet)
	var drops := _orders(w, "cargo_transfer")
	assert_int(drops.size()).is_equal(1)
	assert_int(drops[0]["amounts"][Fleet.CARGO_COLONISTS]).is_equal(-150)


func test_harder_colony_ships_drop_their_colonists_on_enemies() -> void:
	var s := _state()
	s.turn = 10
	_move_to(s, 19).cargo[Fleet.CARGO_COLONISTS] = 20
	var w := _world(s, 2)
	w.state.planet(19).owner = 2
	_robotoids(w)._colony_ship(w.state.fleet(1, 1))
	var here := _orders(w, "waypoint_change")
	assert_int(here.size()).is_equal(1)
	var wp: Dictionary = here[0]["waypoint"]
	assert_str(wp["task"]).is_equal("transport")
	assert_str(wp["task_data"]["cargo"][Fleet.CARGO_COLONISTS]["action"]).is_equal("unload_all")
	# then on to the nearest planet of its own with a starbase
	assert_int(_orders(w, "waypoint_add")[0]["waypoint"]["target_id"]).is_equal(30)
	# not on an Alternate Reality race's planet
	var s2 := _state()
	s2.turn = 10
	_move_to(s2, 19).cargo[Fleet.CARGO_COLONISTS] = 20
	s2.player(2).race.primary_trait = "trait.prt.AR"
	var w2 := _world(s2, 2)
	w2.state.planet(19).owner = 2
	_robotoids(w2)._colony_ship(w2.state.fleet(1, 1))
	for o: Dictionary in _orders(w2, "waypoint_change"):
		assert_str(o["waypoint"]["task"]).is_not_equal("transport")


# --- Whole games -------------------------------------------------------------------------------


## Plays `turns` turns, the computer players' worlds built by hand so that orders their worlds
## refused show; returns every refusal (world and host).
func _play(s: GameState, turns: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t in turns:
		var sets: Array[OrderSet] = []
		var rng := s.rng.get_stream(RngStreams.CLASSIC)
		for p in s.players:
			if p.is_human():
				continue
			var w := ClassicWorld.build(s, _content, p.index, rng, ClassicWorld.ROBOTOIDS)
			ClassicRobotoids.play(w)
			var memory := w.memory_order()
			if not memory.is_empty():
				w.order(memory)
			for reason in w.rejected:
				out.append("turn %d player %d world: %s" % [s.turn, p.index, reason])
			sets.append(w.orders)
		for reason in StandardTurn.generate(s, _content, sets):
			out.append("turn %d host: %s" % [s.turn, reason])
	return out


func test_robotoids_play_without_refused_orders() -> void:
	var s := _load(0)
	var refused := _play(s, 100)
	assert_array(Array(refused)).is_empty()
	for p in [1, 2]:
		var owned := s.planets.filter(func(pl: Planet) -> bool: return pl.owner == p)
		assert_int(owned.size()).is_greater_equal(10)
		assert_int(s.player(p).research_percent).is_equal(15)
		# freighters (a privateer retired after 50 turns is a meta morph by then) and warships
		assert_object(s.player(p).ship_design(11)).is_not_null()
		assert_str(s.player(p).ship_design(14).hull).is_equal("hull.destroyer")


func test_the_brain_plays_in_the_ai_step() -> void:
	var def := _content.get_def("ai_personality", "ai_personality.robotoids")
	assert_str(def["brain"]).is_equal(AiBrains.ROBOTOIDS)
	assert_object(AiBrains.create(AiBrains.ROBOTOIDS)).is_instanceof(ClassicBrain)
	var games: Array[GameState] = [_load(0), _load(0)]
	for s in games:
		for t in 25:
			var given: Array[OrderSet] = []
			var errors := PackedStringArray()
			var sets := ComputerPlayers.add_orders(s, _content, given, errors)
			assert_array(Array(errors)).is_empty()
			assert_array(Array(StandardTurn.generate(s, _content, sets))).is_empty()
	assert_bool(games[0].equals(games[1])).is_true()
	# the freighter depots are kept in the memory from turn 20
	var memory: Array = games[0].player(1).knowledge.get(ClassicWorld.MEMORY_KEY, [])
	assert_int(memory.size()).is_greater(2)
	assert_int(memory[ClassicWorld.DEPOT_COUNT]).is_greater(0)
