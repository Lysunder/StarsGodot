extends GdUnitTestSuite
## Spec S16 "Battle results": who gets a tech bonus try after a battle (S24), and from which
## random stream (fix B36). Uses mine1 turn 69's players (both behind level 20 in some field).

const NEED := 20

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _load() -> GameState:
	var path := "res://tests/fixtures/golden/mine1/t069.json"
	return SaveFile.decode(FileAccess.get_file_as_string(path), _content).state


func _engine(state: GameState) -> BattleEngine:
	var tokens: Array[Dictionary] = []
	var e := BattleEngine.new(state, _content, StarsRandom.new(1, 1), {"attack": [0, 0]}, tokens)
	e.tech_seen.assign([NEED, NEED, NEED, NEED, NEED, NEED])
	return e


## The stream after the tries of `players` (in order), made on a fresh copy of the state.
func _expected(rng: StarsRandom, players: Array) -> Array:
	var copy := _load()
	var probe := StarsRandom.new(rng.s1, rng.s2)
	var need: Array[int] = [NEED, NEED, NEED, NEED, NEED, NEED]
	for p: int in players:
		TechGain.try_bonus(copy.player(p), need, _content, probe)
	return [probe.s1, probe.s2]


func _finish(
	state: GameState, battle: Dictionary, group: Array, rng: StarsRandom, fixes: StarsRandom
) -> void:
	var place := {"id": 1, "starbase_owner": -1, "starbase_slot": 0, "ships": 9, "designs": 9}
	Battles.finish(state, _content, rng, fixes, battle, group, _engine(state), place)


func _battle(players: int, sides: int, bystanders: int, fleets: Array) -> Dictionary:
	return {
		"players": players,
		"sides": sides,
		"bystanders": bystanders,
		"planet": -1,
		"x": 0,
		"y": 0,
		"fleets": fleets,
	}


func test_two_sides_only_survivors_try() -> void:
	var state := _load()
	var ours := state.fleet(0, 2)
	var theirs := state.fleet(1, 2)
	theirs.stacks.clear()
	var rng := StarsRandom.new(5, 673)
	var fixes := StarsRandom.new(7, 7)
	var want := _expected(rng, [0])
	_finish(state, _battle(3, 2, 0, [ours, theirs]), [ours, theirs], rng, fixes)
	assert_array([rng.s1, rng.s2]).is_equal(want)
	assert_array([fixes.s1, fixes.s2]).is_equal([7, 7])


func test_more_sides_everyone_tries() -> void:
	var state := _load()
	var ours := state.fleet(0, 2)
	var theirs := state.fleet(1, 2)
	theirs.stacks.clear()
	var rng := StarsRandom.new(5, 673)
	var want := _expected(rng, [0, 1])
	_finish(state, _battle(3, 3, 0, [ours, theirs]), [ours, theirs], rng, StarsRandom.new(7, 7))
	assert_array([rng.s1, rng.s2]).is_equal(want)


func test_bystander_draws_from_fixes_where_the_original_skips() -> void:
	# player 1 watches player 0's battle: the original tests mask 2 against player number 1
	var state := _load()
	var ours := state.fleet(0, 2)
	var watcher := state.fleet(1, 3)
	var rng := StarsRandom.new(5, 673)
	var fixes := StarsRandom.new(7, 7)
	var want := _expected(rng, [0])
	var want_fixes := _expected(fixes, [1])
	_finish(state, _battle(1, 3, 2, [ours]), [ours, watcher], rng, fixes)
	assert_array([rng.s1, rng.s2]).is_equal(want)
	assert_array([fixes.s1, fixes.s2]).is_equal(want_fixes)


func test_bystander_draws_from_classic_where_the_original_does() -> void:
	# both players watch: mask 3 against player 0 fails (fixes), against player 1 passes (classic)
	var state := _load()
	var a := state.fleet(0, 2)
	var b := state.fleet(1, 3)
	var rng := StarsRandom.new(5, 673)
	var fixes := StarsRandom.new(7, 7)
	var want := _expected(rng, [1])
	var want_fixes := _expected(fixes, [0])
	_finish(state, _battle(0, 0, 3, []), [a, b], rng, fixes)
	assert_array([rng.s1, rng.s2]).is_equal(want)
	assert_array([fixes.s1, fixes.s2]).is_equal(want_fixes)


func _messages(state: GameState, p: int) -> Array:
	return (state.messages[p] as Array).filter(
		func(m: Dictionary) -> bool: return (m.type as String).begins_with("message.battle.")
	)


func test_duel_messages() -> void:
	# one ship each: player 1's ship is destroyed, player 0's takes no damage
	var state := _load()
	TurnMessages.clear(state)
	var ours := state.fleet(0, 2)
	var theirs := state.fleet(1, 2)
	theirs.stacks.clear()
	var engine := _engine(state)
	engine.losses = {1 * 16 + 2: BattleEngine.LOSS_HIT | 1}
	var place := {"id": 7, "starbase_owner": -1, "starbase_slot": 0, "ships": 2, "designs": 2}
	var battle := _battle(3, 2, 0, [ours, theirs])
	battle.x = 10
	battle.y = 20
	var rng := StarsRandom.new(5, 673)
	Battles.finish(
		state, _content, rng, StarsRandom.new(7, 7), battle, [ours, theirs], engine, place
	)
	var won: Dictionary = _messages(state, 0)[0]
	assert_str(won.type).is_equal("message.battle.duel_won")
	assert_dict(won.goto).is_equal({"battle": 7})
	assert_array(won.params).is_equal([10, 20, 2, 34])
	var lost: Array = _messages(state, 1)
	assert_int(lost.size()).is_equal(1)
	assert_str(lost[0].type).is_equal("message.battle.duel_lost")
	assert_array(lost[0].params).is_equal([10, 20, 34, 2])


func test_two_sides_counts_ships_and_names_the_enemy() -> void:
	# player 0's 1 ship of fleet 2 and fleet 3 against player 1's lone ship, destroyed
	var state := _load()
	TurnMessages.clear(state)
	var a := state.fleet(0, 2)
	var b := state.fleet(0, 3)
	var theirs := state.fleet(1, 2)
	theirs.stacks.clear()
	var engine := _engine(state)
	engine.losses = {1 * 16 + 2: BattleEngine.LOSS_HIT | 1}
	var place := {"id": 7, "starbase_owner": -1, "starbase_slot": 0, "ships": 3, "designs": 3}
	var battle := _battle(3, 2, 0, [a, b, theirs])
	var rng := StarsRandom.new(5, 673)
	Battles.finish(
		state, _content, rng, StarsRandom.new(7, 7), battle, [a, b, theirs], engine, place
	)
	var won: Dictionary = _messages(state, 0)[0]
	assert_str(won.type).is_equal("message.battle.won_one")
	assert_array(won.params).is_equal([0, 0, 1, 2, 34])
	assert_str(_messages(state, 1)[0].type).is_equal("message.battle.lost_one")
	assert_array(_messages(state, 1)[0].params).is_equal([0, 0, 0, 34, 2])
