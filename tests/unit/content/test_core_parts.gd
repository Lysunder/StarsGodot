extends GdUnitTestSuite
## Spot checks of the core parts and hulls against spec S04.

var _reg: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(
		FolderModSource.discover("res://content"), PackedStringArray()
	)
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_reg = r.registry


func test_counts() -> void:
	assert_int(_reg.ids("part").size()).is_equal(202)
	assert_int(_reg.ids("hull").size()).is_equal(37)


func test_basic_records() -> void:
	var tritanium := _reg.part("part.armor.tritanium")
	assert_int(tritanium["mass"]).is_equal(60)
	assert_int(tritanium["stats"]["armor"]).is_equal(50)
	assert_int(tritanium["cost"]["resources"]).is_equal(10)
	var laser := _reg.part("part.beam.laser")
	assert_dict(laser["stats"]).is_equal({"range": 1, "power": 10, "initiative": 9})
	assert_str(_reg.display_name("part.beam.gatling_gun")).is_equal("Gatling Gun")
	assert_bool(_reg.part("part.beam.gatling_gun")["tags"].has("gatling")).is_true()
	assert_bool(_reg.part("part.beam.pulsed_sapper")["tags"].has("sapper")).is_true()


func test_multi_effect_parts() -> void:
	assert_dict(_reg.part("part.shield.croby_sharmor")["stats"]).is_equal(
		{"shield": 60, "armor": 65}
	)
	var mega: Dictionary = _reg.part("part.armor.mega_poly_shell")["stats"]
	assert_dict(mega).is_equal(
		{"armor": 400, "shield": 100, "cloak": 40, "jamming": 20, "scan_range": 80}
	)
	var pod: Dictionary = _reg.part("part.mechanical.multi_cargo_pod")["stats"]
	assert_dict(pod).is_equal({"cargo_capacity": 250, "armor": 50, "cloak": 20})


func test_engine_fuel_table() -> void:
	var qj5 := _reg.part("part.engine.quick_jump_5")
	assert_array(qj5["fuel_table"]).is_equal([0, 0, 25, 100, 100, 100, 180, 500, 800, 900, 1080])


func test_hulls() -> void:
	var scout := _reg.hull("hull.scout")
	assert_int(scout["initiative"]).is_equal(1)
	assert_int(scout["fuel"]).is_equal(50)
	assert_int(scout["armor"]).is_equal(20)
	assert_int(scout["slots"].size()).is_equal(3)
	assert_array(scout["slots"][2]["accepts"]).not_contains(["bomb", "mining_robot"])
	assert_int(_reg.hull("hull.battleship")["initiative"]).is_equal(10)
	var death_star := _reg.hull("hull.death_star")
	assert_bool(death_star["starbase"]).is_true()
	assert_int(death_star["dock"]).is_equal(-1)
	assert_int(death_star["initiative"]).is_equal(18)
	assert_int(_reg.hull("hull.space_dock")["dock"]).is_equal(200)


func test_every_part_and_hull_has_a_legacy_id() -> void:
	var parsed := JsonReader.parse(
		FileAccess.get_file_as_string("res://content/core/legacy_ids.json")
	)
	assert_bool(parsed.ok).is_true()
	var legacy: Dictionary = parsed.value
	for type_name in ["part", "hull"]:
		for id in _reg.ids(type_name):
			assert_bool(legacy.has(id)).override_failure_message("no legacy id: " + id).is_true()
	assert_dict(legacy["part.beam.laser"]).is_equal({"kind": 16, "item": 0})
	assert_dict(legacy["hull.death_star"]).is_equal({"hull": 36})
