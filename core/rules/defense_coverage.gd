class_name DefenseCoverage
extends RefCounted
## What a planet's defenses let through (`Planet_DefenseCoverage@1030:0262`, S17): the share of
## bombs (and packet damage, S14) that gets past n operable defenses of the best defense the
## owner has, (1 - value × 0.001)^n, or (1 - value × 0.0005)^n against smart bombs, kept as a
## 32-bit float like the original. 1 for an unowned planet or one without defenses.
##
## The original then multiplies these floats by integers in x87 extended precision, which is
## exact; the helpers below do the same in integers from the float's mantissa and exponent.

const SCALE := 0.001
const SMART_SCALE := 0.0005
## Float32 mantissa bits (with the hidden bit) and exponent bias.
const MANTISSA_BITS := 23
const EXPONENT_BIAS := 127
## Beyond this many fraction bits the products below cannot reach the next integer.
const MAX_SHIFT := 60


static func uncovered(
	state: GameState, content: ContentRegistry, planet: Planet, smart := false
) -> float:
	if planet.owner < 0 or planet.defenses == 0:
		return 1.0
	var owner := state.player(planet.owner)
	var best := PartRules.best_part("planetary", "defense", owner, content)
	if best.is_empty():
		return 1.0
	var value: int = content.part(best).get("stats", {}).get("defense", 0)
	var n := mini(planet.defenses, PlanetEconomy.operable_defenses(planet, owner.race, -1, content))
	var scale := SMART_SCALE if smart else SCALE
	return PackedFloat32Array([pow(1.0 - value * scale, n)])[0]


## [M, s] with f = M / 2^s exactly (f a non-negative float32 below 2).
static func parts(f: float) -> Array[int]:
	var bits := PackedFloat32Array([f]).to_byte_array().decode_u32(0)
	var exponent := (bits >> MANTISSA_BITS) & 0xFF
	var mantissa := bits & ((1 << MANTISSA_BITS) - 1)
	if exponent == 0:
		return [mantissa, EXPONENT_BIAS - 1 + MANTISSA_BITS]
	return [mantissa | (1 << MANTISSA_BITS), EXPONENT_BIAS + MANTISSA_BITS - exponent]


## trunc(x × f + 0.5) for x ≥ 0: x scaled by a coverage, rounded.
static func scale_round(x: int, f: float) -> int:
	var p := parts(f)
	var s: int = p[1]
	if s <= 0:
		return x * (p[0] << -s)
	if s > MAX_SHIFT:
		return 0
	return (x * p[0] + (1 << (s - 1))) >> s


## trunc(x × f) for x ≥ 0.
static func scale_trunc(x: int, f: float) -> int:
	var p := parts(f)
	var s: int = p[1]
	if s <= 0:
		return x * (p[0] << -s)
	if s > MAX_SHIFT:
		return 0
	return (x * p[0]) >> s


## What ground troops get through: U + (1 - U) × 0.25 as a 32-bit float (invaders are covered
## three quarters as well as bombs).
static func troops_through(u: float) -> float:
	return PackedFloat32Array([(1.0 - u) * 0.25 + u])[0]


## trunc(x × (1 - (1 - f) × 0.5) + 0.5): installations against bombs, the coverage halved.
static func halved_round(x: int, f: float) -> int:
	var p := parts(f)
	var s: int = p[1]
	if s > MAX_SHIFT:
		return (x + 1) >> 1
	if x & 1:
		return ((x + 1) >> 1) + ((x * p[0]) >> (s + 1))
	return (x >> 1) + ((x * p[0] + (1 << s)) >> (s + 1))


## trunc((1 - f) × 10000): the share of bombs stopped, in hundredths of a percent.
static func stopped_basis_points(f: float) -> int:
	var p := parts(f)
	var s: int = p[1]
	if p[0] == 0:
		return 10000
	if s > MAX_SHIFT:
		return 9999
	return 10000 - ((10000 * p[0] + (1 << s) - 1) >> s)


## x - trunc((1 - f) × x × 0.5): retro bombs left after the defenses stop their share.
static func retro_left(x: int, f: float) -> int:
	var p := parts(f)
	var s: int = p[1]
	var half := x >> 1
	if x & 1 == 0:
		# trunc(x/2 - y), y = x f / 2: half - ceil(y)
		var up := (1 if p[0] > 0 else 0) if s > MAX_SHIFT else _ceil_shift(x * p[0], s + 1)
		return x - (half - up)
	# trunc(half + 1/2 - y) = half - ceil(y - 1/2)
	var up2 := 0 if s > MAX_SHIFT else _ceil_shift(x * p[0] - (1 << s), s + 1)
	return x - (half - up2)


## ceil(a / 2^k) for any a.
static func _ceil_shift(a: int, k: int) -> int:
	return -((-a) >> k)
