class_name RaceMath
extends RefCounted
## Race wizard math (spec S06): habitability points and advantage points.
##
## Trait costs come from content. Trait-specific rules are trait parameters, read through
## trait_param(): `race.ap_factory_growth_factor` (HE: 3), `race.ap_nas_penalty` (per primary
## trait), `race.ap_scanner_restriction` (NAS), `race.ap_cheap_energy_penalty` (AR),
## `race.hab_terraform_reach_1` / `_2` (TT: 8 and 17).

const START_POINTS := 1650
const GROWTH_START := {6: 5250, 7: 3900, 8: 2250, 9: 1875}
const RESEARCH_BONUS: Array[int] = [0, 150, 330, 540, 780, 1050, 1380]
const TERRAFORM_REACH: Array[int] = [0, 5, 15]
const PASS_WEIGHT: Array[int] = [7, 5, 6]
const SAMPLES := 11
const IMMUNE_SPAN := 11
const RESEARCH_EXPENSIVE := 0
const RESEARCH_CHEAP := 2
const ENERGY := 0


## Why a race is not a valid wizard race (S06 "Race files and presets"); empty when it is.
## Paths are relative to the race.
static func wizard_problems(race: Race, content: ContentRegistry) -> PackedStringArray:
	var out := StateValidator.validate_race(race, content)
	var fields: Array = ["growth_rate"]
	fields.append_array(Race.ECONOMY)
	for field: String in fields:
		var low := content.constant("constant.race.%s_min" % field)
		var high := content.constant("constant.race.%s_max" % field)
		var value: int = race.get(field)
		if value < low or value > high:
			out.append("/%s: must be %d .. %d" % [field, low, high])
	if race.name.strip_edges().is_empty() and not race.random:
		out.append("/name: must not be empty")
	if out.is_empty():
		var points := advantage_points(race, content)
		if points < 0:
			out.append("advantage points left: %d (must not be negative)" % points)
	return out


## Advantage points left (S06). Negative means the race is not valid.
static func advantage_points(race: Race, content: ContentRegistry) -> int:
	var g := clampi(race.growth_rate, 1, 20)
	var points := START_POINTS
	var f: int
	if g < 6:
		points += (6 - g) * 4200
		f = g
	elif g < 14:
		points = GROWTH_START.get(g, START_POINTS)
		f = 2 * g - 5
	else:
		f = 45 if g > 19 else 3 * (g - 6)
	points -= f * (hab_points(race, content) / 2000) / 24
	var immune := 0
	for axis in 3:
		if race.is_immune(axis):
			immune += 1
		else:
			points += 4 * absi(race.hab_center[axis] - 50)
	if immune > 1:
		points -= 150
	points += _factories_vs_growth(race, content, g, immune)
	points += _resources_per_colonist(race.resources_per_colonist)
	points += _factory_settings(race)
	if race.cheap_factories:
		points -= 175
	points += _mine_settings(race)
	points -= _trait_cost(race.primary_trait, content)
	points += _lesser_traits(race, content)
	points += _research(race)
	if race.techs_start_at_3:
		points -= 180
	if race.research_costs[ENERGY] == RESEARCH_CHEAP:
		points -= trait_param(race, content, "race.ap_cheap_energy_penalty", 0)
	return points / 3


## Habitability points H (S06): how much planet space the race can live on, terraforming
## included. Uses floating point where the original does.
static func hab_points(race: Race, content: ContentRegistry) -> int:
	var reach: Array[int] = TERRAFORM_REACH.duplicate()
	reach[1] = trait_param(race, content, "race.hab_terraform_reach_1", reach[1])
	reach[2] = trait_param(race, content, "race.hab_terraform_reach_2", reach[2])
	var total := 0.0
	for pass_index in 3:
		total += _hab_pass(race, reach[pass_index], PASS_WEIGHT[pass_index], pass_index > 0)
	return int(total * 0.1 + 0.5)


## The value of a named trait parameter for this race: the primary trait's, else the first lesser
## trait (in id order) that has it, else `default`.
static func trait_param(race: Race, content: ContentRegistry, name: String, default: int) -> int:
	var ids: Array[String] = [race.primary_trait]
	ids.append_array(race.lesser_traits)
	for id in ids:
		if content.has_def(id):
			var params: Dictionary = content.trait_def(id).get("params", {})
			if params.has(name):
				return params[name]
	return default


static func _hab_pass(race: Race, reach: int, weight: int, terraform: bool) -> float:
	var samples := []
	var spans := []
	for axis in 3:
		if race.is_immune(axis):
			samples.append([50])
			spans.append(-1)
			continue
		var lower := maxi(race.hab_low[axis] - reach, 0)
		var upper := mini(race.hab_high[axis] + reach, 100)
		var width := upper - lower
		var axis_samples := []
		for k in SAMPLES:
			axis_samples.append(lower + k * width / (SAMPLES - 1))
		samples.append(axis_samples)
		spans.append(width)
	var env: Array[int] = [0, 0, 0]
	var sum_g := 0.0
	for g: int in samples[0]:
		var moved_g := _move(race, 0, g, reach, terraform)
		var sum_t := 0.0
		for t: int in samples[1]:
			var moved_t := _move(race, 1, t, reach, terraform)
			var sum_r := 0
			for r: int in samples[2]:
				var moved_r := _move(race, 2, r, reach, terraform)
				env[0] = moved_g[0]
				env[1] = moved_t[0]
				env[2] = moved_r[0]
				var h := Habitability.value(env, race)
				var left: int = moved_g[1] + moved_t[1] + moved_r[1]
				if left > reach:
					h = maxi(h - (left - reach), 0)
				sum_r += weight * h * h
			sum_r = sum_r * IMMUNE_SPAN if spans[2] < 0 else spans[2] * sum_r / 100
			sum_t += sum_r
		sum_t *= IMMUNE_SPAN if spans[1] < 0 else spans[1] * 0.01
		sum_g += sum_t
	sum_g *= IMMUNE_SPAN if spans[0] < 0 else spans[0] * 0.01
	return sum_g


## A sample value moved toward the race's center by up to `reach` (terraforming), and the signed
## distance still left over (center minus value after the move): [value, left]. The original adds
## the three axes' leftovers with their signs, so they can cancel (S06).
static func _move(race: Race, axis: int, v: int, reach: int, terraform: bool) -> Array[int]:
	if not terraform or race.is_immune(axis):
		return [v, 0]
	var center := race.hab_center[axis]
	var dist := center - v
	if absi(dist) <= reach:
		return [center, 0]
	var left := dist + reach if dist < 0 else dist - reach
	return [center - left, left]


static func _factories_vs_growth(race: Race, content: ContentRegistry, g: int, immune: int) -> int:
	var operated := race.factories_operated
	var output := race.factory_output
	if operated <= 10 and output <= 10:
		return 0
	var a := maxi(operated - 9, 1)
	var b := maxi(output - 9, 1) * trait_param(race, content, "race.ap_factory_growth_factor", 2)
	if immune < 2:
		return -(b * a * g / 9)
	return -(g * b * a / 2)


static func _resources_per_colonist(pe: int) -> int:
	pe = mini(pe, 25)
	if pe < 8:
		return -2400
	if pe == 8:
		return -1260
	if pe == 9:
		return -600
	return 120 * (pe - 10) if pe > 10 else 0


static func _factory_settings(race: Race) -> int:
	var output := race.factory_output
	var cost := race.factory_cost
	var operated := race.factories_operated
	var a := (output - 10) * (-121 if output >= 10 else -100)
	var b := (cost - 10) * 55 if cost > 10 else -60 * (10 - cost) * (10 - cost)
	var c := (operated - 10) * (-35 if operated >= 10 else -40)
	var s := a + b + c
	if s > 700:
		s = (s - 700) / 3 + 700
	if operated > 24:
		s -= 360
	elif operated > 21:
		s += 45 * (17 - operated)
	elif operated > 16:
		s += 30 * (16 - operated)
	if output > 12:
		s += 60 * (12 - output)
	return s


static func _mine_settings(race: Race) -> int:
	var output := race.mine_output
	var cost := race.mine_cost
	var operated := race.mines_operated
	var a := (output - 10) * (-169 if output >= 10 else -100)
	var b := 65 * (cost - 3) + 80 if cost >= 3 else -360
	var c := (operated - 10) * (-35 if operated >= 10 else -40)
	return a + b + c


static func _lesser_traits(race: Race, content: ContentRegistry) -> int:
	var points := 0
	var positive := 0
	var negative := 0
	var restricted_scanners := false
	for id in race.lesser_traits:
		var cost := _trait_cost(id, content)
		points -= cost
		if cost > 0:
			positive += 1
		elif cost < 0:
			negative += 1
		if content.has_def(id):
			var params: Dictionary = content.trait_def(id).get("params", {})
			restricted_scanners = (
				restricted_scanners or params.get("race.ap_scanner_restriction", 0) != 0
			)
	var n := positive + negative
	if n > 4:
		points -= 10 * n * (n - 4)
	if negative - positive > 3:
		points -= 60 * (negative - positive - 3)
	if positive - negative > 3:
		points -= 40 * (positive - negative - 3)
	if restricted_scanners:
		points -= trait_param(race, content, "race.ap_nas_penalty", 0)
	return points


static func _research(race: Race) -> int:
	var s := 0
	for setting in race.research_costs:
		s += setting - 1
	if s > 0:
		var points := -130 * s * s
		if s == 6:
			points += 1430
		elif s == 5:
			points += 520
		return points
	if s < 0:
		var points := RESEARCH_BONUS[-s]
		if s < -4 and race.resources_per_colonist < 10:
			points -= 190
		return points
	return 0


static func _trait_cost(id: String, content: ContentRegistry) -> int:
	return content.trait_def(id).get("cost", 0) if content.has_def(id) else 0
