extends GdUnitTestSuite
## Golden turns (plan M4/M6): from each fixture turn and the players' orders for it
## (tNNN.pP.orders.json), our turn generation must give the original's next turn exactly. Only the
## random streams are ignored (a fixture holds the state at the start of the next turn's
## generation, S01), ship design names (fixtures hold neutral names by slot, while a transferred
## design keeps the giver's name, S11), battle plan names (neutral names by number, while a
## deleted plan's successors keep theirs, S11), the score history and the players' planet
## history (the original keeps both in the players' history files, S20, S15), plus what a game's
## phases not built yet would change (GAME_IGNORE), or, for single turns, what a fixed bug changes
## (TURN_IGNORE, the S25 allowlist).
##
## The turns run in compat mode (D12): the test-only harness_compat mod puts back the original's
## behaviour for the few known bugs fixtures cannot avoid (B09), so everything around them is
## checked exactly.
##
## The base of the golden-turn suites (no tests of its own): test_golden_turns.gd (the games
## played in the original client), test_golden_ai_a.gd and test_golden_ai_b.gd (the computer
## player games, S22), split so CI can run them side by side.

const IGNORE := [
	"/rng",
	"/players/*/ship_designs*/name",
	"/players/*/battle_plans*/name",
	"/history*",
	"/players/*/knowledge*",
]
const GAME_IGNORE := {}
## Allowed divergences of single turns (the S25 allowlist): what a fixed bug changes.
const TURN_IGNORE := {
	# B41: the original refuses a Pick Pocket fleet's load from player 2's colony ship ("load
	# cancelled"); we steal the 3 kT and say so
	"steal1":
	{
		22: ["/fleets[0:2]/cargo/0", "/fleets[1:1]/cargo/0", "/messages/0/6*"],
	},
	# B38: the comet changes the axes its message names, not gravity first. B32: a damaged ship
	# moved into a fleet's damaged stack of its design (a merge); the original spreads the stack's
	# damage over all its ships, so the battle that follows starts the stack with less
	"big1":
	{
		66: ["/battles/3", "/fleets[1:31]/stacks[14]/damage*", "/fleets[1:43]/stacks[14]/damage*"],
		68: ["/battles/6", "/fleets[1:31]/stacks[14]/damage*"],
		69: ["/battles/3", "/fleets[1:31]/stacks[14]/damage*"],
		74: ["/planets/118/environment*"],
	},
	# B32 and B38 likewise
	"turin1":
	{
		61: ["/battles/0", "/fleets[1:3]/stacks[10]/damage*"],
		72: ["/planets/67/environment*"],
	},
}

const CompatContent := preload("res://tests/unit/compat_content.gd")

var _content: ContentRegistry


func before() -> void:
	var r := CompatContent.load_mods()
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _load(game: String, turn: int) -> GameState:
	var path := "res://tests/fixtures/golden/%s/t%03d.json" % [game, turn]
	var result := SaveFile.decode(FileAccess.get_file_as_string(path), _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	return result.state


func _orders(game: String, turn: int, players: int) -> Array[OrderSet]:
	var out: Array[OrderSet] = []
	for p in players:
		var path := "res://tests/fixtures/golden/%s/t%03d.p%d.orders.json" % [game, turn, p]
		if not FileAccess.file_exists(path):
			continue
		var result := OrderFile.read(path)
		assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
		out.append(result.order_set)
	return out


## With `computers`, the computer players play first (S22), knowing what the fixture's players
## know (their planet history and memory, as our replay of the earlier turns carried them).
func _check_turn(game: String, turn: int, computers := false) -> void:
	var state := _load(game, turn)
	var sets := _orders(game, turn, state.players.size())
	if computers:
		var errors := PackedStringArray()
		sets.append_array(ComputerPlayers.add_orders(state, _content, [], errors))
		assert_array(Array(errors)).override_failure_message("\n".join(errors)).is_empty()
	var rejected := StandardTurn.generate(state, _content, sets)
	assert_array(Array(rejected)).override_failure_message("\n".join(rejected)).is_empty()
	var expected := _load(game, turn + 1)
	var ignore := PackedStringArray(IGNORE)
	ignore.append_array(GAME_IGNORE.get(game, []))
	ignore.append_array(TURN_IGNORE.get(game, {}).get(turn, []))
	_known_messages_only(expected, state, ignore)
	# player views (S15) only where the fixture kept the players' turn files
	if expected.views.is_empty():
		ignore.append("/views*")
	# score records (S20) likewise: a player's own turn file holds its record
	for p in expected.players.size():
		if expected.player(p).score.is_empty():
			ignore.append("/players/%d/score*" % p)
	var diffs := StateDiff.compare(expected, state, ignore)
	(
		assert_array(diffs)
		. override_failure_message(
			(
				"%s turn %d -> %d: %d differences\n%s"
				% [game, turn, turn + 1, diffs.size(), StateDiff.format(diffs, 40)]
			)
		)
		. is_empty()
	)


## Turn messages (S21) are compared only for the message types built so far (a fixture lists every
## message the original sent, as "legacy.message.<n>" when we have no content id for it), and not
## at all for fixtures without message data (an empty list: the run kept no turn files).
func _known_messages_only(expected: GameState, ours: GameState, ignore: PackedStringArray) -> void:
	if expected.messages.is_empty():
		ignore.append("/messages*")
		return
	for s: GameState in [expected, ours]:
		var lists := []
		for list: Array in s.messages:
			lists.append(
				list.filter(func(m: Dictionary) -> bool: return _content.has_def(m["type"]))
			)
		s.messages = lists
