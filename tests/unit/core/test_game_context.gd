extends GdUnitTestSuite


func test_new_context_keeps_seed() -> void:
	var ctx := GameContext.new(12345)
	assert_int(ctx.game_seed).is_equal(12345)


func test_contexts_are_independent() -> void:
	var a := GameContext.new(1)
	var b := GameContext.new(2)
	a.rng("fixes").next_raw()
	assert_bool(b.rng_streams.has_stream("fixes")).is_false()


func test_classic_from_game_seed() -> void:
	var ctx := GameContext.new(1234567890, true)
	assert_int(ctx.rng("classic").s1).is_equal(71)
	assert_int(ctx.rng("classic").s2).is_equal(41)
