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
## The original's personalities, whose built-in races (one per level, content `races`) every
## personality plays: a built-in one its own, one of the player's those it names.
const RACES := UniverseGenerator.AI_PERSONALITIES
## The races a personality plays when its brain has none of its own (the baseline brain).
const DEFAULT_RACES := "robotoids"
## Files the original writes for each computer player after it plays (log, history), each
## drawing a cipher salt (S01 "Draws outside the rules").
const FILES_WRITTEN := 2
const FILE_SALT_RANGE := 2000


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


## The personality player `p` plays with: the copy the game keeps, else the content definition
## of its key; {} when there is neither.
static func personality_for(p: Player, content: ContentRegistry) -> Dictionary:
	if not p.is_human() and not p.ai_personality.is_empty():
		return p.ai_personality
	var id := personality_id(personality_of(p))
	if not content.ids(PERSONALITY).has(id):
		return {}
	return content.get_def(PERSONALITY, id)


## The races a new personality for `brain` plays: the brain's own, else DEFAULT_RACES.
static func default_races(brain: String) -> String:
	return brain if RACES.has(brain) else DEFAULT_RACES


## The built-in race personality `p` plays at difficulty `level` (S07 step 0, S22): a new copy,
## without a name and with logo 0; a default race when the content has none.
static func race_for(p: Dictionary, level: int, content: ContentRegistry) -> Race:
	var key := str(p.get("races_of", default_races(str(p.get("brain", "")))))
	var id := personality_id(key)
	var races: Array = []
	if content.ids(PERSONALITY).has(id):
		races = content.get_def(PERSONALITY, id).get("races", [])
	if races.is_empty():
		return Race.new()
	var race := RacePresets.from_def(races[clampi(level, 0, races.size() - 1)])
	race.name = ""
	race.plural_name = ""
	race.logo = 0
	return race


## Gives every computer player of a new game a copy of its personality's definition (S22), so
## the game keeps playing the same wherever it is loaded.
static func adopt_personalities(state: GameState, content: ContentRegistry) -> void:
	for p in state.players:
		if p.is_human() or not p.ai_personality.is_empty():
			continue
		var id := personality_id(p.ai)
		if not content.ids(PERSONALITY).has(id):
			continue
		var def := content.get_def(PERSONALITY, id)
		p.ai_personality = {
			"name": content.display_name(id),
			"brain": def["brain"],
			"params": def.get("params", {}).duplicate(true),
			"levels": def.get("levels", []).duplicate(true),
		}


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
	var shared := {}
	for p in state.players:
		if not plays(p) or has_orders.has(p.index):
			continue
		var personality := personality_for(p, content)
		if personality.is_empty():
			errors.append("player %d: no AI personality %s" % [p.index, personality_of(p)])
			continue
		var brain := AiBrains.create(personality["brain"])
		if brain == null:
			errors.append("player %d: no AI brain %s" % [p.index, personality["brain"]])
			continue
		var ctx := AiContext.new(
			PlayerView.new(state, content, p.index), content, rng, personality, p.ai_level
		)
		ctx.shared = shared
		brain.play(ctx)
		out.append(ctx.orders)
		# the original then writes the player's log and history files, one salt draw each (S01)
		for f in FILES_WRITTEN:
			rng.random(FILE_SALT_RANGE)
	return out
