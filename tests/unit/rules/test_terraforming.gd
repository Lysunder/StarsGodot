extends GdUnitTestSuite
## Spec S10. Humanoid race (ideal 50 on every axis); the test planet is at 40/60/50.

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func _player(levels: Array = [3, 3, 3, 3, 3, 3]) -> Player:
	var p := Player.new()
	p.tech_levels.assign(levels)
	return p


func _planet() -> Planet:
	var pl := Planet.new()
	pl.owner = 0
	pl.population = 250
	pl.environment.assign([40, 60, 50])
	pl.environment_original.assign([40, 60, 50])
	return pl


func test_reach_from_tech_and_total_terraforming() -> void:
	assert_array(Terraforming.reach(_player(), _content)).is_equal([3, 3, 3])
	assert_array(Terraforming.reach(_player([0, 0, 0, 0, 0, 0]), _content)).is_equal([0, 0, 0])
	var tt := _player()
	tt.race.lesser_traits.assign(["trait.lrt.TT"])
	assert_array(Terraforming.reach(tt, _content)).is_equal([5, 5, 5])


func test_targets_improve_and_worsen() -> void:
	var race := Race.new()
	var r: Array[int] = [3, 3, 3]
	var t := Terraforming.targets(_planet(), race, r, true)
	assert_array(t).is_equal([[-1, 57, -1], [43, -1, -1]])
	t = Terraforming.targets(_planet(), race, r, false)
	assert_array(t).is_equal([[37, -1, 47], [-1, 63, -1]])
	assert_int(Terraforming.max_steps(_planet(), _player(), _content)).is_equal(6)


func test_step_takes_the_first_best_axis() -> void:
	var pl := _planet()
	var p := _player()
	assert_bool(Terraforming.step(pl, p.race, p, true, _content)).is_true()
	assert_array(pl.environment).is_equal([41, 60, 50])
	var done := _planet()
	done.environment.assign([50, 50, 50])
	assert_bool(Terraforming.step(done, p.race, p, true, _content)).is_false()


func test_terraform_item_builds_steps() -> void:
	var s := GameState.new()
	var p := _player()
	p.research_percent = 0
	s.players.append(p)
	var pl := _planet()
	pl.population = 1000
	pl.queue.append(QueueItem.new("production_item.terraform", 2))
	s.planets.append(pl)
	var research: Array[int] = [0]
	Production.new(s, _content, StarsRandom.new()).run_planet(pl, research)
	assert_array(pl.environment).is_equal([41, 60, 50])
	assert_array(pl.queue.map(func(q: QueueItem) -> int: return q.count)).is_equal([1])


func test_claim_adjuster_terraforms_at_once() -> void:
	var s := GameState.new()
	var p := _player()
	p.race.primary_trait = "trait.prt.CA"
	s.players.append(p)
	var pl := _planet()
	pl.population = 2000
	s.planets.append(pl)
	var rng := StarsRandom.new()
	var replay := rng.duplicate_stream()
	Terraforming.claim_adjuster(s, _content, rng)
	var orig: Array[int] = [40, 60, 50]
	var a := replay.random(3)
	if orig[a] != 50 and replay.random(10) == 0:
		orig[a] += 1 if orig[a] < 50 else -1
	assert_array(pl.environment_original).is_equal(orig)
	var expected: Array[int] = [mini(orig[0] + 3, 50), maxi(orig[1] - 3, 50), 50]
	assert_array(pl.environment).is_equal(expected)


func _remote_game(friendly: bool, starbase: bool) -> GameState:
	var s := GameState.new()
	for i in 2:
		var p := _player()
		p.index = i
		p.relations.assign(["neutral", "neutral"])
		s.players.append(p)
	if friendly:
		s.players[0].relations[1] = "friend"
	var d := Design.new()
	d.hull = "hull.scout"
	d.parts.assign(
		[
			DesignSlot.new(),
			DesignSlot.new("part.mining_robot.orbital_adjuster", 1),
			DesignSlot.new()
		]
	)
	s.players[0].set_design(d, false)
	var pl := _planet()
	pl.owner = 1
	if starbase:
		pl.starbase = Starbase.new()
	s.planets.append(pl)
	var f := s.add_fleet(0, 512)
	f.planet = 0
	f.add_ships(0, 2)
	return s


func test_remote_terraforming() -> void:
	var race := Race.new()
	var before := Habitability.value([40, 60, 50], race)
	var hostile := _remote_game(false, false)
	Terraforming.remote(hostile, _content)
	assert_int(Habitability.value(hostile.planets[0].environment, race)).is_less(before)
	var friend := _remote_game(true, false)
	Terraforming.remote(friend, _content)
	assert_array(friend.planets[0].environment).is_equal([41, 59, 50])
	var guarded := _remote_game(false, true)
	Terraforming.remote(guarded, _content)
	assert_array(guarded.planets[0].environment).is_equal([40, 60, 50])
