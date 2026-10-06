class_name ProductionEstimate
extends RefCounted
## When a planet's queue items will be built (M11, the Production tile's colours and Completion
## line): the planet's production (S09) is run year by year on a copy, with this year's
## resources and mining but no population growth, and each queue item is followed until it is
## done. It is an estimate for the player's eyes only and never changes the game.

enum When { THIS_YEAR_ALL, THIS_YEAR_SOME, LATER, NEVER, SKIPPED }

## No estimate past this many years ("never").
const HORIZON := 100


## {items: [When per queue item], years: years until every item but the auto items is built, 0
## when there is none, or -1 for never}. An auto item that builds nothing this year is SKIPPED.
static func estimate(state: GameState, content: ContentRegistry, planet_id: int) -> Dictionary:
	var copy := state.copy() as GameState
	var planet := copy.planet(planet_id)
	var out := {"items": [], "years": -1}
	if planet == null or planet.owner < 0:
		return out
	var race := copy.player(planet.owner).race
	var rng := StarsRandom.new(1)
	var production := Production.new(copy, content, rng)
	var tracked: Array[QueueItem] = planet.queue.duplicate()
	var start: Array[int] = []
	var when: Array[When] = []
	for q in tracked:
		start.append(q.count)
		when.append(When.NEVER)
	var research: Array[int] = []
	research.resize(copy.players.size())
	research.fill(0)
	var auto: Array[bool] = []
	for q in tracked:
		auto.append(
			(
				not q.is_design()
				and bool(content.get_def("production_item", q.item).get("auto", false))
			)
		)
	if not auto.has(false):
		out["years"] = 0
	for year in range(1, HORIZON + 1):
		var before: Array[int] = []
		for q in tracked:
			before.append(q.count)
		production.run_planet(planet, research)
		for i in tracked.size():
			if when[i] != When.NEVER:
				continue
			var q := tracked[i]
			var gone := not planet.queue.has(q)
			if year == 1:
				if gone:
					when[i] = When.THIS_YEAR_ALL
				elif q.count < before[i]:
					when[i] = When.THIS_YEAR_SOME
			elif gone:
				when[i] = When.LATER
		var left := false
		for i in tracked.size():
			if not auto[i] and planet.queue.has(tracked[i]):
				left = true
		if not left:
			if out["years"] < 0:
				out["years"] = year
			break
		PlanetEconomy.mine(planet, race, content, rng)
	for i in when.size():
		if auto[i] and when[i] != When.THIS_YEAR_ALL and when[i] != When.THIS_YEAR_SOME:
			when[i] = When.SKIPPED
		elif when[i] == When.NEVER and start[i] > tracked[i].count:
			when[i] = When.LATER
	out["items"] = when
	return out
