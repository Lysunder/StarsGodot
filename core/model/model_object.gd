class_name ModelObject
extends RefCounted
## Base class of the game state entities (spec S03).
##
## Each subclass lists its saved fields once in _schema(). That list drives the saved form
## (to_dict / load_dict), deep copies, equality and the state hash, so a new field cannot be
## forgotten in one of them. Variables that are not in the schema are turn-only marks: they are
## not saved, copied or compared.
##
## Schema entries are [name, kind] or [name, kind, extra]:
## - INT, BOOL, STRING, INT_LIST, STRING_LIST: plain values (lists are Array[int] / Array[String]).
## - ENUM: a String that must be one of extra (an Array of allowed values).
## - OBJECT, OBJECT_OR_NULL, OBJECT_LIST: other model objects; extra is their script.
## - JSON: a JSON-style value (integers, strings, booleans, null, lists, maps with string keys),
##   for mod_data and for fields whose shape a later spec defines.

enum Kind {
	INT,
	BOOL,
	STRING,
	ENUM,
	INT_LIST,
	STRING_LIST,
	OBJECT,
	OBJECT_OR_NULL,
	OBJECT_LIST,
	JSON,
}


## Overridden by every entity: its saved fields, in saved order.
func _schema() -> Array:
	return []


func to_dict() -> Dictionary:
	var out := {}
	for field: Array in _schema():
		out[field[0]] = _encode(get(field[0]), field[1])
	return out


## Fills this object from a saved form. Problems are appended to errors as "path: message".
## Unknown and missing fields are errors.
func load_dict(data: Variant, path: String, errors: PackedStringArray) -> void:
	if not data is Dictionary:
		errors.append("%s: expected an object" % path)
		return
	var known := {}
	for field: Array in _schema():
		known[field[0]] = true
		var field_path: String = path + "/" + field[0]
		if not data.has(field[0]):
			errors.append("%s: missing" % field_path)
			continue
		_decode_into(field, data[field[0]], field_path, errors)
	var extra: Array = data.keys()
	extra.sort()
	for key: Variant in extra:
		if not known.has(key):
			errors.append("%s/%s: unknown field" % [path, key])


## A new object of this object's class with the same saved fields (deep copy).
func copy() -> ModelObject:
	var out: ModelObject = get_script().new()
	var errors := PackedStringArray()
	out.load_dict(to_dict(), "", errors)
	assert(errors.is_empty(), "copy: %s" % ", ".join(errors))
	return out


## Equal when the saved forms are equal. Turn-only marks are ignored.
func equals(other: ModelObject) -> bool:
	if other == null or other.get_script() != get_script():
		return false
	return canonical_text() == other.canonical_text()


## Stable text of the saved form: keys sorted, no whitespace, integers in decimal.
func canonical_text() -> String:
	return ContentRegistry.canonical(to_dict())


## SHA-256 (hex) of canonical_text().
func state_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical_text().to_utf8_buffer())
	return ctx.finish().hex_encode()


## Loads one model object of the given script; null (with errors) when data is not an object.
static func object_from(
	script: GDScript, data: Variant, path: String, errors: PackedStringArray
) -> ModelObject:
	if not data is Dictionary:
		errors.append("%s: expected an object" % path)
		return null
	var obj: ModelObject = script.new()
	obj.load_dict(data, path, errors)
	return obj


## True for an integer, or a float without a fraction (JSON readers may return floats).
static func is_whole(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floorf(value) and absf(value) < 9.0e15


## Checks a JSON-style value: no floats with fractions, string keys only. Returns a clean copy
## with whole floats turned into ints, or appends errors.
static func clean_json(value: Variant, path: String, errors: PackedStringArray) -> Variant:
	if value == null or value is bool or value is String or value is int:
		return value
	if value is float:
		if is_whole(value):
			return int(value)
		errors.append("%s: must be an integer" % path)
		return 0
	if value is Array:
		var out := []
		for i in value.size():
			out.append(clean_json(value[i], "%s/%d" % [path, i], errors))
		return out
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			if not key is String:
				errors.append("%s: keys must be strings" % path)
				continue
			out[key] = clean_json(value[key], "%s/%s" % [path, key], errors)
		return out
	errors.append("%s: not a JSON value" % path)
	return null


static func _encode(value: Variant, kind: Kind) -> Variant:
	match kind:
		Kind.INT_LIST, Kind.STRING_LIST:
			return (value as Array).duplicate()
		Kind.OBJECT:
			return (value as ModelObject).to_dict()
		Kind.OBJECT_OR_NULL:
			return null if value == null else (value as ModelObject).to_dict()
		Kind.OBJECT_LIST:
			var out := []
			for item: ModelObject in value:
				out.append(item.to_dict())
			return out
		Kind.JSON:
			return value.duplicate(true) if value is Array or value is Dictionary else value
	return value


func _decode_into(field: Array, value: Variant, path: String, errors: PackedStringArray) -> void:
	var name: String = field[0]
	match field[1]:
		Kind.INT:
			if is_whole(value):
				set(name, int(value))
			else:
				errors.append("%s: must be an integer" % path)
		Kind.BOOL:
			if value is bool:
				set(name, value)
			else:
				errors.append("%s: must be true or false" % path)
		Kind.STRING:
			if value is String:
				set(name, value)
			else:
				errors.append("%s: must be a string" % path)
		Kind.ENUM:
			if value is String and (field[2] as Array).has(value):
				set(name, value)
			else:
				errors.append("%s: must be one of %s" % [path, ", ".join(field[2])])
		Kind.INT_LIST, Kind.STRING_LIST:
			_decode_list(field, value, path, errors)
		Kind.OBJECT:
			var obj: Variant = object_from(field[2], value, path, errors)
			if obj != null:
				set(name, obj)
		Kind.OBJECT_OR_NULL:
			set(name, null if value == null else object_from(field[2], value, path, errors))
		Kind.OBJECT_LIST:
			_decode_object_list(field, value, path, errors)
		Kind.JSON:
			set(name, clean_json(value, path, errors))


func _decode_list(field: Array, value: Variant, path: String, errors: PackedStringArray) -> void:
	if not value is Array:
		errors.append("%s: must be a list" % path)
		return
	var items := []
	for i in value.size():
		var item: Variant = value[i]
		if field[1] == Kind.INT_LIST:
			if not is_whole(item):
				errors.append("%s/%d: must be an integer" % [path, i])
				continue
			items.append(int(item))
		elif item is String:
			items.append(item)
		else:
			errors.append("%s/%d: must be a string" % [path, i])
	(get(field[0]) as Array).assign(items)


func _decode_object_list(
	field: Array, value: Variant, path: String, errors: PackedStringArray
) -> void:
	if not value is Array:
		errors.append("%s: must be a list" % path)
		return
	var items := []
	for i in value.size():
		var obj: Variant = object_from(field[2], value[i], "%s/%d" % [path, i], errors)
		if obj != null:
			items.append(obj)
	(get(field[0]) as Array).assign(items)
