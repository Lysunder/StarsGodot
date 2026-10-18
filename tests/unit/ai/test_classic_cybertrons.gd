extends GdUnitTestSuite
## M12: the original's Cybertrons (S22 "Cybertrons"): designs from template pools, packet
## damage, and whole games played as Cybertrons.

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
	return ClassicWorld.build(s, _content, 1, StarsRandom.new(3, 9), ClassicWorld.CYBERTRONS)


func _set_tech(w: ClassicWorld, level: int) -> void:
	w.me().tech_levels.assign([level, level, level, level, level, level])


func _hull(w: ClassicWorld, slot: int) -> String:
	var d := w.me().ship_design(slot)
	return "" if d == null else d.hull


# --- Designs and packets -----------------------------------------------------------------------


func test_designs_by_turn() -> void:
	var s := _state()
	s.turn = 45
	var w := _world(s)
	_set_tech(w, 26)
	ClassicCybertrons.designs(w)
	# the starting scout stays while ships of it are left
	assert_str(_hull(w, 0)).is_equal("hull.scout")
	assert_str(_hull(w, 4)).is_equal("hull.destroyer")
	assert_str(_hull(w, 2)).is_equal("hull.privateer")
	# the first warship group from turn 41: a flagship in slot 9 and ships below it
	assert_str(_hull(w, 9)).is_not_empty()
	assert_str(_hull(w, 14)).is_not_empty()
	assert_str(_hull(w, 10)).is_empty()


func test_templates_fit_their_hulls() -> void:
	for id in _content.ids("ai_design_template"):
		var def := _content.get_def("ai_design_template", id)
		if id.begins_with(ClassicCybertrons.TEMPLATE):
			var hull := _content.hull(def["hull"])
			assert_int((def["slots"] as Array).size()).is_equal((hull["slots"] as Array).size())


func test_packets_needed() -> void:
	var p := Planet.new()
	p.population_estimate = 100
	p.defense_estimate = 0
	# 500 people, hit (16 x 16) x 95 = 24320: 500 x 16000 / 24320 = 328.9
	assert_int(ClassicCybertronsPackets._packets_needed(p, 16, 0)).is_equal(328)
	# an exact quotient comes out one less, as the original's float scale
	p.population_estimate = 225
	p.defense_estimate = 95 - 64
	assert_int(ClassicCybertronsPackets._packets_needed(p, 16, 0)).is_equal(1000 * 16000 / 16384)


## tiny_random_ai's computer player was created as Cybertrons (its starting designs fit).
func test_cybertrons_play_without_refused_orders() -> void:
	var path := "res://tests/fixtures/golden/tiny_random_ai/t000.json"
	var result := SaveFile.decode(FileAccess.get_file_as_string(path), _content)
	var s := result.state
	var refused := _play(s, 60)
	assert_array(Array(refused)).is_empty()
	var owned := s.planets.filter(func(pl: Planet) -> bool: return pl.owner == 1)
	assert_int(owned.size()).is_greater_equal(2)
	assert_int(s.player(1).research_percent).is_equal(ClassicCybertrons.RESEARCH_PCT)


func test_the_brain_plays_in_the_ai_step() -> void:
	var def := _content.get_def("ai_personality", "ai_personality.cybertrons")
	assert_str(def["brain"]).is_equal(AiBrains.CYBERTRONS)
	assert_object(AiBrains.create(AiBrains.CYBERTRONS)).is_instanceof(ClassicBrain)
	var games: Array[GameState] = [_load(0), _load(0)]
	for s in games:
		for p in s.players:
			if not p.is_human():
				p.ai = "cybertrons"
		for t in 20:
			var errors := PackedStringArray()
			var sets := ComputerPlayers.add_orders(s, _content, [], errors)
			assert_array(Array(errors)).is_empty()
			assert_array(Array(StandardTurn.generate(s, _content, sets))).is_empty()
	assert_bool(games[0].equals(games[1])).is_true()


## Plays `turns` turns as Cybertrons, the computer players' worlds built by hand so that orders
## their worlds refused show; returns every refusal (world and host).
func _play(s: GameState, turns: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t in turns:
		var sets: Array[OrderSet] = []
		var rng := s.rng.get_stream(RngStreams.CLASSIC)
		for p in s.players:
			if p.is_human():
				continue
			var w := ClassicWorld.build(s, _content, p.index, rng, ClassicWorld.CYBERTRONS)
			ClassicCybertrons.play(w)
			var memory := w.memory_order()
			if not memory.is_empty():
				w.order(memory)
			for reason in w.rejected:
				out.append("turn %d player %d world: %s" % [s.turn, p.index, reason])
			sets.append(w.orders)
		for reason in StandardTurn.generate(s, _content, sets):
			out.append("turn %d host: %s" % [s.turn, reason])
	return out
