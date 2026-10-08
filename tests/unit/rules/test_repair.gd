extends GdUnitTestSuite
## Spec S19: fleet and starbase repair, and colonists growing in Inner-Strength fleets.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _game(prt := "") -> GameState:
	var s := GameState.new()
	var p := Player.new()
	p.relations.assign(["neutral"])
	p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
	if not prt.is_empty():
		p.race.primary_trait = prt
	var d := Design.new()
	d.slot = 0
	d.hull = "hull.destroyer"
	d.parts.assign([DesignSlot.new("part.engine.long_hump_6", 1)])
	p.set_design(d, false)
	var base := Design.new()
	base.slot = 0
	base.hull = "hull.space_station"
	p.set_design(base, true)
	s.players.append(p)
	var pl := Planet.new()
	pl.x = 1000
	pl.y = 1000
	pl.owner = 0
	s.planets.append(pl)
	TurnMessages.clear(s)
	return s


func _fleet(s: GameState, damage: int) -> Fleet:
	var f := s.add_fleet(0, 512)
	f.x = 1000
	f.y = 1000
	f.add_ships(0, 2)
	f.stacks[0].damage = damage
	f.stacks[0].damaged_percent = 100
	f.did_not_move = true
	return f


func test_repair_rates_by_place() -> void:
	var s := _game()
	var f := _fleet(s, 300)
	assert_int(Repair.rate(s, _content, f)).is_equal(Repair.STILL_IN_SPACE)
	f.planet = 0
	assert_int(Repair.rate(s, _content, f)).is_equal(Repair.OWN_PLANET)
	s.planets[0].starbase = Starbase.new()
	assert_int(Repair.rate(s, _content, f)).is_equal(Repair.OWN_DOCK)
	f.did_not_move = false
	assert_int(Repair.rate(s, _content, f)).is_equal(Repair.MOVED)
	f.did_not_move = true
	s.planets[0].owner = -1
	assert_int(Repair.rate(s, _content, f)).is_equal(Repair.OTHERS_PLANET)


func test_repair_and_the_marks() -> void:
	var s := _game()
	var f := _fleet(s, 300)
	f.planet = 0
	s.planets[0].starbase = Starbase.new()
	s.planets[0].starbase.damage = 70
	Repair.repair_all(s, _content)
	assert_int(f.stacks[0].damage).is_equal(200)
	assert_int(s.planets[0].starbase.damage).is_equal(20)
	# a fleet hit by mines this turn doesn't repair; the mark is then cleared
	f.mine_hit = true
	Repair.repair_all(s, _content)
	assert_int(f.stacks[0].damage).is_equal(200)
	assert_bool(f.mine_hit).is_false()
	assert_int(s.planets[0].starbase.damage).is_equal(0)
	Repair.repair_all(s, _content)
	Repair.repair_all(s, _content)
	assert_int(f.stacks[0].damage).is_equal(0)
	assert_int(f.stacks[0].damaged_percent).is_equal(0)


func test_inner_strength_doubles_and_fuel_transports_add() -> void:
	var s := _game("trait.prt.IS")
	var f := _fleet(s, 300)
	var xport := Design.new()
	xport.slot = 1
	xport.hull = "hull.super_fuel_xport"
	s.players[0].set_design(xport, false)
	f.add_ships(1, 1)
	# deep space, still: 10 x 2 + 50
	Repair.repair_all(s, _content)
	assert_int(f.stacks[0].damage).is_equal(230)


func test_colonists_grow_in_inner_strength_fleets() -> void:
	var s := _game("trait.prt.IS")
	var d := s.players[0].ship_design(0)
	d.hull = "hull.medium_freighter"
	var f := _fleet(s, 0)
	f.cargo[Fleet.CARGO_COLONISTS] = 200
	s.players[0].race.growth_rate = 10
	Repair.grow_colonists(s, _content, StarsRandom.new())
	# 10% x 200 / 200 = 10 (hundreds)
	assert_int(f.cargo[Fleet.CARGO_COLONISTS]).is_equal(210)
	assert_str(s.messages[0][0]["type"]).is_equal("message.fleet.colonists_grew")
	# a full hold sends the growth down to the owner's planet the fleet orbits
	f.cargo[Fleet.CARGO_IRONIUM] = PartRules.cargo_capacity(d, _content) * 2 - 210
	f.planet = 0
	Repair.grow_colonists(s, _content, StarsRandom.new())
	assert_int(s.planets[0].population).is_equal(10)
	assert_str(s.messages[0][1]["type"]).is_equal("message.fleet.colonists_overflowed")
