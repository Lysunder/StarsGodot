class_name StarsRandom
extends RefCounted
## One random number stream: the combined generator of spec S01 (L'Ecuyer 1988).
##
## The state is two integers, s1 in 1..2147483562 and s2 in 1..2147483398. Every draw advances
## both, so the exact sequence of calls matters: rules must draw exactly where the original does,
## including random(0) calls whose result is unused.

const M1 := 2147483563
const A1 := 40014
const M2 := 2147483399
const A2 := 40692
## Largest bound the original can pass (a signed 16-bit value). Enforced on the classic stream.
const CLASSIC_MAX_RANGE := 32767

## Size of the seed table, and the one entry that differs from the prime sequence (S01).
const SEED_TABLE_SIZE := 128
const SEED_TABLE_QUIRK_INDEX := 55
const SEED_TABLE_QUIRK_VALUE := 279

var s1: int
var s2: int
## Largest allowed bound for random(), or 0 for no limit.
var max_range: int = 0


func _init(p_s1: int = 3, p_s2: int = 5) -> void:
	assert(is_valid_state(p_s1, p_s2), "StarsRandom: state out of range")
	s1 = p_s1
	s2 = p_s2


static func is_valid_state(p_s1: int, p_s2: int) -> bool:
	return p_s1 >= 1 and p_s1 <= M1 - 1 and p_s2 >= 1 and p_s2 <= M2 - 1


## Game-seed method: only bits 0-11 of the seed matter.
static func from_game_seed(value: int) -> StarsRandom:
	var i := value & 63
	var j := (value >> 6) & 63
	if j == i:
		j = (j + 1) & 63
	var table := seed_table()
	return StarsRandom.new(table[i], table[j])


## Clock method, used by the original at program start. Only the harness needs it.
static func from_clock(ticks: int) -> StarsRandom:
	var i := (ticks ^ 0x35) & 127
	var j := ((ticks >> 7) ^ 0x5C) & 127
	if j == i:
		j = (j + 1) & 127
	var table := seed_table()
	return StarsRandom.new(table[i], table[j])


## The seed table: the 128 smallest odd primes (3 .. 727), except that entry 55 is 279 instead of
## 269. Built on demand; seeding is rare.
static func seed_table() -> Array[int]:
	var out: Array[int] = []
	var n := 3
	while out.size() < SEED_TABLE_SIZE:
		var prime := true
		for p in out:
			if p * p > n:
				break
			if n % p == 0:
				prime = false
				break
		if prime:
			out.append(n)
		n += 2
	out[SEED_TABLE_QUIRK_INDEX] = SEED_TABLE_QUIRK_VALUE
	return out


## Our derivation for named streams: FNV-1a-32 of "1:<seed>:<name>" and "2:<seed>:<name>".
static func from_stream_name(game_seed: int, stream_name: String) -> StarsRandom:
	var text := "%d:%s" % [game_seed, stream_name]
	var h1 := fnv1a_32(("1:" + text).to_utf8_buffer())
	var h2 := fnv1a_32(("2:" + text).to_utf8_buffer())
	return StarsRandom.new(1 + h1 % (M1 - 1), 1 + h2 % (M2 - 1))


static func fnv1a_32(bytes: PackedByteArray) -> int:
	var h := 2166136261
	for b in bytes:
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


## Advances the generator and returns the raw value, 1..2147483562.
func next_raw() -> int:
	s1 = (A1 * s1) % M1
	s2 = (A2 * s2) % M2
	var z := s1 - s2
	if z < 1:
		z += M1 - 1
	return z


## An integer in 0..bound-1. Always advances, even when bound < 1 (which returns 0).
func random(bound: int) -> int:
	assert(
		max_range == 0 or bound <= max_range, "StarsRandom: bound %d above %d" % [bound, max_range]
	)
	var z := next_raw()
	if bound < 1:
		return 0
	return z % bound


func duplicate_stream() -> StarsRandom:
	var copy := StarsRandom.new(s1, s2)
	copy.max_range = max_range
	return copy


func to_dict() -> Dictionary:
	return {"s1": s1, "s2": s2}
