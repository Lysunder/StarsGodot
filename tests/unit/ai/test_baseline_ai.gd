extends GdUnitTestSuite
## M12 step 2: the baseline brain (S22 "The baseline brain") plays tiny3ai's two computer players:
## it expands, its orders are all accepted, and the same game plays out the same way twice.

const TURNS := 25

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _state() -> GameState:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/golden/tiny3ai/t000.json")
	var result := SaveFile.decode(text, _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	# tiny3ai's computer players are Robotoids; these tests play them with the baseline brain
	for p in result.state.players:
		if not p.is_human():
			p.ai_personality = {"name": "Baseline", "brain": AiBrains.BASELINE}
	return result.state


## Plays `turns` turns with only the computer players giving orders; returns the rejected orders.
func _play(s: GameState, turns: int) -> PackedStringArray:
	var rejected := PackedStringArray()
	for t in turns:
		var given: Array[OrderSet] = []
		var problems := PackedStringArray()
		var sets := ComputerPlayers.add_orders(s, _content, given, problems)
		rejected.append_array(problems)
		rejected.append_array(StandardTurn.generate(s, _content, sets))
	return rejected


func _planets(s: GameState, p: int) -> int:
	return s.planets.filter(func(pl: Planet) -> bool: return pl.owner == p).size()


func test_computer_players_expand_without_rejected_orders() -> void:
	var s := _state()
	assert_str(ComputerPlayers.personality_for(s.players[1], _content)["brain"]).is_equal(
		AiBrains.BASELINE
	)
	var rejected := _play(s, TURNS)
	assert_array(Array(rejected)).is_empty()
	for p in [1, 2]:
		assert_int(_planets(s, p)).is_greater_equal(4)
		# research is on and the designs were brought up to date
		assert_int(s.player(p).research_percent).is_equal(15)
	# the idle human player stays at home
	assert_int(_planets(s, 0)).is_equal(1)


func test_same_game_same_play() -> void:
	var a := _state()
	var b := _state()
	_play(a, 10)
	_play(b, 10)
	assert_bool(a.equals(b)).is_true()


func test_designs_use_the_best_parts() -> void:
	var s := _state()
	s.player(1).tech_levels.assign([0, 0, 0, 0, 0, 0])
	var view := PlayerView.new(s, _content, 1)
	var designs := BaselineDesigns.new(view, _content)
	var scout := designs.build(BaselineDesigns.SCOUT)
	assert_object(scout).is_not_null()
	assert_str(PartRules.design_problem(scout, false, s.player(1), _content)).is_empty()
	assert_int(designs.merit(scout)[0]).is_greater(0)
	var colony := designs.build(BaselineDesigns.COLONY)
	assert_object(colony).is_not_null()
	var parts: Array = colony.parts.map(func(slot: DesignSlot) -> String: return slot.part)
	assert_array(parts).contains(["part.mechanical.colonization_module"])
	# a warp-10-safe engine (propulsion 11): a faster scout
	assert_int(designs.merit(scout)[0]).is_equal(9)
	s.player(1).tech_levels[PartRules.tech_order(_content)["tech_field.propulsion"]] = 11
	assert_bool(designs.better(designs.build(BaselineDesigns.SCOUT), scout)).is_true()


func test_war_designs_and_docks() -> void:
	var s := _state()
	s.player(1).tech_levels.assign([6, 8, 6, 9, 6, 6])
	var view := PlayerView.new(s, _content, 1)
	var designs := BaselineDesigns.new(view, _content)
	var warship := designs.build(BaselineDesigns.WARSHIP)
	assert_object(warship).is_not_null()
	assert_str(warship.hull).is_equal("hull.cruiser")
	assert_bool(designs.is_armed(warship)).is_true()
	assert_int(designs.strength(warship)).is_greater(0)
	var bomber := designs.build(BaselineDesigns.BOMBER)
	assert_object(bomber).is_not_null()
	assert_int(designs.bomb_power(bomber)).is_greater(0)
	assert_bool(designs.is_armed(bomber)).is_false()
	# without Improved Starbases the only hull that docks is the Space Station
	assert_str(designs.cheapest_dock_hull()).is_equal("hull.space_station")
	var dock := designs.build(BaselineDesigns.DOCK)
	assert_bool(designs.is_dock(dock)).is_true()


## Past the year war starts: warships and bombers are built, still with no order rejected.
func test_computer_players_arm() -> void:
	var s := _state()
	assert_array(Array(_play(s, 60))).is_empty()
	for p in [1, 2]:
		var view := PlayerView.new(s, _content, p)
		var designs := BaselineDesigns.new(view, _content)
		var armed := 0
		for fleet in s.fleets_of(p):
			for stack in fleet.stacks:
				if designs.is_armed(s.player(p).ship_design(stack.design)):
					armed += stack.count
		assert_int(armed).is_greater(0)


## Troops for an invasion (S17 "Ground combat"): enough for the top of the population estimate
## after the defenses, with a margin; none for a race that can't invade.
func test_troops_needed() -> void:
	var s := _state()
	var brain := BaselineAi.new()
	brain._ctx = AiContext.new(PlayerView.new(s, _content, 1), _content, StarsRandom.new(), {}, 1)
	brain._me = s.player(1)
	var strength := RaceMath.trait_param(s.player(1).race, _content, "invasion.troops_pct", 100)
	var bare: int = brain._troops_needed({"population": 400, "defense_estimate": 0})
	# 400 units, 450 at the top of the estimate, beaten by 450 x 1.3 x 100 / strength
	assert_int(bare).is_equal(
		450 * 100 * 100 * BaselineAi.TROOP_MARGIN_PCT / 100 / (strength * 100) + 1
	)
	assert_int(bare * strength / 100).is_greater(450)
	# defenses let fewer troops through: more are needed
	var defended: int = brain._troops_needed({"population": 400, "defense_estimate": 10})
	assert_int(defended).is_greater(bare)


## The brain of player `index` with its turn's working state, ready for the helpers.
func _brain(s: GameState, index: int) -> BaselineAi:
	var brain := BaselineAi.new()
	brain._ctx = AiContext.new(
		PlayerView.new(s, _content, index),
		_content,
		StarsRandom.new(),
		{"name": "Baseline", "brain": AiBrains.BASELINE},
		1
	)
	brain._state = s
	brain._me = s.player(index)
	brain._designs = BaselineDesigns.new(brain._ctx.view, _content)
	return brain


func _orders(brain: BaselineAi, type: String) -> Array:
	return brain._ctx.orders.orders.filter(func(o: Dictionary) -> bool: return o["type"] == type)


## Relations (S22 "The baseline brain" step 1): with alliances the other computer player is a
## friend; a battle between the two makes it an enemy for good, kept in the working memory.
func test_relations() -> void:
	var s := _state()
	s.settings.computer_alliances = true
	var brain := _brain(s, 1)
	brain._update_relations()
	assert_array(_orders(brain, "player_relations")[0]["relations"]).is_equal(
		["enemy", "neutral", "friend"]
	)
	assert_array(_orders(brain, "ai_memory")).is_empty()
	s.player(1).relations.assign(["enemy", "neutral", "friend"])
	# nothing changes: no order
	brain = _brain(s, 1)
	brain._update_relations()
	assert_array(brain._ctx.orders.orders).is_empty()
	# the two fight: player 2 is an enemy, remembered
	s.battles.append({"id": 0, "players": [1, 2], "planet": -1, "x": 0, "y": 0})
	brain = _brain(s, 1)
	brain._update_relations()
	assert_array(_orders(brain, "player_relations")[0]["relations"]).is_equal(
		["enemy", "neutral", "enemy"]
	)
	assert_array(_orders(brain, "ai_memory")[0]["words"]).is_equal([4, 1 << 2])
	# a year later, with no battle, the memory keeps the enmity
	s.battles.clear()
	s.player(1).relations.assign(["enemy", "neutral", "enemy"])
	s.player(1).knowledge[OrderRules.AI_MEMORY_KEY] = [4, 1 << 2]
	brain = _brain(s, 1)
	brain._update_relations()
	assert_array(brain._ctx.orders.orders).is_empty()
	assert_bool(brain._is_enemy(2)).is_true()


## Enemy strength (step 7): a starbase seen only as a hull counts as armed with the player's own
## best parts; a fleet attacks only by the margin.
func test_enemy_strength() -> void:
	var s := _state()
	s.player(1).tech_levels.assign([6, 8, 6, 9, 6, 6])
	var home := s.planet(s.player(0).homeworld)
	var known: Dictionary = s.player(1).knowledge.get(PlanetHistory.KEY, {})
	known[str(home.id)] = PlanetHistory._merged({}, home, PlanetHistory.SCANNED, s.turn)
	s.player(1).knowledge[PlanetHistory.KEY] = known
	var brain := _brain(s, 1)
	var theirs := brain._enemy_strength(home)
	var station := s.player(0).starbase_design(home.starbase.design)
	assert_int(theirs).is_equal(brain._designs.estimate(station, false))
	assert_int(theirs).is_greater(0)
	# in full the starter starbase is weaker than our parts make it
	assert_int(brain._designs.estimate(station, true)).is_less(theirs)
	assert_bool(brain._strong_enough(theirs * 3 / 2, theirs)).is_true()
	assert_bool(brain._strong_enough(theirs * 3 / 2 - 1, theirs)).is_false()


func test_freighter_designs() -> void:
	var s := _state()
	s.player(1).tech_levels.assign([3, 3, 3, 9, 3, 3])
	var designs := BaselineDesigns.new(PlayerView.new(s, _content, 1), _content)
	var transport := designs.build(BaselineDesigns.TRANSPORT)
	var hauler := designs.build(BaselineDesigns.HAULER)
	assert_str(transport.hull).is_equal("hull.large_freighter")
	assert_str(transport.name).is_equal(BaselineDesigns.NAMES[BaselineDesigns.TRANSPORT])
	assert_str(hauler.name).is_equal(BaselineDesigns.NAMES[BaselineDesigns.HAULER])
	assert_int(designs.cargo(transport)).is_greater(
		int(_content.hull("hull.large_freighter")["cargo"])
	)
