class_name RandomRace
extends RefCounted
## Rolls a race with the "random" setting anew at game creation (spec S06 "Random races"),
## drawing from the classic stream in the original's order.

## Advantage points left must end up within 0..TARGET_MAX.
const TARGET_MAX := 50
## Repair attempts before the race falls back to the default race.
const MAX_REPAIRS := 251
## Economy params 0..6, in the original's param order.
const ECONOMY := [
	"resources_per_colonist",
	"factory_output",
	"factory_cost",
	"factories_operated",
	"mine_output",
	"mine_cost",
	"mines_operated",
]
## Leftover-point values are drawn from 0..6; 5 and 6 act as surface minerals.
const LEFTOVER_DRAW := 7
const WIDE := [0, 50, 100]
const IMMUNE := [-1, -1, -1]
const GROWTH_MAX_REPAIR := 15

var _content: ContentRegistry
var _rng: StarsRandom
var _default_race: Race
var _primary: Array[String] = []
var _lesser: Array[String] = []


## `default_race` is the fallback when the repair gives up (null: a new Race, the Humanoid preset).
func _init(content: ContentRegistry, rng: StarsRandom, default_race: Race = null) -> void:
	_content = content
	_rng = rng
	_default_race = default_race if default_race != null else Race.new()
	_primary = _traits_in_order("primary")
	_lesser = _traits_in_order("lesser")


## Rolls `race` in place. An empty name gets one from the race name list.
func roll(race: Race) -> void:
	_roll_habitability(race)
	var q := _rng.random(3)
	for f in race.research_costs.size():
		race.research_costs[f] = 1 if q == 0 else _rng.random(3)
	race.primary_trait = _primary[_rng.random(_primary.size())]
	q = _rng.random(4)
	for t in _lesser.size():
		_set_lesser(race, t, q != 0 and _rng.random(2) == 1)
	race.techs_start_at_3 = _rng.random(2) == 1
	race.cheap_factories = _rng.random(2) == 1
	_roll_economy(race)
	if race.name.is_empty():
		var names := _content.name_list(UniverseGenerator.RACE_NAMES)
		race.name = names[_rng.random(names.size())]
	_repair(race)


# --- Steps 1-6 -------------------------------------------------------------------------------


func _roll_habitability(race: Race) -> void:
	var s := _rng.random(25)
	if s < 4:
		for axis in 3:
			_set_axis(race, axis, IMMUNE)
		race.growth_rate = 2 + _rng.random(4)
	elif s < 7:
		for axis in 3:
			_set_axis(race, axis, WIDE)
		race.growth_rate = 3 + _rng.random(4)
	elif s < 9:
		for axis in 3:
			var c := _rng.random(2)
			if axis == 2 and race.hab_center[0] == race.hab_center[1]:
				c = 0 if race.hab_center[0] == 0 else 1
			if c == 0:
				_set_axis(race, axis, WIDE)
			else:
				race.growth_rate = 2 + _rng.random(4)
		race.growth_rate = 2 + _rng.random(5)
	else:
		for axis in 3:
			var w := 2 * (10 + _rng.random(40))
			var o := _rng.random(101 - w)
			_set_axis(race, axis, [o, o + w / 2, o + w])
		if s < 12:
			_set_axis(race, _rng.random(3), IMMUNE)
		elif s < 14:
			_set_axis(race, _rng.random(3), WIDE)
		elif s < 17:
			var axis := _rng.random(3)
			var r := _rng.random(81)
			_set_axis(race, axis, [r, r + 10, r + 20])
		race.growth_rate = 7 + _rng.random(9)


func _roll_economy(race: Race) -> void:
	if _rng.random(3) == 0:
		var defaults := Race.new()
		for field: String in ECONOMY:
			race.set(field, defaults.get(field))
		race.leftover_points = Race.LEFTOVER[_rng.random(Race.LEFTOVER.size())]
		return
	for field: String in ECONOMY:
		var low := _limit(field, "min")
		race.set(field, low + _rng.random(_limit(field, "max") - low + 1))
	var v := _rng.random(LEFTOVER_DRAW)
	race.leftover_points = Race.LEFTOVER[v] if v < Race.LEFTOVER.size() else Race.LEFTOVER[0]


# --- Step 8: repair --------------------------------------------------------------------------


func _repair(race: Race) -> void:
	var attempts := 0
	while true:
		var d := _distance(race)
		if d <= 0:
			return
		if attempts >= MAX_REPAIRS:
			var name := race.name
			var logo := race.logo
			race.load_dict(_default_race.to_dict(), "", PackedStringArray())
			race.name = name
			race.logo = logo
			return
		attempts += 1
		var r := _rng.random(10)
		if r < 3:
			_repair_research(race, d)
		elif r < 6:
			_repair_lesser(race, d)
		elif r < 9:
			_repair_economy(race, d)
		elif _rng.random(2) == 1:
			_repair_growth(race, d)
		else:
			_repair_axis(race, d)


## How far the advantage points left are outside 0..TARGET_MAX (0 or less: inside).
func _distance(race: Race) -> int:
	var a := RaceMath.advantage_points(race, _content)
	return maxi(a - TARGET_MAX, -a)


func _repair_research(race: Race, d: int) -> void:
	var f := _rng.random(6)
	var old := race.research_costs[f]
	if old > 0:
		race.research_costs[f] = old - 1
		if _distance(race) < d:
			return
		race.research_costs[f] = old
	if old < 2:
		race.research_costs[f] = old + 1
		if _distance(race) < d:
			return
		race.research_costs[f] = old


func _repair_lesser(race: Race, d: int) -> void:
	var t := _rng.random(_lesser.size())
	var had := race.lesser_traits.has(_lesser[t])
	for on: bool in [false, true]:
		_set_lesser(race, t, on)
		if _distance(race) < d:
			return
	_set_lesser(race, t, had)


func _repair_economy(race: Race, d: int) -> void:
	var field: String = ECONOMY[_rng.random(ECONOMY.size())]
	var old: int = race.get(field)
	for delta: int in [-1, 1]:
		race.set(field, clampi(old + delta, _limit(field, "min"), _limit(field, "max")))
		if _distance(race) < d:
			return
	race.set(field, old)


func _repair_growth(race: Race, d: int) -> void:
	var g := race.growth_rate
	if g > 1:
		race.growth_rate = g - 1
		if _distance(race) < d:
			return
	if g < GROWTH_MAX_REPAIR:
		race.growth_rate = g + 1
		if _distance(race) < d:
			return
	race.growth_rate = g


func _repair_axis(race: Race, d: int) -> void:
	var axis := _rng.random(3)
	if race.is_immune(axis):
		var v := _rng.random(31)
		_set_axis(race, axis, [v, v + 35, v + 70])
		if _distance(race) >= d:
			_set_axis(race, axis, IMMUNE)
		return
	var old := [race.hab_low[axis], race.hab_center[axis], race.hab_high[axis]]
	_set_axis(race, axis, IMMUNE)
	if _distance(race) >= d:
		_set_axis(race, axis, old)


# --- Helpers ---------------------------------------------------------------------------------


## [low, center, high] for one axis.
static func _set_axis(race: Race, axis: int, v: Array) -> void:
	race.hab_low[axis] = v[0]
	race.hab_center[axis] = v[1]
	race.hab_high[axis] = v[2]


func _set_lesser(race: Race, index: int, on: bool) -> void:
	var id := _lesser[index]
	var has := race.lesser_traits.has(id)
	if on and not has:
		race.lesser_traits.append(id)
		race.lesser_traits.sort()
	elif not on and has:
		race.lesser_traits.erase(id)


func _limit(field: String, which: String) -> int:
	return _content.constant("constant.race.%s_%s" % [field, which])


func _traits_in_order(kind: String) -> Array[String]:
	var pairs := []
	for id in _content.ids("trait"):
		var def := _content.trait_def(id)
		if def.get("kind") == kind:
			pairs.append([int(def.get("order", 0)), id])
	pairs.sort()
	var out: Array[String] = []
	for p: Array in pairs:
		out.append(p[1])
	return out
