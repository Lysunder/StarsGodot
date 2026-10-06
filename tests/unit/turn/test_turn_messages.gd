extends GdUnitTestSuite
## Turn messages (S21): the start-of-game messages, computer players, and the merging of
## "built a mine" style messages. Everything else is checked against the original by the
## golden-turn tests.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _new_game() -> GameState:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 5
	options.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
	return NewGame.create(_content, options)


func test_a_new_game_starts_with_the_tips_and_the_home_planet() -> void:
	var s := _new_game()
	var ours: Array = s.messages[0]
	var fixture := SaveFile.decode(
		FileAccess.get_file_as_string("res://tests/fixtures/golden/terra1/t000.json"), _content
	)
	var theirs: Array = fixture.state.messages[0]
	assert_int(ours.size()).is_equal(theirs.size())
	for i in ours.size():
		assert_str(ours[i]["type"]).is_equal(theirs[i]["type"])
	var home := s.player(0).homeworld
	assert_dict(ours[-1]["goto"]).is_equal({"planet": home})
	assert_array(ours[-1]["params"]).is_equal([home])


func test_computer_players_get_no_messages() -> void:
	var s := _new_game()
	s.player(0).ai = "ai.standard"
	TurnMessages.clear(s)
	TurnMessages.add(s, _content, 0, "message.production.queue_empty", {"planet": 1}, [1])
	assert_bool((s.messages[0] as Array).is_empty()).is_true()


func test_single_installation_messages_are_merged() -> void:
	var s := _new_game()
	var home := s.planet(s.player(0).homeworld)
	TurnMessages.clear(s)
	var production := Production.new(s, _content, StarsRandom.new())
	production._installed_message(home, "mines", 1)
	production._installed_message(home, "mines", 1)
	production._installed_message(home, "factories", 3)
	var types: Array = (s.messages[0] as Array).map(func(m: Dictionary) -> String: return m["type"])
	assert_array(types).is_equal(
		["message.production.mines_built", "message.production.factories_built"]
	)
	assert_array(s.messages[0][0]["params"]).is_equal([2, home.id])


func test_every_fixture_message_has_text() -> void:
	var checked := 0
	for game in ["terra1", "long1", "prod1"]:
		var dir := "res://tests/fixtures/golden/%s/" % game
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".json") or file.contains("orders"):
				continue
			var res := SaveFile.decode(FileAccess.get_file_as_string(dir + file), _content)
			var view := PlayerView.new(res.state, _content, 0)
			for p in res.state.messages.size():
				for m: Dictionary in res.state.messages[p]:
					if not _content.has_def(m["type"]):
						continue
					var text := MessageText.format(view, p, m)
					(
						assert_bool(text.contains("{") or text.is_empty())
						. override_failure_message("%s %s: %s" % [game, file, text])
						. is_false()
					)
					checked += 1
	assert_int(checked).is_greater(500)
