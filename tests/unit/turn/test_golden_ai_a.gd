extends "res://tests/unit/turn/golden_base.gd"
## Golden turns of computer player games (S22; golden_base.gd): big1, roto1, auto1, mac1.

## Five Robotoids computer players and an idle human (S22 stage 4). Turns left out: B12 (73, 75: a
## caught fleet that was itself chasing stops).
@warning_ignore("unused_parameter")
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
		[66],
		[67],
		[68],
		[69],
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


## Five Automitrons computer players and an idle human (S22 stage 4).
@warning_ignore("unused_parameter")
func test_auto1(
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
		[71],
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
	_check_turn("auto1", turn, true)


## Five Rototills computer players and an idle human (S22 stage 4).
@warning_ignore("unused_parameter")
func test_roto1(
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
		[71],
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
	_check_turn("roto1", turn, true)


## An idle human, a Robotoids, three Macinti and a Turindrones computer player (S22 stage 4).
## Turns left out: B12 (76, 79: a fleet a lower-numbered fleet chases doesn't move). 62, 63 and 66
## have two fleets chasing each other: the one reached has finished, and its chasers go at once.
@warning_ignore("unused_parameter")
func test_mac1(
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
		[71],
		[72],
		[73],
		[74],
		[75],
		[77],
		[78],
	]
) -> void:
	_check_turn("mac1", turn, true)
