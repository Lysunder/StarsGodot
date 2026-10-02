class_name Habitability
extends RefCounted
## How habitable a planet environment is for a race (spec S06, "Planet value for a race"; used by
## S08 and by the advantage points).
##
## The value is in percent: positive values are habitable (100 is ideal), zero or negative values
## are not (the more negative, the further outside the race's ranges).

const AXES := 3
## Most a single axis can count against a planet outside the race's range.
const MAX_BAD_PER_AXIS := 15


## Planet value of an environment (gravity, temperature, radiation) for a race.
static func value(env: Array[int], race: Race) -> int:
	var good := 0
	var bad := 0
	var ideal := 10000
	for axis in AXES:
		if race.is_immune(axis):
			good += 10000
			continue
		var v := env[axis]
		var low := race.hab_low[axis]
		var high := race.hab_high[axis]
		var center := race.hab_center[axis]
		if v < low or v > high:
			bad += mini(low - v if v < low else v - high, MAX_BAD_PER_AXIS)
			continue
		var half_width := center - low if v < center else high - center
		var dist := absi(v - center)
		if half_width == 0:  # zero-width range: only the center itself is inside
			good += 10000
			continue
		var closeness := 100 - dist * 100 / half_width
		good += closeness * closeness
		var excess := 2 * dist - half_width
		if excess > 0:
			ideal = ideal * (2 * half_width - excess) / (2 * half_width)
	if bad != 0:
		return -bad
	# The original works in floating point here; +0.9 never lands near an integer boundary (S06).
	var root := int(sqrt(good * (1.0 / 3.0)) + 0.9)
	return root * ideal / 10000
