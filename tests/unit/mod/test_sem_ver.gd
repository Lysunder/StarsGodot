extends GdUnitTestSuite


func test_parse() -> void:
	assert_array(Array(SemVer.parse("1.2.3"))).is_equal([1, 2, 3])
	assert_array(Array(SemVer.parse("1.2"))).is_equal([1, 2, 0])
	assert_bool(SemVer.is_valid("1.2.3.4")).is_false()
	assert_bool(SemVer.is_valid("1.x")).is_false()
	assert_bool(SemVer.is_valid("")).is_false()


func test_compare() -> void:
	assert_int(SemVer.compare("1.2.0", "1.10.0")).is_equal(-1)
	assert_int(SemVer.compare("2.0", "2.0.0")).is_equal(0)
	assert_int(SemVer.compare("1.0.1", "1.0.0")).is_equal(1)


func test_constraints() -> void:
	assert_bool(SemVer.satisfies("1.2.0", ">=1.0 <2.0")).is_true()
	assert_bool(SemVer.satisfies("2.0.0", ">=1.0 <2.0")).is_false()
	assert_bool(SemVer.satisfies("0.9.9", ">=1.0 <2.0")).is_false()
	assert_bool(SemVer.satisfies("1.2.0", "1.2")).is_true()
	assert_bool(SemVer.satisfies("1.2.1", "=1.2.0")).is_false()
	assert_bool(SemVer.satisfies("3.0.0", "")).is_true()
	assert_bool(SemVer.satisfies("3.0.0", "*")).is_true()


func test_constraint_validity() -> void:
	assert_bool(SemVer.is_valid_constraint(">=1.0 <2.0")).is_true()
	assert_bool(SemVer.is_valid_constraint(">=banana")).is_false()
