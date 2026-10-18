extends GdUnitTestSuite
## S22 "The personality editor": the window saves, overrides per level and deletes the player's
## own personalities (through GameSession, the autoload, for the content).


func test_personality_editor_saves_a_personality() -> void:
	var folder := "user://test_personalities"
	PersonalityStore.dir = folder
	for f in DirAccess.get_files_at(folder) if DirAccess.dir_exists_absolute(folder) else []:
		DirAccess.remove_absolute(folder.path_join(f))
	var editor := PersonalityEditor.new()
	add_child(editor)
	editor.open()
	# the game's own personalities come first, read only, and the original's have no settings
	assert_bool(editor._entries[0]["own"]).is_false()
	assert_bool(editor._save.disabled).is_true()
	assert_int(editor._rows.size()).is_equal(0)
	editor._on_new()
	assert_int(editor._rows.size()).is_equal(BaselineBase.SETTINGS.size())
	editor._name.text = "Cautious"
	editor._name.text_changed.emit("Cautious")
	(editor._rows["research_pct"]["spin"] as SpinBox).value = 25
	editor._races.select(4)
	editor._races.item_selected.emit(4)
	# the expert level overrides the warships
	editor._level.select(4)
	editor._fill_settings()
	var row: Dictionary = editor._rows["warships"]
	assert_bool((row["spin"] as SpinBox).editable).is_false()
	(row["override"] as CheckBox).button_pressed = true
	(row["spin"] as SpinBox).value = 9
	editor._on_save()
	assert_str(editor._status.text).is_equal("Saved.")
	var saved := PersonalityStore.personalities()
	assert_int(saved.size()).is_equal(1)
	assert_int(saved[0]["params"]["research_pct"]).is_equal(25)
	assert_str(saved[0]["races_of"]).is_equal("cybertrons")
	assert_int(saved[0]["levels"][3]["warships"]).is_equal(9)
	assert_bool(saved[0]["levels"][0].has("warships")).is_false()
	# a second personality may not take the same name
	editor._on_copy()
	editor._name.text = "Cautious"
	editor._name.text_changed.emit("Cautious")
	editor._on_save()
	assert_str(editor._status.text).contains("Another personality")
	# delete the saved one
	editor._list.select(editor._entries.size() - 1)
	editor._on_selected(editor._entries.size() - 1)
	editor._on_delete()
	assert_int(PersonalityStore.personalities().size()).is_equal(0)
	PersonalityStore.dir = PersonalityStore.DIR
	editor.queue_free()
	await get_tree().process_frame
