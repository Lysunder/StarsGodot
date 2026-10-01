class_name ModLoader
extends RefCounted
## Reads mod manifests, works out the load order, and loads every mod's content into a fresh
## ContentRegistry (MODDING.md §2–4).
##
## Load order: `core` first; then every mod after its dependencies and `load_after` mods and before
## its `load_before` mods; ties follow the user's order. Cycles, missing dependencies, version
## mismatches and conflicts are errors, and no content is loaded when any are found.
##
## Within a mod: content/**/*.json, then patches/**/*.json, then lang/<locale>.json, each in sorted
## path order.

const API_VERSION := 1
const CORE_ID := ContentRegistry.CORE_MOD_ID
## Mod ids only test mods may use: a copy of the compat mod anywhere else is refused (D12).
const RESERVED_TEST_IDS: Array[String] = ["harness_compat"]


class LoadResult:
	extends RefCounted
	var registry: ContentRegistry = ContentRegistry.new()
	## Mod ids in load order.
	var order: PackedStringArray = []
	## mod id -> ModManifest, for every mod found (enabled or not).
	var manifests: Dictionary = {}
	var errors: Array[ContentError] = []

	func ok() -> bool:
		return errors.is_empty()

	func error_text() -> String:
		var lines: PackedStringArray = []
		for e in errors:
			lines.append(str(e))
		return "\n".join(lines)


var game_version: String = "0.1.0"
## Only test runs set this; it allows mods that live under res://tests/ (D12).
var allow_test_mods: bool = false


## Loads `core` plus the `enabled` mods (in the user's order) from the given sources.
func load_mods(sources: Array[ModSource], enabled: PackedStringArray) -> LoadResult:
	var result := LoadResult.new()
	var source_of := {}
	for source in sources:
		var label := source.root()
		if not source.has_file(ModManifest.FILE):
			result.errors.append(ContentError.new(label, ModManifest.FILE, 0, "no mod.json"))
			continue
		var manifest := ModManifest.from_json(source.read_text(ModManifest.FILE), label)
		if not manifest.errors.is_empty():
			result.errors.append_array(manifest.errors)
			continue
		if source.is_test_mod() and not allow_test_mods:
			result.errors.append(
				ContentError.new(manifest.id, "", 0, "test-only mod refused outside test runs")
			)
			continue
		if RESERVED_TEST_IDS.has(manifest.id) and not source.is_test_mod():
			result.errors.append(
				ContentError.new(
					manifest.id, "", 0, "this id is reserved for the test-only compat mod (D12)"
				)
			)
			continue
		if result.manifests.has(manifest.id):
			result.errors.append(
				ContentError.new(
					manifest.id,
					"",
					0,
					"two mods have this id: %s and %s" % [source_of[manifest.id].root(), label]
				)
			)
			continue
		result.manifests[manifest.id] = manifest
		source_of[manifest.id] = source
	if not result.errors.is_empty():
		return result

	var selected := _select(result, enabled)
	if result.errors.is_empty():
		_check_compatibility(result, selected)
	if result.errors.is_empty():
		result.order = _order(result, selected)
	if not result.errors.is_empty():
		return result

	for mod_id in result.order:
		_load_one(result, result.manifests[mod_id], source_of[mod_id])
	result.registry.finish()
	result.errors.append_array(result.registry.errors)
	return result


## core + enabled, with the user's rank for each (core = -1).
func _select(result: LoadResult, enabled: PackedStringArray) -> Dictionary:
	var selected := {}
	if not result.manifests.has(CORE_ID):
		result.errors.append(ContentError.new(CORE_ID, "", 0, "the core mod is missing"))
		return selected
	selected[CORE_ID] = -1
	for i in enabled.size():
		var mod_id := enabled[i]
		if mod_id == CORE_ID:
			continue
		if not result.manifests.has(mod_id):
			result.errors.append(ContentError.new(mod_id, "", 0, "enabled mod not found"))
		elif not selected.has(mod_id):
			selected[mod_id] = i
	return selected


func _check_compatibility(result: LoadResult, selected: Dictionary) -> void:
	for mod_id: String in _sorted(selected.keys()):
		var m: ModManifest = result.manifests[mod_id]
		if m.api_version != API_VERSION:
			_err(
				result, mod_id, "needs mod API %d; this game has %d" % [m.api_version, API_VERSION]
			)
		if not SemVer.satisfies(game_version, m.game_version):
			_err(result, mod_id, "needs game %s; this is %s" % [m.game_version, game_version])
		for dep: String in _sorted(m.depends.keys()):
			if not selected.has(dep):
				_err(result, mod_id, "needs mod '%s', which is not enabled" % dep)
			elif not SemVer.satisfies(result.manifests[dep].version, m.depends[dep]):
				_err(
					result,
					mod_id,
					"needs %s %s; found %s" % [dep, m.depends[dep], result.manifests[dep].version]
				)
		for dep: String in _sorted(m.optional_depends.keys()):
			if (
				selected.has(dep)
				and not SemVer.satisfies(result.manifests[dep].version, m.optional_depends[dep])
			):
				_err(
					result,
					mod_id,
					(
						"works with %s %s; found %s"
						% [dep, m.optional_depends[dep], result.manifests[dep].version]
					)
				)
		for other in m.conflicts:
			if selected.has(other):
				_err(result, mod_id, "conflicts with '%s'" % other)


## Topological sort; among mods that are ready, the lowest user rank goes first.
func _order(result: LoadResult, selected: Dictionary) -> PackedStringArray:
	var after := {}  # mod -> mods that must load before it
	for mod_id: String in selected:
		after[mod_id] = {}
	for mod_id: String in selected:
		var m: ModManifest = result.manifests[mod_id]
		if mod_id != CORE_ID:
			after[mod_id][CORE_ID] = true
		var before_me: Array = m.depends.keys() + m.optional_depends.keys() + Array(m.load_after)
		for other: String in before_me:
			if selected.has(other):
				after[mod_id][other] = true
		for other in m.load_before:
			if selected.has(other):
				after[other][mod_id] = true
	var order: PackedStringArray = []
	var done := {}
	while order.size() < selected.size():
		var best := ""
		for mod_id: String in selected:
			if done.has(mod_id):
				continue
			var ready := true
			for dep: String in after[mod_id]:
				if not done.has(dep):
					ready = false
					break
			if ready and (best.is_empty() or selected[mod_id] < selected[best]):
				best = mod_id
		if best.is_empty():
			var stuck: PackedStringArray = []
			for mod_id: String in _sorted(selected.keys()):
				if not done.has(mod_id):
					stuck.append(mod_id)
			_err(result, stuck[0], "load-order cycle among: " + ", ".join(stuck))
			return PackedStringArray()
		order.append(best)
		done[best] = true
	return order


func _load_one(result: LoadResult, m: ModManifest, source: ModSource) -> void:
	var registry := result.registry
	var content_files := source.list_files("content", "json")
	var patch_files := source.list_files("patches", "json")
	if m.kind == "cosmetic" and not (content_files.is_empty() and patch_files.is_empty()):
		_err(result, m.id, "a cosmetic mod cannot contain content/ or patches/")
		return
	if m.kind == "gameplay":
		registry.note_gameplay_mod(m.id, m.version)
	for path in content_files:
		registry.add_content_file(m.id, path, source.read_text(path))
	for path in patch_files:
		registry.add_patch_file(m.id, path, source.read_text(path))
	for path in source.list_files("lang", "json"):
		registry.add_strings_file(
			m.id, path, path.get_file().get_basename(), source.read_text(path)
		)


func _err(result: LoadResult, mod_id: String, message: String) -> void:
	result.errors.append(ContentError.new(mod_id, ModManifest.FILE, 0, message))


static func _sorted(items: Array) -> Array:
	var copy := items.duplicate()
	copy.sort()
	return copy
