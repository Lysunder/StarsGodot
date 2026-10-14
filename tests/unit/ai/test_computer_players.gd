extends GdUnitTestSuite
## M12 step 1: the AI step (S22): which players make orders, in what order, from which personality,
## and the personality parameters by level.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## tiny3ai: player 0 is human, players 1 and 2 are computer players.
func _state() -> GameState:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/golden/tiny3ai/t000.json")
	var result := SaveFile.decode(text, _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	return result.state


func test_every_original_personality_is_defined() -> void:
	for ai: String in UniverseGenerator.AI_PERSONALITIES:
		var id := ComputerPlayers.personality_id(ai)
		assert_bool(_content.ids(ComputerPlayers.PERSONALITY).has(id)).is_true()
		(
			assert_bool(AiBrains.has(_content.get_def(ComputerPlayers.PERSONALITY, id)["brain"]))
			. is_true()
		)
		assert_str(_content.display_name(id)).is_not_empty()


func test_computer_players_add_their_orders() -> void:
	var s := _state()
	var before := s.copy() as GameState
	var given: Array[OrderSet] = [OrderSet.new(0, s.turn)]
	var errors := PackedStringArray()
	var sets := ComputerPlayers.add_orders(s, _content, given, errors)
	assert_array(errors).is_empty()
	assert_int(sets.size()).is_equal(3)
	assert_object(sets[0]).is_same(given[0])
	for i in [1, 2]:
		assert_int(sets[i].player).is_equal(i)
		assert_int(sets[i].turn).is_equal(s.turn)
	# the idle brain gives no orders and changes nothing
	assert_bool(s.equals(before)).is_true()
	assert_array(StandardTurn.generate(s, _content, sets)).is_empty()


func test_only_players_still_in_the_game_without_orders_play() -> void:
	var s := _state()
	s.players[1].eliminated = true
	var given: Array[OrderSet] = [OrderSet.new(2, s.turn)]
	var sets := ComputerPlayers.add_orders(s, _content, given)
	# player 0 is an active human, 1 is out, 2 gave its own orders
	assert_int(sets.size()).is_equal(1)


## A human player who is inactive is played by the housekeeping personality.
func test_inactive_human_is_played() -> void:
	var s := _state()
	s.players[0].active = false
	assert_bool(ComputerPlayers.plays(s.players[0])).is_true()
	assert_str(ComputerPlayers.personality_of(s.players[0])).is_equal(ComputerPlayers.INACTIVE)
	var given: Array[OrderSet] = []
	var errors := PackedStringArray()
	var sets := ComputerPlayers.add_orders(s, _content, given, errors)
	assert_array(errors).is_empty()
	assert_int(sets.size()).is_equal(3)
	assert_int(sets[0].player).is_equal(0)


func test_unknown_personality_gives_no_orders() -> void:
	var s := _state()
	s.players[2].ai = "nobody"
	var errors := PackedStringArray()
	var given: Array[OrderSet] = []
	var sets := ComputerPlayers.add_orders(s, _content, given, errors)
	assert_int(sets.size()).is_equal(1)
	assert_int(sets[0].player).is_equal(1)
	assert_int(errors.size()).is_equal(1)
	assert_str(errors[0]).contains("nobody")


func test_param_prefers_the_level_value() -> void:
	var s := _state()
	var personality := {"params": {"aggression": 3, "greed": 5}, "levels": [{"aggression": 1}, {}]}
	var view := PlayerView.new(s, _content, 1)
	var ctx := AiContext.new(view, _content, StarsRandom.new(), personality, 0)
	assert_int(ctx.param("aggression")).is_equal(1)
	assert_int(ctx.param("greed")).is_equal(5)
	assert_int(ctx.param("missing", 7)).is_equal(7)
	ctx.level = 1
	assert_int(ctx.param("aggression")).is_equal(3)
	ctx.level = 3
	assert_int(ctx.param("aggression")).is_equal(3)
	ctx.order({"type": "research", "percent": 10})
	assert_int(ctx.orders.orders.size()).is_equal(1)
	assert_int(ctx.orders.player).is_equal(1)
