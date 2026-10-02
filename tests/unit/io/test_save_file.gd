extends GdUnitTestSuite
## Spec S03 "Saved form", and the M3 "done when": a hand-built state survives save, load and
## compare exactly.

const SampleGame := preload("res://tests/fixtures/model/sample_game.gd")
const SAVE_DIR := "user://test_saves"

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func after() -> void:
	for name in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR + "/" + name)
	DirAccess.remove_absolute(SAVE_DIR)


func _stamped() -> GameState:
	var state := SampleGame.build()
	SaveFile.stamp(state, _content)
	return state


func test_sample_game_is_valid() -> void:
	assert_array(Array(StateValidator.validate(_stamped(), _content))).is_empty()


func test_save_load_compare() -> void:
	var state := _stamped()
	var path := SAVE_DIR + "/round_trip.json"
	assert_int(SaveStore.write(path, state, "0.1.0")).is_equal(OK)
	var result := SaveStore.read(path, _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	assert_bool(result.needs_confirmation()).is_false()
	assert_str(result.game_version).is_equal("0.1.0")
	assert_bool(result.state.equals(state)).is_true()
	assert_str(result.state.state_hash()).is_equal(state.state_hash())
	assert_str(SaveFile.encode(result.state, "0.1.0")).is_equal(FileAccess.get_file_as_string(path))


func test_overwrite_leaves_no_temp_file() -> void:
	var path := SAVE_DIR + "/overwrite.json"
	var state := _stamped()
	assert_int(SaveStore.write(path, state, "0.1.0")).is_equal(OK)
	state.turn += 1
	assert_int(SaveStore.write(path, state, "0.1.0")).is_equal(OK)
	assert_bool(FileAccess.file_exists(path + SaveStore.TEMP_SUFFIX)).is_false()
	assert_int(SaveStore.read(path, _content).state.turn).is_equal(8)


func test_stamp_records_content() -> void:
	var state := _stamped()
	assert_str(state.settings.ruleset_hash).is_equal(_content.ruleset_hash)
	assert_array(state.settings.mods).is_equal([{"id": "core", "version": "0.1.0"}])


func test_other_content_needs_confirmation() -> void:
	var state := _stamped()
	state.settings.ruleset_hash = "0".repeat(64)
	state.settings.mods = [
		{"id": "core", "version": "0.1.0"}, {"id": "extra_hulls", "version": "1.0.0"}
	]
	var result := SaveFile.decode(SaveFile.encode(state, "0.1.0"), _content)
	assert_bool(result.ok()).is_true()
	assert_bool(result.needs_confirmation()).is_true()
	assert_array(Array(result.saved_mods)).is_equal(["core@0.1.0", "extra_hulls@1.0.0"])


func test_rejects_files_that_are_not_saves() -> void:
	assert_array(Array(SaveFile.decode("{", _content).errors)).has_size(1)
	assert_array(Array(SaveFile.decode('{"format": "other"}', _content).errors)).is_equal(
		["not a starsgodot-save file"]
	)
	var missing := SaveStore.read(SAVE_DIR + "/none.json", _content)
	assert_array(Array(missing.errors)).is_equal([SAVE_DIR + "/none.json: no such file"])


func test_rejects_newer_format_and_bad_header() -> void:
	var data: Dictionary = JSON.parse_string(SaveFile.encode(_stamped(), "0.1.0"))
	data["format_version"] = SaveFile.FORMAT_VERSION + 1
	data["extra"] = 1
	data.erase("game_version")
	var result := SaveFile.decode(JSON.stringify(data), _content)
	assert_array(Array(result.errors)).contains_exactly_in_any_order(
		["/game_version: missing", "/extra: unknown field"]
	)
	data.erase("extra")
	data["game_version"] = "9.0.0"
	result = SaveFile.decode(JSON.stringify(data), _content)
	assert_array(Array(result.errors)).is_equal(
		["/format_version: 2 is newer than this game reads (1)"]
	)
	assert_object(result.state).is_null()


func test_header_must_match_state() -> void:
	var data: Dictionary = JsonReader.parse(SaveFile.encode(_stamped(), "0.1.0")).value
	data["ruleset_hash"] = "x"
	data["mods"] = []
	(
		assert_array(Array(SaveFile.decode(JSON.stringify(data), _content).errors))
		. is_equal(
			[
				"/ruleset_hash: does not match /state/settings/ruleset_hash",
				"/mods: does not match /state/settings/mods",
			]
		)
	)


func test_validator_reports_ranges_and_references() -> void:
	var state := _stamped()
	state.planets[0].environment[1] = 101
	state.planets[2].route = 9
	state.planets[1].starbase.design = 4
	state.players[0].race.primary_trait = "trait.lrt.IFE"
	state.players[1].race.lesser_traits.assign(["trait.lrt.RS", "trait.lrt.IFE"])
	state.players[1].race.hab_center[1] = 90
	state.players[0].ship_designs[0].parts[2] = DesignSlot.new("part.engine.quick_jump_5", 1)
	state.players[0].ship_designs[0].hull = "hull.space_station"
	state.players[1].tech_levels[2] = 27
	state.players[1].relations.resize(1)
	state.fleet(1, 0).stacks[0].count = 0
	state.fleet(1, 0).waypoints[1].target_id = 3
	state.fleet(0, 0).waypoints[1].target_id = 5
	state.packets[0].warp = 4
	state.minefields[0].seen_by.assign([1, 0])
	state.wormholes[1].other_end = 7
	(
		assert_array(Array(StateValidator.validate(state, _content)))
		. contains_exactly_in_any_order(
			[
				"/players/0/race/primary_trait: is not a primary trait",
				"/players/0/ship_designs/0/hull: is a starbase hull",
				"/players/0/ship_designs/0/picture: must be one of the hull's four pictures",
				"/players/0/ship_designs/0/parts: must have one entry per hull slot (12)",
				"/players/1/race/lesser_traits/1: lesser traits must be sorted and unique",
				(
					"/players/1/race/hab/1: needs 0 <= low <= center <= high <= 100, or -1 in all three"
					+ " (immune)"
				),
				"/players/1/tech_levels/2: must be 0 .. 26, not 27",
				"/players/1/relations: must have one entry per player",
				"/planets/0/environment/1: must be 0 .. 100, not 101",
				"/planets/1/starbase/design: the owner has no starbase design in that slot",
				"/planets/2/route: no planet 9",
				"/fleets/0/waypoints/1/target: no such fleet",
				"/fleets/1/stacks/0/count: must be 1 .. 32767, not 0",
				"/fleets/1/waypoints/1/target: no such planet",
				"/packets/0: salvage has no destination and warp 0",
				"/minefields/0/seen_by/1: must be sorted and unique",
				"/wormholes/1/other_end: no such wormhole",
			]
		)
	)


func test_validator_checks_design_slots() -> void:
	var state := _stamped()
	var parts := state.players[0].ship_designs[0].parts
	parts[1] = DesignSlot.new("part.engine.quick_jump_5", 1)
	parts[2] = DesignSlot.new("", 2)
	parts[0] = DesignSlot.new("part.engine.no_such", 1)
	(
		assert_array(Array(StateValidator.validate(state, _content)))
		. contains_exactly_in_any_order(
			[
				(
					"/players/0/ship_designs/0/parts/0/part: no part 'part.engine.no_such' in the loaded"
					+ " content"
				),
				"/players/0/ship_designs/0/parts/1/part: this slot does not accept that part",
				"/players/0/ship_designs/0/parts/2/count: must be 0 for an empty slot",
			]
		)
	)


func test_validator_checks_limits() -> void:
	var state := _stamped()
	var f := state.fleet(1, 0)
	for i in 90:
		f.waypoints.append(Waypoint.new(1000, 1000))
	state.rng = RngStreams.new(1 << 53, true)
	f.stacks[0].damage = 500
	state.planets[0].defenses = 4096
	state.planets[1].starbase.damage = 4096
	(
		assert_array(Array(StateValidator.validate(state, _content)))
		. contains_exactly_in_any_order(
			[
				"/rng/game_seed: must be 0 .. 2^53 - 1",
				"/fleets/1/waypoints: more than 87 waypoints",
				"/fleets/1/stacks/0/damage: must be 0 .. 499, not 500",
				"/planets/0/defenses: must be 0 .. 4095, not 4096",
				"/planets/1/starbase/damage: must be 0 .. 4095, not 4096",
			]
		)
	)
