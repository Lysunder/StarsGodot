extends GdUnitTestSuite
## M12: the original's Macinti (S22 "Macinti"): designs by tech and turn, starbase verdicts, and
## whole games played as Macinti.

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


func _world(turn: int = 1) -> ClassicWorld:
	var s := _load(1)
	s.turn = turn
	s.views.clear()
	for p in s.players:
		s.views.append({"planets": {}, "fleets": {}, "designs": {}, "starbase_designs": {}})
		p.knowledge = {}
	return ClassicWorld.build(s, _content, 1, StarsRandom.new(3, 9), ClassicWorld.MACINTI)


func test_designs_follow_the_turn() -> void:
	var w := _world()
	w.me().tech_levels.assign([6, 6, 6, 6, 6, 6])
	ClassicMacinti.designs(w)
	var me := w.me()
	# freighters come at once, nubians from weapons 5 and propulsion 6
	assert_object(me.ship_design(10)).is_not_null()
	assert_object(me.ship_design(12)).is_not_null()
	# nothing past the tech: bombers need weapons 14
	assert_object(me.ship_design(8)).is_null()


func test_starbase_verdicts() -> void:
	var w := _world(30)
	var v := ClassicMacinti.review_designs(w)
	assert_int(v.size()).is_equal(10)
	# both station generations are designed when none of their designs has starbases
	for slot in range(4, 10):
		assert_object(w.me().starbase_design(slot)).is_not_null()
	# the older generation is marked for a refresh (2) while young
	var marked := 0
	for slot in range(4, 10):
		if v[slot] == 2:
			marked += 1
	assert_int(marked).is_equal(3)


func test_the_age_test_counts_later_turns_as_old() -> void:
	assert_bool(ClassicMacinti._older(50, 20, 20)).is_true()
	assert_bool(ClassicMacinti._older(30, 20, 20)).is_false()
	# the starting designs carry turn 1: at turn 0 they count as old (unsigned compare)
	assert_bool(ClassicMacinti._older(0, 1, 20)).is_true()


func test_macinti_play_without_refused_orders() -> void:
	var path := "res://tests/fixtures/golden/tiny_random_ai/t000.json"
	var s := SaveFile.decode(FileAccess.get_file_as_string(path), _content).state
	var refused := _play(s, 60)
	assert_array(Array(refused)).is_empty()
	assert_int(s.player(1).research_percent).is_equal(ClassicMacinti.RESEARCH_PCT)


func test_the_brain_plays_in_the_ai_step() -> void:
	var def := _content.get_def("ai_personality", "ai_personality.macinti")
	assert_str(def["brain"]).is_equal(AiBrains.MACINTI)
	assert_object(AiBrains.create(AiBrains.MACINTI)).is_instanceof(ClassicBrain)
	var games: Array[GameState] = [_load(0), _load(0)]
	for s in games:
		for p in s.players:
			if not p.is_human():
				p.ai = "macinti"
		for t in 20:
			var errors := PackedStringArray()
			var sets := ComputerPlayers.add_orders(s, _content, [], errors)
			assert_array(Array(errors)).is_empty()
			assert_array(Array(StandardTurn.generate(s, _content, sets))).is_empty()
	assert_bool(games[0].equals(games[1])).is_true()


## Plays `turns` turns as Macinti, the computer players' worlds built by hand so that orders their
## worlds refused show; returns every refusal (world and host).
func _play(s: GameState, turns: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t in turns:
		var sets: Array[OrderSet] = []
		var rng := s.rng.get_stream(RngStreams.CLASSIC)
		var shared := {}
		for p in s.players:
			if p.is_human():
				continue
			var w := ClassicWorld.build(s, _content, p.index, rng, ClassicWorld.MACINTI)
			w.load_slot_turns(shared)
			ClassicMacinti.play(w)
			var memory := w.memory_order()
			if not memory.is_empty():
				w.order(memory)
			for reason in w.rejected:
				out.append("turn %d player %d world: %s" % [s.turn, p.index, reason])
			sets.append(w.orders)
		for reason in StandardTurn.generate(s, _content, sets):
			out.append("turn %d host: %s" % [s.turn, reason])
	return out
