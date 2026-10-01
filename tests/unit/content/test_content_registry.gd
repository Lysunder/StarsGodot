extends GdUnitTestSuite

const TECH := '{"type": "tech_field", "id": "tech_field.energy", "order": 0}'
const LASER := """{
  "type": "part",
  "id": "part.beam.laser",
  "category": "beam",
  "tech": { "tech_field.energy": 1 },
  "mass": 1,
  "cost": { "ironium": 0, "boranium": 6, "germanium": 0, "resources": 5 },
  "stats": { "power": 10 },
  "tags": ["beam"]
}"""
const NAMES := '{"tech_field.energy.name": "Energy", "part.beam.laser.name": "Laser"}'


func _registry(extra_content: Dictionary = {}, patches: Dictionary = {}) -> ContentRegistry:
	var reg := ContentRegistry.new()
	reg.add_content_file("core", "content/tech.json", TECH)
	reg.add_content_file("core", "content/laser.json", LASER)
	reg.add_strings_file("core", "lang/en.json", "en", NAMES)
	for file: String in extra_content:
		reg.add_content_file("mymod", file, extra_content[file])
	for file: String in patches:
		reg.add_patch_file("mymod", file, patches[file])
	return reg


func _messages(reg: ContentRegistry) -> String:
	var out: PackedStringArray = []
	for e in reg.errors:
		out.append(str(e))
	return "\n".join(out)


func test_loads_and_freezes() -> void:
	var reg := _registry()
	assert_bool(reg.finish()).override_failure_message(_messages(reg)).is_true()
	assert_int(reg.part("part.beam.laser")["stats"]["power"]).is_equal(10)
	assert_str(reg.display_name("part.beam.laser")).is_equal("Laser")
	assert_bool(reg.part("part.beam.laser").is_read_only()).is_true()
	assert_bool(reg.part("part.beam.laser")["stats"].is_read_only()).is_true()
	assert_array(Array(reg.ids("part"))).is_equal(["part.beam.laser"])
	assert_str(reg.ruleset_hash).has_length(64)


func test_patch_operations() -> void:
	var patch := """[
		{"target": "part.beam.laser", "set": {"stats.power": 12, "stats.range": 1}},
		{"target": "part.beam.laser", "add": {"mass": 2}, "pct": {"cost.boranium": 50}},
		{"target": "part.beam.laser", "ratio": {"cost.resources": [3, 2]}},
		{"target": "part.beam.laser", "append": {"tags": ["cheap"]}, "remove_values": {"tags": ["beam"]}}
	]"""
	var reg := _registry({}, {"patches/p.json": patch})
	assert_bool(reg.finish()).override_failure_message(_messages(reg)).is_true()
	var laser := reg.part("part.beam.laser")
	assert_int(laser["stats"]["power"]).is_equal(12)
	assert_int(laser["stats"]["range"]).is_equal(1)
	assert_int(laser["mass"]).is_equal(3)
	assert_int(laser["cost"]["boranium"]).is_equal(3)
	assert_int(laser["cost"]["resources"]).is_equal(7)  # 5 * 3 / 2 truncates
	assert_array(laser["tags"]).is_equal(["cheap"])
	assert_int(reg.provenance("part.beam.laser").size()).is_equal(5)


func test_select_patch_by_tag() -> void:
	var reg := _registry(
		{}, {"patches/p.json": '{"select": {"type": "part", "tag": "beam"}, "set": {"mass": 9}}'}
	)
	assert_bool(reg.finish()).is_true()
	assert_int(reg.part("part.beam.laser")["mass"]).is_equal(9)


func test_replace() -> void:
	var replacement := LASER.replace('"mass": 1', '"mass": 4').replace(
		"{\n", '{"$replace": true,\n'
	)
	var reg := _registry({"content/r.json": replacement})
	assert_bool(reg.finish()).override_failure_message(_messages(reg)).is_true()
	assert_int(reg.part("part.beam.laser")["mass"]).is_equal(4)


func test_duplicate_id_without_replace() -> void:
	var reg := _registry({"content/dup.json": LASER})
	reg.finish()
	assert_str(_messages(reg)).contains("duplicate id 'part.beam.laser'")


func test_mod_ids_must_be_namespaced() -> void:
	var foreign := LASER.replace("part.beam.laser", "part.beam.better")
	var reg := _registry({"content/x.json": foreign})
	reg.finish()
	assert_str(_messages(reg)).contains("must start with 'mymod.part.'")


func test_remove_reports_dangling_references() -> void:
	var reg := _registry(
		{}, {"patches/rm.json": '{"target": "tech_field.energy", "$remove": true}'}
	)
	assert_bool(reg.finish()).is_false()
	assert_str(_messages(reg)).contains("unknown tech_field 'tech_field.energy'")
	assert_str(_messages(reg)).contains("core:content/laser.json:5")


func test_float_rejected_with_file_and_line() -> void:
	var reg := _registry(
		{}, {"patches/f.json": '{\n"target": "part.beam.laser",\n"set": {\n"mass": 1.5\n}\n}'}
	)
	assert_bool(reg.finish()).is_false()
	assert_str(_messages(reg)).contains("mymod:patches/f.json:4")
	assert_str(_messages(reg)).contains("must be an integer, not 1.5")


func test_schema_errors() -> void:
	var bad := """{
		"type": "part",
		"id": "mymod.part.bad",
		"category": "laser_cannon",
		"mass": -1,
		"cost": { "ironium": 1, "boranium": 0, "germanium": 0 },
		"colour": "red"
	}"""
	var reg := _registry({"content/bad.json": bad})
	assert_bool(reg.finish()).is_false()
	var text := _messages(reg)
	assert_str(text).contains("mymod:content/bad.json:4")  # category
	assert_str(text).contains("must be one of")
	assert_str(text).contains("must be at least 0")
	assert_str(text).contains('missing required field "resources"')
	assert_str(text).contains('unknown field "colour"')
	assert_str(text).contains("no English name")


func test_bad_patches() -> void:
	var patches := """[
		{"target": "part.beam.nope", "set": {"mass": 1}},
		{"target": "part.beam.laser", "pct": {"stats.missing": 50}},
		{"target": "part.beam.laser", "frobnicate": {}},
		{"set": {"mass": 1}}
	]"""
	var reg := _registry({}, {"patches/bad.json": patches})
	reg.finish()
	var text := _messages(reg)
	assert_str(text).contains("patch target 'part.beam.nope' does not exist")
	assert_str(text).contains("target value is not an integer")
	assert_str(text).contains('unknown patch key "frobnicate"')
	assert_str(text).contains('exactly one of "target" or "select"')


func test_invalid_json_reports_line() -> void:
	var reg := _registry({"content/broken.json": '{\n"type": "part",\n"id": \n}'})
	reg.finish()
	assert_str(_messages(reg)).contains("mymod:content/broken.json:4: invalid JSON")


func test_hash_is_stable_and_sensitive() -> void:
	var a := _registry()
	a.finish()
	var b := _registry()
	b.finish()
	assert_str(a.ruleset_hash).is_equal(b.ruleset_hash)
	var c := _registry({}, {"patches/p.json": '{"target": "part.beam.laser", "add": {"mass": 1}}'})
	c.finish()
	assert_str(c.ruleset_hash).is_not_equal(a.ruleset_hash)


func test_names_do_not_affect_hash() -> void:
	var a := _registry()
	a.finish()
	var b := _registry()
	b.add_strings_file("mymod", "lang/en.json", "en", '{"part.beam.laser.name": "Zap"}')
	b.finish()
	assert_str(b.display_name("part.beam.laser")).is_equal("Zap")
	assert_str(b.ruleset_hash).is_equal(a.ruleset_hash)


func test_canonical_sorts_keys() -> void:
	assert_str(ContentRegistry.canonical({"b": [1, true, null], "a": "x"})).is_equal(
		'{"a":"x","b":[1,true,null]}'
	)
