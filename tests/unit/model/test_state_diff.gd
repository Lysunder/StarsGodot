extends GdUnitTestSuite
## StateDiff: field-by-field differences, identity matching for numbered objects, ignores.

const SampleGame := preload("res://tests/fixtures/model/sample_game.gd")


func _texts(diffs: Array[StateDiff.Difference]) -> Array:
	return diffs.map(func(d: StateDiff.Difference) -> String: return str(d))


func test_equal_states_have_no_differences() -> void:
	assert_array(StateDiff.compare(SampleGame.build(), SampleGame.build())).is_empty()


func test_reports_changed_fields_with_paths() -> void:
	var a := SampleGame.build()
	var b := SampleGame.build()
	b.turn = 8
	b.planets[2].surface[1] = 201
	b.players[1].race.lesser_traits.append("trait.lrt.GR")
	b.fleet(1, 0).stacks[0].count = 5
	(
		assert_array(_texts(StateDiff.compare(a, b)))
		. is_equal(
			[
				"/fleets[1:0]/stacks[3]/count: 2 -> 5",
				"/planets/2/surface/1: 200 -> 201",
				'/players/1/race/lesser_traits/2: added "trait.lrt.GR"',
				"/turn: 7 -> 8",
			]
		)
	)


func test_matches_fleets_by_identity() -> void:
	var a := SampleGame.build()
	var b := SampleGame.build()
	var created := b.add_fleet(0, 512)
	created.add_ships(3, 1)
	created.waypoints.append(Waypoint.new(1000, 1100))
	b.remove_fleet(b.fleet(1, 0))
	var diffs := StateDiff.compare(a, b)
	assert_array(_texts(diffs)).is_equal(
		["/fleets[0:1]: added {12 fields}", "/fleets[1:0]: removed {12 fields}"]
	)
	assert_str(diffs[0].kind).is_equal(StateDiff.ADDED)
	assert_int(diffs[0].after["number"]).is_equal(1)


func test_matches_designs_and_space_objects_by_identity() -> void:
	var a := SampleGame.build()
	var b := SampleGame.build()
	var d := Design.new()
	d.slot = 1
	d.hull = "hull.scout"
	b.players[0].set_design(d, false)
	b.wormholes[1].stability = 9
	b.add_minefield(1, 512).mines = 10
	(
		assert_array(_texts(StateDiff.compare(a, b)))
		. is_equal(
			[
				"/minefields[1:0]: added {9 fields}",
				"/players/0/ship_designs[1]: added {9 fields}",
				"/wormholes[1]/stability: 0 -> 9",
			]
		)
	)


func test_ignore_patterns() -> void:
	var a := SampleGame.build()
	var b := SampleGame.build()
	b.rng.get_stream("classic").next_raw()
	b.planets[0].mines = 11
	b.planets[1].mines = 12
	b.fleet(1, 0).cargo[4] = 1
	b.turn = 9
	var diffs := StateDiff.compare(a, b, PackedStringArray(["/rng", "/planets/*/mines", "/fleets"]))
	assert_array(_texts(diffs)).is_equal(["/turn: 7 -> 9"])


func test_whole_floats_equal_ints() -> void:
	var a := SampleGame.build().to_dict()
	var b: Dictionary = JSON.parse_string(JSON.stringify(a))
	assert_array(StateDiff.compare_dicts(a, b)).is_empty()
	b["turn"] = 7.5
	assert_array(_texts(StateDiff.compare_dicts(a, b))).is_equal(["/turn: 7 -> 7.5"])


func test_format_limits_lines() -> void:
	var a := SampleGame.build()
	var b := SampleGame.build()
	for pl in b.planets:
		pl.mines += 1
	var text := StateDiff.format(StateDiff.compare(a, b), 2)
	assert_str(text).is_equal(
		"/planets/0/mines: 10 -> 11\n/planets/1/mines: 10 -> 11\n... and 1 more"
	)


func test_golden_turns_differ_in_expected_places() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	var t0 := SaveFile.decode(
		FileAccess.get_file_as_string("res://tests/fixtures/golden/tiny2/t000.json"), r.registry
	)
	var t1 := SaveFile.decode(
		FileAccess.get_file_as_string("res://tests/fixtures/golden/tiny2/t001.json"), r.registry
	)
	var diffs := StateDiff.compare(t0.state, t1.state)
	var paths: Array = diffs.map(func(d: StateDiff.Difference) -> String: return d.path)
	assert_array(paths).contains(["/turn"])
	# homeworld populations grow in the first year
	assert_bool(paths.any(func(p: String) -> bool: return p.ends_with("/population"))).is_true()
