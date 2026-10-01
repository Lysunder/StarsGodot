class_name ModManifest
extends RefCounted
## A mod's mod.json: identity, version, kind, dependencies and load-order hints (MODDING.md §2).

const FILE := "mod.json"
const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const KINDS: Array[String] = ["gameplay", "cosmetic"]
const _FIELDS := {
	"id": "string",
	"name": "string",
	"version": "string",
	"game_version": "string",
	"api_version": "int",
	"kind": "string",
	"authors": "list",
	"description": "string",
	"depends": "map",
	"optional_depends": "map",
	"conflicts": "list",
	"load_after": "list",
	"load_before": "list",
	"entry": "string",
}
const _REQUIRED: Array[String] = ["id", "name", "version", "api_version", "kind"]

var id: String = ""
var name: String = ""
var version: String = ""
## Constraint on the game version ("" = any).
var game_version: String = ""
var api_version: int = 0
var kind: String = ""
var authors: PackedStringArray = []
var description: String = ""
## mod id -> version constraint
var depends: Dictionary = {}
var optional_depends: Dictionary = {}
var conflicts: PackedStringArray = []
var load_after: PackedStringArray = []
var load_before: PackedStringArray = []
## Optional entry script (scripts are not loaded yet; see PLAN M6).
var entry: String = ""
var errors: Array[ContentError] = []


static func from_json(text: String, mod_label: String) -> ModManifest:
	var m := ModManifest.new()
	var parsed := JsonReader.parse(text)
	if not parsed.ok:
		m._err(mod_label, parsed.error_line, "invalid JSON: " + parsed.error)
		return m
	if not (parsed.value is Dictionary):
		m._err(mod_label, 1, "mod.json must hold one object")
		return m
	var data: Dictionary = parsed.value
	for key: String in data:
		var line: int = parsed.lines.get("/" + JsonReader.pointer_escape(key), 1)
		if not _FIELDS.has(key):
			m._err(mod_label, line, 'unknown field "%s"' % key)
		elif not _has_kind(data[key], _FIELDS[key]):
			m._err(mod_label, line, '"%s" must be a %s' % [key, _FIELDS[key]])
	for key in _REQUIRED:
		if not data.has(key):
			m._err(mod_label, 1, 'missing required field "%s"' % key)
	if not m.errors.is_empty():
		return m
	m.id = data["id"]
	m.name = data["name"]
	m.version = data["version"]
	m.game_version = data.get("game_version", "")
	m.api_version = data["api_version"]
	m.kind = data["kind"]
	m.authors = PackedStringArray(data.get("authors", []))
	m.description = data.get("description", "")
	m.depends = data.get("depends", {})
	m.optional_depends = data.get("optional_depends", {})
	m.conflicts = PackedStringArray(data.get("conflicts", []))
	m.load_after = PackedStringArray(data.get("load_after", []))
	m.load_before = PackedStringArray(data.get("load_before", []))
	m.entry = data.get("entry", "")
	var label := m.id if not m.id.is_empty() else mod_label
	if RegEx.create_from_string(ID_PATTERN).search(m.id) == null:
		m._err(mod_label, _line(parsed, "id"), "id must be lowercase letters, digits and _")
	if not SemVer.is_valid(m.version):
		m._err(label, _line(parsed, "version"), "version must look like 1.2.0")
	if not SemVer.is_valid_constraint(m.game_version):
		m._err(label, _line(parsed, "game_version"), "game_version is not a valid constraint")
	if not KINDS.has(m.kind):
		m._err(label, _line(parsed, "kind"), "kind must be gameplay or cosmetic")
	for field in ["depends", "optional_depends"]:
		var deps: Dictionary = data.get(field, {})
		for dep: String in deps:
			if not (deps[dep] is String) or not SemVer.is_valid_constraint(deps[dep]):
				m._err(
					label, _line(parsed, field), "%s: bad version constraint for %s" % [field, dep]
				)
	return m


static func _has_kind(value: Variant, kind_name: String) -> bool:
	match kind_name:
		"string":
			return value is String
		"int":
			return value is int
		"map":
			return value is Dictionary
		"list":
			if not (value is Array):
				return false
			for item: Variant in value:
				if not (item is String):
					return false
			return true
	return false


static func _line(parsed: JsonReader.Result, key: String) -> int:
	return parsed.lines.get("/" + key, 1)


func _err(mod_label: String, line: int, message: String) -> void:
	errors.append(ContentError.new(mod_label, FILE, line, message))
