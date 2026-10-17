extends GdUnitTestSuite
## S22 "Classic production", "Classic fleets", "Classic freight" and S12 "Default warp": the
## toolkit the classic personalities share.

const P := preload("res://core/ai/classic/classic_production.gd")

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## tiny3ai turn 1 as player 1 (homeworld 30, three colony ships there) has it.
func _state() -> GameState:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/golden/tiny3ai/t001.json")
	var result := SaveFile.decode(text, _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	var s := result.state
	s.views.clear()
	for p in s.players:
		s.views.append({"planets": {}, "fleets": {}, "designs": {}, "starbase_designs": {}})
		p.knowledge = {}
	return s


func _world(s: GameState = null, seed_a: int = 3, seed_b: int = 9) -> ClassicWorld:
	return ClassicWorld.build(
		s if s != null else _state(), _content, 1, StarsRandom.new(seed_a, seed_b)
	)


func _home(w: ClassicWorld) -> Planet:
	return w.state.planet(30)


func _types(w: ClassicWorld) -> Array:
	return w.orders.orders.map(func(o: Dictionary) -> String: return o["type"])


# --- Production --------------------------------------------------------------------------------


func test_the_buildable_list_follows_the_original_order() -> void:
	var w := _world()
	var list := P.buildable(w, _home(w))
	var keys := list.map(
		func(q: QueueItem) -> String: return q.item if not q.is_design() else "design"
	)
	# the station docks ships: both ship designs, then starbase designs 1..4 (not 0, the one it
	# has), then installations, alchemy, auto items
	assert_array(keys.slice(0, 6)).is_equal(
		["design", "design", "design", "design", "design", "design"]
	)
	assert_bool(list[0].starbase).is_false()
	assert_int(list[2].design).is_equal(1)
	assert_bool(list[2].starbase).is_true()
	var rest := keys.slice(6)
	assert_array(rest.slice(0, 4)).is_equal([P.FACTORIES, P.MINES, P.DEFENSES, P.ALCHEMY])
	assert_str(rest[rest.size() - 1]).is_equal("production_item.auto_packets")
	# no planetary scanner (it has one), no packets (no mass driver)
	assert_bool(rest.has(P.SCANNER)).is_false()
	assert_bool(rest.has(P.PACKETS[0])).is_false()
	var mines: QueueItem = list.filter(func(q: QueueItem) -> bool: return q.item == P.MINES)[0]
	var race := w.me().race
	assert_int(mines.count).is_equal(
		mini(PlanetEconomy.max_mines(_home(w), race, _content) - _home(w).mines, P.INSTALLATION_CAP)
	)


func test_opening_holds_the_queue_to_the_list() -> void:
	var s := _state()
	s.planet(30).queue.assign([QueueItem.new(P.MINES, 1000), QueueItem.new(P.GENESIS, 1)])
	var w := _world(s)
	w.select_planet(30)
	var e := P.open(w)
	var home := _home(w)
	var room := PlanetEconomy.max_mines(home, w.me().race, _content) - home.mines
	assert_int(e.queue[0].count).is_equal(room)
	assert_int(e.listed(P.standard(P.MINES)).count).is_equal(0)
	# the genesis device is not listed: alchemy x0
	assert_str(e.queue[1].item).is_equal(P.ALCHEMY)
	assert_int(e.queue[1].count).is_equal(0)


func test_adding_opens_caps_and_commits() -> void:
	var w := _world()
	w.select_planet(30)
	P.add(w, P.standard(P.DEFENSES), 5000, P.Mode.APPEND)
	assert_array(_types(w)).is_equal(["production_queue"])
	var q := _home(w).queue
	assert_int(q.size()).is_equal(1)
	assert_int(q[0].count).is_equal(PlanetEconomy.max_defenses(_home(w), w.me().race) - 10)
	assert_object(w.editing).is_null()
	# with an edit open nothing is capped and nothing is committed until asked
	P.open(w)
	P.add(w, P.standard(P.MINES), 5000, P.Mode.TOP)
	assert_int(w.orders.orders.size()).is_equal(1)
	P.commit(w, true)
	# 5000 in 10 bits
	assert_int(_home(w).queue[0].count).is_equal(5000 & 1023)
	assert_str(_home(w).queue[0].item).is_equal(P.MINES)


func test_output_is_surface_plus_mining_less_research() -> void:
	var w := _world()
	var home := _home(w)
	var out := P.output(w, home)
	var copy := home.copy() as Planet
	PlanetEconomy.mine(copy, w.me().race, _content, null)
	assert_int(out[0]).is_equal(copy.surface[0])
	var r := PlanetEconomy.resources(home, w.me().race, _content)
	assert_int(out[3]).is_equal(r - r * w.me().research_percent / 100)


func test_completion_counts_years() -> void:
	var s := _state()
	s.planet(30).queue.assign([QueueItem.new(P.MINES, 1), QueueItem.new(P.FACTORIES, 2000)])
	var w := _world(s)
	assert_array(P.completion(w, _home(w), 0)).is_equal([1, 1])
	var late := P.completion(w, _home(w), 1)
	assert_int(late[0]).is_equal(1)
	assert_int(late[1]).is_equal(P.ESTIMATE_YEARS)


# --- Planning ----------------------------------------------------------------------------------


func test_the_last_pass_fills_the_queue() -> void:
	var w := _world()
	ClassicPlanning.finish_turn(w)
	var q := _home(w).queue
	assert_int(q.size()).is_greater(0)
	var items := q.map(func(i: QueueItem) -> String: return i.item)
	# with minerals to spare: factories at the end, mines at the top
	assert_bool(items.has(P.FACTORIES) or items.has(P.MINES)).is_true()
	if items.has(P.MINES):
		assert_str(items[0]).is_equal(P.MINES)


func test_defenses_for_a_big_population() -> void:
	var s := _state()
	s.planet(30).population = 2000
	var w := _world(s)
	w.select_planet(30)
	P.open(w)
	assert_bool(ClassicPlanning.queue_defenses(w, _home(w))).is_true()
	P.commit(w, true)
	assert_str(_home(w).queue[0].item).is_equal(P.DEFENSES)
	assert_int(_home(w).queue[0].count).is_less_equal(4)


# --- Fleets ------------------------------------------------------------------------------------


func test_new_orders_replace_or_follow() -> void:
	var w := _world()
	var f := w.state.fleet(1, 1)
	var other := w.state.planet(21)
	assert_bool(ClassicFleets.go(w, f, ClassicFleets.planet_waypoint(w, 21, 5))).is_true()
	assert_int(f.waypoints.size()).is_equal(2)
	assert_int(f.waypoints[1].target_id).is_equal(other.id)
	# a waypoint where the fleet is replaces the orders
	assert_bool(ClassicFleets.go(w, f, ClassicFleets.planet_waypoint(w, 30, 4, "scrap"))).is_true()
	assert_int(f.waypoints.size()).is_equal(1)
	assert_str(f.waypoints[0].task).is_equal("scrap")


func test_colony_ships_are_neither_warships_nor_freighters() -> void:
	var w := _world()
	var f := w.state.fleet(1, 1)
	assert_bool(ClassicFleets.is_combat(w, f)).is_false()
	assert_bool(ClassicFleets.is_freighter(w, f)).is_false()


func test_fleets_at_one_place_merge() -> void:
	var w := _world()
	ClassicFleets.merge_by_slots(w, [1])
	var mine := w.state.fleets_of(1)
	# fleet 2 merges into 1; fleet 3 is passed over (it took 2's place in the list)
	assert_int(mine.size()).is_equal(2)
	assert_int(ClassicFleets.ships(w.state.fleet(1, 1))).is_equal(2)


func test_mixed_fleets_split() -> void:
	var s := _state()
	var f := s.fleet(1, 1)
	var scout := ShipStack.new()
	scout.design = 0
	scout.count = 2
	f.stacks.insert(0, scout)
	var w := _world(s)
	ClassicFleets.split_slots(w, [0])
	var wf := w.state.fleet(1, 1)
	assert_bool(ClassicFleets.has_slot(wf, 0)).is_false()
	assert_int(w.state.fleets_of(1).size()).is_equal(4)


func test_minefields_slow_fleets() -> void:
	var s := _state()
	var field := Minefield.new()
	field.owner = 0
	field.x = 1344
	field.y = 1303
	field.mines = 400
	field.seen_by.append(1)
	s.minefields.append(field)
	var f := s.fleet(1, 1)
	var wp := Waypoint.new(1300, 1300)
	wp.warp = 9
	f.waypoints.append(wp)
	var w := _world(s, 5, 6)
	ClassicFleets.avoid_minefields(w)
	var check := StarsRandom.new(5, 6)
	for i in w.own_planets.size() - 1:
		check.random(1)
	var expected := 4 if check.random(10) < 4 else 5
	assert_int(w.state.fleet(1, 1).waypoints[1].warp).is_equal(expected)


func test_wormhole_distance_wraps_in_16_bits() -> void:
	var s := _state()
	var hole := Wormhole.new()
	hole.number = 1
	# 190 light years: 36100, past 32767 in 16 bits
	hole.x = 1344 + 190
	hole.y = 1303
	hole.seen_by.append(1)
	s.views[1]["wormholes"] = [1]
	s.wormholes.append(hole)
	var w := _world(s)
	var found := 0
	for i in 20:
		if ClassicFleets.pick_wormhole(w, 1344, 1303, 10) != null:
			found += 1
	# in reach although far: picked about 70% of the time
	assert_int(found).is_greater(5)


func test_random_planet_draws_once_per_planet_in_reach() -> void:
	var w := _world(null, 7, 8)
	var check := StarsRandom.new(7, 8)
	for i in w.own_planets.size() - 1:
		check.random(1)
	var home := _home(w)
	var pick := ClassicFleets.random_planet(w, home.x, home.y, 100, false)
	var expected := -1
	var seen := 1
	for p in w.state.planets:
		if ClassicFleets.d2(home.x, home.y, p.x, p.y) <= 10000:
			var r := check.random(seen)
			seen += 1
			if r == 0:
				expected = p.id
	assert_int(pick).is_equal(expected)


# --- Freight -----------------------------------------------------------------------------------


func test_cargo_moves_as_orders() -> void:
	var w := _world()
	var f := w.state.fleet(1, 1)
	var moved := ClassicFreight.move_cargo(w, f, {"planet": 30}, Fleet.CARGO_COLONISTS, 5)
	assert_int(moved).is_equal(mini(5, ClassicFreight.cargo_capacity(f, w.me(), _content)))
	assert_array(_types(w)).contains(["cargo_transfer"])


func test_depots_from_turn_20() -> void:
	var s := _state()
	s.turn = 25
	var w := _world(s)
	ClassicFreight.plan_depots(w)
	assert_int(w.memory[ClassicWorld.DEPOT_COUNT]).is_equal(1)
	assert_int(w.memory[ClassicWorld.DEPOT_FIRST]).is_equal(30)
	assert_int(w.memory[0]).is_equal(1 * 20 + 4)
	assert_bool(w.is_depot(30)).is_true()


func test_colony_ships_early_and_on_easy() -> void:
	var w := _world()
	w.me().ai_level = 1
	assert_bool(ClassicFreight.colony_ships(w)["build"]).is_true()
	w.me().ai_level = 0
	w.state.turn = 3
	assert_bool(ClassicFreight.colony_ships(w)["build"]).is_false()


# --- Default warp ------------------------------------------------------------------------------


func test_default_warp_of_the_current_place_is_the_fleets() -> void:
	var w := _world()
	var f := w.state.fleet(1, 1)
	assert_int(WaypointWarp.default_warp(w.state, _content, f, 0, true)).is_equal(
		Retargeting.default_warp(f, w.me(), _content)
	)


func test_a_colonizer_heads_out_at_the_slowest_speed_taking_as_long() -> void:
	var w := _world()
	var f := w.state.fleet(1, 1)
	var wp := Waypoint.new(1344 + 30, 1303)
	f.waypoints.append(wp)
	var warp := WaypointWarp.default_warp(w.state, _content, f, 1, true)
	var dist := 30
	var years := (warp * warp + dist - 1) / (warp * warp)
	# one less would take longer (or the speed is the floor of 2)
	if warp > 2:
		var w2 := warp - 1
		assert_int((w2 * w2 + dist - 1) / (w2 * w2)).is_greater(years)
	assert_int(warp).is_less_equal(WaypointWarp.WARP_FAST)
