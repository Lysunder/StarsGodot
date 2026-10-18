extends "res://tests/unit/turn/golden_base.gd"
## Golden turns of the games played in the original client (golden_base.gd).


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
