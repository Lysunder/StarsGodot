class_name SemVer
extends RefCounted
## Version numbers ("1.2.0") and version constraints (">=1.0 <2.0") for mod manifests.
##
## A version has one to three numeric parts; missing parts count as 0. A constraint is a
## space-separated list of terms that must all hold; each term is an optional operator
## (>=, <=, >, <, =) followed by a version. "" and "*" accept any version.

const _OPERATORS: Array[String] = [">=", "<=", ">", "<", "="]


## [major, minor, patch], or an empty array when the text is not a version.
static func parse(text: String) -> PackedInt32Array:
	var parts := text.strip_edges().split(".")
	if parts.size() < 1 or parts.size() > 3:
		return PackedInt32Array()
	var out := PackedInt32Array([0, 0, 0])
	for i in parts.size():
		if not parts[i].is_valid_int() or parts[i].to_int() < 0 or parts[i].begins_with("+"):
			return PackedInt32Array()
		out[i] = parts[i].to_int()
	return out


static func is_valid(text: String) -> bool:
	return parse(text).size() == 3


## -1, 0 or 1. Both arguments must be valid versions.
static func compare(a: String, b: String) -> int:
	var va := parse(a)
	var vb := parse(b)
	for i in 3:
		if va[i] != vb[i]:
			return -1 if va[i] < vb[i] else 1
	return 0


static func is_valid_constraint(constraint: String) -> bool:
	for term in _terms(constraint):
		if not is_valid(_split_term(term)[1]):
			return false
	return true


static func satisfies(version: String, constraint: String) -> bool:
	if not is_valid(version):
		return false
	for term in _terms(constraint):
		var op_version := _split_term(term)
		if not is_valid(op_version[1]):
			return false
		var c := compare(version, op_version[1])
		var ok: bool
		match op_version[0]:
			">=":
				ok = c >= 0
			"<=":
				ok = c <= 0
			">":
				ok = c > 0
			"<":
				ok = c < 0
			_:
				ok = c == 0
		if not ok:
			return false
	return true


static func _terms(constraint: String) -> PackedStringArray:
	var text := constraint.strip_edges()
	if text.is_empty() or text == "*":
		return PackedStringArray()
	return text.split(" ", false)


static func _split_term(term: String) -> PackedStringArray:
	for op in _OPERATORS:
		if term.begins_with(op):
			return PackedStringArray([op, term.substr(op.length())])
	return PackedStringArray(["=", term])
