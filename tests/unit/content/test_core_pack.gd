extends GdUnitTestSuite
## M2 "done when": the real core pack loads, a test mod adds a hull and overrides a part stat.

const FIXTURE_MOD := "res://tests/fixtures/mods/extra_hulls"


func _sources(with_fixture: bool) -> Array[ModSource]:
	var sources := FolderModSource.discover("res://content")
	if with_fixture:
		sources.append(FolderModSource.new(FIXTURE_MOD))
	return sources


func test_core_pack_loads_cleanly() -> void:
	var r := ModLoader.new().load_mods(_sources(false), PackedStringArray())
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	var reg := r.registry
	assert_int(reg.ids("tech_field").size()).is_equal(6)
	assert_int(reg.part("part.beam.laser")["stats"]["power"]).is_equal(10)
	assert_int(reg.constant("constant.battle.max_rounds")).is_equal(16)
	assert_str(reg.display_name("hull.small_freighter")).is_equal("Small Freighter")


func test_fixture_mod_adds_hull_and_overrides_stat() -> void:
	var loader := ModLoader.new()
	loader.allow_test_mods = true
	var r := loader.load_mods(_sources(true), PackedStringArray(["extra_hulls"]))
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	var reg := r.registry
	assert_array(Array(r.order)).is_equal(["core", "extra_hulls"])
	assert_bool(reg.has_def("extra_hulls.hull.long_scout")).is_true()
	assert_str(reg.display_name("extra_hulls.hull.long_scout")).is_equal("Long Scout")
	assert_int(reg.part("part.beam.laser")["stats"]["power"]).is_equal(12)
	assert_bool(reg.part("part.beam.laser")["tags"].has("extra_hulls")).is_true()
	# select patch: every hull's resource cost * 90 / 100, truncated
	assert_int(reg.hull("hull.scout")["cost"]["resources"]).is_equal(9)
	assert_int(reg.hull("hull.small_freighter")["cost"]["resources"]).is_equal(18)
	assert_int(reg.hull("extra_hulls.hull.long_scout")["cost"]["resources"]).is_equal(12)
	assert_array(Array(reg.provenance("part.beam.laser"))).is_equal(
		["core:add content/parts/beam.json", "extra_hulls:patch patches/laser.json"]
	)


func test_fixture_mod_is_test_only() -> void:
	var r := ModLoader.new().load_mods(_sources(true), PackedStringArray(["extra_hulls"]))
	assert_str(r.error_text()).contains("test-only mod refused")
