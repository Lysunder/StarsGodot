extends GdUnitTestSuite
## Plan M14, the Mods window and mods in the game (through GameSession, the autoload): mods found in
## the player's folder are turned on and ordered, script mods only once trusted; the choice is saved
## and loaded; a saved game turns on the gameplay mods it was played with, or names those missing.

const SETTINGS := "user://test_mod_settings.cfg"
const DIR := "user://test_mods"
const SAVE := "user://test_mod_game.json"


func before_test() -> void:
	ModSettings.path = SETTINGS
	ModSettings.mods_dir = DIR
	_clear(DIR)
	for id in ["extra_hulls", "fast_growth"]:
		_copy("res://mods/" + id, DIR.path_join(id))


func after_test() -> void:
	_clear(DIR)
	for f in [SETTINGS, SAVE, SAVE + ".orders", SAVE + ".round"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	ModSettings.path = UiSettings.PATH
	ModSettings.mods_dir = ModSettings.USER_MODS
	GameSession.reload_content()


static func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for sub in DirAccess.get_directories_at(from):
		_copy(from.path_join(sub), to.path_join(sub))
	for f in DirAccess.get_files_at(from):
		if f.get_extension() in ["json", "gd"]:
			DirAccess.copy_absolute(from.path_join(f), to.path_join(f))


static func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _manager() -> ModManager:
	var m := ModManager.new()
	add_child(m)
	m.open()
	return m


func _entry(m: ModManager, id: String) -> Dictionary:
	for e in m._mods:
		if (e["manifest"] as ModManifest).id == id:
			return e
	return {}


func test_mods_are_turned_on_and_saved() -> void:
	var m := _manager()
	assert_int(m._mods.size()).is_equal(2)
	_entry(m, "extra_hulls")["on"] = true
	m._apply()
	assert_array(Array(ModSettings.enabled())).is_equal(["extra_hulls"])
	assert_bool(GameSession.content.has_def("extra_hulls.hull.picket")).is_true()
	# opened again, the saved choice comes first and on
	m.open()
	assert_bool(m._mods[0]["on"]).is_true()
	m.queue_free()
	await get_tree().process_frame


func test_a_script_mod_is_asked_about_and_trusted() -> void:
	var m := _manager()
	var i := m._mods.find(_entry(m, "fast_growth"))
	assert_bool(m.set_on(i, true)).is_false()
	# not trusted yet: asked, still off
	assert_int(m._asking).is_equal(i)
	assert_bool(m._mods[i]["on"]).is_false()
	m._on_trusted()
	assert_bool(m._mods[i]["on"]).is_true()
	m._apply()
	assert_str(ModSettings.trusted()["fast_growth"]).is_equal(m._mods[i]["hash"])
	var growth: Callable = GameSession.content.ruleset.formula(PlanetEconomy.POP_GROWTH)
	assert_bool(growth == Callable(PlanetEconomy, "standard_growth")).is_false()
	m.queue_free()
	await get_tree().process_frame


func test_mods_that_dont_load_change_nothing() -> void:
	_copy("res://tests/fixtures/mods/bad_script", DIR.path_join("bad_script"))
	var m := _manager()
	var bad := _entry(m, "bad_script")
	bad["on"] = true
	m._trusted["bad_script"] = bad["hash"]
	m._apply()
	assert_str(m._status.text).contains("can't be used together")
	assert_array(Array(ModSettings.enabled())).is_empty()
	m.queue_free()
	await get_tree().process_frame


func test_a_saved_game_turns_on_its_mods() -> void:
	ModSettings.save(PackedStringArray(["extra_hulls"]), {})
	GameSession.reload_content()
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 3
	GameSession.new_game(options)
	assert_int(GameSession.save_game(SAVE)).is_equal(OK)
	# the player turns the mod off: the saved game turns it back on for itself
	ModSettings.save(PackedStringArray(), {})
	GameSession.reload_content()
	assert_bool(GameSession.content.has_def("extra_hulls.hull.picket")).is_false()
	assert_str(GameSession.load_game(SAVE)).is_empty()
	assert_bool(GameSession.content.has_def("extra_hulls.hull.picket")).is_true()
	# without the mod installed, it says which is missing
	_clear(DIR.path_join("extra_hulls"))
	GameSession.reload_content()
	assert_str(GameSession.load_game(SAVE)).contains("extra_hulls 1.0.0")
