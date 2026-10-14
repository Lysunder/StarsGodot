class_name RaceEditing
extends RefCounted
## The race wizard's habitability edits and its "1 in N planets" figure (M11 step 9; S06 "The race
## wizard"; the original's `Environment_OnMouse@10d8:1806`, `Environment_Paint`). Values are the
## 0..100 scale every rule uses; the center is always low + (high - low) div 2.

## The narrowest range the wizard allows.
const MIN_WIDTH := 20
## The range an axis gets back when it stops being immune.
const RESET := [20, 50, 80]
const SCALE := 100
## The odds figure's base: 1 in (BASE / chance) planets.
const ODDS_BASE := 1000000


## Moves the range by `shift` and widens each end by `widen` (negative narrows), then keeps it
## inside 0..100 (pushed back in at either end, its width kept up to the full scale) and at least
## MIN_WIDTH wide (grown evenly). No effect on an immune axis.
static func adjust(race: Race, axis: int, shift: int, widen: int) -> void:
	if race.is_immune(axis):
		return
	var low := race.hab_low[axis] - widen + shift
	var high := race.hab_high[axis] + widen + shift
	if high > SCALE:
		low += SCALE - high
		high = SCALE
	if low < 0:
		high = mini(high - low, SCALE)
		low = 0
	if high - low < MIN_WIDTH:
		var grow := (MIN_WIDTH - (high - low)) >> 1
		high += grow
		low -= grow
	_set_range(race, axis, low, high)


## Dragging the range: its middle goes to `at` (0..100), its half width kept, the range kept inside
## 0..100.
static func drag(race: Race, axis: int, at: int) -> void:
	if race.is_immune(axis):
		return
	var half := (race.hab_high[axis] - race.hab_low[axis]) / 2
	var middle := clampi(at, half, SCALE - half)
	_set_range(race, axis, middle - half, middle + half)


static func set_immune(race: Race, axis: int, immune: bool) -> void:
	if immune:
		race.hab_low[axis] = -1
		race.hab_center[axis] = -1
		race.hab_high[axis] = -1
	elif race.is_immune(axis):
		_set_range(race, axis, RESET[0], RESET[2])


static func _set_range(race: Race, axis: int, low: int, high: int) -> void:
	race.hab_low[axis] = low
	race.hab_high[axis] = high
	race.hab_center[axis] = low + (high - low) / 2


## About 1 in how many planets the race can live on: 0 when all of them, 1 when virtually all.
## Per axis a chance out of 100 (immune or the full range: 100; radiation: its width; gravity
## and temperature: each value of the range weighted 10, less near the ends, the sum div 9), all
## multiplied; then 1,000,000 div that, rounded.
static func habitable_odds(race: Race) -> int:
	var chance := 1
	for axis in 3:
		var low := race.hab_low[axis]
		var high := race.hab_high[axis]
		if race.is_immune(axis) or high - low == SCALE:
			chance *= SCALE
		elif axis == EnvironmentUnits.RADIATION:
			chance *= high - low
		else:
			var weight := 0
			for v in range(low, high + 1):
				if v < 10:
					weight += v
				elif v > 89:
					weight += SCALE - v
				else:
					weight += 10
			chance = chance * weight / 9
	if chance <= 0:
		chance = 1
	if chance == ODDS_BASE:
		return 0
	return (ODDS_BASE + chance / 2) / chance
