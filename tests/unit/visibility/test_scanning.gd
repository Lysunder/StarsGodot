extends GdUnitTestSuite
## Spec S15 (first part): scanner ranges and what end-of-turn scanning records.

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
	p.tech_levels.assign([0, 0, 0, 0, 3, 0])
	return p


func _design(hull: String, parts: Array) -> Design:
	var d := Design.new()
	d.hull = hull
	var slots: Array[DesignSlot] = []
	for pc: Array in parts:
		slots.append(DesignSlot.new(pc[0], pc[1]))
	d.parts.assign(slots)
	return d


func test_design_ranges() -> void:
	var p := _player("trait.prt.HE")
	# the fourth root of the summed fourth powers: two Rhinos see 2^(1/4) x 50
	var d := _design("hull.scout", [["part.scanner.rhino_scanner", 2]])
	assert_array(Scanning.design_ranges(d, p, _content)).is_equal([59, 0])
	(
		assert_array(
			Scanning.design_ranges(
				_design("hull.scout", [["part.scanner.dolphin_scanner", 1]]), p, _content
			)
		)
		. is_equal([220, 100])
	)
	# no scanner at all: -1; a Bat Scanner sees 0
	assert_int(Scanning.design_ranges(_design("hull.scout", []), p, _content)[0]).is_equal(-1)
	(
		assert_int(
			(
				Scanning
				. design_ranges(
					_design("hull.scout", [["part.scanner.bat_scanner", 1]]), p, _content
				)[0]
			)
		)
		. is_equal(0)
	)


func test_joat_builtin_scanner_and_no_advanced_scanners() -> void:
	var joat := _player("trait.prt.JoaT")
	# electronics 3: a built-in 60 ly scanner, penetrating 30 ly, on scouts, frigates and destroyers
	assert_array(Scanning.design_ranges(_design("hull.scout", []), joat, _content)).is_equal(
		[60, 30]
	)
	(
		assert_int(Scanning.design_ranges(_design("hull.medium_freighter", []), joat, _content)[0])
		. is_equal(-1)
	)
	var nas := _player("trait.prt.HE", ["trait.lrt.NAS"])
	var d := _design("hull.scout", [["part.scanner.rhino_scanner", 1]])
	assert_int(Scanning.design_ranges(d, nas, _content)[0]).is_equal(100)


func test_scanning_marks_minefields_and_wormholes() -> void:
	var s := GameState.new()
	for i in 2:
		var p := _player("trait.prt.HE")
		p.index = i
		p.set_design(_design("hull.scout", [["part.scanner.rhino_scanner", 1]]), false)
		s.players.append(p)
	var f := s.add_fleet(1, 512)
	f.x = 1000
	f.y = 1000
	f.add_ships(0, 1)
	# 30 ly away: beyond a quarter of the 50 ly range; then 12 ly away: within it
	var far := s.add_minefield(0, 512)
	far.x = 1030
	far.y = 1000
	far.mines = 100
	var near := s.add_minefield(0, 512)
	near.x = 1012
	near.y = 1000
	near.mines = 100
	var w := Wormhole.new()
	w.x = 1000
	w.y = 1010
	s.wormholes.append(w)
	Scanning.record_all(s, _content)
	assert_array(far.known_by).is_empty()
	assert_array(near.known_by).is_equal([1])
	assert_array(near.seen_by).is_equal([1])
	assert_array(w.tracked_by).is_equal([1])
	# a field the player already knows is seen again anywhere within the normal range
	far.known_by.assign([1])
	Scanning.record_all(s, _content)
	assert_array(far.seen_by).is_equal([1])


# --- Views (S15 second part) ------------------------------------------------------------------


func _world(prts: Array) -> GameState:
	var s := GameState.new()
	for i in prts.size():
		var p := _player(prts[i])
		p.index = i
		var relations: Array[String] = []
		for j in prts.size():
			relations.append("neutral" if i == j else "enemy")
		p.relations.assign(relations)
		s.players.append(p)
	return s


func _planet(s: GameState, x: int, y: int, owner := -1) -> Planet:
	var pl := Planet.new()
	pl.id = s.planets.size()
	pl.x = x
	pl.y = y
	pl.owner = owner
	s.planets.append(pl)
	return pl


func _fleet(
	s: GameState, owner: int, slot: int, parts: Array, x: int, y: int, planet := -1
) -> Fleet:
	var p := s.player(owner)
	if p.ship_design(slot) == null:
		var d := _design("hull.scout", parts)
		d.slot = slot
		p.set_design(d, false)
	var f := s.add_fleet(owner, 512)
	f.x = x
	f.y = y
	f.planet = planet
	f.add_ships(slot, 1)
	return f


func _starbase(s: GameState, pl: Planet, parts: Array) -> void:
	var d := _design("hull.space_station", parts)
	s.player(pl.owner).set_design(d, true)
	pl.starbase = Starbase.new()


func _view(s: GameState, p: int) -> Dictionary:
	Scanning.record_all(s, _content, StarsRandom.new())
	return s.views[p]


func test_cloaked_fleets_and_tachyon_detectors() -> void:
	var s := _world(["trait.prt.HE", "trait.prt.HE"])
	_fleet(s, 0, 0, [["part.scanner.rhino_scanner", 1]], 1000, 1000)
	# a Stealth Cloak alone: 35%, so the 50 ly Rhino reaches √(65 × 2500 div 100 × 65 div 100) ly
	var near := _fleet(s, 1, 0, [["part.electrical.stealth_cloak", 1]], 1030, 1000)
	var edge := _fleet(s, 1, 0, [], 1033, 1000)
	assert_dict(_view(s, 0).fleets).is_equal({"1/%d" % near.number: 3})
	# four Tachyon Detectors leave 90% of the cloak: 31%
	var tachyon := _design(
		"hull.scout", [["part.scanner.rhino_scanner", 1], ["part.electrical.tachyon_detector", 4]]
	)
	s.player(0).set_design(tachyon, false)
	assert_int(Cloaking.fleet_pct(edge, s.player(1), _content)).is_equal(35)
	assert_dict(_view(s, 0).fleets).is_equal({"1/0": 3, "1/1": 3})


func test_fleets_in_orbit_need_penetrating_scanners() -> void:
	var s := _world(["trait.prt.HE", "trait.prt.HE"])
	var pl := _planet(s, 1020, 1000)
	_fleet(s, 0, 0, [["part.scanner.rhino_scanner", 1]], 1000, 1000)
	_fleet(s, 1, 0, [], 1020, 1000, pl.id)
	var v := _view(s, 0)
	assert_dict(v.fleets).is_empty()
	assert_array(v.met).is_empty()
	s.player(0).ship_design(0).parts[0].part = "part.scanner.ferret_scanner"
	v = _view(s, 0)
	assert_dict(v.fleets).is_equal({"1/0": 3})
	assert_dict(v.planets).is_equal({str(pl.id): 3})
	assert_dict(v.designs).is_equal({"1/0": 3})
	assert_array(v.met).is_equal([1])


func test_cargo_and_mineral_scanners() -> void:
	var s := _world(["trait.prt.HE", "trait.prt.HE"])
	var pl := _planet(s, 1000, 1000)
	_fleet(s, 0, 0, [["part.scanner.robber_baron_scanner", 1]], 1000, 1000, pl.id)
	_fleet(s, 1, 0, [], 1000, 1000, pl.id)
	_fleet(s, 1, 0, [], 1010, 1000)
	var v := _view(s, 0)
	assert_dict(v.fleets).is_equal({"1/0": 4, "1/1": 3})
	assert_dict(v.planets).is_equal({str(pl.id): 4})
	# without a scanner, an orbiting fleet only knows the planet is there
	s.player(0).ship_design(0).parts.clear()
	assert_dict(_view(s, 0).planets).is_equal({str(pl.id): 1})


func test_cloaked_starbases_stay_hidden() -> void:
	var s := _world(["trait.prt.HE", "trait.prt.HE"])
	_fleet(s, 0, 0, [["part.scanner.dolphin_scanner", 1]], 1000, 1000)
	var hidden := _planet(s, 1060, 1000, 1)
	_starbase(s, hidden, [["part.electrical.ultra_stealth_cloak", 1]])
	# the same starbase design 10 ly away: within √(15² × 100² div 10000) ly
	var open := _planet(s, 1000, 1010, 1)
	open.starbase = Starbase.new()
	var v := _view(s, 0)
	assert_dict(v.planets).is_equal({str(hidden.id): 2, str(open.id): 3})
	assert_dict(v.starbase_designs).is_equal({"1/0": 3})


func test_space_demolition_minefields_scan() -> void:
	var s := _world(["trait.prt.SD", "trait.prt.HE"])
	var field := s.add_minefield(0, 512)
	field.x = 1000
	field.y = 1000
	field.mines = 400
	_fleet(s, 1, 0, [], 1010, 1000)
	var cloaked := _fleet(s, 1, 1, [["part.electrical.ultra_stealth_cloak", 1]], 1000, 1010)
	_fleet(s, 1, 0, [], 1030, 1000)
	var cloak := Cloaking.fleet_pct(cloaked, s.player(1), _content)
	var rng := StarsRandom.new()
	var expected := StarsRandom.new()
	Scanning.record_all(s, _content, rng)
	var fleets := {"1/0": 3}
	if cloak <= expected.random(100):
		fleets["1/1"] = 3
	assert_dict(s.views[0].fleets).is_equal(fleets)
	# one draw, for the cloaked fleet only
	assert_int(rng.random(1000)).is_equal(expected.random(1000))


func test_stargates_scan_other_stargates() -> void:
	var s := _world(["trait.prt.IT", "trait.prt.HE"])
	var home := _planet(s, 1000, 1000, 0)
	_starbase(s, home, [["part.orbital.stargate_100_250", 1]])
	var near := _planet(s, 1200, 1000, 1)
	_starbase(s, near, [["part.orbital.stargate_100_250", 1]])
	var far := _planet(s, 1300, 1000, 1)
	far.starbase = Starbase.new()
	_planet(s, 1100, 1000, 1)
	# beyond the gate's range, and a planet without a stargate, stay unseen
	assert_dict(_view(s, 0).planets).is_equal({str(near.id): 3})
	assert_int(far.id).is_equal(2)


func test_packet_physics_packets_scan() -> void:
	var s := _world(["trait.prt.PP", "trait.prt.HE"])
	var packet := s.add_packet(0, false, 512)
	packet.x = 1000
	packet.y = 1000
	packet.warp = 10
	var other := s.add_packet(1, false, 512)
	other.x = 3000
	other.y = 3000
	_fleet(s, 1, 0, [], 1090, 1000)
	var v := _view(s, 0)
	assert_dict(v.fleets).is_equal({"1/0": 3})
	assert_array(v.packets).is_equal(["0/0", "1/0"])


func test_war_mongers_see_designs_in_full() -> void:
	var s := _world(["trait.prt.WM", "trait.prt.HE"])
	_fleet(s, 0, 0, [["part.scanner.rhino_scanner", 1]], 1000, 1000)
	_fleet(s, 1, 2, [], 1010, 1000)
	assert_dict(_view(s, 0).designs).is_equal({"1/2": 7})


func test_bombing_fleets_see_their_planet() -> void:
	var s := _world(["trait.prt.HE", "trait.prt.HE"])
	var pl := _planet(s, 1000, 1000, 1)
	var bomber := _fleet(s, 0, 0, [], 1000, 1000, pl.id)
	var escort := _fleet(s, 0, 1, [], 1000, 1000, pl.id)
	Bombing.mark_fleets(s)
	assert_bool(bomber.at_bombing).is_false()
	assert_dict(_view(s, 0).planets).is_equal({str(pl.id): 1})
	# one fleet's battle plan attacks everyone: every fleet of the player there takes part
	s.player(0).battle_plans = [{"number": 1, "attack": 3}]
	escort.battle_plan = 1
	Bombing.mark_fleets(s)
	assert_bool(bomber.at_bombing).is_true()
	assert_dict(_view(s, 0).planets).is_equal({str(pl.id): 3})
	assert_bool(bomber.at_bombing).is_false()


func test_lost_planets_and_designs_shown_in_full() -> void:
	var s := _world(["trait.prt.HE", "trait.prt.HE"])
	var pl := _planet(s, 1000, 1000, 1)
	_fleet(s, 1, 3, [], 2000, 2000)
	s.messages = [
		[{"type": "message.planet.died", "goto": {"planet": pl.id}, "params": [pl.id]}], []
	]
	s.player(1).ship_design(3).revealed_to[0] = true
	var v := _view(s, 0)
	assert_dict(v.planets).is_equal({str(pl.id): 3})
	assert_dict(v.designs).is_equal({"1/3": 7})
	assert_array(v.met).is_equal([1])
	assert_dict(s.player(1).ship_design(3).revealed_to).is_empty()
