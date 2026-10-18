class_name ScoreView
extends RefCounted
## The score report's data (M11 step 7; S20 "What a player sees"): the score table, the victory
## conditions and the history graph's lines, from the players' score records the viewer may see:
## its own, and everyone's in a game with public scores once the turn is above 19.

## The table's rows, top to bottom.
const TABLE_FIELDS := [
	"planets", "starbases", "unarmed", "escorts", "capitals", "tech", "resources", "score", "rank"
]
## The figures the history graph can show (the table's but rank).
const GRAPH_FIELDS := [
	"planets", "starbases", "unarmed", "escorts", "capitals", "tech", "resources", "score"
]
## The switchable victory conditions, in the New Game dialog's order (S20 "Victory settings").
const CONDITIONS := [
	"owns_planets",
	"tech_level",
	"score",
	"exceeds_second",
	"production",
	"capital_ships",
	"highest_score",
]
const PUBLIC_AFTER := 19
const START_YEAR := 2400


## Whether the viewer may see `p`'s score record of `turn`.
static func can_see(view: PlayerView, p: int, turn: int) -> bool:
	if p == view.player:
		return true
	return view.state.settings.public_scores and turn > PUBLIC_AFTER


## The table: {players: [{index, name, known, eliminated}], rows: [{field, values, best}]}. A value
## is -1 for a record the viewer can't see; `best` is the highest value shown (the lowest for rank),
## -1 with nothing shown.
static func table(view: PlayerView) -> Dictionary:
	var players: Array[Dictionary] = []
	for p in view.state.players.size():
		var player := view.state.player(p)
		(
			players
			. append(
				{
					"index": p,
					"name": player.race.display_plural(),
					"known": can_see(view, p, view.state.turn) and not player.score.is_empty(),
					"eliminated": player.eliminated,
				}
			)
		)
	var rows: Array[Dictionary] = []
	for field: String in TABLE_FIELDS:
		var values: Array[int] = []
		var best := -1
		for info in players:
			var v := -1
			if info["known"]:
				v = int(view.state.player(info["index"]).score.get(field, 0))
				if best < 0 or (v < best if field == "rank" else v > best):
					best = v
			values.append(v)
		rows.append({"field": field, "values": values, "best": best})
	return {"players": players, "rows": rows}


## The victory conditions: [{id, on, value, met: [true/false per player, null when unknown]}],
## then the settings every game has: `criteria` and `min_years` (with value only), and `tech_fields`
## folded into `tech_level` as `fields`.
static func conditions(view: PlayerView) -> Array[Dictionary]:
	var settings: Dictionary = view.state.settings.victory
	var out: Array[Dictionary] = []
	for id: String in CONDITIONS:
		var c: Dictionary = settings.get(id, {})
		var met: Array = []
		for p in view.state.players.size():
			var score: Dictionary = view.state.player(p).score
			if can_see(view, p, view.state.turn) and not score.is_empty():
				met.append((score.get("met", []) as Array).has(id))
			else:
				met.append(null)
		var row := {
			"id": id, "on": bool(c.get("on", false)), "value": int(c.get("value", 0)), "met": met
		}
		if id == "tech_level":
			row["fields"] = int(settings.get("tech_fields", 0))
		out.append(row)
	out.append({"id": "criteria", "value": int(settings.get("criteria", 0))})
	out.append({"id": "min_years", "value": int(settings.get("min_years", 0))})
	return out


## The players the viewer knows to have won (from their records).
static func winners(view: PlayerView) -> Array[int]:
	var out: Array[int] = []
	for p in view.state.players.size():
		var score: Dictionary = view.state.player(p).score
		if can_see(view, p, view.state.turn) and score.get("winner", false):
			out.append(p)
	return out


## The history graph's lines for `field`: [{player, points: [Vector2i(year, value)...]}], one per
## player with any record the viewer may see, in player order.
static func series(view: PlayerView, field: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in view.state.players.size():
		var points: Array[Vector2i] = []
		for entry: Dictionary in view.state.history:
			var records: Array = entry.get("records", [])
			var turn := int(entry["turn"])
			if p < records.size() and can_see(view, p, turn):
				points.append(Vector2i(START_YEAR + turn, int(records[p].get(field, 0))))
		if not points.is_empty():
			out.append({"player": p, "points": points})
	return out
