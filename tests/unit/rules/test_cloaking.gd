extends GdUnitTestSuite
## Spec S15 "Cloaking".

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _player(prt: String, lrts: Array[String] = []) -> Player:
	var p := Player.new()
	p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
	p.race.primary_trait = prt
	p.race.lesser_traits.assign(lrts)
	return p


func _design(hull: String, parts: Array, slot := 0) -> Design:
	var d := Design.new()
	d.slot = slot
	d.hull = hull
	var slots: Array[DesignSlot] = []
	for pc: Array in parts:
		slots.append(DesignSlot.new(pc[0], pc[1]))
	d.parts.assign(slots)
	return d


func test_units_to_pct() -> void:
	var cases := [
		[0, 0],
		[70, 35],
		[100, 50],
		[101, 50],
		[300, 75],
		[540, 85],
		[612, 88],
		[1124, 96],
		[1380, 97],
		[1612, 98],
		[5000, 98],
	]
	for c: Array in cases:
		assert_int(Cloaking.units_to_pct(c[0])).override_failure_message(str(c)).is_equal(c[1])


func test_fleet_cloak_counts_cargo_except_for_super_stealth() -> void:
	var he := _player("trait.prt.HE")
	var d := _design("hull.medium_freighter", [["part.electrical.transport_cloaking", 1]])
	he.set_design(d, false)
	var f := Fleet.new()
	f.add_ships(0, 1)
	var mass := PartRules.mass(d, _content)
	assert_int(Cloaking.fleet_pct(f, he, _content)).is_equal(75)
	f.cargo.assign([0, 0, 0, mass, 1000])
	# the colonists double the mass, so 300 units count as 150; fuel weighs nothing
	assert_int(Cloaking.fleet_pct(f, he, _content)).is_equal(Cloaking.units_to_pct(150))
	var ss := _player("trait.prt.SS")
	ss.set_design(d.copy() as Design, false)
	assert_int(Cloaking.fleet_pct(f, ss, _content)).is_equal(Cloaking.units_to_pct(600))


func test_fleet_cloak_weighs_stacks_by_mass() -> void:
	var he := _player("trait.prt.HE")
	var cloaked := _design("hull.scout", [["part.electrical.stealth_cloak", 1]], 0)
	var plain := _design("hull.scout", [], 1)
	he.set_design(cloaked, false)
	he.set_design(plain, false)
	var f := Fleet.new()
	f.add_ships(0, 1)
	f.add_ships(1, 1)
	var m0 := PartRules.mass(cloaked, _content)
	var m1 := PartRules.mass(plain, _content)
	assert_int(Cloaking.fleet_pct(f, he, _content)).is_equal(
		Cloaking.units_to_pct(70 * m0 / (m0 + m1))
	)


func test_starbase_cloak_and_tachyon_detectors() -> void:
	var base := _design("hull.space_station", [["part.electrical.stealth_cloak", 1]])
	assert_int(Cloaking.starbase_pct(base, _player("trait.prt.HE"), _content)).is_equal(35)
	var isb := _player("trait.prt.HE", ["trait.lrt.ISB"])
	assert_int(Cloaking.starbase_pct(base, isb, _content)).is_equal(Cloaking.units_to_pct(110))
	assert_int(Cloaking.tachyon_pct(base, _content)).is_equal(100)
	var td := _design("hull.scout", [["part.electrical.tachyon_detector", 2]])
	assert_int(Cloaking.tachyon_pct(td, _content)).is_equal(93)
	td.parts[0].count = 25
	assert_int(Cloaking.tachyon_pct(td, _content)).is_equal(81)
	# a 50% cloak halves the reach: (50 × 100 div 100) × 50 div 100 = 25
	assert_bool(Cloaking.within(25, 100, 50)).is_true()
	assert_bool(Cloaking.within(26, 100, 50)).is_false()
