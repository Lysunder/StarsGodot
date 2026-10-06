extends GdUnitTestSuite
## M11 step 7: the report rows and the original's two-level sort.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## A new game with a second, smaller colony.
func _view() -> PlayerView:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 77
	options.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
	var s := NewGame.create(_content, options)
	for pl in s.planets:
		if pl.owner < 0:
			pl.owner = 0
			pl.population = 30
			break
	return PlayerView.new(s, _content, 0)


func test_planet_rows_show_the_columns() -> void:
	var view := _view()
	var rows := ReportView.rows(view, ReportView.PLANETS)
	assert_int(rows.size()).is_equal(2)
	var home_id := view.me().homeworld
	var home: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r["id"] == home_id)[0]
	assert_str(home["starbase"]).is_not_empty()
	assert_bool(home["dock"] or home["no_dock"]).is_true()
	assert_int(home["population"]).is_equal(view.state.planet(home["id"]).population * 100)
	assert_int(home["minerals"].size()).is_equal(3)
	assert_int(home["resources_available"]).is_less_equal(home["resources"])
	for column: String in ReportView.COLUMNS[ReportView.PLANETS]:
		ReportView.key(ReportView.PLANETS, column, 0, home)


func test_sort_forward_reverse_and_second_level() -> void:
	var view := _view()
	var rows := ReportView.rows(view, ReportView.PLANETS)
	var pop := {"column": "population", "sub": 0, "forward": true}
	var ids := ReportView.sorted(rows, ReportView.PLANETS, pop, {}).map(
		func(r: Dictionary) -> int: return r["population"]
	)
	assert_bool(ids[0] < ids[1]).is_true()
	pop["forward"] = false
	ids = ReportView.sorted(rows, ReportView.PLANETS, pop, {}).map(
		func(r: Dictionary) -> int: return r["population"]
	)
	assert_bool(ids[0] > ids[1]).is_true()
	# equal by the first level: the second decides
	var cap := {"column": "mines", "sub": 0, "forward": true}
	for r in rows:
		r["mines"] = 5
	var by_pop := ReportView.sorted(rows, ReportView.PLANETS, cap, pop)
	assert_bool(by_pop[0]["population"] > by_pop[1]["population"]).is_true()
	# a starbase sorts first
	var sb := {"column": "starbase", "sub": 0, "forward": true}
	assert_str(ReportView.sorted(rows, ReportView.PLANETS, sb, {})[0]["starbase"]).is_not_empty()


func test_fleet_rows_and_order() -> void:
	var view := _view()
	var rows := ReportView.rows(view, ReportView.FLEETS)
	assert_int(rows.size()).is_equal(view.fleets().size())
	for r in rows:
		assert_str(r["location"]).is_not_empty()
		assert_str(r["composition"]["name"]).is_not_empty()
		assert_int(r["cargo"].size()).is_equal(4)
		assert_int(r["eta"]).is_equal(-1)
	var by_name := {"column": "name", "sub": 0, "forward": false}
	var order := ReportView.order(view, ReportView.FLEETS, by_name, {})
	var names := order.map(func(n: int) -> String: return view.fleet_name(view.state.fleet(0, n)))
	var expected := names.duplicate()
	expected.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) > 0)
	assert_array(names).is_equal(expected)


func test_short_numbers() -> void:
	assert_str(ReportTable.short_number(9999)).is_equal("9999")
	assert_str(ReportTable.short_number(12499)).is_equal("12k")
	assert_str(ReportTable.short_number(12500)).is_equal("13k")
	assert_str(ReportTable.short_number(999999)).is_equal("999k")
	assert_str(ReportTable.short_number(2500000)).is_equal("3M")
