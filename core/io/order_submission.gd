class_name OrderSubmission
extends RefCounted
## A player's orders sent to a play-by-email host (spec S27 "Play by email"): the orders for one
## year of one game, with an integrity checksum like the turn file's (TurnFile.checksum), so a file
## damaged on its way, or meant for another game, player or year, is refused.
##
## Format: {format, format_version, game_version, game_id, player, turn, orders, checksum}.

const FORMAT := "starsgodot-submission"
const FORMAT_VERSION := 1
const EXTENSION := "orders"
const _KEYS := [
	"format", "format_version", "game_version", "game_id", "player", "turn", "orders", "checksum"
]


class LoadResult:
	extends RefCounted
	var order_set: OrderSet = null
	var game_id: String = ""
	var errors: PackedStringArray = []

	func ok() -> bool:
		return errors.is_empty() and order_set != null


static func encode(order_set: OrderSet, game_id: String, game_version: String) -> String:
	var data := {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"game_version": game_version,
		"game_id": game_id,
		"player": order_set.player,
		"turn": order_set.turn,
		"orders": order_set.orders.duplicate(true),
	}
	data["checksum"] = TurnFile.checksum(data)
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
	if not result.errors.is_empty():
		return result
	if str(data["checksum"]) != TurnFile.checksum(data):
		result.errors.append("the file is damaged (its checksum does not match)")
		return result
	if not data["format_version"] is int or data["format_version"] > FORMAT_VERSION:
		result.errors.append("/format_version: not one this game reads")
	for key: String in ["player", "turn"]:
		if not data[key] is int or data[key] < 0:
			result.errors.append("/%s: must be a non-negative integer" % key)
	if not data["orders"] is Array:
		result.errors.append("/orders: must be a list")
	else:
		for o: Variant in data["orders"]:
			if not o is Dictionary or not o.get("type") is String:
				result.errors.append('/orders: each must be an object with a "type"')
				break
	if not result.errors.is_empty():
		return result
	result.game_id = str(data["game_id"])
	var order_set := OrderSet.new(data["player"], data["turn"])
	for o: Dictionary in data["orders"]:
		order_set.add(o)
	result.order_set = order_set
	return result


static func write(
	path: String, order_set: OrderSet, game_id: String, game_version: String
) -> Error:
	return SaveStore.write_text(path, encode(order_set, game_id, game_version))


static func read(path: String) -> LoadResult:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var r := LoadResult.new()
		r.errors.append("cannot read %s" % path)
		return r
	return decode(text)
