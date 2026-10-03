extends GdUnitTestSuite
## Spec S12 "Wormholes shift" (the drift is also checked by the prod1 golden turns).


func _state() -> GameState:
	var s := GameState.new()
	s.settings.universe_width = 400
	for i in 2:
		var w := s.add_wormhole(100)
		w.x = 1100 + 200 * i
		w.y = 1200
		w.other_end = 1 - i
	return s


func test_jump_chance() -> void:
	var w := Wormhole.new()
	var cases := [[0, 0, 0], [10, 0, 0], [10, 2, 2], [14, 1, 1], [40, 3, 6], [5, 1, 0]]
	for c: Array in cases:
		w.age = c[0]
		w.stability = c[1]
		assert_int(Wormholes.jump_chance(w)).override_failure_message(str(c)).is_equal(c[2])


func test_drift_stays_near_and_ages() -> void:
	var s := _state()
	Wormholes.shift_all(s, StarsRandom.new())
	for i in 2:
		var w := s.wormholes[i]
		assert_int(w.age).is_equal(1)
		assert_int(absi(w.x - (1100 + 200 * i))).is_less_equal(Wormholes.DRIFT)
		assert_int(absi(w.y - 1200)).is_less_equal(Wormholes.DRIFT)
		assert_bool(w.x != 1100 + 200 * i or w.y != 1200).is_true()


func test_jump_resets_age_and_lands_inside() -> void:
	# A start state whose first draw is below the 6% chance of an old, unstable wormhole.
	var game_seed := 0
	while StarsRandom.from_game_seed(game_seed).random(100) >= Wormholes.MAX_JUMP_PCT:
		game_seed += 1
	var s := _state()
	var w := s.wormholes[0]
	w.age = 40
	w.stability = 3
	Wormholes.shift_all(s, StarsRandom.from_game_seed(game_seed))
	assert_int(w.age).is_equal(0)
	assert_int(Wormholes.score(s, w, 400)).is_less(Wormholes.IMPOSSIBLE)
	assert_bool(w.x >= 1000 and w.x <= 1400 and w.y >= 1000 and w.y <= 1400).is_true()
