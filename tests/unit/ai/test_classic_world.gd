extends GdUnitTestSuite
## S22 "The classic world": what one of the original's computer players has loaded, and the
## per-turn setup every classic personality shares.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## tiny3ai turn 1: player 0's homeworld is planet 21, player 1's 30, player 2's 19.
func _state() -> GameState:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/golden/tiny3ai/t001.json")
	var result := SaveFile.decode(text, _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	var s := result.state
	s.views.clear()
	for p in s.players:
		s.views.append({"planets": {}, "fleets": {}, "designs": {}, "starbase_designs": {}})
		p.knowledge = {}
	return s


func test_other_planets_are_as_the_history_knows_them() -> void:
	var s := _state()
	# player 1 scanned player 0's homeworld; it never saw player 2's
	s.views[1]["planets"]["21"] = 3
	PlanetHistory.note_all(s)
	var w := ClassicWorld.build(s, _content, 1, StarsRandom.new())
	var seen := w.state.planet(21)
	assert_int(seen.owner).is_equal(0)
	assert_int(seen.population).is_equal(0)
	assert_int(seen.factories).is_equal(0)
	assert_int(seen.population_estimate).is_equal(s.planet(21).population_estimate)
	assert_array(seen.environment).is_equal(Array(s.planet(21).environment))
	assert_int(w.detail[21]).is_equal(ClassicWorld.SCANNED)
	var unseen := w.state.planet(19)
	assert_int(unseen.owner).is_equal(-1)
	assert_object(unseen.starbase).is_null()
	assert_int(w.detail[19]).is_equal(0)
	# its own homeworld is as it is
	assert_int(w.state.planet(30).population).is_equal(s.planet(30).population)
	assert_int(w.detail[30]).is_equal(ClassicWorld.OWN)
	# the host state is untouched
	assert_int(s.planet(21).population).is_greater(0)


func test_other_fleets_and_designs_only_when_seen() -> void:
	var s := _state()
	s.views[1]["fleets"]["0/1"] = 3
	s.views[1]["designs"]["0/%d" % s.fleet(0, 1).stacks[0].design] = 3
	var w := ClassicWorld.build(s, _content, 1, StarsRandom.new())
	var owners := w.state.fleets.map(func(f: Fleet) -> String: return "%d/%d" % [f.owner, f.number])
	assert_array(owners).contains(["0/1", "1/1", "1/2", "1/3"])
	assert_array(owners).not_contains(["0/0", "0/2", "2/1"])
	var theirs := w.state.player(0).ship_designs
	assert_int(theirs.size()).is_equal(1)
	# seen at level 3: the hull, not the parts
	for slot in theirs[0].parts:
		assert_str(slot.part).is_empty()
	assert_int(w.state.player(2).ship_designs.size()).is_equal(0)


func test_packets_only_when_seen() -> void:
	var s := _state()
	for i in 3:
		var pk := Packet.new()
		pk.owner = [0, 1, 1][i]
		pk.number = [2, 0, 1][i]
		pk.salvage = true
		s.packets.append(pk)
	s.views[1]["packets"] = ["1/0", "0/2"]
	var w := ClassicWorld.build(s, _content, 1, StarsRandom.new())
	var seen := w.state.packets.map(func(p: Packet) -> String: return "%d/%d" % [p.owner, p.number])
	# its own salvage out of sight (1/1) is not loaded
	assert_array(seen).is_equal(["0/2", "1/0"])


## The turn's first draws: the player's planets shuffled with one random(n - i) per place but the
## last.
func test_own_planets_are_shuffled() -> void:
	var s := _state()
	for id in [3, 5, 7]:
		s.planet(id).owner = 1
	var rng := StarsRandom.new(11, 22)
	var w := ClassicWorld.build(s, _content, 1, rng)
	assert_int(w.own_planets.size()).is_equal(4)
	var expected: Array = [3, 5, 7, 30]
	var check := StarsRandom.new(11, 22)
	for i in 3:
		var j: int = i + check.random(4 - i)
		var swap: int = expected[i]
		expected[i] = expected[j]
		expected[j] = swap
	assert_array(w.own_planets.map(func(p: Planet) -> int: return p.id)).is_equal(expected)
	# exactly three draws were made
	assert_int(rng.random(1000)).is_equal(check.random(1000))


func test_orders_apply_to_the_world_and_are_kept() -> void:
	var s := _state()
	var w := ClassicWorld.build(s, _content, 1, StarsRandom.new())
	var reason := w.order({"type": "research", "percent": 40, "field": 2, "next": 7})
	assert_str(reason).is_empty()
	assert_int(w.me().research_percent).is_equal(40)
	assert_int(s.player(1).research_percent).is_not_equal(40)
	assert_int(w.orders.orders.size()).is_equal(1)
	assert_str(w.order({"type": "research", "percent": 400, "field": 2, "next": 7})).is_not_empty()
	assert_int(w.orders.orders.size()).is_equal(1)


func test_setup_records() -> void:
	var s := _state()
	var w := ClassicWorld.build(s, _content, 1, StarsRandom.new())
	assert_int(w.memory[0]).is_equal(ClassicWorld.MEMORY_FIRST)
	assert_int(w.ratings.size()).is_greater(0)
	for id in w.planet_info:
		assert_int((w.planet_info[id] as PackedByteArray).size()).is_equal(ClassicWorld.INFO_SIZE)
