extends GdUnitTestSuite
## Spec S18: random events (comet, environment change, mineral deposit) and the Mystery Trader
## (arrival, movement, meetings with fleets and planets).

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _world(players := 2) -> GameState:
	var s := GameState.new()
	s.turn = 30
	for i in players:
		var p := Player.new()
		p.index = i
		p.race = RacePresets.make(_content, RacePresets.ids(_content)[0])
		p.relations.assign(["neutral", "neutral"].slice(0, players))
		var d := Design.new()
		d.slot = 0
		d.hull = "hull.medium_freighter"
		d.parts.assign([DesignSlot.new("part.engine.long_hump_6", 1)])
		p.set_design(d, false)
		s.players.append(p)
	var pl := Planet.new()
	pl.id = 0
	pl.x = 1200
	pl.y = 1200
	pl.owner = 0
	pl.population = 1000
	pl.environment.assign([50, 50, 50])
	pl.environment_original.assign([50, 50, 50])
	pl.concentration.assign([40, 40, 40])
	s.planets.append(pl)
	TurnMessages.clear(s)
	return s


## A generator whose first `random(n)` is 0 (so the event fires).
func _firing(n: int) -> StarsRandom:
	for seed_value in range(1, 5000):
		var probe := StarsRandom.new(seed_value, 673)
		if probe.random(n) == 0:
			return StarsRandom.new(seed_value, 673)
	return null


func _copy(rng: StarsRandom) -> StarsRandom:
	return StarsRandom.new(rng.s1, rng.s2)


func test_comet_changes_the_axes_it_names() -> void:
	var s := _world()
	var pl := s.planet(0)
	pl.queue.assign(
		[QueueItem.new("production_item.auto_mines", 5), QueueItem.new("production_item.mines", 5)]
	)
	var rng := _firing(20)
	var probe := _copy(rng)
	probe.random(20)
	probe.random(1)
	var k := probe.random(4)
	RandomEvents.comet(s, _content, rng)
	var mine: Dictionary = s.messages[0][0]
	assert_str(mine.type).is_equal("message.event.comet_hit_yours_" + RandomEvents.SIZES[k])
	assert_str(s.messages[1][0].type).is_equal("message.event.comet_hit_" + RandomEvents.SIZES[k])
	# fix B38: exactly the named axes moved, each in both its value and its original value
	var named: Array = mine.params.slice(1)
	assert_int(named.size()).is_equal(mini(k, 2) + 1)
	for axis in 3:
		var moved := pl.environment[axis] != 50
		assert_bool(moved).is_equal(named.has(axis))
		assert_int(pl.environment_original[axis]).is_equal(pl.environment[axis])
	assert_int(pl.population).is_equal(1000 - 1000 * (25 + 20 * k) / 100)
	for m in 3:
		assert_int(pl.surface[m]).is_greater_equal(50 >> 4)
	# only auto items stay queued
	assert_int(pl.queue.size()).is_equal(1)
	assert_str(pl.queue[0].item).is_equal("production_item.auto_mines")


func test_no_comet_on_a_young_colony_early() -> void:
	var s := _world()
	s.turn = 15
	s.planet(0).population = 20
	var big := _world()
	big.turn = 15
	var rng := _firing(20)
	RandomEvents.comet(big, _content, _copy(rng))
	# a colony of 100,000 colonists is spared before year 20
	assert_array(big.messages[0]).is_empty()
	RandomEvents.comet(s, _content, rng)
	assert_int(s.messages[0].size()).is_equal(1)


func test_environment_change_and_mineral_deposit() -> void:
	var s := _world()
	var rng := _firing(20)
	var probe := _copy(rng)
	probe.random(20)
	probe.random(1)
	var axis := probe.random(3)
	RandomEvents.environment_change(s, _content, rng)
	assert_str(s.messages[0][0].type).is_equal("message.event.environment_changed")
	assert_array(s.messages[0][0].params).is_equal([0, axis])
	var d := absi(s.planet(0).environment[axis] - 50)
	assert_bool(d >= 4 and d <= 8).is_true()
	var deposit := _world()
	var rng2 := _firing(15)
	RandomEvents.mineral_deposit(deposit, _content, rng2)
	var m: int = deposit.messages[0][0].params[1]
	var c := deposit.planet(0).concentration[m]
	assert_bool(c >= 45 and c <= 59).is_true()


func test_trader_arrives_on_an_edge() -> void:
	var s := _world()
	s.turn = 40
	var rng := _firing(7)
	MysteryTrader.arrive(s, _content, rng)
	assert_int(s.traders.size()).is_equal(1)
	var t := s.traders[0]
	assert_bool(t.warp >= 8 and t.warp <= 12).is_true()
	var on_edge := [t.x, t.y].has(1020) or [t.x, t.y].has(1380)
	assert_bool(on_edge).is_true()
	assert_str(s.messages[1][0].type).is_equal("message.trader.arrived")
	assert_dict(s.messages[1][0].goto).is_equal({"trader": t.number})
	# odd years without a special date: no trader
	var odd := _world()
	odd.turn = 41
	MysteryTrader.arrive(odd, _content, _firing(7))
	assert_array(odd.traders).is_empty()


func _trader(s: GameState, item: String) -> Trader:
	var t := s.add_trader(512)
	t.x = 1100
	t.y = 1100
	t.destination_x = 1380
	t.destination_y = 1100
	t.warp = 13
	t.item = item
	return t


func test_trader_moves_and_turns_back() -> void:
	var s := _world()
	var t := _trader(s, "research")
	MysteryTrader.move_all(s, _content, StarsRandom.new(5, 673))
	# warp 13: 169 ly a year, no startling above warp 12
	assert_array([t.x, t.y]).is_equal([1269, 1100])
	# at the edge: random(2) not 0 turns it back
	MysteryTrader.move_all(s, _content, _rolling(2, false))
	assert_array([t.x, t.y]).is_equal([1380, 1100])
	assert_int(t.warp).is_equal(12)
	assert_str(s.messages[0][-1].type).is_equal("message.trader.turned_back")


func test_trader_leaves_at_its_destination() -> void:
	var s := _world()
	var t := _trader(s, "research")
	t.x = 1300
	MysteryTrader.move_all(s, _content, _rolling(2, true))
	assert_array(s.traders).is_empty()
	# with another trader about it leaves without a roll
	var two := _world()
	var first := _trader(two, "research")
	first.x = 1300
	var other := _trader(two, "ships")
	other.x = 1020
	other.destination_x = 1020
	other.destination_y = 1380
	MysteryTrader.move_all(two, _content, _rolling(2, false))
	assert_array(two.traders.map(func(x: Trader) -> int: return x.number)).is_equal([other.number])


## A generator whose first `random(n)` is 0 (`zero`) or not.
func _rolling(n: int, zero: bool) -> StarsRandom:
	var rng := StarsRandom.new(5, 673)
	for i in 5000:
		var probe := StarsRandom.new(rng.s1, rng.s2)
		if (probe.random(n) == 0) == zero:
			return rng
		rng.random(n)
	return null


func _fleet(s: GameState, owner_index: int, minerals: int) -> Fleet:
	var f := s.add_fleet(owner_index, 512)
	f.x = 1100
	f.y = 1100
	f.add_ships(0, 1)
	f.cargo[0] = minerals
	f.waypoints.append(Waypoint.new(1100, 1100))
	return f


func test_a_fleet_trades_for_a_part() -> void:
	var s := _world()
	var t := _trader(s, "part.engine.enigma_pulsar")
	var rich := _fleet(s, 0, 6000)
	var poor := _fleet(s, 1, 100)
	var waited := _fleet(s, 1, 100)
	waited.did_not_move = true
	MysteryTrader.meet_all(s, _content, StarsRandom.new(5, 673))
	assert_array(s.player(0).trader_parts).is_equal(["part.engine.enigma_pulsar"])
	assert_bool(s.fleets.has(rich)).is_false()
	assert_array(t.met).is_equal([0])
	assert_str(s.messages[0][0].type).is_equal("message.trader.part")
	assert_dict(s.messages[0][0].goto).is_equal({"item": "part.engine.enigma_pulsar"})
	# the poor fleet that moved there is refused; the one that waited all year is not
	assert_int(s.messages[1].size()).is_equal(1)
	assert_array(s.messages[1][0].params).is_equal([poor.owner * 512 + poor.number])
	# a second rich fleet of the same player: the trader is still recovering
	var again := _fleet(s, 0, 6000)
	MysteryTrader.meet_all(s, _content, StarsRandom.new(5, 673))
	assert_bool(s.fleets.has(again)).is_true()
	assert_str(s.messages[0][-1].type).is_equal("message.trader.recovering")


func test_research_levels() -> void:
	var s := _world()
	_trader(s, "research")
	_fleet(s, 0, 7400)
	MysteryTrader.meet_all(s, _content, StarsRandom.new(5, 673))
	# (7400 - 5000) div 1200 + 6 = 8 levels for a player with no levels yet
	assert_str(s.messages[0][0].type).is_equal("message.trader.research")
	assert_int(s.messages[0][0].params[1]).is_equal(8)
	var total := 0
	for level in s.player(0).tech_levels:
		total += level
	assert_int(total).is_equal(8)


func test_ships_for_a_human_player() -> void:
	var s := _world()
	_trader(s, "ships")
	var f := _fleet(s, 0, 5000)
	MysteryTrader.meet_all(s, _content, StarsRandom.new(5, 673))
	assert_bool(s.fleets.has(f)).is_false()
	assert_str(s.messages[0][0].type).is_equal("message.trader.ships")
	var gift := s.fleet(0, s.messages[0][0].goto.fleet)
	var n: int = s.messages[0][0].params[1]
	assert_int(gift.ship_count()).is_equal(n)
	var design := s.player(0).ship_design(gift.stacks[0].design)
	assert_bool(design.hull in ["hull.nubian", "hull.mini_morph"]).is_true()
	assert_int(design.built).is_equal(n)
	assert_int(gift.cargo[Fleet.CARGO_FUEL]).is_greater(0)


func test_expert_computer_trades_from_a_planet() -> void:
	var s := _world()
	var ai := s.player(1)
	ai.ai = "ai.robotoids"
	ai.ai_level = 3
	var pl := s.planet(0)
	pl.owner = 1
	pl.x = 1150
	pl.y = 1100
	pl.starbase = Starbase.new()
	pl.surface.assign([1000, 2000, 3000])
	var t := _trader(s, "research")
	MysteryTrader.meet_all(s, _content, StarsRandom.new(5, 673))
	# six levels, 5,000 kT taken (germanium first)
	var total := 0
	for level in ai.tech_levels:
		total += level
	assert_int(total).is_equal(6)
	assert_array(pl.surface).is_equal([1000, 0, 0])
	assert_array(t.met).is_equal([1])


func test_saved_trader_items_validate() -> void:
	var s := _world()
	var t := _trader(s, "hull.mini_morph")
	s.player(0).trader_parts.assign(["hull.mini_morph", "part.engine.enigma_pulsar", "ships"])
	var errors := Array(StateValidator.validate(s, _content))
	assert_array(errors.filter(func(e: String) -> bool: return e.contains("trader"))).is_empty()
	t.item = "part.engine.long_hump_6"
	errors = Array(StateValidator.validate(s, _content))
	var flagged := errors.any(func(e: String) -> bool: return e.contains("not a Mystery Trader"))
	assert_bool(flagged).is_true()
