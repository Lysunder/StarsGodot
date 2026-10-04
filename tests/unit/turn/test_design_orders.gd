extends GdUnitTestSuite
## Spec S11 `design_change` and `design_delete`, with fix B19 (S09 step 7a).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _scout(armor := false) -> Design:
	var d := Design.new()
	d.hull = "hull.scout"
	d.picture = _content.hull("hull.scout").get("pictures", 0)
	(
		d
		. parts
		. assign(
			[
				DesignSlot.new("part.engine.long_hump_6", 1),
				DesignSlot.new("part.scanner.bat_scanner", 1),
				DesignSlot.new("part.armor.tritanium" if armor else "", 1 if armor else 0),
			]
		)
	)
	return d


func _game() -> GameState:
	var s := GameState.new()
	var p := Player.new()
	p.relations.assign(["neutral"])
	p.tech_levels.assign([3, 3, 3, 3, 3, 3])
	for slot in 2:
		var d := _scout()
		d.slot = slot
		p.set_design(d, false)
	var base := Design.new()
	base.hull = "hull.orbital_fort"
	base.picture = _content.hull("hull.orbital_fort").get("pictures", 0)
	for i in 5:
		base.parts.append(DesignSlot.new("", 0))
	p.set_design(base, true)
	s.players.append(p)
	var pl := Planet.new()
	pl.owner = 0
	pl.starbase = Starbase.new()
	s.planets.append(pl)
	return s


func _change(s: GameState, slot: int, design: Design, starbase := false) -> String:
	var order := {
		"type": "design_change", "starbase": starbase, "slot": slot, "design": design.to_dict()
	}
	return OrderRules.apply(s, _content, 0, order)


func _queue_item(design: int, starbase := false, progress := 0) -> QueueItem:
	var q := QueueItem.new()
	q.design = design
	q.starbase = starbase
	q.count = 1
	q.progress = progress
	return q


func test_create_and_replace() -> void:
	var s := _game()
	var d := _scout(true)
	d.built = 99
	d.remaining = 7
	assert_str(_change(s, 5, d)).is_empty()
	var made := s.players[0].ship_design(5)
	assert_array([made.slot, made.built, made.remaining, made.hull]).is_equal(
		[5, 0, 0, "hull.scout"]
	)
	s.players[0].ship_design(1).built = 4
	assert_str(_change(s, 1, _scout(true))).is_empty()
	# a replaced design starts counting again, as the original's client sends it
	assert_int(s.players[0].ship_design(1).built).is_equal(0)
	s.players[0].ship_design(1).remaining = 2
	assert_str(_change(s, 1, _scout())).is_equal("the design has ships")


func test_invalid_designs_are_rejected() -> void:
	var s := _game()
	var d := _scout()
	d.parts[1] = DesignSlot.new("part.armor.tritanium", 1)
	assert_str(_change(s, 3, d)).is_equal("a slot does not accept that part")
	d = _scout()
	d.parts[2] = DesignSlot.new("part.beam.yakimora_light_phaser", 1)
	assert_str(_change(s, 3, d)).is_equal("part not available")
	assert_str(_change(s, 3, _scout(), true)).is_equal("wrong kind of hull")
	assert_str(_change(s, 16, _scout())).is_equal("bad design slot")


func test_progress_is_carried_by_resources() -> void:
	var s := _game()
	var p := s.players[0]
	s.planets[0].queue.append(_queue_item(1, false, 60))
	var old_cost: int = ProductionCosts.design_cost(p.ship_design(1), p, _content)[3]
	var bigger := _scout(true)
	var new_cost: int = ProductionCosts.design_cost(bigger, p, _content)[3]
	assert_str(_change(s, 1, bigger)).is_empty()
	assert_int(s.planets[0].queue[0].progress).is_equal(60 * old_cost / new_cost)


func test_delete_ship_design() -> void:
	var s := _game()
	var mixed := s.add_fleet(0, 512)
	mixed.add_ships(0, 1)
	mixed.add_ships(1, 1)
	mixed.cargo.assign([0, 0, 0, 0, 100])
	var only := s.add_fleet(0, 512)
	only.add_ships(1, 2)
	s.planets[0].queue.assign([_queue_item(1), _queue_item(0)])
	var order := {"type": "design_delete", "starbase": false, "slot": 1}
	assert_str(OrderRules.apply(s, _content, 0, order)).is_empty()
	assert_object(s.players[0].ship_design(1)).is_null()
	assert_int(s.fleets.size()).is_equal(1)
	assert_int(mixed.stacks.size()).is_equal(1)
	# half the fuel capacity left with the deleted ships
	assert_int(mixed.cargo[4]).is_equal(50)
	assert_int(s.planets[0].queue.size()).is_equal(1)
	assert_int(s.planets[0].queue[0].design).is_equal(0)


func test_delete_starbase_design() -> void:
	var s := _game()
	var packet := QueueItem.new()
	packet.item = "production_item.ironium_packet"
	packet.count = 1
	var mines := QueueItem.new()
	mines.item = "production_item.mines"
	mines.count = 5
	s.planets[0].queue.assign([_queue_item(0), packet, mines, _queue_item(0, true)])
	var order := {"type": "design_delete", "starbase": true, "slot": 0}
	assert_str(OrderRules.apply(s, _content, 0, order)).is_empty()
	assert_object(s.planets[0].starbase).is_null()
	assert_object(s.players[0].starbase_design(0)).is_null()
	assert_int(s.planets[0].queue.size()).is_equal(1)
	assert_str(s.planets[0].queue[0].item).is_equal("production_item.mines")
