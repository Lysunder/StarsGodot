extends GdUnitTestSuite
## M11 step 8: playing back a battle record step by step (the battle viewer) and the Battle
## Summary report's counts, on recorded battles from the golden fixtures.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _view(game: String, turn: int, player: int) -> PlayerView:
	var path := "res://tests/fixtures/golden/%s/t%03d.json" % [game, turn]
	var result := SaveFile.decode(FileAccess.get_file_as_string(path), _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	return PlayerView.new(result.state, _content, player)


## terra1 turn 31: player 1's destroyer, two scouts and a freighter attack player 0's colony ship
## at its starbase; the starbase kills a scout.
func test_summary_row_counts_the_sides() -> void:
	var view := _view("terra1", 31, 0)
	var battles := BattleReplay.battles(view)
	assert_int(battles.size()).is_equal(1)
	var row := BattleReplay.summary_row(view, battles[0])
	assert_str(row["location"]).is_equal(view.state.planet(23).name)
	assert_str(row["starbase"]).is_equal("O")
	assert_int(row["sides"]).is_equal(2)
	assert_int(row["units"]).is_equal(6)
	assert_int(row["ours"]).is_equal(2)
	assert_int(row["theirs"]).is_equal(4)
	assert_int(row["unarmed"]).is_equal(2)
	assert_int(row["scout"]).is_equal(3)
	assert_int(row["warship"]).is_equal(0)
	assert_int(row["our_dead"]).is_equal(0)
	assert_int(row["their_dead"]).is_equal(1)
	assert_int(row["ours_left"]).is_equal(2)
	assert_int(row["theirs_left"]).is_equal(3)
	# the other side sees the starbase as theirs and the losses the other way round
	var other := BattleReplay.summary_row(_view("terra1", 31, 1), battles[0])
	assert_str(other["starbase"]).is_equal("T")
	assert_int(other["our_dead"]).is_equal(1)
	assert_int(other["ours"]).is_equal(4)


func test_report_lists_the_battles() -> void:
	var view := _view("terra1", 31, 0)
	assert_int(ReportView.rows(view, ReportView.BATTLES).size()).is_equal(1)
	assert_int(ReportView.rows(_view("terra1", 30, 0), ReportView.BATTLES).size()).is_equal(0)


func test_steps_move_tokens_and_land_hits() -> void:
	var view := _view("terra1", 31, 0)
	var replay := BattleReplay.new(view, BattleReplay.battles(view)[0])
	assert_int(replay.step).is_equal(-1)
	assert_int(replay.last).is_equal(44)
	assert_int(replay.last_round).is_equal(15)
	assert_dict(replay.action()).is_empty()
	# event 22: the starbase (token 5) kills the scout (token 2)
	replay.seek(22)
	assert_int(replay.current_round()).is_equal(4)
	assert_int(replay.tokens[2]["count"]).is_equal(0)
	assert_array(replay.tokens_at(88)).not_contains([2])
	var a := replay.action()
	assert_int(a["token"]).is_equal(5)
	assert_int(a["target"]).is_equal(2)
	assert_int(a["killed"]).is_equal(1)
	var scout_armor := PartRules.armor(replay.design(2), _content, view.state.player(1).race)
	assert_int(a["armor_damage"]).is_equal(scout_armor)
	# event 23: a torpedo the starbase's shields absorb
	replay.seek(23)
	a = replay.action()
	assert_int(int(replay.tokens[0]["square"])).is_equal(69)
	assert_bool(a["no_damage"]).is_true()
	# event 27: 2 damage to the starbase's shields and some to its armor
	replay.seek(27)
	a = replay.action()
	assert_int(a["shield_damage"]).is_equal(2)
	assert_int(int(replay.tokens[5]["shields"])).is_equal(798)
	assert_int(a["armor_damage"]).is_greater(0)
	var s := replay.status(5)
	assert_bool(s["starbase"]).is_true()
	assert_int(s["movement_quarters"]).is_equal(-1)
	assert_int(s["damage_pct"]).is_greater(0)


func test_seeking_back_gives_the_same_board() -> void:
	var view := _view("terra1", 31, 0)
	var b := BattleReplay.battles(view)[0]
	var forward := BattleReplay.new(view, b)
	forward.seek(30)
	var back := BattleReplay.new(view, b)
	back.seek(44)
	back.seek(30)
	assert_array(back.tokens).is_equal(forward.tokens)
	back.seek(-1)
	assert_int(back.step).is_equal(-1)
	for i in back.tokens.size():
		assert_int(int(back.tokens[i]["square"])).is_equal(int(b["tokens"][i]["square"]))
	back.seek(1000)
	assert_int(back.step).is_equal(44)


## The damage word: armor points per damaged ship in 1/500ths of its armor (high bits), and the
## percent of ships damaged (low 7 bits).
func test_armor_left_and_damage_status() -> void:
	var view := _view("terra1", 31, 0)
	var replay := BattleReplay.new(view, BattleReplay.battles(view)[0])
	var armor := PartRules.armor(replay.design(3), _content, view.state.player(1).race)
	# four ships, half of them damaged by half their armor: one ship's armor is gone
	replay.tokens[3]["count"] = 4
	replay.tokens[3]["damage"] = 250 << 7 | 50
	assert_int(replay.armor_left(3)).is_equal(3 * armor)
	var s := replay.status(3)
	assert_int(s["damaged"]).is_equal(2)
	assert_int(s["damage_pct"]).is_equal(50)
	assert_int(s["movement_quarters"]).is_equal(3)


## mine1 turn 86: the last of player 0's ships is destroyed by a torpedo.
func test_a_destroyed_token_leaves_the_board() -> void:
	var view := _view("mine1", 86, 0)
	var replay := BattleReplay.new(view, BattleReplay.battles(view)[0])
	replay.seek(9)
	assert_int(int(replay.tokens[1]["count"])).is_equal(0)
	assert_bool(replay.status(1)["alive"]).is_false()
	assert_array(replay.tokens_at(int(replay.tokens[1]["square"]))).is_empty()
	var row := BattleReplay.summary_row(view, replay.battle)
	assert_int(row["our_dead"]).is_equal(1)
	assert_int(row["ours_left"]).is_equal(0)
