class_name EnvironmentUnits
extends RefCounted
## How the game shows environment values (spec S06 "Display units"): gravity in g, temperature in
## degrees C, radiation in mR, from the 0..100 scale every rule uses.

const GRAVITY := 0
const TEMPERATURE := 1
const RADIATION := 2
const MID := 50


## "0.59g", "84°C", "10mR".
static func format(axis: int, value: int) -> String:
	match axis:
		GRAVITY:
			var g := gravity_hundredths(value)
			return "%d.%02dg" % [g / 100, g % 100]
		TEMPERATURE:
			return "%d°C" % ((value - MID) * 4)
	return "%dmR" % value


## Gravity in hundredths of a g (FormatHabValue/HabValueToDisplay@1040:3ebe): from the distance d
## to the middle, (d + 25) × 4 below 26, else d × 24 − 400; below the middle it is 10000 over that.
static func gravity_hundredths(value: int) -> int:
	var d := absi(value - MID)
	var g := (d + 25) * 4 if d < 26 else d * 24 - 400
	if value < MID:
		g = 10000 / g
	return g
