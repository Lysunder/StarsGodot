extends GdUnitTestSuite
## M11 step 10: the interface settings' font sizes and scale (UiSettings).


func test_font_sizes_fall_back_to_the_usual_one() -> void:
	# W95FA only at whole-pixel sizes
	assert_int(UiSettings.size_for(0, 25)).is_equal(25)
	assert_int(UiSettings.size_for(0, 14)).is_equal(13)
	# Terminus only at its bitmap sizes
	assert_int(UiSettings.size_for(1, 15)).is_equal(14)
	assert_int(UiSettings.size_for(2, 18)).is_equal(18)
	for spec: Dictionary in ClassicTheme.FONTS:
		assert_array(spec["sizes"]).contains([spec["size"]])


func test_scale_follows_the_window_or_the_choice() -> void:
	assert_float(UiSettings.factor_for(Vector2(1280, 720), 0)).is_equal(1.0)
	assert_float(UiSettings.factor_for(Vector2(1920, 1080), 0)).is_equal(1.5)
	# the smaller ratio, in quarter steps, within limits
	assert_float(UiSettings.factor_for(Vector2(2560, 900), 0)).is_equal(1.25)
	assert_float(UiSettings.factor_for(Vector2(200, 100), 0)).is_equal(UiSettings.SCALE_MIN)
	assert_float(UiSettings.factor_for(Vector2(1280, 720), 150)).is_equal(1.5)


func test_theme_takes_the_size() -> void:
	assert_int(ClassicTheme.build(1, 20).default_font_size).is_equal(20)
	assert_int(ClassicTheme.build(1).default_font_size).is_equal(14)
