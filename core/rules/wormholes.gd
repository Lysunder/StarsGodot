class_name Wormholes
extends RefCounted
## Wormhole placement and the yearly shift (specs S07 step 12.3, S12 "Wormholes shift").

const TRIES := 100
const IMPOSSIBLE := 15
const EDGE := 10
const DRIFT := 12
const AGE_PER_PERCENT := 5
const STABILITY_OFFSET := 2
const MAX_JUMP_PCT := 6


## Lower is better: 0 is a clean spot, 15 an impossible one (S07 step 12.3).
static func score(state: GameState, w: Wormhole, width: int) -> int:
	var limit := width + 1000
	if w.x < 1000 or w.y < 1000 or w.x > limit or w.y > limit:
		return IMPOSSIBLE
	for other in state.space_objects():
		if other != w and other.get("x") == w.x and other.get("y") == w.y:
			return IMPOSSIBLE
	for pl in state.planets:
		if pl.x == w.x and pl.y == w.y:
			return IMPOSSIBLE
	for f in state.fleets:
		if f.x == w.x and f.y == w.y:
			return IMPOSSIBLE
	var s := 0
	if w.x < 1000 + EDGE or w.y < 1000 + EDGE or w.x > limit - EDGE or w.y > limit - EDGE:
		s |= 4
	for other in state.wormholes:
		if other == w:
			continue
		var d2 := (w.x - other.x) * (w.x - other.x) + (w.y - other.y) * (w.y - other.y)
		if other.number == w.other_end:
			s |= _closeness(d2, [25, 100, 900, 4900])
		else:
			s |= _closeness(d2, [16, 64, 225, 900])
	for pl in state.planets:
		var d2 := (w.x - pl.x) * (w.x - pl.x) + (w.y - pl.y) * (w.y - pl.y)
		s |= _closeness(d2, [25, 100, 400, 784])
	return s


## Percent chance that a wormhole jumps this year: age div 5 + stability - 2, within 0..6.
static func jump_chance(w: Wormhole) -> int:
	return clampi(w.age / AGE_PER_PERCENT + w.stability - STABILITY_OFFSET, 0, MAX_JUMP_PCT)


## Every wormhole, in number order, drifts or jumps (S12 "Wormholes shift").
static func shift_all(state: GameState, rng: StarsRandom) -> void:
	var width := state.settings.universe_width
	for w in state.wormholes:
		var jump := rng.random(100) < jump_chance(w)
		if jump:
			# The original also clears the players-who-have-been-through mask, which is not in our
			# model yet (S15).
			w.age = 0
		else:
			w.age += 1
		var old := [w.x, w.y]
		var best_score := IMPOSSIBLE + 1
		var best := old
		var last := -1
		for t in TRIES:
			if jump:
				w.x = rng.random(width) + 1000
				w.y = rng.random(width) + 1000
			else:
				w.x = rng.random(2 * DRIFT + 1) + old[0] - DRIFT
				w.y = rng.random(2 * DRIFT + 1) + old[1] - DRIFT
			if w.x == old[0] and w.y == old[1]:
				continue
			last = score(state, w, width)
			if last == 0:
				break
			if last < best_score:
				best_score = last
				best = [w.x, w.y]
		if last != 0:
			w.x = best[0]
			w.y = best[1]


static func _closeness(d2: int, limits: Array) -> int:
	if d2 < limits[0]:
		return 8
	if d2 < limits[1]:
		return 4
	if d2 < limits[2]:
		return 2
	return 1 if d2 < limits[3] else 0
