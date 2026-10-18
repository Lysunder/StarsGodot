extends GdUnitTestSuite
## S22 "Computer players in a new game": the built-in computer races, the simple New Game's pick
## of opponents, and games created with computer players.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func test_every_personality_has_a_race_per_level() -> void:
	for key: String in ComputerPlayers.RACES:
		var def := _content.get_def(
			ComputerPlayers.PERSONALITY, ComputerPlayers.personality_id(key)
		)
		assert_int(def["races"].size()).is_equal(ComputerPlayers.LEVELS.size())
		for level in ComputerPlayers.LEVELS.size():
			var race := ComputerPlayers.race_for(def, level, _content)
			assert_str(race.name).is_empty()
			assert_int(race.logo).is_equal(0)
	var macinti := _content.get_def(ComputerPlayers.PERSONALITY, "ai_personality.macinti")
	assert_str(ComputerPlayers.race_for(macinti, 3, _content).primary_trait).is_equal(
		"trait.prt.AR"
	)
	# a personality of the player's plays the races it names
	var own := PersonalityFile.make("Mine", AiBrains.BASELINE)
	assert_str(own["races_of"]).is_equal(ComputerPlayers.DEFAULT_RACES)
	own["races_of"] = "cybertrons"
	assert_str(ComputerPlayers.race_for(own, 0, _content).primary_trait).is_equal("trait.prt.PP")


func test_player_counts_follow_size_and_difficulty() -> void:
	var rng := StarsRandom.new(3, 9)
	# below Harder the counts are fixed
	for d in 2:
		var counts := []
		for size in NewGame.SIZES.size():
			counts.append(NewGame.player_count(size, d, rng))
		assert_array(counts).is_equal([2, 3, 7, 12, 16])
	# Harder and Expert vary within their ranges
	var ranges := [[2, 3], [3, 5], [5, 9], [9, 15], [11, 16]]
	for d in [2, 3]:
		for size in NewGame.SIZES.size():
			for i in 50:
				var n := NewGame.player_count(size, d, rng)
				assert_int(n).is_between(ranges[size][0], ranges[size][1])


func test_standard_opponents_by_share() -> void:
	var opponents := NewGame.pick_opponents(3, 1, StarsRandom.new(3, 9))
	assert_int(opponents.size()).is_equal(11)
	var tally := {}
	for o in opponents:
		var k := "%s %d" % [o["ai"], o["level"]]
		tally[k] = tally.get(k, 0) + 1
	# 12 players: slots 1-4 Turindrones, 5-5 Robotoids, 6-7 Automitrons, 8-8 Rototills, 9-10
	# Cybertrons, 11 random
	var expected := {
		"turindrones 1": 4,
		"robotoids 1": 1,
		"automitrons 1": 2,
		"rototills 1": 1,
		"cybertrons 1": 2,
		"random -1": 1,
	}
	assert_dict(tally).is_equal(expected)


func test_a_game_with_computer_players() -> void:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 77
	var own := PersonalityFile.make("Settler", AiBrains.BASELINE)
	own["races_of"] = "rototills"
	options.opponents = [
		{"ai": "macinti", "level": 3, "personality": {}},
		{"ai": NewGame.RANDOM, "level": -1, "personality": {}},
		{"ai": NewGame.personality_key(own), "level": 0, "personality": own},
	]
	var s := NewGame.create(_content, options)
	assert_int(s.players.size()).is_equal(4)
	assert_bool(s.player(0).is_human()).is_true()
	var mac := s.player(1)
	assert_str(mac.ai).is_equal("macinti")
	assert_str(mac.race.primary_trait).is_equal("trait.prt.AR")
	assert_str(mac.race.name).is_not_empty()
	assert_str(mac.ai_personality["brain"]).is_equal(AiBrains.MACINTI)
	var rnd := s.player(2)
	assert_bool(ComputerPlayers.RACES.has(rnd.ai)).is_true()
	assert_int(rnd.ai_level).is_between(0, 3)
	var mine := s.player(3)
	assert_str(mine.race.primary_trait).is_equal("trait.prt.CA")
	assert_dict(mine.ai_personality).is_equal(own)
	# every computer player plays its turns
	for t in 3:
		var errors := PackedStringArray()
		var sets := ComputerPlayers.add_orders(s, _content, [], errors)
		assert_array(Array(errors)).is_empty()
		assert_array(Array(StandardTurn.generate(s, _content, sets))).is_empty()
