class_name RngStreams
extends RefCounted
## The named random streams of one game (spec S01, "Our design: streams").
##
## - "classic": the original's sequence. Every draw listed in a rule spec uses it.
## - "fixes": extra draws needed by bug fixes, so the classic sequence stays aligned.
## - "mod.<mod_id>" or "mod.<mod_id>.<name>": one or more streams per mod.
##
## Streams other than classic are derived from the game seed and their name when first used, so
## adding a mod or a fix never shifts another stream. Each stream's state is saved with the game.

const CLASSIC := "classic"
const FIXES := "fixes"

const _NAME_PATTERN := "^(classic|fixes|mod\\.[a-z0-9_]+(\\.[a-z0-9_]+)?)$"

var game_seed: int
var _streams: Dictionary = {}


## With classic_from_game_seed, the classic stream starts from the original's game-seed method
## (definition files and fixtures that give a seed); otherwise it is derived like the others.
func _init(p_game_seed: int = 0, classic_from_game_seed: bool = false) -> void:
	game_seed = p_game_seed
	var classic: StarsRandom
	if classic_from_game_seed:
		classic = StarsRandom.from_game_seed(game_seed)
	else:
		classic = StarsRandom.from_stream_name(game_seed, CLASSIC)
	_add(CLASSIC, classic)


static func is_valid_name(stream_name: String) -> bool:
	var re := RegEx.create_from_string(_NAME_PATTERN)
	return re.search(stream_name) != null


## The stream with that name, created from the game seed on first use.
func get_stream(stream_name: String) -> StarsRandom:
	if not _streams.has(stream_name):
		assert(is_valid_name(stream_name), "RngStreams: bad stream name '%s'" % stream_name)
		_add(stream_name, StarsRandom.from_stream_name(game_seed, stream_name))
	return _streams[stream_name]


func has_stream(stream_name: String) -> bool:
	return _streams.has(stream_name)


## Names of the streams created so far, sorted.
func names() -> PackedStringArray:
	var out := PackedStringArray(_streams.keys())
	out.sort()
	return out


func duplicate_streams() -> RngStreams:
	var copy := RngStreams.new(game_seed)
	copy._streams.clear()
	for stream_name in names():
		copy._streams[stream_name] = (_streams[stream_name] as StarsRandom).duplicate_stream()
	return copy


## {"game_seed": int, "streams": {name: {"s1", "s2"}}}, with streams in name order.
func to_dict() -> Dictionary:
	var streams := {}
	for stream_name in names():
		streams[stream_name] = (_streams[stream_name] as StarsRandom).to_dict()
	return {"game_seed": game_seed, "streams": streams}


## Rebuilds the streams from to_dict() output (numbers may come back from JSON as floats).
## Returns null when the data is malformed.
static func from_dict(data: Dictionary) -> RngStreams:
	if not _is_whole(data.get("game_seed")) or not data.get("streams") is Dictionary:
		return null
	var streams: Dictionary = data["streams"]
	if not streams.has(CLASSIC):
		return null
	var out := RngStreams.new(int(data["game_seed"]))
	out._streams.clear()
	for stream_name: Variant in streams:
		var state: Variant = streams[stream_name]
		if not stream_name is String or not is_valid_name(stream_name) or not state is Dictionary:
			return null
		var s1: Variant = state.get("s1")
		var s2: Variant = state.get("s2")
		if not _is_whole(s1) or not _is_whole(s2):
			return null
		if not StarsRandom.is_valid_state(int(s1), int(s2)):
			return null
		out._add(stream_name, StarsRandom.new(int(s1), int(s2)))
	return out


static func _is_whole(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floorf(value)


func _add(stream_name: String, stream: StarsRandom) -> void:
	if stream_name == CLASSIC:
		stream.max_range = StarsRandom.CLASSIC_MAX_RANGE
	_streams[stream_name] = stream
