extends GdUnitTestSuite
## The production list (ProductionList, S09 section 9): what a planet is offered, in the original's
## order.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	_content = r.registry


func _game() -> GameState:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 5
	return NewGame.create(_content, options)


func _items(pl: Planet, player: Player, can_terraform := false) -> Array:
	return ProductionList.entries(pl, player, _content, can_terraform).map(
		func(e: Dictionary) -> String:
			if e["item"] != "":
				return e["item"]
			return "%s%d" % ["starbase " if e["starbase"] else "ship ", e["design"]]
	)


func test_a_homeworld_with_a_scanner_is_not_offered_one() -> void:
	var s := _game()
	var me := s.player(0)
	var home := s.planet(me.homeworld)
	assert_bool(home.has_scanner).is_true()
	var items := _items(home, me)
	for item: String in items:
		assert_bool(item.begins_with("production_item.scanner")).is_false()
	assert_bool(items.has("production_item.planetary_scanner")).is_false()
	# the scanners of one kind are never offered, even without a scanner
	home.has_scanner = false
	items = _items(home, me)
	assert_bool(items.has("production_item.planetary_scanner")).is_true()
	for item: String in items:
		assert_bool(item.begins_with("production_item.scanner_")).is_false()


func test_the_order_and_what_depends_on_the_planet() -> void:
	var s := _game()
	var me := s.player(0)
	var home := s.planet(me.homeworld)
	home.has_scanner = false
	var items := _items(home, me, true)
	# the homeworld's starbase has an unlimited dock: every ship design, then starbase designs
	assert_str(items[0]).is_equal("ship %d" % me.ship_designs[0].slot)
	var first_standard := items.find("production_item.factories")
	var order := [
		"production_item.factories",
		"production_item.mines",
		"production_item.defenses",
		"production_item.alchemy",
		"production_item.planetary_scanner",
		"production_item.terraform",
		"production_item.auto_mines",
	]
	var last := first_standard - 1
	for item: String in order:
		var at := items.find(item)
		assert_int(at).override_failure_message("%s missing or out of order" % item).is_greater(
			last
		)
		last = at
	# no mass driver: no packets; the starbase itself isn't offered again
	assert_bool(items.has("production_item.ironium_packet")).is_false()
	assert_bool(items.has("starbase %d" % home.starbase.design)).is_false()
	# without terraforming to do, no Terraform; the auto item stays
	items = _items(home, me, false)
	assert_bool(items.has("production_item.terraform")).is_false()
	assert_bool(items.has("production_item.auto_max_terraform")).is_true()
	# at the factory limit, no factories
	home.factories = PlanetEconomy.max_factories(home, me.race, _content)
	assert_bool(_items(home, me).has("production_item.factories")).is_false()
	# without a starbase: no ship designs, every starbase design
	home.starbase = null
	items = _items(home, me)
	assert_bool(items.any(func(i: String) -> bool: return i.begins_with("ship "))).is_false()
	assert_bool(items.has("starbase %d" % me.starbase_designs[0].slot)).is_true()


func test_alternate_reality_has_no_scanner_or_auto_installations() -> void:
	var s := _game()
	var me := s.player(0)
	me.race.primary_trait = "trait.prt.AR"
	var home := s.planet(me.homeworld)
	home.has_scanner = false
	var items := _items(home, me)
	assert_bool(items.has("production_item.planetary_scanner")).is_false()
	assert_bool(items.has("production_item.auto_mines")).is_false()
	assert_bool(items.has("production_item.auto_factories")).is_false()
	assert_bool(items.has("production_item.auto_alchemy")).is_true()


func test_room_for_factories_mines_and_defenses_after_the_queue() -> void:
	var s := _game()
	var me := s.player(0)
	var home := s.planet(me.homeworld)
	var most := PlanetEconomy.max_defenses(home, me.race, _content)
	var room := ProductionList.room(home, me, _content, "production_item.defenses", 0)
	assert_int(room).is_equal(most - home.defenses)
	(
		assert_int(ProductionList.room(home, me, _content, "production_item.defenses", room - 3))
		. is_equal(3)
	)
	(
		assert_int(ProductionList.room(home, me, _content, "production_item.defenses", room + 5))
		. is_equal(0)
	)
	var factories := PlanetEconomy.max_factories(home, me.race, _content) - home.factories
	assert_int(ProductionList.room(home, me, _content, "production_item.factories", 0)).is_equal(
		factories
	)
	# no limit on auto items, alchemy or designs' items
	assert_int(ProductionList.room(home, me, _content, "production_item.auto_mines", 99)).is_equal(
		-1
	)
	assert_int(ProductionList.room(home, me, _content, "production_item.alchemy", 99)).is_equal(-1)
