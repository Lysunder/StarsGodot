extends GdUnitTestSuite
## Golden turns (plan M4/M6): from each fixture turn and the players' orders for it
## (tNNN.pP.orders.json), our turn generation must give the original's next turn exactly. Only the
## random streams are ignored (a fixture holds the state at the start of the next turn's
## generation, S01), ship design names (fixtures hold neutral names by slot, while a transferred
## design keeps the giver's name, S11), plus what a game's phases not built yet would change
## (GAME_IGNORE), or, for single turns, what an event not built yet changed (TURN_IGNORE).

const IGNORE := ["/rng", "/players/*/ship_designs*/name"]
const GAME_IGNORE := {}
## terra1 turn 30: player 1's starbase fought player 2's gift fleet at its homeworld (battles, M9;
## the battle also shows both sides' designs in full, S15); turn 40: player 2's colonists unloaded
## onto player 1's colony fought its ground troops (ground combat, S17); mine1 turn 69: player 2's
## patrol caught player 1's fleet 2 (a battle: damage, designs shown in full).
const TURN_IGNORE := {
	"terra1":
	{
		30:
		[
			"/fleets[1:1]*",
			"/planets/23/starbase/damage",
			"/planets/23/surface*",
			"/players/1/ship_designs[3]/remaining",
			"/views/*designs/*",
		],
		40: ["/planets/30/population"],
	},
	"mine1": {69: ["/fleets[0:2]/stacks[2]/damage*", "/views/*designs/*"]},
}

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
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


func _check_turn(game: String, turn: int) -> void:
	var state := _load(game, turn)
	var rejected := StandardTurn.generate(
		state, _content, _orders(game, turn, state.players.size())
	)
	assert_array(Array(rejected)).override_failure_message("\n".join(rejected)).is_empty()
	var expected := _load(game, turn + 1)
	var ignore := PackedStringArray(IGNORE)
	ignore.append_array(GAME_IGNORE.get(game, []))
	ignore.append_array(TURN_IGNORE.get(game, {}).get(turn, []))
	_known_messages_only(expected, state, ignore)
	# player views (S15) only where the fixture kept the players' turn files
	if expected.views.is_empty():
		ignore.append("/views*")
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


## Two human players without orders, no random events: mining, research, growth.
# gdlint: ignore=unused-argument
func test_tiny2(turn: int, test_parameters := [[0], [1], [2], [3], [4]]) -> void:
	_check_turn("tiny2", turn)


## A human player's production orders, given in the original client: factories with partial
## progress, a ship, auto items and their carry-over, "only leftover to research" (S09, S11).
# gdlint: ignore=unused-argument
func test_prod1(turn: int, test_parameters := [[0], [1], [2], [3], [4]]) -> void:
	_check_turn("prod1", turn)


## Turns 0-1: both players load colonists and send colony ships, which move, colonize and found
## colonies (S11, S12). Then a Total Terraforming race's terraform items on its colony and a Claim
## Adjuster colony terraforming itself (S10); research level gains. Turns 0-3 and 13-28.
func test_terra1(
	turn: int,
	# gdlint: ignore=unused-argument
	test_parameters := [
		[0],
		[1],
		[2],
		[13],
		[14],
		[15],
		[16],
		[17],
		[18],
		[19],
		[20],
		[21],
		[22],
		[23],
		[24],
		[25],
		[26],
		[27],
		[28],
		[29],
		[30],
		[31],
		[32],
		[33],
		[34],
		[35],
		[36],
		[37],
		[38],
		[39],
		[40],
		[41],
		[42],
		[43],
		[44],
		[45],
	]
) -> void:
	_check_turn("terra1", turn)


## long1 (the M6 long game): one player playing normally, checked in batches.
func test_long1(
	turn: int,
	# gdlint: ignore=unused-argument
	test_parameters := [
		[0],
		[1],
		[2],
		[3],
		[4],
		[5],
		[6],
		[7],
		[8],
		[9],
		[10],
		[11],
		[12],
		[13],
		[14],
		[15],
		[16],
		[17],
		[18],
		[19],
		[20],
		[21],
		[22],
		[23],
		[24],
		[25],
		[26],
		[27],
		[28],
		[29],
		[30],
		[31],
		[32],
		[33],
		[34]
	]
) -> void:
	_check_turn("long1", turn)


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


## M7: following and chasing fleets (S12), orders given in the original client: turn 0 three
## follow orders on waypoint 0 (a chain of two, and one whose fleet isn't going anywhere); turn 1
## chasing a moving fleet; turn 2 a fleet chasing a chaser, in steps; turn 3 a chased fleet merged;
## turns 4-5 plain moves; turn 13 a jump through a wormhole.
# gdlint: ignore=unused-argument
func test_follow1(turn: int, test_parameters := [[0], [1], [2], [3], [4], [5], [13]]) -> void:
	_check_turn("follow1", turn)


## M7: stargates (S12) with an Inter-stellar Traveler race (gates at its homeworld and extra
## planet), orders given in the original client: turn 0 a jump within the limits, two ships over
## the gates' mass limit (damage), and a jump to a planet without a gate; turn 1 the damaged ships
## jump back (damage adds up, one is destroyed).
# gdlint: ignore=unused-argument
func test_gate1(turn: int, test_parameters := [[0], [1]]) -> void:
	_check_turn("gate1", turn)


## M7: minefields (S13), two players (a Space Demolition race and the long1 race), orders given in
## the original client (other turns generated without orders): mine laying in place and while
## moving, merging into fields, decay, fleets crossing fields, speed-bump hits in turns 30 and 31.
func test_mine1(
	turn: int,
	# gdlint: ignore=unused-argument
	test_parameters := [
		[0],
		[1],
		[2],
		[3],
		[4],
		[5],
		[6],
		[7],
		[8],
		[9],
		[10],
		[11],
		[12],
		[13],
		[14],
		[15],
		[16],
		[17],
		[18],
		[19],
		[20],
		[21],
		[22],
		[23],
		[24],
		[25],
		[26],
		[27],
		[28],
		[29],
		[30],
		[31],
		[32],
		[33],
		[34],
		[35],
		[36],
		[37],
		[38],
		[39],
		[40],
		[41],
		[42],
		[43],
		[44],
		[45],
		[46],
		[47],
		[48],
		[49],
		[50],
		[51],
		[52],
		[53],
		[54],
		[55],
		[56],
		[57],
		[58],
		[59],
		[60],
		[61],
		[62],
		[63],
		[64],
		[65],
		[66],
		[67],
		[68],
		[69],
		[70]
	]
) -> void:
	_check_turn("mine1", turn)
