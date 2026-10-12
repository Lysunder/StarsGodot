extends RefCounted
## harness_compat formulas (D12): the original's armor damage (bug B09, spec S16 "Damage", "Known
## bugs") and mine damage top-up (bug B04, spec S13), so golden turns can match 2.6i exactly. Test
## runs only.

const SCALE := 500
const POINTS_MAX := 499
const PERCENT := 100


func build(ruleset: Ruleset) -> void:
	ruleset.replace(StandardRuleset.ARMOR_DAMAGE, ships)
	ruleset.replace(StandardRuleset.STARBASE_DAMAGE, starbase)
	ruleset.replace(StandardRuleset.MINE_TOP_UP, mine_top_up)


## B04: the whole minimum-damage top-up goes to the first stack hit.
static func mine_top_up(top_up: int, _n: int, _ships: int, first: bool) -> int:
	return top_up if first else 0


## B09: each hit is spread over the surviving ships rounded to at least 1 damage point per ship,
## and the damage per ship is rounded up to at least 1/500 of the armor.
static func ships(o: Dictionary, x: int, allowed: int) -> Array:
	var armor: int = o._armor
	var count: int = o.count
	var damaged := 0
	var per := 0
	if o.damage & 0xFF80:
		damaged = maxi((o.damage & 0x7F) * count / PERCENT, 1)
		per = maxi((o.damage >> 7) * armor / SCALE, 1)
	var damaged_left := damaged
	if damaged != 0:
		var rest := armor - per
		if rest <= x:
			while damaged_left != 0 and allowed != 0:
				x -= rest
				damaged_left -= 1
				allowed -= 1
				if x < rest:
					break
		count = damaged_left + (count - damaged)
	while armor <= x and count != 0 and allowed != 0:
		x -= armor
		count -= 1
		allowed -= 1
	if allowed < 1:
		x = 0
	if count == 0:
		return [0, x, allowed]
	var points := 0
	var pct := 0
	if x == 0:
		if damaged_left != 0:
			pct = (damaged_left * PERCENT + count - 1) / count
			points = o.damage >> 7
	else:
		if damaged_left != 0:
			x += damaged_left * per + count - 1
		x = maxi(x / count, 1)
		points = maxi((x * SCALE + armor - 1) / armor, 1) if armor > 0 else 1
		pct = PERCENT
	o.damage = mini(points, POINTS_MAX) << 7 | (pct & 0x7F)
	return [count, 0, allowed]


## B09 for starbases: the damage so far is rounded down to whole points, and a hit that leaves the
## damage unchanged still adds 1/500 of the armor.
static func starbase(o: Dictionary, x: int) -> int:
	var armor: int = o._armor
	if o.damage & 0xFF80:
		x += (o.damage >> 7) * armor / SCALE
	if x >= armor:
		return -1
	var planet: Planet = o._planet
	var v := x * SCALE / armor
	return planet.starbase.damage + 1 if planet.starbase.damage == v else v
