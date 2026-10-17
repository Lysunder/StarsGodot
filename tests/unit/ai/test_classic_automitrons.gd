extends GdUnitTestSuite
## M12: the original's Automitrons (S22 "Automitrons"): designs by tech, the escort strength,
## the research budget, and whole games of tiny3ai's two computer players played as Automitrons.

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
	return ClassicWorld.build(s, _content, 1, StarsRandom.new(3, 9), ClassicWorld.AUTOMITRONS)


func _automitrons(w: ClassicWorld) -> ClassicAutomitrons:
	var t := ClassicAutomitrons.new()
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
	ClassicAutomitrons.designs(w)
	assert_str(_hull(w, 4)).is_equal("hull.medium_freighter")
	# some of their part classes have nothing to offer yet
	assert_str(_hull(w, 5)).is_empty()
	assert_str(_hull(w, 14)).is_equal("hull.destroyer")
	assert_str(_hull(w, 0)).is_equal("hull.scout")
	assert_str(_hull(w, 6)).is_empty()
	assert_str(_hull(w, 2)).is_equal("hull.b_17_bomber")
	assert_str(_hull(w, 3)).is_empty()
	assert_str(_hull(w, 9)).is_empty()


func test_designs_at_the_top_of_the_tech() -> void:
	var w := _world()
	_set_tech(w, 26)
	ClassicAutomitrons.designs(w)
	assert_str(_hull(w, 3)).is_equal("hull.b_52_bomber")
	# super freighters are an IS hull, the mine layer's parts SD parts
	assert_str(_hull(w, 5)).is_empty()
	assert_str(_hull(w, 6)).is_empty()
	var cases := [
		["trait.prt.IS", 5, "hull.super_freighter"], ["trait.prt.SD", 6, "hull.privateer"]
	]
	for case: Array in cases:
		var o := _world()
		_set_tech(o, 26)
		o.me().race.primary_trait = case[0]
		ClassicAutomitrons.designs(o)
		assert_str(_hull(o, case[1])).is_equal(case[2])
	assert_str(_hull(w, 9)).is_equal("hull.battleship")
	# warships (slots 11-12) are never designed
	assert_str(_hull(w, 11)).is_empty()


func test_escort_strength_counts_battleships_twice() -> void:
	var w := _world()
	_set_tech(w, 26)
	ClassicAutomitrons.designs(w)
	var f := Fleet.new()
	f.add_ships(9, 2)
	f.add_ships(3, 5)
	assert_int(ClassicAutomitrons.strength(f)).is_equal(4)


func test_automitrons_play_without_refused_orders() -> void:
	var s := _load(0)
	var refused := _play(s, 100)
	assert_array(Array(refused)).is_empty()
	for p in [1, 2]:
		var owned := s.planets.filter(func(pl: Planet) -> bool: return pl.owner == p)
		assert_int(owned.size()).is_greater_equal(2)
		assert_int(s.player(p).research_percent).is_equal(ClassicAutomitrons.RESEARCH_PCT)


func test_the_brain_plays_in_the_ai_step() -> void:
	var def := _content.get_def("ai_personality", "ai_personality.automitrons")
	assert_str(def["brain"]).is_equal(AiBrains.AUTOMITRONS)
	assert_object(AiBrains.create(AiBrains.AUTOMITRONS)).is_instanceof(ClassicBrain)
	var games: Array[GameState] = [_load(0), _load(0)]
	for s in games:
		for p in s.players:
			if not p.is_human():
				p.ai = "automitrons"
		for t in 20:
			var errors := PackedStringArray()
			var sets := ComputerPlayers.add_orders(s, _content, [], errors)
			assert_array(Array(errors)).is_empty()
			assert_array(Array(StandardTurn.generate(s, _content, sets))).is_empty()
	assert_bool(games[0].equals(games[1])).is_true()


## Plays `turns` turns as Automitrons, the computer players' worlds built by hand so that orders
## their worlds refused show; returns every refusal (world and host).
func _play(s: GameState, turns: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t in turns:
		var sets: Array[OrderSet] = []
		var rng := s.rng.get_stream(RngStreams.CLASSIC)
		for p in s.players:
			if p.is_human():
				continue
			var w := ClassicWorld.build(s, _content, p.index, rng, ClassicWorld.AUTOMITRONS)
			ClassicAutomitrons.play(w)
			var memory := w.memory_order()
			if not memory.is_empty():
				w.order(memory)
			for reason in w.rejected:
				out.append("turn %d player %d world: %s" % [s.turn, p.index, reason])
			sets.append(w.orders)
		for reason in StandardTurn.generate(s, _content, sets):
			out.append("turn %d host: %s" % [s.turn, reason])
	return out
