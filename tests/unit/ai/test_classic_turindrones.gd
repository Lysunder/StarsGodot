extends GdUnitTestSuite
## M12: the original's Turindrones (S22 "Turindrones"): designs by tech, thresholds, the planet
## marks, warships hunting and exploring (`AI_DirectFleet`), miners moving on, and whole games
## of tiny3ai's two computer players played as Turindrones.

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


func _world(s: GameState = null) -> ClassicWorld:
	if s == null:
		s = _state()
	return ClassicWorld.build(s, _content, 1, StarsRandom.new(3, 9), ClassicWorld.TURINDRONES)


func _turindrones(w: ClassicWorld) -> ClassicTurindrones:
	var t := ClassicTurindrones.new()
	t.w = w
	t.turn = w.state.turn
	t._thresholds()
	return t


func _set_tech(w: ClassicWorld, level: int) -> void:
	w.me().tech_levels.assign([level, level, level, level, level, level])


func _hull(w: ClassicWorld, slot: int) -> String:
	var d := w.me().ship_design(slot)
	return "" if d == null else d.hull


# --- Designs -----------------------------------------------------------------------------------


func test_designs_follow_the_tech() -> void:
	var w := _world()
	_set_tech(w, 8)
	ClassicTurindrones.designs(w)
	assert_str(_hull(w, 9)).is_empty()
	assert_str(_hull(w, 10)).is_equal("hull.destroyer")
	# the colony design is kept while ships of it are left
	assert_str(_hull(w, 1)).is_equal("hull.mini_colony_ship")
	# the scout slot holds a frigate scout once the starting scout has no ships left
	assert_str(_hull(w, 0)).is_equal("hull.frigate")
	assert_str(_hull(w, 12)).is_equal("hull.privateer")
	assert_str(_hull(w, 14)).is_empty()
	assert_str(_hull(w, 4)).is_empty()


func test_designs_at_the_top_of_the_tech() -> void:
	var w := _world()
	_set_tech(w, 26)
	ClassicTurindrones.designs(w)
	# rogues and stealth bombers are Super Stealth hulls, miners need Advanced Remote Mining
	assert_str(_hull(w, 8)).is_empty()
	assert_str(_hull(w, 2)).is_empty()
	assert_str(_hull(w, 13)).is_empty()
	var ss := _world()
	_set_tech(ss, 26)
	ss.me().race.primary_trait = "trait.prt.SS"
	ss.me().race.lesser_traits.assign(["trait.lrt.ARM"])
	ClassicTurindrones.designs(ss)
	assert_str(_hull(ss, 8)).is_equal("hull.rogue")
	assert_str(_hull(ss, 2)).is_equal("hull.miner")
	assert_str(_hull(ss, 13)).is_equal("hull.stealth_bomber")
	assert_str(_hull(ss, 14)).is_equal("hull.stealth_bomber")
	assert_str(_hull(ss, 15)).is_equal("hull.rogue")
	assert_str(_hull(w, 9)).is_equal("hull.galleon")
	assert_str(_hull(w, 4)).is_equal("hull.battleship")


func test_thresholds_grow_late() -> void:
	var t := _turindrones(_world())
	var cases := [[1, 3, 6], [115, 3, 6], [122, 3, 7], [140, 4, 7], [400, 17, 12], [2000, 50, 12]]
	for case: Array in cases:
		t.turn = case[0]
		t._thresholds()
		assert_int(t.escort).is_equal(case[1])
		assert_int(t.troops).is_equal(case[2])


func test_mining_worth() -> void:
	var p := Planet.new()
	p.concentration.assign([10, 66, 67])
	# 5 + 33 + 75
	assert_int(ClassicTurindrones._mining_worth(p)).is_equal(113)
	p.concentration.assign([100, 100, 1])
	assert_int(ClassicTurindrones._mining_worth(p)).is_equal(ClassicTurindrones.MINING_MAX)


# --- Fleets ------------------------------------------------------------------------------------


func test_unseen_planets_are_explored() -> void:
	var s := _state()
	var w := _world(s)
	# player 1's own planets are loaded; nothing else is
	var scout := w.state.fleet(1, 1)
	var pick := ClassicFleets.choose_colony_target(w, scout, false)
	assert_int(pick["planet"]).is_not_equal(-1)
	assert_bool(w.loaded.has(pick["planet"])).is_false()
	var info: PackedByteArray = w.planet_info[pick["planet"]]
	assert_int(info[15]).is_equal(ClassicFleets.UNSEEN)


func test_an_unarmed_fleet_explores_at_its_top_warp() -> void:
	var s := _state()
	var w := _world(s)
	var scout := w.state.fleet(1, 1)
	var own: Array[Fleet] = []
	var enemies: Array[Fleet] = []
	assert_int(ClassicFleets.direct_fleet(w, scout, own, enemies, false, false)).is_equal(0)
	assert_int(scout.waypoints.size()).is_equal(2)
	var next := scout.waypoints[1]
	assert_str(next.target).is_equal("planet")
	assert_int(next.warp).is_equal(Retargeting.default_warp(scout, w.me(), _content, false))
	# claimed for the others
	assert_int((w.planet_info[next.target_id] as PackedByteArray)[15]).is_equal(4)


func test_turindrones_play_without_refused_orders() -> void:
	var s := _load(0)
	var refused := _play(s, 100)
	assert_array(Array(refused)).is_empty()
	for p in [1, 2]:
		var owned := s.planets.filter(func(pl: Planet) -> bool: return pl.owner == p)
		assert_int(owned.size()).is_greater_equal(2)
		assert_int(s.player(p).research_percent).is_equal(ClassicTurindrones.RESEARCH_PCT)
		assert_object(s.player(p).ship_design(ClassicTurindrones.COLONY_SLOT)).is_not_null()


func test_the_brain_plays_in_the_ai_step() -> void:
	var def := _content.get_def("ai_personality", "ai_personality.turindrones")
	assert_str(def["brain"]).is_equal(AiBrains.TURINDRONES)
	assert_object(AiBrains.create(AiBrains.TURINDRONES)).is_instanceof(ClassicBrain)
	var games: Array[GameState] = [_load(0), _load(0)]
	for s in games:
		for p in s.players:
			if not p.is_human():
				p.ai = "turindrones"
		for t in 20:
			var errors := PackedStringArray()
			var sets := ComputerPlayers.add_orders(s, _content, [], errors)
			assert_array(Array(errors)).is_empty()
			assert_array(Array(StandardTurn.generate(s, _content, sets))).is_empty()
	assert_bool(games[0].equals(games[1])).is_true()


## Plays `turns` turns as Turindrones, the computer players' worlds built by hand so that orders
## their worlds refused show; returns every refusal (world and host).
func _play(s: GameState, turns: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t in turns:
		var sets: Array[OrderSet] = []
		var rng := s.rng.get_stream(RngStreams.CLASSIC)
		for p in s.players:
			if p.is_human():
				continue
			var w := ClassicWorld.build(s, _content, p.index, rng, ClassicWorld.TURINDRONES)
			ClassicTurindrones.play(w)
			var memory := w.memory_order()
			if not memory.is_empty():
				w.order(memory)
			for reason in w.rejected:
				out.append("turn %d player %d world: %s" % [s.turn, p.index, reason])
			sets.append(w.orders)
		for reason in StandardTurn.generate(s, _content, sets):
			out.append("turn %d host: %s" % [s.turn, reason])
	return out
