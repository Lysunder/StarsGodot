extends "res://tests/unit/turn/golden_base.gd"
## Golden turns of computer player games (S22; golden_base.gd): turin1, cyber1.


## Five Turindrones computer players and an idle human (S22 stage 4). Turn left out: B12 (71: a
## caught fleet that was itself chasing stops). Turn 77: a fleet crossing two overlapping fields of
## one type rolls once per light year of the joined stretch (S13).
func test_turin1(
	turn: int,
	# gdlint: ignore=unused-argument
	test_parameters := [
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
		[72],
		[73],
		[74],
		[75],
		[76],
		[77],
		[78],
		[79],
	]
) -> void:
	_check_turn("turin1", turn, true)


## An idle human, a Robotoids, three Cybertrons and a Rototills computer player (S22 stage 4).
## Turns left out: B32 (70, 71: damage on ship moves).
func test_cyber1(
	turn: int,
	# gdlint: ignore=unused-argument
	test_parameters := [
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
		[72],
		[73],
		[74],
		[75],
		[76],
		[77],
		[78],
		[79],
	]
) -> void:
	_check_turn("cyber1", turn, true)
