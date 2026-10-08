extends GdUnitTestSuite
## Spec S14: launching packets, their flight, decay and impact, and salvage.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## Two players; player 0 owns planet 0 at (1000, 1000) with a starbase carrying `drivers` (part
## ids, one slot each) aimed at planet 1, 200 ly east.
func _game(drivers: Array) -> GameState:
	var s := GameState.new()
	for i in 2:
		var p := Player.new()
		p.index = i
		p.relations.assign(["neutral", "neutral"])
		p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
		s.players.append(p)
	var d := Design.new()
	d.slot = 0
	d.hull = "hull.space_station"
	var slots: Array[DesignSlot] = []
	for part: String in drivers:
		slots.append(DesignSlot.new(part, 1))
	d.parts.assign(slots)
	s.players[0].set_design(d, true)
	for i in 2:
		var pl := Planet.new()
		pl.id = i
		pl.x = 1000 + 200 * i
		pl.y = 1000
		s.planets.append(pl)
	var home := s.planets[0]
	home.owner = 0
	home.population = 1000
	home.starbase = Starbase.new()
	home.mass_driver_target = 1
	TurnMessages.clear(s)
	return s


func _item(id: String) -> Dictionary:
	return _content.get_def("production_item", id)


func test_launching_and_merging() -> void:
	var s := _game(["part.orbital.mass_driver_7"])
	var home := s.planets[0]
	Packets.launch(s, _content, home, _item("production_item.mixed_packet"), 3)
	assert_int(s.packets.size()).is_equal(1)
	var p := s.packets[0]
	assert_array(p.minerals).is_equal([120, 120, 120])
	assert_int(p.warp).is_equal(7)
	assert_int(p.decay).is_equal(0)
	assert_int(p.mass_tenths).is_equal(36)
	# a second launch the same year joins it
	Packets.launch(s, _content, home, _item("production_item.ironium_packet"), 1)
	assert_int(s.packets.size()).is_equal(1)
	assert_array(p.minerals).is_equal([220, 120, 120])
	var types := (s.messages[0] as Array).map(func(m: Dictionary) -> String: return m["type"])
	assert_array(types).is_equal(
		["message.production.packet_launched", "message.production.packet_merged"]
	)


func test_overdriving_sets_the_decay_class() -> void:
	var s := _game(["part.orbital.mass_driver_7", "part.orbital.mass_driver_7"])
	var home := s.planets[0]
	# two warp 7 drivers: warp 8 is the driver's own speed, 10 the fastest
	home.mass_driver_warp = 10
	Packets.launch(s, _content, home, _item("production_item.ironium_packet"), 1)
	assert_int(s.packets[0].warp).is_equal(10)
	assert_int(s.packets[0].decay).is_equal(2)
	home.mass_driver_warp = 11
	Packets.launch(s, _content, home, _item("production_item.ironium_packet"), 1)
	assert_int(s.packets[1].warp).is_equal(8)
	assert_int(s.packets[1].decay).is_equal(0)


func _packet(s: GameState, speed: int, minerals: Array[int]) -> Packet:
	var p := s.add_packet(0, false, 512)
	p.x = 1000
	p.y = 1000
	p.warp = speed
	p.destination = 1
	p.minerals = minerals
	return p


func test_flight_half_in_the_launch_year_then_full() -> void:
	var s := _game(["part.orbital.mass_driver_7"])
	var p := _packet(s, 7, [100, 0, 0])
	Packets.move_all(s, _content, StarsRandom.new(), true)
	assert_int(p.x).is_equal(1024)
	assert_bool(p.fresh).is_true()
	# launched packets don't move again after production
	Packets.move_all(s, _content, StarsRandom.new(), true)
	assert_int(p.x).is_equal(1024)
	Packets.move_all(s, _content, StarsRandom.new(), false)
	assert_int(p.x).is_equal(1073)


func test_an_unowned_target_gets_a_ninth() -> void:
	var s := _game(["part.orbital.mass_driver_7"])
	var p := _packet(s, 7, [900, 90, 0])
	p.x = 1180
	Packets.move_all(s, _content, StarsRandom.new(), false)
	assert_bool(s.packets.has(p)).is_false()
	# landing share (1000 - 0) / 9 = 111 per mille
	assert_array(s.planets[1].surface.slice(0, 3)).is_equal([99, 9, 0])


func test_a_matching_driver_catches_everything() -> void:
	var s := _game(["part.orbital.mass_driver_7"])
	var p := _packet(s, 7, [500, 0, 0])
	p.destination = 0
	p.x = 1020
	Packets.move_all(s, _content, StarsRandom.new(), false)
	assert_int(s.planets[0].surface[0]).is_equal(500)
	assert_str(s.messages[0][0]["type"]).is_equal("message.planet.packet_caught")
	assert_array(s.messages[0][0]["params"]).is_equal([0, 0, 500])


func test_an_uncaught_packet_kills_colonists() -> void:
	var s := _game([])
	var home := s.planets[0]
	home.starbase = null
	var p := _packet(s, 8, [1000, 0, 0])
	p.owner = 1
	p.destination = 0
	p.x = 1030
	Packets.move_all(s, _content, StarsRandom.new(), false)
	# 64 x 1000 / 160 = 400: 400 hundred colonists of 1000
	assert_int(home.population).is_equal(600)
	assert_str(s.messages[0][0]["type"]).is_equal("message.planet.packet_damage")
	assert_array(s.messages[0][0]["params"]).is_equal([0, 1000, 1, 400])


func test_decay() -> void:
	var s := _game([])
	var p := _packet(s, 7, [1000, 50, 0])
	p.decay = 1
	assert_bool(Packets.decay(s, _content, p, 100)).is_false()
	# 10%, at least 10 kT of each mineral that isn't empty
	assert_array(p.minerals).is_equal([900, 40, 0])
	assert_int(p.mass_tenths).is_equal(94)
	# half a year
	Packets.decay(s, _content, p, 50)
	assert_array(p.minerals).is_equal([855, 30, 0])


func test_salvage_piles_and_decay() -> void:
	var s := _game([])
	var amounts: Array[int] = [25000, 10000, 0]
	var last := Packets.drop_salvage(s, _content, StarsRandom.new(), 1, 1100, 1100, amounts)
	# a pile holds 30,000 kT: the rest starts a second pile
	assert_int(s.packets.size()).is_equal(2)
	assert_array(s.packets[0].minerals).is_equal([25000, 5000, 0])
	assert_array(last.minerals).is_equal([0, 5000, 0])
	assert_bool(s.packets[0].fresh).is_true()
	assert_bool(last.fresh).is_false()
	Packets.decay_all(s, _content)
	assert_array(s.packets[0].minerals).is_equal([25000, 5000, 0])
	assert_array(last.minerals).is_equal([0, 4500, 0])
	# nothing is left on a planet's position
	var none := Packets.drop_salvage(s, _content, StarsRandom.new(), 1, 1000, 1000, amounts)
	assert_object(none).is_null()
