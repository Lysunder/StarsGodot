class_name Score
extends RefCounted
## Scores, ranks, elimination and victory (spec S20), each turn right after the year advances
## (`UpdateScoresAndVictory@10b0:3b78`).

const CLASS_UNARMED := 0
const CLASS_ESCORT := 1
const CLASS_CAPITAL := 2
## A ship rating from this is a capital ship.
const CAPITAL_RATING := 2000
## One population point per this many hundreds of colonists on a planet, at most POP_POINTS_MAX.
const POP_PER_POINT := 1000
const POP_POINTS_MAX := 6
const RESOURCES_PER_POINT := 30
const STARBASE_POINTS := 3
const CAPACITOR_START := 1000
const CAPACITOR_MAX := 255
const PERCENT := 100
const PRODUCTION_UNIT := 1000
## The victory conditions that can be switched on, in the order of the record's flags.
const CONDITIONS: Array[String] = [
	"owns_planets",
	"tech_level",
	"score",
	"exceeds_second",
	"production",
	"capital_ships",
	"highest_score",
]
const SCORE_GOTO := {"score": true}


## Formula `score.ship_rating` (`Design_Evaluate@1030:079e`): a design's fighting value.
static func ship_rating(design: Design, content: ContentRegistry) -> int:
	var beams := 0
	var torpedoes := 0
	var bombs := 0
	var boost := CAPACITOR_START
	for slot in design.parts:
		if slot.count <= 0 or slot.part.is_empty():
			continue
		var part := content.part(slot.part)
		var stats: Dictionary = part.get("stats", {})
		var tags: Array = part.get("tags", [])
		var n := slot.count
		match part.get("category", ""):
			"beam":
				var b := (int(stats.get("range", 0)) + 3) * int(stats.get("power", 0)) * n / 4
				beams += b / 3 if tags.has("sapper") else b
			"torpedo":
				torpedoes += (int(stats.get("range", 0)) - 2) * int(stats.get("power", 0)) * n / 2
			"bomb":
				var kill := int(stats.get("kill_rate", 0)) + int(stats.get("installations", 0))
				bombs += kill * n * 2
			_:
				if tags.has("capacitor"):
					for i in n:
						boost = (int(stats.get("beam_damage_pct", 0)) + PERCENT) * boost / PERCENT
	if boost != CAPACITOR_START:
		beams = mini(boost / 10, CAPACITOR_MAX) * beams / PERCENT
	var move := BattleSetup.design_movement(design, content)
	return beams + (move - 4) * beams / 10 + torpedoes + bombs


## Formula `score.player` (`ComputePlayerScore@1030:3832`): player `p`'s score record, without
## rank and conditions.
static func record(state: GameState, content: ContentRegistry, p: int) -> Dictionary:
	var player := state.player(p)
	var planets := 0
	var starbases := 0
	var resources := 0
	var score := 0
	for pl in state.planets:
		if pl.owner != p:
			continue
		planets += 1
		score += mini((pl.population + POP_PER_POINT - 1) / POP_PER_POINT, POP_POINTS_MAX)
		if pl.starbase != null:
			var design := player.starbase_design(pl.starbase.design)
			if design != null and int(content.hull(design.hull).get("dock", 0)) != 0:
				starbases += 1
		resources += PlanetEconomy.resources(pl, player.race, content)
	score += resources / RESOURCES_PER_POINT + STARBASE_POINTS * starbases
	var tech := 0
	if not player.eliminated:
		for level in player.tech_levels:
			tech += level
			score += _tech_points(level)
	var rating: Callable = content.ruleset.formula(StandardRuleset.SHIP_RATING)
	var class_of := {}
	for design in player.ship_designs:
		var r: int = rating.call(design, content)
		class_of[design.slot] = (
			CLASS_UNARMED if r <= 0 else (CLASS_ESCORT if r < CAPITAL_RATING else CLASS_CAPITAL)
		)
	var ships: Array[int] = [0, 0, 0]
	for fleet in state.fleets:
		if fleet.owner != p:
			continue
		for stack in fleet.stacks:
			if stack.count > 0 and class_of.has(stack.design):
				ships[class_of[stack.design]] += stack.count
	score += mini(ships[CLASS_UNARMED], planets) / 2 + 2 * mini(ships[CLASS_ESCORT], planets)
	if ships[CLASS_CAPITAL] > 0:
		score += planets * ships[CLASS_CAPITAL] * 8 / (planets + ships[CLASS_CAPITAL])
	return {
		"score": score,
		"resources": resources,
		"planets": planets,
		"starbases": starbases,
		"unarmed": packed(ships[CLASS_UNARMED]),
		"escorts": packed(ships[CLASS_ESCORT]),
		"capitals": packed(ships[CLASS_CAPITAL]),
		"tech": tech,
		"rank": 0,
		"met": [],
		"winner": false,
	}


## Tech points for one field's level: steeper from levels 4, 7 and 10.
static func _tech_points(level: int) -> int:
	if level <= 3:
		return level
	if level < 7:
		return 2 * level - 3
	if level < 10:
		return 3 * (level - 3)
	return 4 * level - 18


## A count as the record keeps it: 13 bits, the low bits dropped two at a time above 8,191
## (`PackLongToWord`, as for battle shield damage, S16).
static func packed(n: int) -> int:
	return BattleEngine.unpack(BattleEngine.pack(n))


## S20 "The turn's update": every player's record, eliminations, ranks and the victory
## conditions, with the messages.
static func update(state: GameState, content: ContentRegistry) -> void:
	var settings: Dictionary = state.settings.victory
	var count := state.players.size()
	var met: Array[int] = []
	met.resize(count)
	var formula: Callable = content.ruleset.formula(StandardRuleset.PLAYER_SCORE)
	for p in count:
		var player := state.player(p)
		var r: Dictionary = formula.call(state, content, p)
		player.score = r
		var nothing_left: bool = (
			r.planets == 0 and r.unarmed == 0 and r.escorts == 0 and r.capitals == 0
		)
		if nothing_left and not player.eliminated:
			player.eliminated = true
			for other in count:
				if other != p:
					_first(state, content, other, "message.game.player_eliminated", [p])
		var planets_needed := _mul_div(state.planets.size(), _value(settings, "owns_planets"), 100)
		var fields := 0
		for level in player.tech_levels:
			if level >= _value(settings, "tech_level"):
				fields += 1
		var checks := {
			"owns_planets": r.planets >= planets_needed,
			"capital_ships": r.capitals >= _value(settings, "capital_ships"),
			"score": r.score >= _value(settings, "score"),
			"tech_level": fields >= int(settings.get("tech_fields", 0)),
			"production": r.resources / PRODUCTION_UNIT >= _value(settings, "production"),
		}
		for id: String in checks:
			if checks[id]:
				met[p] += _meet(settings, r, id)
	if count == 1:
		state.player(0).score.rank = 1
		_sort_met(state)
		return
	var leader := -1
	var leaders := 0
	var second := 0
	for p in count:
		var rank := 1
		for other in state.players:
			if other.score.score > state.player(p).score.score:
				rank += 1
		state.player(p).rank = rank
		state.player(p).score.rank = rank
		if rank == 1:
			leader = p
			leaders += 1
		elif rank == 2:
			second = state.player(p).score.score
	var top: Dictionary = state.player(leader).score
	if leaders > 1:
		second = top.score
	if state.turn >= _value(settings, "highest_score") and leaders == 1:
		met[leader] += _meet(settings, top, "highest_score")
	var alive := 0
	for player in state.players:
		if not player.eliminated:
			alive += 1
	if alive >= 2:
		if (_value(settings, "exceeds_second") + PERCENT) * second / PERCENT <= top.score:
			met[leader] += _meet(settings, top, "exceeds_second")
		_declare_winners(state, content, settings, met)
	else:
		for p in count:
			if p == leader:
				if not state.player(p).eliminated:
					_first(state, content, p, "message.game.last_standing", [])
			else:
				_first(state, content, p, "message.game.dead", [])
	_sort_met(state)


static func _declare_winners(
	state: GameState, content: ContentRegistry, settings: Dictionary, met: Array[int]
) -> void:
	var needed := mini(int(settings.get("criteria", 0)), _switched_on(settings))
	if state.turn < int(settings.get("min_years", 0)) or needed <= 0:
		return
	var winners: Array[int] = []
	for p in state.players.size():
		if met[p] >= needed:
			winners.append(p)
			state.player(p).score.winner = true
	if winners.is_empty():
		return
	for p in state.players.size():
		if state.player(p).eliminated:
			_first(state, content, p, "message.game.dead", [])
		elif not winners.has(p):
			_first(state, content, p, "message.game.won_by_other", [winners.duplicate()])
		elif winners.size() == 1:
			_first(state, content, p, "message.game.won", [])
		else:
			var others := winners.duplicate()
			others.erase(p)
			_first(state, content, p, "message.game.won_shared", [others])


## Notes condition `id` as met in record `r`; 1 when it is switched on (it counts), else 0.
static func _meet(settings: Dictionary, r: Dictionary, id: String) -> int:
	(r.met as Array).append(id)
	return 1 if (settings.get(id, {}) as Dictionary).get("on", false) else 0


## The record's conditions in flag order.
static func _sort_met(state: GameState) -> void:
	for player in state.players:
		var ordered := []
		for id in CONDITIONS:
			if (player.score.met as Array).has(id):
				ordered.append(id)
		player.score.met = ordered


static func _value(settings: Dictionary, id: String) -> int:
	return int((settings.get(id, {}) as Dictionary).get("value", 0))


static func _switched_on(settings: Dictionary) -> int:
	var n := 0
	for id in CONDITIONS:
		if (settings.get(id, {}) as Dictionary).get("on", false):
			n += 1
	return n


## Windows `MulDiv`: a × b / c rounded to nearest, halves away from zero (a, b ≥ 0, c > 0).
static func _mul_div(a: int, b: int, c: int) -> int:
	return (2 * a * b + c) / (2 * c)


## Sends a message put at the start of the player's list (`AddMessageFirst`).
static func _first(
	state: GameState, content: ContentRegistry, player: int, type: String, params: Array
) -> void:
	TurnMessages.add(state, content, player, type, SCORE_GOTO, params, true)
