extends GdUnitTestSuite
## The build label in the window title and the About box (BuildInfo; tools/build.sh).


func test_a_run_from_the_project_is_a_dev_build() -> void:
	if FileAccess.file_exists(BuildInfo.PATH):
		return
	assert_str(BuildInfo.label()).is_equal("%s (dev)" % ModLoader.new().game_version)
