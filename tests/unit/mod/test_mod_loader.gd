extends GdUnitTestSuite

const CORE_FILES := {
	"mod.json":
	'{"id": "core", "name": "Core", "version": "0.1.0", "api_version": 1, "kind": "gameplay"}',
	"content/tech.json": '{"type": "tech_field", "id": "tech_field.energy", "order": 0}',
	"lang/en.json": '{"tech_field.energy.name": "Energy"}',
}


func _core() -> MemoryModSource:
	return MemoryModSource.new("mem://core", CORE_FILES.duplicate())


func _mod(id: String, extra: Dictionary = {}, files: Dictionary = {}) -> MemoryModSource:
	var manifest := {"id": id, "name": id, "version": "1.0.0", "api_version": 1, "kind": "gameplay"}
	manifest.merge(extra, true)
	var all := {"mod.json": JSON.stringify(manifest)}
	all.merge(files)
	return MemoryModSource.new("mem://" + id, all)


func _load(sources: Array, enabled: Array, allow_test_mods: bool = false) -> ModLoader.LoadResult:
	var typed: Array[ModSource] = []
	typed.assign(sources)
	var loader := ModLoader.new()
	loader.allow_test_mods = allow_test_mods
	return loader.load_mods(typed, PackedStringArray(enabled))


func test_core_only() -> void:
	var r := _load([_core()], [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	assert_array(Array(r.order)).is_equal(["core"])
	assert_bool(r.registry.frozen).is_true()


func test_user_order_is_tiebreak() -> void:
	var r := _load([_core(), _mod("a"), _mod("b"), _mod("c")], ["c", "a", "b"])
	assert_array(Array(r.order)).is_equal(["core", "c", "a", "b"])


func test_dependencies_and_hints_win_over_user_order() -> void:
	var sources := [
		_core(),
		_mod("a", {"depends": {"b": ">=1.0"}}),
		_mod("b"),
		_mod("c", {"load_before": ["b"]}),
		_mod("d", {"load_after": ["a"]}),
	]
	var r := _load(sources, ["d", "a", "b", "c"])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	assert_array(Array(r.order)).is_equal(["core", "c", "b", "a", "d"])


func test_missing_dependency() -> void:
	var r := _load([_core(), _mod("a", {"depends": {"b": ""}})], ["a"])
	assert_str(r.error_text()).contains("needs mod 'b', which is not enabled")


func test_dependency_version_mismatch() -> void:
	var r := _load([_core(), _mod("a", {"depends": {"b": ">=2.0"}}), _mod("b")], ["a", "b"])
	assert_str(r.error_text()).contains("needs b >=2.0; found 1.0.0")


func test_conflicts() -> void:
	var r := _load([_core(), _mod("a", {"conflicts": ["b"]}), _mod("b")], ["a", "b"])
	assert_str(r.error_text()).contains("conflicts with 'b'")


func test_cycle() -> void:
	var sources := [_core(), _mod("a", {"load_after": ["b"]}), _mod("b", {"load_after": ["a"]})]
	var r := _load(sources, ["a", "b"])
	assert_str(r.error_text()).contains("load-order cycle among: a, b")


func test_api_and_game_version() -> void:
	var r := _load(
		[_core(), _mod("a", {"api_version": 99}), _mod("b", {"game_version": ">=5.0"})], ["a", "b"]
	)
	assert_str(r.error_text()).contains("needs mod API 99")
	assert_str(r.error_text()).contains("needs game >=5.0")


func test_unknown_and_duplicate_mods() -> void:
	var r := _load([_core(), _mod("a"), _mod("a")], ["a"])
	assert_str(r.error_text()).contains("two mods have this id")
	var r2 := _load([_core()], ["ghost"])
	assert_str(r2.error_text()).contains("ghost: enabled mod not found")


func test_missing_core() -> void:
	var r := _load([_mod("a")], ["a"])
	assert_str(r.error_text()).contains("the core mod is missing")


func test_bad_manifest() -> void:
	var source := MemoryModSource.new(
		"mem://bad", {"mod.json": '{"id": "Bad-Id", "name": "x", "version": "one", "kind": "x"}'}
	)
	var r := _load([_core(), source], [])
	var text := r.error_text()
	assert_str(text).contains('missing required field "api_version"')


func test_bad_manifest_fields() -> void:
	var source := (
		MemoryModSource
		. new(
			"mem://bad",
			{
				"mod.json":
				'{"id": "Bad-Id", "name": "x", "version": "one", "api_version": 1, "kind": "x", "extra": 1}'
			}
		)
	)
	var text := _load([_core(), source], []).error_text()
	assert_str(text).contains('unknown field "extra"')


func test_test_mods_refused_unless_allowed() -> void:
	var test_mod := MemoryModSource.new("res://tests/harness_compat", _mod("compat").files, true)
	var r := _load([_core(), test_mod], ["compat"])
	assert_str(r.error_text()).contains("test-only mod refused")
	var r2 := _load([_core(), test_mod], ["compat"], true)
	assert_bool(r2.ok()).override_failure_message(r2.error_text()).is_true()


func test_compat_id_reserved_outside_tests() -> void:
	var copy := _mod("harness_compat")  # not under res://tests/, e.g. copied to user://mods
	for allow in [false, true]:
		var r := _load([_core(), copy], ["harness_compat"], allow)
		assert_str(r.error_text()).contains("reserved for the test-only compat mod")


func test_cosmetic_mods_cannot_change_gameplay() -> void:
	var cosmetic := _mod(
		"pretty",
		{"kind": "cosmetic"},
		{"patches/p.json": '{"target": "tech_field.energy", "set": {"order": 3}}'}
	)
	var r := _load([_core(), cosmetic], ["pretty"])
	assert_str(r.error_text()).contains("a cosmetic mod cannot contain content/ or patches/")


func test_cosmetic_mods_do_not_change_hash() -> void:
	var base := _load([_core()], [])
	var cosmetic := _mod(
		"pretty", {"kind": "cosmetic"}, {"lang/en.json": '{"tech_field.energy.name": "Power"}'}
	)
	var r := _load([_core(), cosmetic], ["pretty"])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	assert_str(r.registry.display_name("tech_field.energy")).is_equal("Power")
	assert_str(r.registry.ruleset_hash).is_equal(base.registry.ruleset_hash)


func test_gameplay_mod_changes_hash() -> void:
	var base := _load([_core()], [])
	var r := _load([_core(), _mod("a")], ["a"])
	assert_str(r.registry.ruleset_hash).is_not_equal(base.registry.ruleset_hash)
