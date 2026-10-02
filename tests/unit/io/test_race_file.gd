extends GdUnitTestSuite
## Spec S06 "Race files and presets": the race file format, the wizard checks and the presets.

const VERSION := "test"
## Advantage points left per preset (S06 worked examples).
const PRESET_POINTS := {
	"race_preset.default": 25,
	"race_preset.traveler": 32,
	"race_preset.warrior": 43,
	"race_preset.shadow": 11,
	"race_preset.expander": 9,
	"race_preset.demolisher": 7,
	"race_preset.random": 12,
}

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _named(id: String) -> Race:
	var race := RacePresets.make(_content, id)
	race.name = "Testers"
	race.plural_name = "Testers"
	return race


func test_presets_are_valid_with_the_specs_points() -> void:
	assert_array(RacePresets.ids(_content)).is_equal(PRESET_POINTS.keys())
	for id: String in PRESET_POINTS:
		var race := _named(id)
		var problems := RaceMath.wizard_problems(race, _content)
		assert_array(Array(problems)).override_failure_message(id).is_empty()
		var points := RaceMath.advantage_points(race, _content)
		assert_int(points).override_failure_message(id).is_equal(PRESET_POINTS[id])


func test_default_preset_is_a_new_race() -> void:
	assert_bool(RacePresets.make(_content, "race_preset.default").equals(Race.new())).is_true()


func test_round_trip_is_canonical() -> void:
	for id in RacePresets.ids(_content):
		var race := _named(id)
		var text := RaceFile.encode(race, VERSION)
		var loaded := RaceFile.decode(text, _content)
		assert_bool(loaded.ok()).override_failure_message("\n".join(loaded.errors)).is_true()
		assert_bool(loaded.race.equals(race)).is_true()
		assert_str(loaded.game_version).is_equal(VERSION)
		assert_str(RaceFile.encode(loaded.race, VERSION)).is_equal(text)


func test_random_race_needs_no_name() -> void:
	var race := RacePresets.make(_content, "race_preset.random")
	assert_bool(RaceFile.decode(RaceFile.encode(race, VERSION), _content).ok()).is_true()
	race.random = false
	var loaded := RaceFile.decode(RaceFile.encode(race, VERSION), _content)
	assert_array(Array(loaded.errors)).contains(["/race/name: must not be empty"])


func test_wizard_limits() -> void:
	var race := _named("race_preset.default")
	race.growth_rate = 21
	race.mine_cost = 1
	var errors := RaceFile.decode(RaceFile.encode(race, VERSION), _content).errors
	assert_array(Array(errors)).contains_exactly_in_any_order(
		["/race/growth_rate: must be 1 .. 20", "/race/mine_cost: must be 2 .. 15"]
	)


func test_negative_points_are_refused() -> void:
	var race := _named("race_preset.default")
	race.primary_trait = "trait.prt.IT"
	race.lesser_traits.assign(["trait.lrt.ARM", "trait.lrt.IFE", "trait.lrt.ISB", "trait.lrt.UR"])
	assert_int(RaceMath.advantage_points(race, _content)).is_less(0)
	var loaded := RaceFile.decode(RaceFile.encode(race, VERSION), _content)
	assert_bool(loaded.ok()).is_false()
	assert_str(loaded.errors[0]).starts_with("advantage points left: -")


func test_unknown_trait_is_reported() -> void:
	var race := _named("race_preset.default")
	race.primary_trait = "trait.prt.XX"
	var loaded := RaceFile.decode(RaceFile.encode(race, VERSION), _content)
	assert_bool(loaded.ok()).is_false()
	assert_str(loaded.errors[0]).starts_with("/race/primary_trait")


func test_header_problems() -> void:
	assert_array(Array(RaceFile.decode("{}", _content).errors)).is_equal(
		["not a starsgodot-race file"]
	)
	var data: Dictionary = JSON.parse_string(
		RaceFile.encode(_named("race_preset.default"), VERSION)
	)
	data["format_version"] = RaceFile.FORMAT_VERSION + 1
	data["extra"] = 1
	var errors := RaceFile.decode(JSON.stringify(data), _content).errors
	assert_array(Array(errors)).is_equal(["/extra: unknown field"])
	data.erase("extra")
	errors = RaceFile.decode(ContentRegistry.canonical(data), _content).errors
	assert_str(errors[0]).contains("is newer than this game reads")


func test_write_and_read() -> void:
	var path := "user://test_race_file.%s" % RaceFile.EXTENSION
	var race := _named("race_preset.traveler")
	assert_int(RaceFile.write(path, race, VERSION)).is_equal(OK)
	var loaded := RaceFile.read(path, _content)
	assert_bool(loaded.ok()).override_failure_message("\n".join(loaded.errors)).is_true()
	assert_bool(loaded.race.equals(race)).is_true()
	DirAccess.remove_absolute(path)
	assert_str(RaceFile.read(path, _content).errors[0]).ends_with("no such file")
