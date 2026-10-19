extends GdUnitTestSuite
## M12: the original's Rototills (S22 "Rototills"): no designs of their own, the research budget
## without a plan, and whole games of tiny3ai's two computer players played as Rototills.

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
	return ClassicWorld.build(s, _content, 1, StarsRandom.new(3, 9), ClassicWorld.ROTOTILLS)


func _set_tech(w: ClassicWorld, level: int) -> void:
	w.me().tech_levels.assign([level, level, level, level, level, level])


func _hull(w: ClassicWorld, slot: int) -> String:
	var d := w.me().ship_design(slot)
	return "" if d == null else d.hull


# --- Research and designs ---------------------------------------------------------------------


func test_no_designs_of_their_own() -> void:
	var w := _world()
	_set_tech(w, 26)
	var earlier := []
	for slot in 16:
		earlier.append(_hull(w, slot))
	ClassicRototills.play(w)
	for slot in 16:
		assert_str(_hull(w, slot)).is_equal(earlier[slot])


func test_research_the_lowest_field() -> void:
	var w := _world()
	w.me().tech_levels.assign([3, 2, 1, 1, 4, 5])
	w.me().research_field = 0
	assert_int(ClassicResearch.follow_plan(w, "", 15)).is_equal(-1)
	assert_int(w.me().research_field).is_equal(2)
	assert_int(w.me().research_percent).is_equal(15)


func test_rototills_play_without_refused_orders() -> void:
	var s := _load(0)
	var refused := _play(s, 100)
	assert_array(Array(refused)).is_empty()
	for p in [1, 2]:
		var owned := s.planets.filter(func(pl: Planet) -> bool: return pl.owner == p)
		assert_int(owned.size()).is_greater_equal(2)


func test_the_brain_plays_in_the_ai_step() -> void:
	var def := _content.get_def("ai_personality", "ai_personality.rototills")
	assert_str(def["brain"]).is_equal(AiBrains.ROTOTILLS)
	assert_object(AiBrains.create(AiBrains.ROTOTILLS)).is_instanceof(ClassicBrain)
	var games: Array[GameState] = [_load(0), _load(0)]
	for s in games:
		for p in s.players:
			if not p.is_human():
				p.ai = "rototills"
		for t in 20:
			var errors := PackedStringArray()
			var sets := ComputerPlayers.add_orders(s, _content, [], errors)
			assert_array(Array(errors)).is_empty()
			assert_array(Array(StandardTurn.generate(s, _content, sets))).is_empty()
	assert_bool(games[0].equals(games[1])).is_true()


## Plays `turns` turns as Rototills, the computer players' worlds built by hand so that orders
## their worlds refused show; returns every refusal (world and host).
func _play(s: GameState, turns: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t in turns:
		var sets: Array[OrderSet] = []
		var rng := s.rng.get_stream(RngStreams.CLASSIC)
		for p in s.players:
			if p.is_human():
				continue
			var w := ClassicWorld.build(s, _content, p.index, rng, ClassicWorld.ROTOTILLS)
			ClassicRototills.play(w)
			var memory := w.memory_order()
			if not memory.is_empty():
				w.order(memory)
			for reason in w.rejected:
				out.append("turn %d player %d world: %s" % [s.turn, p.index, reason])
			sets.append(w.orders)
		for reason in StandardTurn.generate(s, _content, sets):
			out.append("turn %d host: %s" % [s.turn, reason])
	return out
