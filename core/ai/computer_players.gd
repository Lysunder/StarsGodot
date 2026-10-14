class_name ComputerPlayers
extends RefCounted
## The AI step (spec S22 "The AI step"): before a turn is generated, every computer player still
## in the game that has no orders of its own makes them, in player order, drawing from the classic
## stream; so does every inactive human player, with the INACTIVE personality (housekeeping only).
## Each sees only its own view of the game, and its orders are checked and applied with everyone's
## when the turn is generated.

const PERSONALITY := "ai_personality"
## The personality that plays for a human player who is inactive (not offered for new players).
const INACTIVE := "inactive"
## The difficulty levels, easiest first (Player.ai_level).
const LEVELS := ["easy", "standard", "harder", "expert"]


## The content id of personality `ai` (Player.ai).
static func personality_id(ai: String) -> String:
	return "%s.%s" % [PERSONALITY, ai]


## Whether player `p` makes its orders in the AI step: a computer player, or an inactive human
## player, still in the game.
static func plays(p: Player) -> bool:
	return not p.eliminated and (not p.is_human() or not p.active)


## The personality key player `p` plays with (Player.ai, or INACTIVE for an inactive human).
static func personality_of(p: Player) -> String:
	return p.ai if not p.is_human() else INACTIVE


## `given` followed by the orders of each computer player that has none in it. A player whose
## personality or brain is unknown gives no orders, and `errors` gets a line for it.
static func add_orders(
	state: GameState,
	content: ContentRegistry,
	given: Array[OrderSet],
	errors: PackedStringArray = PackedStringArray()
) -> Array[OrderSet]:
	var out: Array[OrderSet] = given.duplicate()
	var has_orders := {}
	for s in given:
		has_orders[s.player] = true
	var rng := state.rng.get_stream(RngStreams.CLASSIC)
	for p in state.players:
		if not plays(p) or has_orders.has(p.index):
			continue
		var id := personality_id(personality_of(p))
		if not content.ids(PERSONALITY).has(id):
			errors.append("player %d: no AI personality %s" % [p.index, personality_of(p)])
			continue
		var personality := content.get_def(PERSONALITY, id)
		var brain := AiBrains.create(personality["brain"])
		if brain == null:
			errors.append("player %d: no AI brain %s" % [p.index, personality["brain"]])
			continue
		var ctx := AiContext.new(
			PlayerView.new(state, content, p.index), content, rng, personality, p.ai_level
		)
		brain.play(ctx)
		out.append(ctx.orders)
	return out
