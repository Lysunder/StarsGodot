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


func test_every_palette_has_every_colour() -> void:
	var roles: Array = Palette.COLORS[Palette.STANDARD].keys()
	for mode: String in Palette.MODES:
		assert_array(Palette.COLORS[mode].keys()).contains_exactly_in_any_order(roles)
	var before := Palette.mode
	Palette.mode = Palette.RED_GREEN
	assert_that(Palette.cargo(1)).is_equal(Palette.COLORS[Palette.RED_GREEN][Palette.BORANIUM])
	assert_that(Palette.axis(2)).is_equal(Palette.COLORS[Palette.RED_GREEN][Palette.RADIATION])
	Palette.mode = before


func test_key_bindings_default_change_and_steal() -> void:
	KeyBindings.path = "user://test_keys.cfg"
	DirAccess.remove_absolute(KeyBindings.path)
	assert_int(KeyBindings.key("reports")).is_equal(KEY_F3)
	assert_str(KeyBindings.text(KeyBindings.key("save"))).is_equal("Ctrl+S")
	KeyBindings.set_key("research", KEY_F3)
	assert_int(KeyBindings.key("research")).is_equal(KEY_F3)
	# the reports action lost the key
	assert_int(KeyBindings.key("reports")).is_equal(0)
	var press := InputEventKey.new()
	press.keycode = KEY_F3
	press.pressed = true
	assert_bool(KeyBindings.matches(press, "research")).is_true()
	assert_bool(KeyBindings.matches(press, "reports")).is_false()
	KeyBindings.reset()
	assert_int(KeyBindings.key("reports")).is_equal(KEY_F3)
	DirAccess.remove_absolute(KeyBindings.path)
	KeyBindings.path = UiSettings.PATH
