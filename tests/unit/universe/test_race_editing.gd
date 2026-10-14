extends GdUnitTestSuite
## M11 step 9: the race wizard's habitability edits and its habitable-planets figure (RaceEditing,
## after the original's `Environment_OnMouse` and `Environment_Paint`).


func _race(low: int, high: int) -> Race:
	var race := Race.new()
	for axis in 3:
		race.hab_low[axis] = low
		race.hab_high[axis] = high
		race.hab_center[axis] = low + (high - low) / 2
	return race


func test_shift_moves_both_ends_and_stops_at_the_edges() -> void:
	var race := _race(15, 85)
	RaceEditing.adjust(race, 0, 10, 0)
	assert_array(race.hab_low).is_equal([25, 15, 15])
	assert_int(race.hab_high[0]).is_equal(95)
	assert_int(race.hab_center[0]).is_equal(60)
	# pushed back in at the top, keeping the width
	RaceEditing.adjust(race, 0, 10, 0)
	assert_int(race.hab_low[0]).is_equal(30)
	assert_int(race.hab_high[0]).is_equal(100)
	# and at the bottom
	RaceEditing.adjust(race, 1, -20, 0)
	assert_int(race.hab_low[1]).is_equal(0)
	assert_int(race.hab_high[1]).is_equal(70)


func test_widen_and_narrow_keep_twenty_wide() -> void:
	var race := _race(40, 60)
	RaceEditing.adjust(race, 2, 0, 1)
	assert_int(race.hab_low[2]).is_equal(39)
	assert_int(race.hab_high[2]).is_equal(61)
	RaceEditing.adjust(race, 2, 0, -1)
	RaceEditing.adjust(race, 2, 0, -1)
	assert_int(race.hab_low[2]).is_equal(40)
	assert_int(race.hab_high[2]).is_equal(60)
	RaceEditing.adjust(race, 2, 0, -10)
	assert_int(race.hab_high[2] - race.hab_low[2]).is_equal(RaceEditing.MIN_WIDTH)


func test_drag_moves_the_middle_within_range() -> void:
	var race := _race(15, 85)
	RaceEditing.drag(race, 0, 40)
	assert_int(race.hab_low[0]).is_equal(5)
	assert_int(race.hab_high[0]).is_equal(75)
	RaceEditing.drag(race, 0, 99)
	assert_int(race.hab_low[0]).is_equal(30)
	assert_int(race.hab_high[0]).is_equal(100)


func test_immune_and_back() -> void:
	var race := _race(15, 85)
	RaceEditing.set_immune(race, 1, true)
	assert_bool(race.is_immune(1)).is_true()
	RaceEditing.adjust(race, 1, 5, 0)
	assert_int(race.hab_low[1]).is_equal(-1)
	RaceEditing.set_immune(race, 1, false)
	assert_int(race.hab_low[1]).is_equal(20)
	assert_int(race.hab_center[1]).is_equal(50)
	assert_int(race.hab_high[1]).is_equal(80)


func test_habitable_odds() -> void:
	# 15..85 everywhere: gravity and temperature 71 values × 10 / 9 each, radiation 70 wide
	assert_int(RaceEditing.habitable_odds(_race(15, 85))).is_equal(2)
	# gravity 21 values × 10: 1 × 210 div 9 = 23; temperature 23 × 210 div 9 = 536; radiation
	# 20 wide: 10,720; 1,000,000 div that, rounded: 93
	assert_int(RaceEditing.habitable_odds(_race(40, 60))).is_equal(93)
	var immune := Race.new()
	for axis in 3:
		RaceEditing.set_immune(immune, axis, true)
	assert_int(RaceEditing.habitable_odds(immune)).is_equal(0)
	# the ends weigh less: gravity 0..20 weighs 0 + 1 + ... + 9 + 11 × 10 = 155: 17, then 396,
	# then 7,920: 126
	var edge := _race(40, 60)
	edge.hab_low[0] = 0
	edge.hab_high[0] = 20
	assert_int(RaceEditing.habitable_odds(edge)).is_equal(126)
