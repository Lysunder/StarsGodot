class_name PlanetHistory
extends RefCounted
## What each player remembers of the planets (spec S15 "Planet history"; the original's history
## file, `DecodePlanetBlock@1068:1f0c` merging the turn file into it, `WritePlanetDataBlock`): after
## each turn's scanning, every planet the player owns or saw this turn updates the player's record
## of it in `Player.knowledge["planets"]`, keyed by planet id:
##
## - always: `turn` (the year index it was last seen), `owner`, `homeworld`, `starbase_design`
##   (-1 none or hidden), and `detail`, the best detail it was ever seen at (1 or SCANNED);
## - when scanned this turn: `environment`, `environment_original`, `concentration`,
##   `concentration_fraction`, and, when owned, `population_estimate` and `defense_estimate`.
##
## Surface minerals are not kept: they are known only in the turn they are seen (the turn's view).

const KEY := "planets"
## The best detail a record keeps: scanned (S15 detail levels).
const SCANNED := 3
## Scanned, but the starbase stayed hidden (S15).
const STARBASE_HIDDEN := 2
const OWN := 7


## Every player's record, after the turn's scanning (state.views filled).
static func note_all(state: GameState) -> void:
	for p in state.players.size():
		note(state, p)


static func note(state: GameState, p: int) -> void:
	var seen: Dictionary = {}
	if p < state.views.size() and state.views[p] is Dictionary:
		seen = state.views[p].get("planets", {})
	var me := state.player(p)
	if not me.knowledge.has(KEY):
		me.knowledge[KEY] = {}
	var known: Dictionary = me.knowledge[KEY]
	for planet in state.planets:
		var level := OWN if planet.owner == p else int(seen.get(str(planet.id), 0))
		if level > 0:
			known[str(planet.id)] = _merged(
				known.get(str(planet.id), {}), planet, level, state.turn
			)


## A record updated by a sighting at `level`.
static func _merged(old: Dictionary, planet: Planet, level: int, turn: int) -> Dictionary:
	var entry := old.duplicate(true)
	entry["turn"] = turn
	entry["owner"] = planet.owner
	entry["homeworld"] = planet.homeworld
	var shown := planet.starbase != null and level != STARBASE_HIDDEN
	entry["starbase_design"] = planet.starbase.design if shown else -1
	var detail := SCANNED if level >= STARBASE_HIDDEN else level
	entry["detail"] = maxi(int(old.get("detail", 0)), detail)
	if level < STARBASE_HIDDEN:
		return entry
	entry["environment"] = planet.environment.duplicate()
	entry["environment_original"] = planet.environment_original.duplicate()
	entry["concentration"] = planet.concentration.duplicate()
	entry["concentration_fraction"] = planet.concentration_fraction.duplicate()
	# an unowned planet's sighting carries no estimates: the old ones stay
	if planet.owner >= 0:
		entry["population_estimate"] = planet.population_estimate
		entry["defense_estimate"] = planet.defense_estimate
	elif not entry.has("population_estimate"):
		entry["population_estimate"] = 0
		entry["defense_estimate"] = 0
	return entry
