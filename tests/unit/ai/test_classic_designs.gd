extends GdUnitTestSuite
## S22 "Classic designs": designs from templates, names and pictures, retiring old designs, and
## the starbase designs every classic personality keeps.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## tiny3ai turn 1, seen by player 1 (a computer player).
func _world(tech: int = 0, seed_a: int = 5, seed_b: int = 7) -> ClassicWorld:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/golden/tiny3ai/t001.json")
	var result := SaveFile.decode(text, _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	var s := result.state
	s.views.clear()
	for p in s.players:
		s.views.append({"planets": {}, "fleets": {}, "designs": {}, "starbase_designs": {}})
		p.knowledge = {}
	var me := s.player(1)
	me.race.primary_trait = "trait.prt.HE"
	me.race.lesser_traits.clear()
	me.tech_levels.assign([tech, tech, tech, tech, tech, tech])
	return ClassicWorld.build(s, _content, 1, StarsRandom.new(seed_a, seed_b))


func _design_orders(w: ClassicWorld) -> Array:
	return w.orders.orders.filter(
		func(o: Dictionary) -> bool: return str(o["type"]).begins_with("design")
	)


func test_best_part_takes_the_first_part_the_player_can_use() -> void:
	var w := _world()
	assert_str(ClassicDesigns.best_part(w, "ai_part_class.armor")).is_equal("part.armor.tritanium")
	w.me().tech_levels[3] = 6
	assert_str(ClassicDesigns.best_part(w, "ai_part_class.armor")).is_equal("part.armor.strobnium")
	# a part the race may not use is passed over
	w.me().tech_levels.assign([10, 10, 10, 10, 10, 10])
	assert_str(ClassicDesigns.best_part(w, "ai_part_class.armor")).is_equal("part.armor.kelarium")
	w.me().race.primary_trait = "trait.prt.IS"
	assert_str(ClassicDesigns.best_part(w, "ai_part_class.armor")).is_equal(
		"part.armor.fielded_kelarium"
	)


func test_a_template_fills_every_slot_to_the_hull_maximum() -> void:
	var w := _world(10)
	var d := ClassicDesigns.from_template(w, "ai_design_template.privateer_a")
	assert_object(d).is_not_null()
	var slots: Array = _content.hull("hull.privateer")["slots"]
	assert_int(d.parts.size()).is_equal(slots.size())
	for i in slots.size():
		assert_str(d.parts[i].part).is_not_empty()
		assert_int(d.parts[i].count).is_equal(int(slots[i]["max"]))
	# no ram scoop engine at tech 0: no design
	var low := _world()
	assert_object(ClassicDesigns.from_template(low, "ai_design_template.b_52_bomber_a")).is_null()


func test_outfit_names_the_design_and_gives_the_order() -> void:
	var w := _world(10)
	assert_bool(ClassicDesigns.outfit(w, 11, "ai_design_template.privateer_a")).is_true()
	var d := w.me().ship_design(11)
	assert_object(d).is_not_null()
	assert_int(d.turn_designed).is_equal(w.state.turn)
	# the first of the privateer's four pictures (no other privateer design)
	assert_int(d.picture).is_equal(int(_content.hull("hull.privateer")["pictures"]))
	var names := ClassicDesigns.names_for(_content, "hull.privateer", false)
	assert_int(names.find(d.name)).is_equal(StarsRandom.new(5, 7).random(names.size()))
	var orders := _design_orders(w)
	assert_int(orders.size()).is_equal(1)
	assert_str(orders[0]["type"]).is_equal("design_change")
	assert_int(orders[0]["slot"]).is_equal(11)
	assert_int(w.ratings["1/11"]).is_equal(0)
	# the host state is untouched
	assert_object(w.state).is_not_same(null)


func test_a_taken_name_is_drawn_again() -> void:
	var w := _world(10)
	var names := ClassicDesigns.names_for(_content, "hull.privateer", false)
	var check := StarsRandom.new(5, 7)
	var first: int = check.random(names.size())
	var second: int = check.random(names.size())
	while second == first:
		second = check.random(names.size())
	# a design of another hull already has the first name drawn
	var other := w.me().ship_designs[0]
	other.name = names[first]
	assert_bool(ClassicDesigns.outfit(w, 11, "ai_design_template.privateer_a")).is_true()
	assert_str(w.me().ship_design(11).name).is_equal(names[second])


func test_the_picture_is_the_first_free_one() -> void:
	var w := _world(10)
	assert_bool(ClassicDesigns.outfit(w, 11, "ai_design_template.privateer_a")).is_true()
	assert_bool(ClassicDesigns.outfit(w, 12, "ai_design_template.privateer_b")).is_true()
	var first := int(_content.hull("hull.privateer")["pictures"])
	assert_int(w.me().ship_design(12).picture).is_equal(first + 1)


func test_saving_over_a_design_deletes_it_first() -> void:
	var w := _world(10)
	assert_bool(ClassicDesigns.outfit(w, 11, "ai_design_template.privateer_a")).is_true()
	assert_bool(ClassicDesigns.outfit(w, 11, "ai_design_template.privateer_b")).is_true()
	var types := _design_orders(w).map(func(o: Dictionary) -> String: return o["type"])
	assert_array(types).is_equal(["design_change", "design_delete", "design_change"])


func test_smaller_starbases_hold_fewer_parts() -> void:
	var w := _world(16)
	var full := ClassicDesigns.from_template(w, ClassicDesigns.STATION)
	assert_bool(ClassicDesigns.create_starbase(w, 0, 3)).is_true()
	assert_bool(ClassicDesigns.create_starbase(w, 2, 2)).is_true()
	assert_bool(ClassicDesigns.create_starbase(w, 5, 1)).is_true()
	var medium := w.me().starbase_design(2)
	var small := w.me().starbase_design(5)
	for i in full.parts.size():
		var n := full.parts[i].count
		assert_int(w.me().starbase_design(0).parts[i].count).is_equal(n)
		if n >= 4:
			assert_int(medium.parts[i].count).is_equal(n >> 1)
			assert_int(small.parts[i].count).is_equal(n >> 2)
		else:
			assert_int(medium.parts[i].count).is_equal(n)
			var category: String = _content.part(full.parts[i].part)["category"]
			var expected := n - 1 if category == "orbital" or n > 1 else n
			assert_int(small.parts[i].count).is_equal(expected)
			if expected == 0:
				assert_str(small.parts[i].part).is_empty()
	# a fort in fort slots; a medium fort is a full one
	assert_bool(ClassicDesigns.create_starbase(w, 3, 2)).is_true()
	var fort := w.me().starbase_design(3)
	assert_str(fort.hull).is_equal("hull.orbital_fort")
	var full_fort := ClassicDesigns.from_template(w, ClassicDesigns.FORT)
	for i in full_fort.parts.size():
		assert_int(fort.parts[i].count).is_equal(full_fort.parts[i].count)


func test_old_designs_are_retired() -> void:
	var w := _world(10)
	w.state.turn = 100
	for slot in [11, 12, 13]:
		assert_bool(ClassicDesigns.outfit(w, slot, "ai_design_template.privateer_a")).is_true()
	w.me().ship_design(11).turn_designed = 20
	w.me().ship_design(12).turn_designed = 30
	w.me().ship_design(12).remaining = 4
	w.me().ship_design(13).turn_designed = 90
	w.me().ship_design(13).remaining = 2
	var obsolete := []
	obsolete.resize(16)
	obsolete.fill(0)
	var found := ClassicDesigns.newest_in_slots(w, 11, 13, 50, obsolete)
	assert_int(found["slot"]).is_equal(13)
	assert_int(found["remaining"]).is_equal(6)
	assert_object(w.me().ship_design(11)).is_null()
	assert_object(w.me().ship_design(12)).is_not_null()
	assert_array(obsolete.slice(11, 14)).is_equal([0, 1, 0])


func test_starbase_designs_are_kept() -> void:
	var w := _world(16)
	ClassicDesigns.update_starbase_designs(w)
	var p := w.me()
	for slot in [1, 2, 3, 4]:
		assert_object(p.starbase_design(slot)).is_not_null()
	assert_str(p.starbase_design(1).hull).is_equal("hull.orbital_fort")
	assert_str(p.starbase_design(2).hull).is_equal("hull.space_station")
	# forty turns later the other generation of stations and forts
	w.state.turn = w.state.turn + ClassicDesigns.STARBASE_REVIEW_TURN + 40
	ClassicDesigns.update_starbase_designs(w)
	for slot in [5, 6, 7, 8, 9]:
		assert_object(p.starbase_design(slot)).is_not_null()
	assert_int(ClassicDesigns.newer_starbase(w, 0, 5)).is_equal(5)
	assert_int(ClassicDesigns.newer_starbase(w, 1, 6)).is_equal(6)
	assert_int(ClassicDesigns.newer_starbase(w, 5, 0)).is_equal(5)


func test_memory_is_kept_between_turns() -> void:
	var w := _world()
	w.memory[0] = 8
	w.memory[1] = 1
	w.memory[2] = 42
	w.memory[3] = 7
	var o := w.memory_order()
	assert_array(o["words"]).is_equal([8, 1, 42, 7])
	# the order keeps the words in the player's knowledge for the next turn
	var host := w.state.copy() as GameState
	host.player(1).knowledge = {}
	assert_str(OrderRules.apply(host, _content, 1, o)).is_empty()
	assert_array(host.player(1).knowledge[ClassicWorld.MEMORY_KEY]).is_equal([8, 1, 42, 7])
	var w2 := _world()
	w2.state.player(1).knowledge = host.player(1).knowledge.duplicate(true)
	w2._load_memory()
	assert_int(w2.memory[2]).is_equal(42)
	assert_int(w2.memory[5]).is_equal(0)
	# unchanged, no order; emptied, the order clears it
	assert_dict(w2.memory_order()).is_empty()
	w2.memory[0] = ClassicWorld.MEMORY_FIRST
	o = w2.memory_order()
	assert_array(o["words"]).is_empty()
	assert_str(OrderRules.apply(host, _content, 1, o)).is_empty()
	assert_bool(host.player(1).knowledge.has(ClassicWorld.MEMORY_KEY)).is_false()
	(
		assert_str(OrderRules.apply(host, _content, 1, {"type": "ai_memory", "words": [70000]}))
		. is_not_empty()
	)
