class_name ContentRegistry
extends RefCounted
## All content definitions of one game, keyed by type and string id.
##
## Loading happens in three steps (MODDING.md §3):
## 1. Load: the ModLoader feeds each mod's files in load order (add_content_file, add_patch_file,
##    add_strings_file).
## 2. Resolve: finish() validates every definition against its schema, checks references and names.
## 3. Freeze: definitions become read-only and the ruleset hash is computed.
##
## Problems are collected in `errors` with mod, file and line; loading continues so one run reports
## as many problems as possible.

const CORE_MOD_ID := "core"
const PATCH_OPS: Array[String] = ["set", "add", "pct", "ratio", "append", "remove_values"]
const PATCH_KEYS: Array[String] = [
	"target", "select", "$remove", "set", "add", "pct", "ratio", "append", "remove_values"
]

var errors: Array[ContentError] = []
var frozen: bool = false
## SHA-256 (hex) of all gameplay content and the gameplay mod list; set by finish().
var ruleset_hash: String = ""

var _defs: Dictionary = {}  # type -> {id -> Dictionary}
var _type_of: Dictionary = {}  # id -> type
var _origins: Dictionary = {}  # id -> {def-relative pointer -> [mod, file, line]}
var _provenance: Dictionary = {}  # id -> Array of String
var _strings: Dictionary = {}  # locale -> {key -> String}
var _gameplay_mods: PackedStringArray = []  # "id@version" in load order


func _init() -> void:
	for type_name: String in ContentSchemas.TYPES:
		_defs[type_name] = {}


# --- Queries (after finish) -------------------------------------------------------------------


func has_def(id: String) -> bool:
	return _type_of.has(id)


func type_of(id: String) -> String:
	return _type_of.get(id, "")


func get_def(type_name: String, id: String) -> Dictionary:
	var table: Dictionary = _defs.get(type_name, {})
	if not table.has(id):
		push_error("ContentRegistry: no %s with id '%s'" % [type_name, id])
		return {}
	return table[id]


func part(id: String) -> Dictionary:
	return get_def("part", id)


func hull(id: String) -> Dictionary:
	return get_def("hull", id)


func trait_def(id: String) -> Dictionary:
	return get_def("trait", id)


func tech_field(id: String) -> Dictionary:
	return get_def("tech_field", id)


## The names of a name_list definition (S07: planet and race names).
func name_list(id: String) -> Array:
	return get_def("name_list", id).get("names", [])


func constant(id: String) -> int:
	return get_def("constant", id).get("value", 0)


## All ids of a type, sorted (the defined iteration order for content).
func ids(type_name: String) -> PackedStringArray:
	var result := PackedStringArray(_defs.get(type_name, {}).keys())
	result.sort()
	return result


## All ids of a type in definition order: files in load order, entries in file order (the
## original's catalogue order for the core parts and hulls, S21).
func ids_in_order(type_name: String) -> PackedStringArray:
	return PackedStringArray(_defs.get(type_name, {}).keys())


## The gameplay mods this content came from, as "id@version" in load order (cosmetic mods are
## not listed: they never change the rules).
func gameplay_mods() -> PackedStringArray:
	return _gameplay_mods.duplicate()


## Which mods touched a definition, in order ("core:add", "extra_hulls:patch patches/x.json", ...).
func provenance(id: String) -> PackedStringArray:
	return PackedStringArray(_provenance.get(id, []))


## Display name of a definition; falls back to English, then to the id.
func display_name(id: String, locale: String = "en") -> String:
	var key := id + ".name"
	for loc: String in [locale, "en"]:
		if _strings.has(loc) and _strings[loc].has(key):
			return _strings[loc][key]
	return id


func string_for(key: String, locale: String = "en") -> String:
	for loc: String in [locale, "en"]:
		if _strings.has(loc) and _strings[loc].has(key):
			return _strings[loc][key]
	return key


# --- Loading ----------------------------------------------------------------------------------


func note_gameplay_mod(mod_id: String, version: String) -> void:
	_gameplay_mods.append("%s@%s" % [mod_id, version])


## A content file holds one definition object or a list of them.
func add_content_file(mod_id: String, file: String, text: String) -> void:
	var parsed := _parse(mod_id, file, text)
	if parsed == null:
		return
	if parsed.value is Dictionary:
		_add_def(mod_id, file, parsed, "")
	elif parsed.value is Array:
		for i in parsed.value.size():
			_add_def(mod_id, file, parsed, "/%d" % i)
	else:
		_err(mod_id, file, 1, "a content file must hold an object or a list of objects")


## A patch file holds one patch object or a list of them.
func add_patch_file(mod_id: String, file: String, text: String) -> void:
	var parsed := _parse(mod_id, file, text)
	if parsed == null:
		return
	if parsed.value is Dictionary:
		_apply_patch(mod_id, file, parsed, "")
	elif parsed.value is Array:
		for i in parsed.value.size():
			_apply_patch(mod_id, file, parsed, "/%d" % i)
	else:
		_err(mod_id, file, 1, "a patch file must hold an object or a list of objects")


## A strings file is a flat object of key -> text for one locale. Later mods override earlier ones.
func add_strings_file(mod_id: String, file: String, locale: String, text: String) -> void:
	var parsed := _parse(mod_id, file, text)
	if parsed == null:
		return
	if not (parsed.value is Dictionary):
		_err(mod_id, file, 1, "a strings file must hold one object of key -> text")
		return
	var table: Dictionary = _strings.get_or_add(locale, {})
	for key: String in parsed.value:
		var value: Variant = parsed.value[key]
		if value is String:
			table[key] = value
		else:
			var line: int = parsed.lines.get("/" + JsonReader.pointer_escape(key), 0)
			_err(mod_id, file, line, 'string "%s" must be text' % key)


## Validates, resolves references, checks names, freezes and hashes. Returns true when error-free.
func finish() -> bool:
	for type_name in ContentSchemas.TYPES:
		for id in ids(type_name):
			_validate(id, _defs[type_name][id])
	for type_name in ContentSchemas.TYPES:
		for id in ids(type_name):
			if not _strings.get("en", {}).has(id + ".name"):
				var origin := _origin(id, "")
				_err(origin[0], origin[1], origin[2], 'no English name: add "%s.name"' % id)
	for type_name in ContentSchemas.TYPES:
		for id in _defs[type_name]:
			_deep_freeze(_defs[type_name][id])
	ruleset_hash = _compute_hash()
	frozen = true
	return errors.is_empty()


# --- Definitions ------------------------------------------------------------------------------


func _add_def(mod_id: String, file: String, parsed: JsonReader.Result, base: String) -> void:
	var line: int = parsed.lines.get(base, 0)
	var raw: Variant = _at_pointer(parsed.value, base)
	if not (raw is Dictionary):
		_err(mod_id, file, line, "a definition must be an object")
		return
	var def: Dictionary = raw.duplicate(true)
	var replace: bool = def.get("$replace", false) == true
	def.erase("$replace")
	var type_name: Variant = def.get("type")
	var id: Variant = def.get("id")
	if not (type_name is String) or not ContentSchemas.has_type(type_name):
		_err(mod_id, file, line, "unknown definition type %s" % JSON.stringify(type_name))
		return
	if not (id is String) or id.is_empty():
		_err(mod_id, file, line, "a definition needs a string id")
		return
	if replace:
		if not _type_of.has(id):
			_err(mod_id, file, line, "$replace: no existing definition '%s'" % id)
			return
		if _type_of[id] != type_name:
			_err(
				mod_id,
				file,
				line,
				"$replace: '%s' is a %s, not a %s" % [id, _type_of[id], type_name]
			)
			return
		_provenance[id].append("%s:replace %s" % [mod_id, file])
	else:
		if _type_of.has(id):
			_err(mod_id, file, line, "duplicate id '%s' (use $replace or a patch)" % id)
			return
		var prefix := "%s." % type_name if mod_id == CORE_MOD_ID else "%s.%s." % [mod_id, type_name]
		if not id.begins_with(prefix):
			_err(
				mod_id,
				file,
				line,
				"new %s ids from this mod must start with '%s'" % [type_name, prefix]
			)
			return
		_provenance[id] = ["%s:add %s" % [mod_id, file]]
	_defs[type_name][id] = def
	_type_of[id] = type_name
	var origins := {}
	for pointer: String in parsed.lines:
		if pointer == base or pointer.begins_with(base + "/"):
			origins[pointer.substr(base.length())] = [mod_id, file, parsed.lines[pointer]]
	_origins[id] = origins


func _validate(id: String, def: Dictionary) -> void:
	var report := ContentSchemas.validate_def(def)
	for entry: Array in report.errors:
		var origin := _origin(id, entry[0])
		_err(origin[0], origin[1], origin[2], "%s %s: %s" % [id, entry[0], entry[1]])
	for ref: Array in report.refs:
		if _type_of.get(ref[2], "") != ref[1]:
			var origin := _origin(id, ref[0])
			_err(origin[0], origin[1], origin[2], "%s: unknown %s '%s'" % [id, ref[1], ref[2]])


# --- Patches ----------------------------------------------------------------------------------


func _apply_patch(mod_id: String, file: String, parsed: JsonReader.Result, base: String) -> void:
	var line: int = parsed.lines.get(base, 0)
	var patch: Variant = _at_pointer(parsed.value, base)
	if not (patch is Dictionary):
		_err(mod_id, file, line, "a patch must be an object")
		return
	for key: String in patch:
		if not PATCH_KEYS.has(key):
			_err(
				mod_id,
				file,
				parsed.lines.get(base + "/" + key, line),
				'unknown patch key "%s"' % key
			)
			return
	var targets: PackedStringArray = []
	if patch.has("target") == patch.has("select"):
		_err(mod_id, file, line, 'a patch needs exactly one of "target" or "select"')
		return
	if patch.has("target"):
		if not _type_of.has(patch["target"]):
			_err(mod_id, file, line, "patch target '%s' does not exist" % str(patch["target"]))
			return
		targets.append(patch["target"])
	else:
		targets = _select(mod_id, file, line, patch["select"])
	if patch.get("$remove", false) == true:
		for id in targets:
			_defs[_type_of[id]].erase(id)
			_type_of.erase(id)
			_origins.erase(id)
			_provenance[id].append("%s:remove %s" % [mod_id, file])
		return
	for id in targets:
		var def: Dictionary = _defs[_type_of[id]][id]
		for op in PATCH_OPS:
			if not patch.has(op):
				continue
			var op_pointer := base + "/" + op
			if not (patch[op] is Dictionary):
				_err(mod_id, file, parsed.lines.get(op_pointer, line), "%s must be an object" % op)
				continue
			for path: String in patch[op]:
				var value_pointer := op_pointer + "/" + JsonReader.pointer_escape(path)
				var value_line: int = parsed.lines.get(value_pointer, line)
				var problem := _apply_op(def, op, path, patch[op][path])
				if not problem.is_empty():
					_err(mod_id, file, value_line, "%s %s '%s': %s" % [id, op, path, problem])
				else:
					_origins[id][_dotted_to_pointer(path)] = [mod_id, file, value_line]
		_provenance[id].append("%s:patch %s" % [mod_id, file])


func _select(mod_id: String, file: String, line: int, selector: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	if not (selector is Dictionary) or not ContentSchemas.has_type(selector.get("type", "")):
		_err(mod_id, file, line, 'select needs a known "type" (and optionally a "tag")')
		return result
	var tag: Variant = selector.get("tag")
	for id in ids(selector["type"]):
		if tag == null or _defs[selector["type"]][id].get("tags", []).has(tag):
			result.append(id)
	return result


## Applies one patch operation; returns an error message, or "" on success.
func _apply_op(def: Dictionary, op: String, path: String, arg: Variant) -> String:
	var segments := path.split(".")
	var parent: Variant = def
	for i in segments.size() - 1:
		var next: Variant = _child(parent, segments[i])
		if next == null and op == "set" and parent is Dictionary:
			next = {}
			parent[segments[i]] = next
		if not (next is Dictionary or next is Array):
			return "no such path"
		parent = next
	var leaf := segments[segments.size() - 1]
	var current: Variant = _child(parent, leaf)
	if op == "set":
		return _put(parent, leaf, arg.duplicate(true) if arg is Dictionary or arg is Array else arg)
	if op == "append" or op == "remove_values":
		return _list_op(parent, leaf, current, op, arg)
	if not (current is int):
		return "target value is not an integer"
	var result := _number_op(current, op, arg)
	if result.size() == 1:
		return result[0]
	return _put(parent, leaf, result[1])


## add / pct / ratio with integer math (truncating toward zero). Returns [error] or ["", value].
static func _number_op(current: int, op: String, arg: Variant) -> Array:
	match op:
		"add":
			return ["", current + arg] if arg is int else ["add needs an integer"]
		"pct":
			return ["", current * arg / 100] if arg is int else ["pct needs an integer percent"]
	var ok: bool = (
		arg is Array and arg.size() == 2 and arg[0] is int and arg[1] is int and arg[1] != 0
	)
	return (
		["", current * arg[0] / arg[1]] if ok else ["ratio needs [numerator, denominator] integers"]
	)


func _list_op(parent: Variant, leaf: String, current: Variant, op: String, arg: Variant) -> String:
	if not (arg is Array):
		return "%s needs a list" % op
	if current == null and op == "append":
		current = []
		var problem := _put(parent, leaf, current)
		if not problem.is_empty():
			return problem
	if not (current is Array):
		return "target value is not a list"
	for item: Variant in arg:
		if op == "append":
			current.append(item)
		else:
			current.erase(item)
	return ""


func _child(container: Variant, segment: String) -> Variant:
	if container is Dictionary:
		return container.get(segment)
	if container is Array and segment.is_valid_int():
		var index := segment.to_int()
		return container[index] if index >= 0 and index < container.size() else null
	return null


func _put(container: Variant, segment: String, value: Variant) -> String:
	if container is Dictionary:
		container[segment] = value
		return ""
	if container is Array and segment.is_valid_int():
		var index := segment.to_int()
		if index >= 0 and index < container.size():
			container[index] = value
			return ""
	return "no such path"


# --- Helpers ----------------------------------------------------------------------------------


func _parse(mod_id: String, file: String, text: String) -> JsonReader.Result:
	var parsed := JsonReader.parse(text)
	if not parsed.ok:
		_err(mod_id, file, parsed.error_line, "invalid JSON: " + parsed.error)
		return null
	return parsed


func _err(mod_id: String, file: String, line: int, message: String) -> void:
	errors.append(ContentError.new(mod_id, file, line, message))


## Where a value of a definition came from: the nearest recorded pointer at or above `pointer`.
func _origin(id: String, pointer: String) -> Array:
	var origins: Dictionary = _origins.get(id, {})
	var p := pointer
	while true:
		if origins.has(p):
			return origins[p]
		if p.is_empty():
			break
		p = p.substr(0, p.rfind("/"))
	return ["?", "", 0]


static func _at_pointer(root: Variant, pointer: String) -> Variant:
	var node: Variant = root
	for segment in pointer.split("/", false):
		node = node[segment.to_int()] if node is Array else node.get(segment)
	return node


static func _dotted_to_pointer(path: String) -> String:
	var out := ""
	for segment in path.split("."):
		out += "/" + JsonReader.pointer_escape(segment)
	return out


static func _deep_freeze(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value:
			_deep_freeze(value[key])
		value.make_read_only()
	elif value is Array:
		for item: Variant in value:
			_deep_freeze(item)
		value.make_read_only()


func _compute_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("mods:" + ",".join(_gameplay_mods) + "\n").to_utf8_buffer())
	for type_name: String in ContentSchemas.TYPES.keys():
		for id in ids(type_name):
			ctx.update(
				("%s|%s|%s\n" % [type_name, id, canonical(_defs[type_name][id])]).to_utf8_buffer()
			)
	return ctx.finish().hex_encode()


## Stable text form of a JSON-like value: object keys sorted, no whitespace.
static func canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for key: Variant in keys:
			parts.append(JSON.stringify(str(key)) + ":" + canonical(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var items: PackedStringArray = []
		for item: Variant in value:
			items.append(canonical(item))
		return "[" + ",".join(items) + "]"
	if value is String:
		return JSON.stringify(value)
	if value is bool:
		return "true" if value else "false"
	if value == null:
		return "null"
	return str(value)
