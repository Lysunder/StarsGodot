extends GdUnitTestSuite
## Spec S16 "Damage": armor damage, Standard (exact within a battle, fix B09) against the
## original's (the harness_compat mod's formulas, rounding every hit up).

const Compat := preload("res://tests/harness_compat/ruleset.gd")
const F := ArmorDamage.FINE


func _ships(count: int, armor: int, damage := 0) -> Dictionary:
	return {"count": count, "_armor": armor, "damage": damage}


func test_tiny_hits_add_only_what_they_did() -> void:
	var exact := _ships(100, 2000)
	var original := _ships(100, 2000)
	for i in 100:
		assert_array(ArmorDamage.ships(exact, 1, 0x7FFFFFFF)).is_equal([100, 0, 0x7FFFFFFF])
		Compat.ships(original, 1, 0x7FFFFFFF)
	# 100 damage points over 100 ships: 1 each, 1/2000 of the armor, recorded as 0/500
	assert_int(exact._hurt).is_equal(F)
	assert_int(exact._hurt_ships).is_equal(100)
	assert_int(exact.damage).is_equal(0)
	# the original rounds each hit up to another 1/500 of the armor per ship: 400 times as much
	assert_int(original.damage >> 7).is_equal(100)


func test_exact_damage_kills_exactly() -> void:
	var exact := _ships(10, 100)
	assert_array(ArmorDamage.ships(exact, 250, 0x7FFFFFFF)).is_equal([8, 0, 0x7FFFFFFF - 2])
	# 50 over 8 ships: 6.25 each, recorded as 31/500 (rounded to nearest), all 8 damaged
	assert_int(exact.damage).is_equal(31 << 7 | 100)
	exact.count = 8  # (the engine records the losses)
	# 8 × 93.75 = 750 destroys them all
	assert_array(ArmorDamage.ships(exact, 750, 0x7FFFFFFF)).is_equal([0, 0, 0x7FFFFFFF - 8])
	var original := _ships(10, 100)
	Compat.ships(original, 250, 0x7FFFFFFF)
	assert_int(original.damage).is_equal(30 << 7 | 100)
	original.count = 8
	# 6/500 is rounded up to 30/500: 94 left on each, 7 destroyed and the last one nearly
	assert_array(Compat.ships(original, 750, 0x7FFFFFFF)).is_equal([1, 0, 0x7FFFFFFF - 7])


func test_damage_from_before_the_battle_and_kill_cap() -> void:
	# 2 of 4 ships at 250/500 of 100 armor: 50 points left on each
	var o := _ships(4, 100, 250 << 7 | 50)
	# one kill allowed (a torpedo): the rest of the hit is lost
	assert_array(ArmorDamage.ships(o, 120, 1)).is_equal([3, 0, 0])
	assert_int(o._hurt_ships).is_equal(1)
	assert_int(o.damage).is_equal(250 << 7 | 34)


func test_starbase_damage() -> void:
	var planet := Planet.new()
	planet.starbase = Starbase.new()
	var exact := {"count": 1, "_armor": 1000, "damage": 0, "_planet": planet}
	var original := {"count": 1, "_armor": 1000, "damage": 0, "_planet": planet}
	var out := []
	for i in 3:
		out.append(ArmorDamage.starbase(exact, 1))
		var v: int = Compat.starbase(original, 1)
		planet.starbase.damage = v
		original.damage = v << 7 | 100
	# 3 points of 1000: 1.5/500, rounded to nearest; the original adds at least 1/500 per hit
	assert_array(out).is_equal([1, 1, 2])
	assert_int(planet.starbase.damage).is_equal(3)
	assert_int(ArmorDamage.starbase(exact, 997)).is_equal(-1)
