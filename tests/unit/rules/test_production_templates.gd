extends GdUnitTestSuite
## S09 "Production templates": importing a queue into a template, applying one to a queue (with the
## race's skipped items), and the `production_templates` order (S11).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


static func _item(key: String, count: int, progress := 0) -> Dictionary:
	return {
		"item": "production_item." + key,
		"design": -1,
		"starbase": false,
		"count": count,
		"progress": progress,
	}


static func _ship(slot: int, count: int) -> Dictionary:
	return {"item": "", "design": slot, "starbase": false, "count": count, "progress": 30}


static func _race(prt: String) -> Race:
	var race := Race.new()
	race.primary_trait = "trait.prt." + prt
	return race


func _keys(queue: Array) -> Array:
	return queue.map(func(q: Dictionary) -> String: return str(q["item"]).get_slice(".", 1))


func test_import_takes_the_auto_items_in_order() -> void:
	var queue := [
		_item("factories", 4),
		_item("auto_mines", 10, 40),
		_ship(0, 1),
		_item("auto_max_terraform", 2),
	]
	var t := ProductionTemplates.import_queue(queue, _content)
	assert_array(_keys(t)).is_equal(["auto_mines", "auto_max_terraform"])
	assert_int(t[0]["count"]).is_equal(10)
	assert_int(t[0]["progress"]).is_equal(0)
	# at most 12
	var long := []
	for i in 15:
		long.append(_item("auto_factories", i + 1))
	assert_int(ProductionTemplates.import_queue(long, _content).size()).is_equal(12)


func test_apply_replaces_the_auto_items_after_the_rest() -> void:
	var queue := [
		_item("auto_defenses", 3),
		_ship(0, 2),
		_item("factories", 4),
		_item("auto_mines", 10),
	]
	var template := [_item("auto_factories", 10), _item("auto_min_terraform", 1)]
	var out := ProductionTemplates.apply(queue, template, _race("JoaT"), _content)
	assert_array(_keys(out)).is_equal(["", "factories", "auto_factories", "auto_min_terraform"])
	# the kept ship keeps its progress
	assert_int(out[0]["progress"]).is_equal(30)


func test_apply_skips_what_the_race_never_builds() -> void:
	var template := [
		_item("auto_mines", 5),
		_item("auto_factories", 5),
		_item("auto_defenses", 5),
		_item("auto_min_terraform", 5),
		_item("auto_max_terraform", 5),
		_item("auto_alchemy", 5),
	]
	var ar := ProductionTemplates.apply([], template, _race("AR"), _content)
	assert_array(_keys(ar)).is_equal(["auto_min_terraform", "auto_max_terraform", "auto_alchemy"])
	var ca := ProductionTemplates.apply([], template, _race("CA"), _content)
	assert_array(_keys(ca)).is_equal(
		["auto_mines", "auto_factories", "auto_defenses", "auto_alchemy"]
	)


func test_order_stores_the_templates() -> void:
	var s := GameState.new()
	var p := Player.new()
	s.players.append(p)
	var t := {
		"name": "Build up",
		"leftover_to_research": true,
		"queue": [_item("auto_factories", 10, 50), _item("auto_mines", 10)],
	}
	var ok := OrderRules.apply(s, _content, 0, {"type": "production_templates", "templates": [t]})
	assert_str(ok).is_empty()
	assert_int(p.production_templates.size()).is_equal(1)
	assert_str(p.production_templates[0]["name"]).is_equal("Build up")
	assert_int(p.production_templates[0]["queue"][0]["progress"]).is_equal(0)
	for bad: Dictionary in [
		{"templates": [t, t, t, t]},
		{"templates": [t.merged({"name": ""}, true)]},
		{"templates": [t.merged({"name": "A name too long"}, true)]},
		{"templates": [t.merged({"queue": [_ship(0, 1)]}, true)]},
		{"templates": [t.merged({"leftover_to_research": 1}, true)]},
	]:
		bad["type"] = "production_templates"
		assert_str(OrderRules.apply(s, _content, 0, bad)).is_not_empty()
	assert_int(p.production_templates.size()).is_equal(1)
	(
		assert_str(
			OrderRules.apply(s, _content, 0, {"type": "production_templates", "templates": []})
		)
		. is_empty()
	)
	assert_array(p.production_templates).is_empty()
