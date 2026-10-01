class_name ContentSchemas
extends RefCounted
## Schemas for every content definition type, and the validator that checks definitions
## against them.
##
## A field spec is a Dictionary with key "t" (kind) plus options:
##   int (min, max), string, bool, enum (values), id, ref (to: a definition type),
##   list (of, min, max), object (fields, required), map (key, value).
## Objects reject unknown fields, so typos are caught. Gameplay numbers must be JSON integers:
## a float anywhere is an error.

const ID_PATTERN := "^[a-z][a-z0-9_]*(\\.[A-Za-z0-9_]+)+$"
const KEY_PATTERN := "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)*$"

const PART_CATEGORIES: Array[String] = [
	"engine",
	"scanner",
	"shield",
	"armor",
	"beam",
	"torpedo",
	"bomb",
	"mining_robot",
	"mine_layer",
	"orbital",
	"planetary",
	"electrical",
	"mechanical",
	"terraform",
]

const _INT0 := {"t": "int", "min": 0}
const _TAGS := {"t": "list", "of": {"t": "string"}}
const _TRAIT_LIST := {"t": "list", "of": {"t": "ref", "to": "trait"}}
const _TECH_REQ := {"t": "map", "key": {"t": "ref", "to": "tech_field"}, "value": _INT0}
const _COST := {
	"t": "object",
	"fields": {"ironium": _INT0, "boranium": _INT0, "germanium": _INT0, "resources": _INT0},
	"required": ["ironium", "boranium", "germanium", "resources"],
}
const _INT_MAP := {"t": "map", "key": {"t": "key"}, "value": {"t": "int"}}
const _SLOT := {
	"t": "object",
	"fields":
	{
		"accepts": {"t": "list", "of": {"t": "enum", "values": PART_CATEGORIES}, "min": 1},
		"max": {"t": "int", "min": 1},
		"required": {"t": "bool"},
	},
	"required": ["accepts", "max"],
}

## Fields every definition has, merged into each type's own fields.
const _COMMON := {"type": {"t": "string"}, "id": {"t": "id"}, "tags": _TAGS}

const TYPES := {
	"tech_field":
	{
		"fields": {"order": _INT0},
		"required": ["order"],
	},
	"trait":
	{
		"fields":
		{
			"kind": {"t": "enum", "values": ["primary", "lesser"]},
			"cost": {"t": "int"},
			"params": _INT_MAP,
			"excludes": _TRAIT_LIST,
		},
		"required": ["kind", "cost"],
	},
	"part":
	{
		"fields":
		{
			"category": {"t": "enum", "values": PART_CATEGORIES},
			"tech": _TECH_REQ,
			"mass": _INT0,
			"cost": _COST,
			"stats": _INT_MAP,
			"fuel_table": {"t": "list", "of": _INT0, "min": 11, "max": 11},
			"required_traits": _TRAIT_LIST,
			"forbidden_traits": _TRAIT_LIST,
		},
		"required": ["category", "mass", "cost"],
	},
	"hull":
	{
		"fields":
		{
			"starbase": {"t": "bool"},
			"tech": _TECH_REQ,
			"mass": _INT0,
			"cost": _COST,
			"armor": _INT0,
			"fuel": _INT0,
			"cargo": _INT0,
			"initiative": _INT0,
			"dock": {"t": "int", "min": -1},
			"slots": {"t": "list", "of": _SLOT, "min": 1},
			"required_traits": _TRAIT_LIST,
			"forbidden_traits": _TRAIT_LIST,
		},
		"required": ["mass", "cost", "armor", "slots"],
	},
	"constant":
	{
		"fields": {"value": {"t": "int"}},
		"required": ["value"],
	},
}


class Report:
	extends RefCounted
	## [pointer, message] pairs; pointers are JSON pointers relative to the definition.
	var errors: Array = []
	## [pointer, type, id] for every reference, resolved by the registry once all mods are loaded.
	var refs: Array = []


static func has_type(type_name: String) -> bool:
	return TYPES.has(type_name)


## Spec for a whole definition of the given type (common fields included).
static func def_spec(type_name: String) -> Dictionary:
	var own: Dictionary = TYPES[type_name]
	var fields: Dictionary = _COMMON.duplicate()
	fields.merge(own["fields"])
	var required: Array = ["type", "id"]
	required.append_array(own["required"])
	return {"t": "object", "fields": fields, "required": required}


static func validate_def(def: Dictionary) -> Report:
	var report := Report.new()
	var type_name: Variant = def.get("type")
	if not (type_name is String) or not has_type(type_name):
		report.errors.append(["/type", "unknown definition type %s" % JSON.stringify(type_name)])
		return report
	_check(def, def_spec(type_name), "", report)
	return report


static func _check(value: Variant, spec: Dictionary, pointer: String, report: Report) -> void:
	match spec["t"]:
		"int":
			if value is float:
				report.errors.append([pointer, "must be an integer, not %s" % str(value)])
			elif not (value is int):
				report.errors.append([pointer, "must be an integer"])
			else:
				if spec.has("min") and value < spec["min"]:
					report.errors.append([pointer, "must be at least %d" % spec["min"]])
				if spec.has("max") and value > spec["max"]:
					report.errors.append([pointer, "must be at most %d" % spec["max"]])
		"string":
			if not (value is String) or value.is_empty():
				report.errors.append([pointer, "must be a non-empty string"])
		"bool":
			if not (value is bool):
				report.errors.append([pointer, "must be true or false"])
		"enum":
			if not (value is String) or not spec["values"].has(value):
				report.errors.append(
					[pointer, "must be one of: %s" % ", ".join(PackedStringArray(spec["values"]))]
				)
		"id":
			if not (value is String) or not _matches(ID_PATTERN, value):
				report.errors.append([pointer, "must be an id like 'part.beam.laser'"])
		"key":
			if not (value is String) or not _matches(KEY_PATTERN, value):
				report.errors.append([pointer, "must be a lowercase key like 'max_pop_pct'"])
		"ref":
			if not (value is String) or not _matches(ID_PATTERN, value):
				report.errors.append([pointer, "must be the id of a %s" % spec["to"]])
			else:
				report.refs.append([pointer, spec["to"], value])
		"list":
			if not (value is Array):
				report.errors.append([pointer, "must be a list"])
				return
			if value.size() < spec.get("min", 0):
				report.errors.append([pointer, "needs at least %d entries" % spec["min"]])
			if spec.has("max") and value.size() > spec["max"]:
				report.errors.append([pointer, "allows at most %d entries" % spec["max"]])
			for i in value.size():
				_check(value[i], spec["of"], "%s/%d" % [pointer, i], report)
		"object":
			_check_object(value, spec, pointer, report)
		"map":
			if not (value is Dictionary):
				report.errors.append([pointer, "must be an object"])
				return
			for key: String in value:
				var key_pointer := pointer + "/" + JsonReader.pointer_escape(key)
				_check(key, spec["key"], key_pointer, report)
				_check(value[key], spec["value"], key_pointer, report)


static func _check_object(
	value: Variant, spec: Dictionary, pointer: String, report: Report
) -> void:
	if not (value is Dictionary):
		report.errors.append([pointer, "must be an object"])
		return
	var fields: Dictionary = spec["fields"]
	for key: String in value:
		var key_pointer := pointer + "/" + JsonReader.pointer_escape(key)
		if not fields.has(key):
			report.errors.append([key_pointer, 'unknown field "%s"' % key])
		else:
			_check(value[key], fields[key], key_pointer, report)
	for key: String in spec.get("required", []):
		if not value.has(key):
			report.errors.append([pointer, 'missing required field "%s"' % key])


static func _matches(pattern: String, text: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null
