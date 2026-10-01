extends GdUnitTestSuite
## Spec S01. Expected values are the spec's worked examples, computed independently in Python.
## The component generators and the seed table (entry 55 = 279) are confirmed by the harness: the
## original's file cipher uses both, and a real file keyed through entry 55 only decodes with 279.


func _raws(rng: StarsRandom, count: int) -> Array[int]:
	var out: Array[int] = []
	for i in count:
		out.append(rng.next_raw())
	return out


func _draws(rng: StarsRandom, bound: int, count: int) -> Array[int]:
	var out: Array[int] = []
	for i in count:
		out.append(rng.random(bound))
	return out


func test_seed_table() -> void:
	var table := StarsRandom.seed_table()
	assert_int(table.size()).is_equal(128)
	assert_int(table[0]).is_equal(3)
	assert_int(table[54]).is_equal(263)
	assert_int(table[55]).is_equal(279)
	assert_int(table[56]).is_equal(271)
	assert_int(table[127]).is_equal(727)
	var total := 0
	for p in table:
		total += p
	assert_int(total).is_equal(42476)


func test_first_raw_value_by_hand() -> void:
	var rng := StarsRandom.new(3, 5)
	assert_int(rng.next_raw()).is_equal(2147400144)
	assert_int(rng.s1).is_equal(120042)
	assert_int(rng.s2).is_equal(203460)


func test_game_seed_0() -> void:
	var rng := StarsRandom.from_game_seed(0)
	assert_array(_raws(rng, 5)).is_equal([2147400144, 819132901, 2112045575, 549227523, 1079672687])
	assert_array(_draws(StarsRandom.from_game_seed(0), 100, 5)).is_equal([44, 1, 75, 23, 87])


func test_game_seed_1() -> void:
	var rng := StarsRandom.from_game_seed(1)
	assert_int(rng.s1).is_equal(5)
	assert_int(rng.s2).is_equal(3)
	assert_array(_raws(rng, 5)).is_equal([77994, 890600497, 421707707, 878171086, 1702513118])
	assert_array(_draws(StarsRandom.from_game_seed(1), 100, 5)).is_equal([94, 97, 7, 86, 18])


func test_game_seed_ignores_high_bits() -> void:
	assert_array(_raws(StarsRandom.from_game_seed(64), 5)).is_equal(
		_raws(StarsRandom.from_game_seed(0), 5)
	)


func test_game_seed_tutorial_constant() -> void:
	var rng := StarsRandom.from_game_seed(1234567890)
	assert_int(rng.s1).is_equal(71)
	assert_int(rng.s2).is_equal(41)
	assert_array(_raws(rng, 5)).is_equal([1172622, 692980585, 763769720, 1721447872, 1598024419])
	assert_array(_draws(StarsRandom.from_game_seed(1234567890), 100, 5)).is_equal(
		[22, 85, 20, 72, 19]
	)


func test_game_seed_index_collision() -> void:
	var rng := StarsRandom.from_game_seed(65)  # i = 1, j = 1 -> j = 2
	assert_array([rng.s1, rng.s2]).is_equal([5, 7])
	rng = StarsRandom.from_game_seed(4095)  # i = 63, j = 63 -> j wraps to 0
	assert_array([rng.s1, rng.s2]).is_equal([313, 3])


func test_clock_method() -> void:
	var rng := StarsRandom.from_clock(0)
	assert_array([rng.s1, rng.s2]).is_equal([257, 491])
	rng = StarsRandom.from_clock(0x1234)
	assert_array([rng.s1, rng.s2]).is_equal([5, 673])


func test_random_zero_still_advances() -> void:
	var rng := StarsRandom.from_game_seed(0)
	assert_int(rng.random(0)).is_equal(0)
	assert_int(rng.random(1000)).is_equal(901)
	assert_array([rng.s1, rng.s2]).is_equal([508393462, 1836744123])
	assert_int(rng.random(-5)).is_equal(0)


func test_long_run() -> void:
	var rng := StarsRandom.from_game_seed(0)
	var last := 0
	for i in 100000:
		last = rng.next_raw()
	assert_int(last).is_equal(1645015685)
	assert_array([rng.s1, rng.s2]).is_equal([912830294, 1415298171])


func test_fnv1a_32() -> void:
	assert_int(StarsRandom.fnv1a_32(PackedByteArray())).is_equal(2166136261)
	assert_int(StarsRandom.fnv1a_32("a".to_utf8_buffer())).is_equal(3826002220)


func test_stream_name_derivation() -> void:
	var rng := StarsRandom.from_stream_name(1234567890, "classic")
	assert_array([rng.s1, rng.s2]).is_equal([1190734222, 1788698839])
	assert_array(_raws(rng, 3)).is_equal([890516109, 1108286283, 1584059532])
	rng = StarsRandom.from_stream_name(1234567890, "fixes")
	assert_array([rng.s1, rng.s2]).is_equal([406364607, 349871482])
	rng = StarsRandom.from_stream_name(1234567890, "mod.extra_hulls")
	assert_array([rng.s1, rng.s2]).is_equal([100079191, 947238176])
	assert_array(_raws(rng, 3)).is_equal([1823058264, 1425391283, 1313790896])


func test_duplicate_is_independent() -> void:
	var rng := StarsRandom.from_game_seed(0)
	rng.next_raw()
	var copy := rng.duplicate_stream()
	assert_int(copy.next_raw()).is_equal(rng.next_raw())
	copy.next_raw()
	assert_int(copy.s1).is_not_equal(rng.s1)


func test_valid_state() -> void:
	assert_bool(StarsRandom.is_valid_state(1, 1)).is_true()
	assert_bool(StarsRandom.is_valid_state(2147483562, 2147483398)).is_true()
	assert_bool(StarsRandom.is_valid_state(0, 5)).is_false()
	assert_bool(StarsRandom.is_valid_state(5, 2147483399)).is_false()
	assert_bool(StarsRandom.is_valid_state(2147483563, 5)).is_false()
