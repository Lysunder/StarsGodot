class_name StateDiff
extends RefCounted
## Field-by-field comparison of two game states (used by the golden-turn runner, M4, and by PBEM
## consistency checks).
##
## Works on the saved forms (S03), so it sees exactly what a save holds. Lists of numbered objects
## are matched by identity, not position, so one new fleet shows as one added fleet:
##
## - fleets, minefields, packets: by (owner, number), path segment `[owner:number]`
## - wormholes, traders: by number, `[number]`
## - ship_designs, starbase_designs: by slot, `[slot]`
## - stacks: by design slot, `[design]`
##
## Other lists compare by position (`/planets/17/surface/0`). Ignore patterns use String.match
## wildcards (`*` matches any text, including "/"); a pattern also ignores everything below a
## matching path.

const CHANGED := "changed"
const ADDED := "added"
const REMOVED := "removed"

const _KEYS := {
	"fleets": ["owner", "number"],
	"minefields": ["owner", "number"],
	"packets": ["owner", "number"],
	"wormholes": ["number"],
	"traders": ["number"],
	"ship_designs": ["slot"],
	"starbase_designs": ["slot"],
	"stacks": ["design"],
}


## One difference. For ADDED, `before` is null; for REMOVED, `after` is null.
class Difference:
	extends RefCounted
	var path: String
	var kind: String
	var before: Variant
	var after: Variant

	func _init(p_path: String, p_kind: String, p_before: Variant, p_after: Variant) -> void:
		path = p_path
		kind = p_kind
		before = p_before
		after = p_after

	func _to_string() -> String:
		match kind:
			ADDED:
				return "%s: added %s" % [path, StateDiff.short(after)]
			REMOVED:
				return "%s: removed %s" % [path, StateDiff.short(before)]
		return "%s: %s -> %s" % [path, StateDiff.short(before), StateDiff.short(after)]


var _ignore: PackedStringArray = []
var _out: Array[Difference] = []


## Differences between two states, in a stable order (paths in document order).
static func compare(
	before: GameState, after: GameState, ignore: PackedStringArray = PackedStringArray()
) -> Array[Difference]:
	return compare_dicts(before.to_dict(), after.to_dict(), ignore)


## The same on saved forms (dictionaries from to_dict() or a parsed save's "state").
static func compare_dicts(
	before: Dictionary, after: Dictionary, ignore: PackedStringArray = PackedStringArray()
) -> Array[Difference]:
	var diff := StateDiff.new()
	diff._ignore = ignore
	diff._value("", "", before, after)
	return diff._out


## A readable report: one line per difference, at most `limit` lines plus a count of the rest.
static func format(diffs: Array[Difference], limit: int = 200) -> String:
	var lines := PackedStringArray()
	for i in mini(diffs.size(), limit):
		lines.append(str(diffs[i]))
	if diffs.size() > limit:
		lines.append("... and %d more" % (diffs.size() - limit))
	return "\n".join(lines)


## Compact text of a value for reports (objects and long lists are summarized).
static func short(value: Variant) -> String:
	if value is Dictionary:
		return "{%d fields}" % value.size()
	if value is Array and value.size() > 8:
		return "[%d items]" % value.size()
	return ContentRegistry.canonical(value)


func _ignored(path: String) -> bool:
	for pattern in _ignore:
		if (
			path.match(pattern)
			or path.begins_with(pattern + "/")
			or path.begins_with(pattern + "[")
		):
			return true
	return false


func _add(path: String, kind: String, before: Variant, after: Variant) -> void:
	if not _ignored(path):
		_out.append(Difference.new(path, kind, before, after))


func _value(path: String, name: String, before: Variant, after: Variant) -> void:
	if _ignored(path):
		return
	if before is Dictionary and after is Dictionary:
		_dict(path, before, after)
	elif before is Array and after is Array:
		if _KEYS.has(name) and _all_keyed(before, _KEYS[name]) and _all_keyed(after, _KEYS[name]):
			_keyed_list(path, _KEYS[name], before, after)
		else:
			_list(path, before, after)
	elif not _same(before, after):
		_add(path, CHANGED, before, after)


func _dict(path: String, before: Dictionary, after: Dictionary) -> void:
	var keys := {}
	for k: Variant in before:
		keys[k] = true
	for k: Variant in after:
		keys[k] = true
	var sorted: Array = keys.keys()
	sorted.sort()
	for k: Variant in sorted:
		var sub := "%s/%s" % [path, k]
		if not after.has(k):
			_add(sub, REMOVED, before[k], null)
		elif not before.has(k):
			_add(sub, ADDED, null, after[k])
		else:
			_value(sub, str(k), before[k], after[k])


func _list(path: String, before: Array, after: Array) -> void:
	for i in maxi(before.size(), after.size()):
		var sub := "%s/%d" % [path, i]
		if i >= after.size():
			_add(sub, REMOVED, before[i], null)
		elif i >= before.size():
			_add(sub, ADDED, null, after[i])
		else:
			_value(sub, "", before[i], after[i])


func _keyed_list(path: String, key_fields: Array, before: Array, after: Array) -> void:
	var old := {}
	for item: Dictionary in before:
		old[_key(item, key_fields)] = item
	var new := {}
	for item: Dictionary in after:
		new[_key(item, key_fields)] = item
	var keys: Array = old.keys()
	for k: Variant in new:
		if not old.has(k):
			keys.append(k)
	keys.sort_custom(_key_less)
	for k: Array in keys:
		var sub := "%s[%s]" % [path, ":".join(k.map(func(v: int) -> String: return str(v)))]
		if not new.has(k):
			_add(sub, REMOVED, old[k], null)
		elif not old.has(k):
			_add(sub, ADDED, null, new[k])
		else:
			_dict(sub, old[k], new[k])


## Equal values; integers and whole floats with the same value count as equal (JSON readers
## may return either).
static func _same(a: Variant, b: Variant) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return a == b
	return typeof(a) == typeof(b) and a == b


static func _all_keyed(items: Array, key_fields: Array) -> bool:
	for item: Variant in items:
		if not item is Dictionary:
			return false
		for field: String in key_fields:
			if not ModelObject.is_whole(item.get(field)):
				return false
	return true


static func _key(item: Dictionary, key_fields: Array) -> Array:
	var out := []
	for field: String in key_fields:
		out.append(int(item[field]))
	return out


static func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
