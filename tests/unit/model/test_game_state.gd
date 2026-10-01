extends GdUnitTestSuite
## Spec S03: the model round-trips, copies deeply, compares by saved form, and keeps the
## original's numbering and iteration order.

const SampleGame := preload("res://tests/fixtures/model/sample_game.gd")
const FLEET_LIMIT := 512


static func sample_state() -> GameState:
	return SampleGame.build()


func _reload(text: String) -> GameState:
	var parsed := JsonReader.parse(text)
	assert_bool(parsed.ok).is_true()
	var errors := PackedStringArray()
	var loaded := ModelObject.object_from(GameState, parsed.value, "", errors) as GameState
	assert_array(Array(errors)).is_empty()
	return loaded


func test_round_trip_through_json() -> void:
	var state := sample_state()
	var loaded := _reload(JSON.stringify(state.to_dict()))
	assert_bool(loaded.equals(state)).is_true()
	assert_str(loaded.state_hash()).is_equal(state.state_hash())
	assert_int(loaded.fleet(1, 0).stacks[0].count).is_equal(2)
	assert_int(loaded.rng.get_stream("classic").next_raw()).is_equal(
		state.rng.get_stream("classic").next_raw()
	)


func test_round_trip_with_godot_json_floats() -> void:
	var state := sample_state()
	var errors := PackedStringArray()
	var data: Variant = JSON.parse_string(JSON.stringify(state.to_dict()))
	var loaded := ModelObject.object_from(GameState, data, "", errors) as GameState
	assert_array(Array(errors)).is_empty()
	assert_bool(loaded.equals(state)).is_true()


func test_canonical_text_is_stable() -> void:
	var a := sample_state()
	var b := sample_state()
	b.mod_data = {"extra_hulls": {"a": [1, "x", true, null], "b": 2}}
	assert_str(a.canonical_text()).is_equal(b.canonical_text())
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_int(a.state_hash().length()).is_equal(64)


func test_any_change_changes_equality_and_hash() -> void:
	var a := sample_state()
	var b := sample_state()
	b.planets[2].surface[1] += 1
	assert_bool(a.equals(b)).is_false()
	assert_str(a.state_hash()).is_not_equal(b.state_hash())
	var c := sample_state()
	c.rng.get_stream("classic").next_raw()
	assert_bool(a.equals(c)).is_false()


func test_copy_is_deep() -> void:
	var state := sample_state()
	var copy := state.copy() as GameState
	assert_bool(copy.equals(state)).is_true()
	copy.fleet(1, 0).stacks[0].count = 99
	copy.players[0].race.lesser_traits.append("trait.lrt.gr")
	copy.mod_data["extra_hulls"]["b"] = 3
	copy.rng.get_stream("classic").next_raw()
	assert_int(state.fleet(1, 0).stacks[0].count).is_equal(2)
	assert_int(state.players[0].race.lesser_traits.size()).is_equal(2)
	assert_int(state.mod_data["extra_hulls"]["b"]).is_equal(2)
	assert_bool(copy.equals(state)).is_false()


func test_turn_only_marks_are_not_saved() -> void:
	var a := sample_state()
	var b := sample_state()
	a.fleet(1, 0).did_not_move = true
	a.fleet(1, 0).waypoints[0].frozen = true
	assert_bool(a.equals(b)).is_true()
	assert_bool(a.to_dict()["fleets"][0].has("did_not_move")).is_false()
	assert_bool((a.copy() as GameState).fleet(1, 0).did_not_move).is_false()


func test_lowest_free_fleet_number() -> void:
	var state := GameState.new()
	for i in 4:
		state.add_fleet(2, FLEET_LIMIT)
	state.add_fleet(1, FLEET_LIMIT)
	state.remove_fleet(state.fleet(2, 2))
	var created := state.add_fleet(2, FLEET_LIMIT)
	assert_int(created.number).is_equal(2)
	var keys := []
	for f in state.fleets:
		keys.append([f.owner, f.number])
	assert_array(keys).is_equal([[1, 0], [2, 0], [2, 1], [2, 2], [2, 3]])
	assert_int(state.add_fleet(2, FLEET_LIMIT).number).is_equal(4)
	assert_object(state.fleet(2, 2)).is_same(created)
	assert_object(state.fleet(3, 0)).is_null()
	assert_int(state.fleets_of(2).size()).is_equal(5)


func test_fleet_limit() -> void:
	var state := GameState.new()
	for i in 3:
		assert_object(state.add_fleet(0, 3)).is_not_null()
	assert_object(state.add_fleet(0, 3)).is_null()
	assert_object(state.add_fleet(1, 3)).is_not_null()


func test_space_objects_combined_order() -> void:
	var state := GameState.new()
	state.add_wormhole(512)
	state.add_packet(0, false, 512)
	state.add_minefield(1, 512)
	state.add_minefield(0, 512)
	state.add_packet(0, true, 512)
	state.add_trader(512)
	var order := []
	for obj in state.space_objects():
		order.append(obj.get_script().get_global_name())
	assert_array(order).is_equal(
		["Minefield", "Minefield", "Packet", "Packet", "Wormhole", "Trader"]
	)
	assert_int((state.space_objects()[0] as Minefield).owner).is_equal(0)
	assert_array([state.packets[0].number, state.packets[1].number]).is_equal([0, 1])
	assert_bool(state.packets[1].salvage).is_true()
	assert_int(state.space_object_count()).is_equal(6)


func test_fleet_stacks_stay_in_design_order() -> void:
	var f := Fleet.new()
	f.add_ships(5, 1)
	f.add_ships(2, 3)
	f.add_ships(5, 4)
	assert_array([f.stacks[0].design, f.stacks[1].design]).is_equal([2, 5])
	assert_int(f.stack_for(5).count).is_equal(5)
	assert_int(f.ship_count()).is_equal(8)


func test_designs_keep_their_slots() -> void:
	var p := Player.new()
	for slot in [4, 1, 9]:
		var d := Design.new()
		d.slot = slot
		p.set_design(d, true)
	p.remove_design(4, true)
	assert_array(p.starbase_designs.map(func(d: Design) -> int: return d.slot)).is_equal([1, 9])
	assert_object(p.starbase_design(9)).is_not_null()
	assert_object(p.starbase_design(4)).is_null()
	assert_object(p.ship_design(1)).is_null()


func test_year() -> void:
	var state := GameState.new()
	state.turn = 25
	assert_int(state.year()).is_equal(2425)


func _errors_for(data: Dictionary) -> Array:
	var errors := PackedStringArray()
	ModelObject.object_from(GameState, data, "", errors)
	return Array(errors)


func test_load_reports_bad_fields() -> void:
	var data := sample_state().to_dict()
	data["planets"][1]["population"] = 2.5
	data["planets"][1]["colour"] = 3
	data["fleets"][1]["waypoints"][0]["task"] = "dance"
	data["settings"].erase("slow_tech")
	data["players"][0]["race"]["lesser_traits"] = ["trait.lrt.ife", 4]
	data["mod_data"] = {"m": 1.5}
	var errors := _errors_for(data)
	(
		assert_array(errors)
		. contains_exactly_in_any_order(
			[
				"/settings/slow_tech: missing",
				"/players/0/race/lesser_traits/1: must be a string",
				"/planets/1/population: must be an integer",
				"/planets/1/colour: unknown field",
				"/fleets/1/waypoints/0/task: must be one of " + ", ".join(Waypoint.TASKS),
				"/mod_data/m: must be an integer",
			]
		)
	)


func test_load_reports_bad_order() -> void:
	var data := sample_state().to_dict()
	data["fleets"].reverse()
	data["planets"][2]["id"] = 5
	(
		assert_array(_errors_for(data))
		. contains_exactly_in_any_order(
			[
				"/planets/2/id: must be 2",
				"/fleets/1: not in (owner, number) order or a duplicate",
			]
		)
	)
	data = sample_state().to_dict()
	data["minefields"].append(data["minefields"][0])
	assert_array(_errors_for(data)).contains_exactly(
		["/minefields/1: not in (owner, number) order or a duplicate"]
	)


func test_load_reports_bad_rng() -> void:
	var data := sample_state().to_dict()
	data["rng"]["streams"]["classic"]["s1"] = 0
	assert_array(_errors_for(data)).contains_exactly(["/rng: invalid random stream state"])
	data.erase("rng")
	assert_array(_errors_for(data)).contains_exactly(["/rng: missing"])
