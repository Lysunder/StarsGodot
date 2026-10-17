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
	# played by the idle brain, which draws nothing
	for i in [1, 2]:
		s.player(i).ai_personality = {"name": "Idle", "brain": AiBrains.IDLE}
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
	# the idle brain gives no orders and changes nothing; the classic stream advances by the two
	# file salts the original draws for each computer player (S01)
	assert_array(StateDiff.compare(before, s, PackedStringArray(["/rng"]))).is_empty()
	var rng := before.rng.get_stream(RngStreams.CLASSIC)
	for i in 4:
		rng.random(ComputerPlayers.FILE_SALT_RANGE)
	assert_dict(s.rng.get_stream(RngStreams.CLASSIC).to_dict()).is_equal(rng.to_dict())
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


## Every setting a brain declares has a default in range and a name and description to show.
func test_brain_settings_are_declared() -> void:
	for brain: String in AiBrains.IDS:
		for s: Dictionary in AiBrains.settings(brain):
			assert_int(s["default"]).is_between(s["min"], s["max"])
			for suffix in [".name", ".description"]:
				var key: String = "ai_setting.%s%s" % [s["key"], suffix]
				assert_str(_content.string_for(key)).override_failure_message(key).is_not_equal(key)
	assert_int(AiBrains.settings(AiBrains.BASELINE).size()).is_greater(10)


## A personality may only set what its brain declares, within range (checked when content loads).
func test_personality_settings_are_checked() -> void:
	var good := {
		"brain": AiBrains.BASELINE, "params": {"research_pct": 20}, "levels": [{"scouts": 5}]
	}
	assert_array(AiBrains.problems(good)).is_empty()
	var bad := {
		"brain": AiBrains.BASELINE,
		"params": {"research_pct": 120, "luck": 3},
		"levels": [{"scouts": -1}]
	}
	var problems := AiBrains.problems(bad)
	assert_int(problems.size()).is_equal(3)
	var pointers: Array = problems.map(func(p: Array) -> String: return p[0])
	assert_array(pointers).contains(["/params/research_pct", "/params/luck", "/levels/0/scouts"])
	# a setting the personality leaves out comes from the brain's default
	var s := _state()
	var ctx := AiContext.new(PlayerView.new(s, _content, 1), _content, StarsRandom.new(), good, 0)
	assert_int(ctx.param("research_pct")).is_equal(20)
	assert_int(ctx.param("scouts")).is_equal(5)
	assert_int(ctx.param("war_turn")).is_equal(40)


## A new game keeps a copy of each computer player's personality, which the AI step then uses.
func test_games_keep_their_personalities() -> void:
	var s := _state()
	assert_dict(s.players[1].ai_personality).is_empty()
	ComputerPlayers.adopt_personalities(s, _content)
	assert_dict(s.players[0].ai_personality).is_empty()
	var copy: Dictionary = s.players[1].ai_personality
	assert_str(copy["brain"]).is_equal(AiBrains.ROBOTOIDS)
	assert_str(copy["name"]).is_equal(
		_content.display_name(ComputerPlayers.personality_id(s.players[1].ai))
	)
	# the copy wins over the content, even when the content no longer has it
	s.players[1].ai = "gone"
	copy["params"] = {"research_pct": 33}
	assert_dict(ComputerPlayers.personality_for(s.players[1], _content)).is_equal(copy)
	var given: Array[OrderSet] = []
	var errors := PackedStringArray()
	ComputerPlayers.add_orders(s, _content, given, errors)
	assert_array(errors).is_empty()
