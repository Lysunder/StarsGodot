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
	Battles.finish(state, _content, rng, fixes, battle, group, _engine(state), -1)


func _battle(players: int, sides: int, bystanders: int, fleets: Array) -> Dictionary:
	return {
		"players": players,
		"sides": sides,
		"bystanders": bystanders,
		"planet": -1,
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
