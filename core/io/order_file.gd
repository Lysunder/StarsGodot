class_name OrderFile
extends RefCounted
## Our order file format (spec S11, "Order files"): one player's orders for one turn, as a JSON
## object with a header, in canonical form. Each order is checked against the game state only when
## the turn is generated (OrderRules).

const FORMAT := "starsgodot-orders"
const FORMAT_VERSION := 1
const EXTENSION := "orders"
const _KEYS := ["format", "format_version", "game_version", "player", "turn", "orders"]


class LoadResult:
	extends RefCounted
	var order_set: OrderSet = null
	var errors: PackedStringArray = []
	var game_version: String = ""

	func ok() -> bool:
		return errors.is_empty() and order_set != null


static func encode(order_set: OrderSet, game_version: String) -> String:
	var data := order_set.to_dict()
	data["format"] = FORMAT
	data["format_version"] = FORMAT_VERSION
	data["game_version"] = game_version
	return ContentRegistry.canonical(data) + "\n"


static func decode(text: String) -> LoadResult:
	var result := LoadResult.new()
	var parsed := JsonReader.parse(text)
	if not parsed.ok:
		result.errors.append("line %d: %s" % [parsed.error_line, parsed.error])
		return result
	var data: Variant = parsed.value
	if not data is Dictionary or data.get("format") != FORMAT:
		result.errors.append("not a %s file" % FORMAT)
		return result
	for key: String in _KEYS:
		if not data.has(key):
			result.errors.append("/%s: missing" % key)
	for key: Variant in data:
		if not _KEYS.has(key):
			result.errors.append("/%s: unknown field" % key)
	if not result.errors.is_empty():
		return result
	var version: Variant = data["format_version"]
	if not version is int or version < 1:
		result.errors.append("/format_version: must be a positive integer")
	elif version > FORMAT_VERSION:
		result.errors.append(
			"/format_version: %d is newer than this game reads (%d)" % [version, FORMAT_VERSION]
		)
	if not data["game_version"] is String:
		result.errors.append("/game_version: must be a string")
	else:
		result.game_version = data["game_version"]
	for key: String in ["player", "turn"]:
		if not data[key] is int or data[key] < 0:
			result.errors.append("/%s: must be a non-negative integer" % key)
	if not data["orders"] is Array:
		result.errors.append("/orders: must be a list")
	else:
		var orders: Array = data["orders"]
		for i in orders.size():
			if not orders[i] is Dictionary or not orders[i].get("type") is String:
				result.errors.append('/orders/%d: must be an object with a "type"' % i)
	if not result.errors.is_empty():
		return result
	var order_set := OrderSet.new(data["player"], data["turn"])
	for o: Dictionary in data["orders"]:
		order_set.add(o)
	result.order_set = order_set
	return result


static func write(path: String, order_set: OrderSet, game_version: String) -> Error:
	return SaveStore.write_text(path, encode(order_set, game_version))


static func read(path: String) -> LoadResult:
	if not FileAccess.file_exists(path):
		var missing := LoadResult.new()
		missing.errors.append("%s: no such file" % path)
		return missing
	var result := decode(FileAccess.get_file_as_string(path))
	var prefixed := PackedStringArray()
	for e in result.errors:
		prefixed.append("%s: %s" % [path, e])
	result.errors = prefixed
	return result
