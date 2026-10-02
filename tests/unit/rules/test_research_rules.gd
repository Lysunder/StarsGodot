extends GdUnitTestSuite
## Spec S05: research costs and the tech update.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _player(levels: Array, lesser: Array[String] = []) -> Player:
	var p := Player.new()
	p.tech_levels.assign(levels)
	p.race.lesser_traits = lesser
	p.research_field = 0
	p.next_research_field = Player.NEXT_FIELD_SAME
	return p


func _state(players: Array[Player]) -> GameState:
	var s := GameState.new()
	for i in players.size():
		players[i].index = i
		s.players.append(players[i])
	return s


func test_level_cost_worked_examples() -> void:
	var p := _player([3, 3, 3, 3, 3, 3])
	assert_int(ResearchRules.level_cost(p, 0, _content, false)).is_equal(390)
	assert_int(ResearchRules.level_cost(p, 0, _content, true)).is_equal(780)
	p.race.research_costs[0] = ResearchRules.EXPENSIVE
	assert_int(ResearchRules.level_cost(p, 0, _content, false)).is_equal(683)
	p.race.research_costs[0] = ResearchRules.CHEAP
	assert_int(ResearchRules.level_cost(p, 0, _content, false)).is_equal(195)


func test_generalized_research_split() -> void:
	var p := _player([0, 0, 0, 0, 0, 0], ["trait.lrt.GR"])
	p.tech_levels.assign([10, 10, 10, 10, 10, 10])
	var spent: Array[int] = [100]
	ResearchRules.update(_state([p]), _content, spent)
	assert_array(p.research_points).is_equal([50, 15, 15, 15, 15, 15])


func test_level_gain_and_switch_to_lowest() -> void:
	var p := _player([3, 3, 3, 3, 3, 1])
	p.next_research_field = Player.NEXT_FIELD_LOWEST
	# energy 3 -> 4 costs 210 + 160 = 370; 30 points are left over
	var spent: Array[int] = [400]
	ResearchRules.update(_state([p]), _content, spent)
	assert_array(p.tech_levels).is_equal([4, 3, 3, 3, 3, 1])
	assert_int(p.research_field).is_equal(5)
	assert_int(p.next_research_field).is_equal(Player.NEXT_FIELD_LOWEST)
	assert_array(p.research_points).is_equal([0, 0, 0, 0, 0, 30])


func test_switch_to_set_field_then_same() -> void:
	var p := _player([3, 3, 3, 3, 3, 3])
	p.next_research_field = 2
	var spent: Array[int] = [400]
	ResearchRules.update(_state([p]), _content, spent)
	assert_int(p.research_field).is_equal(2)
	assert_int(p.next_research_field).is_equal(Player.NEXT_FIELD_SAME)
	assert_array(p.research_points).is_equal([0, 0, 10, 0, 0, 0])


func test_top_level_drops_new_points() -> void:
	var p := _player([26, 0, 0, 0, 0, 0])
	p.research_points[0] = 7
	var spent: Array[int] = [500]
	ResearchRules.update(_state([p]), _content, spent)
	assert_array(p.research_points).is_equal([7, 0, 0, 0, 0, 0])


func test_spying_shares_half_the_average() -> void:
	var spy := _player([0, 0, 0, 0, 0, 0])
	spy.race.primary_trait = "trait.prt.SS"
	spy.research_field = 1
	var other := _player([0, 0, 0, 0, 0, 0])
	other.research_field = 1
	var third := _player([0, 0, 0, 0, 0, 0])
	third.research_field = 1
	for p in [spy, other, third]:
		p.tech_levels.assign([10, 10, 10, 10, 10, 10])
	var spent: Array[int] = [300, 0, 600]
	ResearchRules.update(_state([spy, other, third]), _content, spent)
	assert_int(spy.research_points[1]).is_equal(300 + 150)
