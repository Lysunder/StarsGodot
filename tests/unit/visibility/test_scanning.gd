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
