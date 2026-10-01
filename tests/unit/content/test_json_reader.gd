extends GdUnitTestSuite


func test_keeps_ints_and_floats_apart() -> void:
	var r := JsonReader.parse('{"a": 1, "b": 1.0, "c": -2e3, "d": 0}')
	assert_bool(r.ok).is_true()
	assert_int(typeof(r.value["a"])).is_equal(TYPE_INT)
	assert_int(typeof(r.value["b"])).is_equal(TYPE_FLOAT)
	assert_int(typeof(r.value["c"])).is_equal(TYPE_FLOAT)
	assert_int(r.value["d"]).is_equal(0)


func test_large_ints_are_exact() -> void:
	var r := JsonReader.parse("[2147483563, -9007199254740993]")
	assert_int(r.value[0]).is_equal(2147483563)
	assert_int(r.value[1]).is_equal(-9007199254740993)


func test_records_lines_by_pointer() -> void:
	var text := (
		'{\n  "id": "x",\n  "cost": {\n    "ironium": 5\n  },\n'
		+ '  "list": [\n    1,\n    2\n  ]\n}'
	)
	var r := JsonReader.parse(text)
	assert_bool(r.ok).is_true()
	assert_int(r.lines[""]).is_equal(1)
	assert_int(r.lines["/id"]).is_equal(2)
	assert_int(r.lines["/cost/ironium"]).is_equal(4)
	assert_int(r.lines["/list/1"]).is_equal(8)


func test_keeps_key_order() -> void:
	var r := JsonReader.parse('{"z": 1, "a": 2, "m": 3}')
	assert_array(r.value.keys()).is_equal(["z", "a", "m"])


func test_rejects_duplicate_keys_with_line() -> void:
	var r := JsonReader.parse('{\n"a": 1,\n"a": 2\n}')
	assert_bool(r.ok).is_false()
	assert_str(r.error).contains("duplicate key")
	assert_int(r.error_line).is_equal(3)


func test_reports_syntax_error_line() -> void:
	var r := JsonReader.parse('{\n"a": 1,\n"b": tru\n}')
	assert_bool(r.ok).is_false()
	assert_int(r.error_line).is_equal(3)


func test_rejects_trailing_commas_and_comments() -> void:
	assert_bool(JsonReader.parse("[1, 2,]").ok).is_false()
	assert_bool(JsonReader.parse('{"a": 1,}').ok).is_false()
	assert_bool(JsonReader.parse('// note\n{"a": 1}').ok).is_false()
	assert_bool(JsonReader.parse("[1] 2").ok).is_false()


func test_rejects_bad_numbers() -> void:
	for bad in ["01", "1.", ".5", "+1", "1e", "-", "12345678901234567890"]:
		assert_bool(JsonReader.parse(bad).ok).override_failure_message(bad).is_false()


func test_string_escapes() -> void:
	var r := JsonReader.parse('"a\\"b\\\\c\\n\\u00e9\\ud83d\\ude00"')
	assert_bool(r.ok).is_true()
	assert_str(r.value).is_equal('a"b\\c\né' + char(0x1F600))


func test_literals() -> void:
	var r := JsonReader.parse("[true, false, null]")
	assert_array(r.value).is_equal([true, false, null])


func test_pointer_escape() -> void:
	assert_str(JsonReader.pointer_escape("a/b~c")).is_equal("a~1b~0c")
