extends GdUnitTestSuite
## Languages (UiLocale): a translation's strings reach the interface (tr), content names and the
## help, English fills the gaps, and English comes back when chosen.

var _content: ContentRegistry


func before_test() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	_content = r.registry
	var strings := {
		"ui.Save": "Sauver",
		"ui.%s Summary": "Résumé de %s",
		"part.beam.laser.name": "Rayon",
		"help.start.title": "Débuter",
	}
	_content.add_strings_file("test_fr", "lang/fr.json", "fr", JSON.stringify(strings))


func after_test() -> void:
	UiLocale.apply(GameSession.content, "en")


func test_a_translation_reaches_the_interface_and_the_content() -> void:
	assert_array(Array(UiLocale.locales(_content))).contains(["en", "fr"])
	UiLocale.apply(_content, "fr")
	assert_str(tr("Save")).is_equal("Sauver")
	assert_str(tr("%s Summary") % "Terre").is_equal("Résumé de Terre")
	assert_str(_content.display_name("part.beam.laser")).is_equal("Rayon")
	assert_str(HelpText.title(_content, "start")).is_equal("Débuter")
	# what the translation leaves out stays English
	assert_str(tr("Generate")).is_equal("Generate")
	assert_str(_content.display_name("part.beam.x_ray_laser")).is_equal(
		_content.display_name("part.beam.x_ray_laser", "en")
	)
	UiLocale.apply(_content, "en")
	assert_str(tr("Save")).is_equal("Save")
	assert_str(_content.display_name("part.beam.laser")).is_equal("Laser")


func test_the_settings_offer_the_languages() -> void:
	var dialog := SettingsDialog.new()
	add_child(dialog)
	dialog.open()
	assert_int(dialog._language.item_count).is_equal(UiLocale.locales(GameSession.content).size())
	dialog.queue_free()
	await get_tree().process_frame
