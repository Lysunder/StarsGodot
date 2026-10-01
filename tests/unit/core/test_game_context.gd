extends GdUnitTestSuite


func test_new_context_keeps_seed() -> void:
	var ctx := GameContext.new(12345)
	assert_int(ctx.game_seed).is_equal(12345)


func test_contexts_are_independent() -> void:
	var a := GameContext.new(1)
	var b := GameContext.new(2)
	a.rng_streams["classic"] = 7
	assert_bool(b.rng_streams.has("classic")).is_false()
