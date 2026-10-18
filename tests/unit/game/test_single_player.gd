extends GdUnitTestSuite
## M13 single player: a game against computer players run the way GameSession runs it (the human's
## order set given, the computer players adding theirs): saving and loading mid-game changes
## nothing, and a human wiped out is eliminated while the computer players play on (S20).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _game() -> GameState:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 321
	options.opponents = [
		{"ai": "macinti", "level": 1, "personality": {}},
		{"ai": "robotoids", "level": 2, "personality": {}},
		{
			"ai": "own_baseline",
			"level": 3,
			"personality": PersonalityFile.make("Baseline", AiBrains.BASELINE)
		},
	]
	return NewGame.create(_content, options)


## Plays `turns` turns with the human giving no orders; returns every refusal and AI step error.
func _play(s: GameState, turns: int) -> PackedStringArray:
	var out := PackedStringArray()
	for t in turns:
		var given: Array[OrderSet] = [OrderSet.new(0, s.turn)]
		var sets := ComputerPlayers.add_orders(s, _content, given, out)
		out.append_array(StandardTurn.generate(s, _content, sets))
	return out


func _reload(s: GameState) -> GameState:
	var result := SaveFile.decode(SaveFile.encode(s, "test"), _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	return result.state


func test_saving_mid_game_changes_nothing() -> void:
	var a := _game()
	assert_array(Array(_play(a, 12))).is_empty()
	var b := _reload(a)
	assert_bool(b.equals(a)).is_true()
	assert_array(Array(_play(a, 8))).is_empty()
	assert_array(Array(_play(b, 8))).is_empty()
	(
		assert_bool(b.equals(a))
		. override_failure_message("the reloaded game played differently")
		. is_true()
	)


func test_a_human_wiped_out_is_eliminated_and_the_game_goes_on() -> void:
	var s := _game()
	_play(s, 3)
	for pl in s.planets:
		if pl.owner == 0:
			pl.owner = -1
			pl.population = 0
			pl.starbase = null
	for f in s.fleets_of(0):
		s.remove_fleet(f)
	assert_array(Array(_play(s, 1))).is_empty()
	assert_bool(s.player(0).eliminated).is_true()
	# the computer players play on; the human's (empty) orders are still taken
	assert_array(Array(_play(s, 5))).is_empty()
	assert_bool(s.player(0).eliminated).is_true()
	# from the next year an eliminated player's record has no tech (S20)
	assert_int(s.player(0).score.get("tech", -1)).is_equal(0)
