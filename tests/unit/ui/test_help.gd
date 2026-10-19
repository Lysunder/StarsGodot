extends GdUnitTestSuite
## The help (HelpText, HelpWindow): every topic has a title and a body, links go to topics that
## exist, keys show the player's binding, and the window follows links and Back.


func test_every_topic_has_a_title_a_body_and_good_links() -> void:
	var content := GameSession.content
	var topics := HelpText.topics(content)
	assert_int(topics.size()).is_greater(10)
	var link := RegEx.create_from_string("\\[\\[([a-z_]+)")
	for t in topics:
		assert_str(HelpText.title(content, t)).is_not_equal("help.%s.title" % t)
		var body := content.string_for("help.%s.body" % t)
		assert_str(body).is_not_equal("help.%s.body" % t)
		for m in link.search_all(body):
			(
				assert_bool(topics.has(m.get_string(1)))
				. override_failure_message("%s links to %s" % [t, m.get_string(1)])
				. is_true()
			)
		for m in RegEx.create_from_string("\\{key:([a-z_]+)\\}").search_all(body):
			assert_int(KeyBindings.default_key(m.get_string(1))).is_not_equal(0)


func test_markup_becomes_bbcode() -> void:
	var text := HelpText.bbcode(GameSession.content, "start", 16)
	assert_str(text).contains("[url=planets]planet tiles[/url]")
	assert_str(text).contains("[b]%s[/b]" % KeyBindings.text(KeyBindings.key("generate")))
	assert_str(text).contains("[font_size=20][b]A year at a time[/b][/font_size]")
	assert_str(text).contains("[indent]\u2022 ")
	assert_str(text).not_contains("**")
	assert_str(HelpText.bbcode(GameSession.content, "keys", 16)).contains("Generate the turn")


func test_the_window_follows_links_and_back() -> void:
	var help := HelpWindow.new()
	add_child(help)
	help.open()
	assert_str(help.topic).is_equal("start")
	help.show_topic("fleets")
	help.show_topic("combat")
	assert_str(help.topic).is_equal("combat")
	help._go_back()
	assert_str(help.topic).is_equal("fleets")
	help._go_back()
	assert_str(help.topic).is_equal("start")
	assert_bool(help._back.disabled).is_true()
	help.queue_free()
	await get_tree().process_frame
