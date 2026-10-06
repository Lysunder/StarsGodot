class_name TurnMessages
extends RefCounted
## The players' turn messages (spec S21): `state.messages` holds one list per player, each message
## {type, goto, params}: a `message` content id, what its Goto shows (S21 "Goto codes") and its
## parameters, in the order the rules send them. A turn's generation starts with empty lists.
## Computer players get only the message types marked `ai` (the original drops the rest).


## Empties every player's list (the start of a turn's generation, S21).
static func clear(state: GameState) -> void:
	var lists := []
	for p in state.players.size():
		lists.append([])
	state.messages = lists


## Sends message `type` to `player`.
static func add(
	state: GameState,
	content: ContentRegistry,
	player: int,
	type: String,
	goto: Dictionary,
	params: Array
) -> void:
	if player < 0 or player >= state.players.size():
		return
	var for_ai: bool = content.has_def(type) and content.get_def("message", type).get("ai", false)
	if not state.players[player].is_human() and not for_ai:
		return
	while state.messages.size() < state.players.size():
		state.messages.append([])
	(state.messages[player] as Array).append(
		{"type": type, "goto": goto, "params": params.duplicate()}
	)
