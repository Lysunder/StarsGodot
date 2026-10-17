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
	# B38: the comet changes the axes its message names, not gravity first
	"big1":
	{
		74: ["/planets/118/environment*"],
	},
	# B38 likewise
	"turin1":
	{
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
		[70],
		[71],
		[72],
		[73],
		[74],
		[75],
		[76],
		[77],
		[78],
		[79],
		[80],
		[81],
		[82],
		[83],
		[84],
		[85],
		[86],
		[87],
		[88],
		[89],
		[90],
		[91],
		[92],
		[93],
		[94],
		[95],
		[96],
		[97],
		[98],
		[99],
		[100],
		[101],
		[102],
		[103],
		[104],
		[105],
		[106],
		[107],
		[108],
		[109],
		[110],
		[111],
		[112],
		[113],
		[114],
		[115],
		[116],
		[117],
		[118],
		[119],
		[120],
		[121],
		[122],
		[123],
		[124],
		[125],
		[126],
		[127],
		[128],
		[129],
		[130],
		[131]
	]
) -> void:
	_check_turn("mine1", turn)


## M10: random events and the Mystery Trader (S18), score and victory (S20): a tiny universe with
## random events on, the long1 race played in the client against an idle Space Demolition race.
func test_rand1(
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
		[70],
		[71],
		[72],
		[73],
		[74],
		[75],
		[76],
		[77],
		[78],
		[79],
		[80],
		[81],
		[82],
		[83],
		[84],
		[85],
		[86],
		[87],
		[88],
		[89],
		[90],
		[91],
		[92],
		[93],
		[94],
		[95],
		[96],
		[97],
		[98],
		[99],
		[100],
		[101],
		[102],
		[103],
	]
) -> void:
	_check_turn("rand1", turn)


func test_steal1(
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
	]
) -> void:
	_check_turn("steal1", turn)


func test_plan1(
	turn: int,
	# gdlint: ignore=unused-argument
	test_parameters := [
		[0],
		[1],
	]
) -> void:
	_check_turn("plan1", turn)


## Five Robotoids computer players and an idle human (S22 stage 4). Turns left out: B32 (66, 68:
## merged damage), B12 (73, 75: a caught fleet that was itself chasing stops) and 69 (one draw short
## somewhere between player 5's last fleet pass and the first engine roll; not found yet).
func test_big1(
	turn: int,
	# gdlint: ignore=unused-argument
	test_parameters := [
		[60],
		[61],
		[62],
		[63],
		[64],
		[65],
		[67],
		[70],
		[71],
		[72],
		[74],
		[76],
		[77],
		[78],
		[79],
	]
) -> void:
	_check_turn("big1", turn, true)


## Five Turindrones computer players and an idle human (S22 stage 4). Turns left out: B32 (61:
## merged damage), B12 (71: a caught fleet that was itself chasing stops) and 77 (mining one off on
## several planets, battle token order and wormholes differ; not found yet).
func test_turin1(
	turn: int,
	# gdlint: ignore=unused-argument
	test_parameters := [
		[60],
		[62],
		[63],
		[64],
		[65],
		[66],
		[67],
		[68],
		[69],
		[70],
		[72],
		[73],
		[74],
		[75],
		[76],
		[78],
		[79],
	]
) -> void:
	_check_turn("turin1", turn, true)
