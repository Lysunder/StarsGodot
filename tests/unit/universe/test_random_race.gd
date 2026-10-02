extends GdUnitTestSuite
## Spec S06 "Random races": properties of the roll. The draw-by-draw check against the original
## is in the generator's whole-game golden tests (the random-race fixtures).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## The race wizard's "Random" preset: HE, 17-83 on every axis, mine cost 3, random setting.
static func _preset() -> Race:
	var race := Race.new()
	race.primary_trait = "trait.prt.HE"
	race.hab_low.assign([17, 17, 17])
	race.hab_high.assign([83, 83, 83])
	race.mine_cost = 3
	race.random = true
	return race


func _roll(game_seed: int) -> Race:
	var race := _preset()
	RandomRace.new(_content, StarsRandom.from_game_seed(game_seed)).roll(race)
	return race


func test_preset_is_valid() -> void:
	assert_int(RaceMath.advantage_points(_preset(), _content)).is_equal(12)


func test_same_seed_same_race() -> void:
	assert_bool(_roll(42).equals(_roll(42))).is_true()
	assert_bool(_roll(42).equals(_roll(43))).is_false()


func test_rolled_races_are_valid() -> void:
	var names := _content.name_list(UniverseGenerator.RACE_NAMES)
	var primaries := {}
	for game_seed in range(1, 51):
		var race := _roll(game_seed)
		var where := "seed %d" % game_seed
		var points := RaceMath.advantage_points(race, _content)
		assert_int(points).override_failure_message(where).is_between(0, RandomRace.TARGET_MAX)
		assert_bool(race.random).override_failure_message(where).is_true()
		assert_bool(names.has(race.name)).override_failure_message(where).is_true()
		primaries[race.primary_trait] = true
		var state := GameState.new()
		var p := Player.new()
		p.race = race
		state.players.append(p)
		var errors := StateValidator.validate(state, _content)
		var race_errors := Array(errors).filter(func(e: String) -> bool: return "/race" in e)
		assert_array(race_errors).override_failure_message(where).is_empty()
	assert_int(primaries.size()).is_equal(10)


func test_a_named_race_keeps_its_name() -> void:
	var race := _preset()
	race.name = "Wanderers"
	RandomRace.new(_content, StarsRandom.from_game_seed(7)).roll(race)
	assert_str(race.name).is_equal("Wanderers")
