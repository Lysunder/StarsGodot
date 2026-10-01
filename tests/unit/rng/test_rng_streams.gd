extends GdUnitTestSuite
## Spec S01, "Our design: streams".


func test_classic_from_game_seed() -> void:
	var streams := RngStreams.new(1234567890, true)
	var classic := streams.get_stream("classic")
	assert_array([classic.s1, classic.s2]).is_equal([71, 41])
	assert_int(classic.max_range).is_equal(32767)


func test_classic_derived_without_explicit_seed() -> void:
	var classic := RngStreams.new(1234567890).get_stream("classic")
	assert_array([classic.s1, classic.s2]).is_equal([1190734222, 1788698839])


func test_other_streams_derived_and_unlimited() -> void:
	var fixes := RngStreams.new(1234567890, true).get_stream("fixes")
	assert_array([fixes.s1, fixes.s2]).is_equal([406364607, 349871482])
	assert_int(fixes.max_range).is_equal(0)


func test_new_stream_does_not_shift_classic() -> void:
	var a := RngStreams.new(42, true)
	var b := RngStreams.new(42, true)
	b.get_stream("mod.extra_hulls").next_raw()
	b.get_stream("fixes").random(10)
	assert_int(a.get_stream("classic").next_raw()).is_equal(b.get_stream("classic").next_raw())


func test_get_stream_returns_same_object() -> void:
	var streams := RngStreams.new(7)
	streams.get_stream("fixes").next_raw()
	var again := streams.get_stream("fixes")
	assert_int(again.s1).is_not_equal(StarsRandom.from_stream_name(7, "fixes").s1)


func test_names() -> void:
	assert_bool(RngStreams.is_valid_name("classic")).is_true()
	assert_bool(RngStreams.is_valid_name("fixes")).is_true()
	assert_bool(RngStreams.is_valid_name("mod.extra_hulls")).is_true()
	assert_bool(RngStreams.is_valid_name("mod.extra_hulls.battle")).is_true()
	assert_bool(RngStreams.is_valid_name("mod")).is_false()
	assert_bool(RngStreams.is_valid_name("mod.Bad")).is_false()
	assert_bool(RngStreams.is_valid_name("mod.a.b.c")).is_false()
	assert_bool(RngStreams.is_valid_name("other")).is_false()
	var streams := RngStreams.new(1)
	streams.get_stream("mod.b")
	streams.get_stream("fixes")
	assert_array(Array(streams.names())).is_equal(["classic", "fixes", "mod.b"])


func test_round_trip_through_json() -> void:
	var streams := RngStreams.new(99, true)
	streams.get_stream("classic").random(100)
	streams.get_stream("fixes").random(100)
	var text := JSON.stringify(streams.to_dict())
	var loaded := RngStreams.from_dict(JSON.parse_string(text))
	assert_object(loaded).is_not_null()
	assert_dict(loaded.to_dict()).is_equal(streams.to_dict())
	assert_int(loaded.get_stream("classic").max_range).is_equal(32767)
	for stream_name in ["classic", "fixes", "mod.later"]:
		assert_int(loaded.get_stream(stream_name).next_raw()).is_equal(
			streams.get_stream(stream_name).next_raw()
		)


func test_from_dict_rejects_bad_data() -> void:
	var good := {"game_seed": 1, "streams": {"classic": {"s1": 3, "s2": 5}}}
	assert_object(RngStreams.from_dict(good)).is_not_null()
	assert_object(RngStreams.from_dict({"game_seed": 1, "streams": {}})).is_null()
	assert_object(RngStreams.from_dict({"streams": good["streams"]})).is_null()
	var bad_state := {"game_seed": 1, "streams": {"classic": {"s1": 0, "s2": 5}}}
	assert_object(RngStreams.from_dict(bad_state)).is_null()
	var fraction := {"game_seed": 1, "streams": {"classic": {"s1": 3.5, "s2": 5}}}
	assert_object(RngStreams.from_dict(fraction)).is_null()
	var bad_name := {
		"game_seed": 1, "streams": {"classic": {"s1": 3, "s2": 5}, "x": {"s1": 3, "s2": 5}}
	}
	assert_object(RngStreams.from_dict(bad_name)).is_null()


func test_duplicate_is_independent() -> void:
	var streams := RngStreams.new(5, true)
	streams.get_stream("fixes")
	var copy := streams.duplicate_streams()
	copy.get_stream("classic").next_raw()
	assert_dict(copy.to_dict()).is_not_equal(streams.to_dict())
	assert_int(copy.get_stream("classic").max_range).is_equal(32767)
	assert_array(Array(copy.names())).is_equal(["classic", "fixes"])
