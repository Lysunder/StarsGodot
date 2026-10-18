extends GdUnitTestSuite
## S22 "The personality editor": the player's own personalities, their files and settings.

const PATH := "user://test_personality.json"

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func after() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_a_new_personality_takes_the_brains_defaults() -> void:
	var p := PersonalityFile.make("Careful", AiBrains.BASELINE)
	assert_array(PersonalityFile.check(p)).is_empty()
	assert_int(p["levels"].size()).is_equal(ComputerPlayers.LEVELS.size())
	assert_int(PersonalityFile.value(p, -1, "research_pct")).is_equal(15)
	# the personality's value, then a level's override of it
	p["params"]["research_pct"] = 30
	p["levels"][3]["research_pct"] = 40
	assert_int(PersonalityFile.value(p, 0, "research_pct")).is_equal(30)
	assert_int(PersonalityFile.value(p, 3, "research_pct")).is_equal(40)
	assert_int(PersonalityFile.value(p, -1, "research_pct")).is_equal(30)


func test_problems() -> void:
	var p := PersonalityFile.make("", AiBrains.BASELINE)
	assert_array(PersonalityFile.check(p)).contains(["the personality needs a name"])
	p["name"] = "x".repeat(PersonalityFile.NAME_MAX + 1)
	assert_int(PersonalityFile.check(p).size()).is_equal(1)
	p["name"] = "Bold"
	p["params"]["research_pct"] = 101
	assert_str(PersonalityFile.check(p)[0]).contains("must be 0 to 100")
	p["params"] = {"no_such_setting": 1}
	assert_str(PersonalityFile.check(p)[0]).contains("not a setting")
	# the idle brain only plays inactive humans
	assert_array(PersonalityFile.check(PersonalityFile.make("Idle", AiBrains.IDLE))).is_not_empty()
	assert_bool(PersonalityFile.brains().has(AiBrains.IDLE)).is_false()


func test_from_content() -> void:
	var p := PersonalityFile.from_content(_content, "ai_personality.macinti")
	assert_str(p["name"]).is_equal("Macinti")
	assert_str(p["brain"]).is_equal(AiBrains.MACINTI)
	assert_array(PersonalityFile.check(p)).is_empty()


func test_the_file_round_trip() -> void:
	var p := PersonalityFile.make("Settler", AiBrains.BASELINE)
	p["params"]["colony_ships"] = 6
	p["levels"][0]["warships"] = 1
	assert_int(PersonalityFile.write(PATH, p)).is_equal(OK)
	var r := PersonalityFile.read(PATH)
	assert_array(Array(r.errors)).is_empty()
	assert_dict(r.personality).is_equal(p)
	# the same shape a game keeps for its computer players
	var player := Player.new()
	player.ai = "settler"
	player.ai_personality = r.personality
	assert_dict(ComputerPlayers.personality_for(player, _content)).is_equal(p)


func test_a_bad_file_is_refused() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string('{"format": "stars_personality", "name": "X", "brain": "nobody"}')
	f.close()
	var r := PersonalityFile.read(PATH)
	assert_bool(r.ok()).is_false()
	assert_str(r.errors[0]).contains("unknown brain")
