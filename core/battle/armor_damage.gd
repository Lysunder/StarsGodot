class_name ArmorDamage
extends RefCounted
## Armor damage in battle, Standard (spec S16 "Damage", fix B09): within a battle a token keeps
## the exact damage of its damaged ships, so a hit adds only what it did; the stack's damage word
## (in 1/500 of the armor) is derived from it, rounded to nearest, after each hit. The original
## rounds every hit up to at least 1/500 of the armor per ship (B09; its version is the
## harness_compat mod's).
##
## Token fields used (besides the battle's own): `_hurt`, the damage of each damaged ship in
## 1/FINE of a damage point, and `_hurt_ships`, how many ships are damaged.

## 1/FINE damage points: a multiple of 500 so the stored 1/500 of the armor converts exactly.
const FINE := 500 * 1024
const SCALE := 500
const POINTS_MAX := 499
const PERCENT := 100
const POINTS_SHIFT := 7
const POINTS_MASK := 0xFF80
const PERCENT_MASK := 0x7F


## Formula `battle.armor_damage`: `x` damage points reach the armor of ship token `o`, killing at
## most `allowed` ships. Returns [ships left, damage left over, kills still allowed]; when ships
## are left, the token's damage word is updated and nothing is left over.
static func ships(o: Dictionary, x: int, allowed: int) -> Array:
	var armor: int = o._armor
	if not o.has("_hurt"):
		_start(o)
	var whole := armor * FINE
	var count: int = o.count
	var damaged: int = o._hurt_ships
	var hurt: int = o._hurt
	var left := x * FINE
	# damaged ships go first, then whole ones
	while damaged > 0 and allowed > 0 and left >= whole - hurt:
		left -= whole - hurt
		damaged -= 1
		count -= 1
		allowed -= 1
	while count > damaged and allowed > 0 and left >= whole:
		left -= whole
		count -= 1
		allowed -= 1
	if allowed < 1:
		left = 0
	if count == 0:
		return [0, left / FINE, allowed]
	if left > 0:
		hurt = (left + damaged * hurt) / count
		damaged = count
	if hurt == 0:
		damaged = 0
	o._hurt = hurt
	o._hurt_ships = damaged
	var points := _points(hurt, armor)
	var pct := 0
	if points > 0:
		pct = (damaged * PERCENT + count - 1) / count
	o.damage = points << POINTS_SHIFT | pct
	return [count, 0, allowed]


## Formula `battle.starbase_damage`: `x` damage points reach the armor of starbase token `o`.
## Returns the planet's new starbase damage (1/500 of the armor), or -1 when it is destroyed.
static func starbase(o: Dictionary, x: int) -> int:
	var armor: int = o._armor
	if not o.has("_hurt"):
		_start(o)
	var hurt: int = o._hurt + x * FINE
	if hurt >= armor * FINE:
		return -1
	o._hurt = hurt
	return _points(hurt, armor)


## The token's damage at the start of the battle, from its damage word.
static func _start(o: Dictionary) -> void:
	o._hurt = 0
	o._hurt_ships = 0
	if o.damage & POINTS_MASK:
		o._hurt = (o.damage >> POINTS_SHIFT) * o._armor * (FINE / SCALE)
		o._hurt_ships = maxi((o.damage & PERCENT_MASK) * o.count / PERCENT, 1)


## Damage per ship in 1/500 of the armor, rounded to nearest, at most 499.
static func _points(hurt: int, armor: int) -> int:
	if armor <= 0:
		return 0
	var unit := armor * (FINE / SCALE)
	return mini((hurt * 2 + unit) / (unit * 2), POINTS_MAX)
