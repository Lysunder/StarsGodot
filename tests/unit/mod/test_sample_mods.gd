extends GdUnitTestSuite
## Plan M14: the five sample mods in mods/ load with the game and do what they say; script mods load
## only when trusted; the validator passes them and reports what is wrong with a bad one.

const SAMPLES := ["extra_hulls", "fast_growth", "burrowers", "supernova", "retro_text"]


func _load(mods: Array, trust := true) -> ModLoader.LoadResult:
	var sources: Array[ModSource] = FolderModSource.discover("res://content")
	var loader := ModLoader.new()
	var enabled := PackedStringArray()
	for id: String in mods:
		var source := FolderModSource.new("res://mods/" + id)
		sources.append(source)
		enabled.append(id)
		if trust:
			loader.trusted[id] = ModLoader.script_hash(source)
	return loader.load_mods(sources, enabled)


func _core() -> ContentRegistry:
	return _load([]).registry


func test_every_sample_validates() -> void:
	for id: String in SAMPLES:
		var r := ModValidator.validate("res://mods/" + id)
		assert_bool(r.ok()).override_failure_message("\n".join(r.problems)).is_true()
		assert_str(r.mod_id).is_equal(id)


func test_all_samples_load_together() -> void:
	var r := _load(SAMPLES)
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	# the cosmetic one is not a gameplay mod: games record the other four
	assert_int(r.registry.gameplay_mods().size()).is_equal(5)


func test_script_mods_need_trust() -> void:
	var r := _load(["fast_growth"], false)
	assert_bool(r.ok()).is_false()
	assert_str(r.error_text()).contains("trust")
	# data-only mods need none
	assert_bool(_load(["extra_hulls"], false).ok()).is_true()


func test_extra_hulls() -> void:
	var content := _load(["extra_hulls"]).registry
	assert_bool(content.has_def("extra_hulls.hull.bulk_freighter")).is_true()
	assert_str(content.display_name("extra_hulls.hull.picket")).is_equal("Picket")
	var core := _core()
	var cargo: int = core.hull("hull.small_freighter")["cargo"]
	assert_int(content.hull("hull.small_freighter")["cargo"]).is_equal(cargo * 125 / 100)


func test_fast_growth_doubles_gains() -> void:
	var core := _core()
	var fast := _load(["fast_growth"]).registry
	var race := Race.new()
	var planet := Planet.new()
	planet.environment.assign([50, 50, 50])
	planet.population = 100
	var normal := PlanetEconomy.grow(planet, race, core, false)
	assert_int(normal).is_greater(0)
	assert_int(PlanetEconomy.grow(planet, race, fast, false)).is_equal(normal * 2)
	# a hostile planet's losses stay as they were
	planet.environment.assign([0, 0, 0])
	assert_int(PlanetEconomy.grow(planet, race, fast, false)).is_equal(
		PlanetEconomy.grow(planet, race, core, false)
	)


func test_burrowers_dig_minerals() -> void:
	var content := _load(["burrowers"]).registry
	assert_str(content.trait_def("burrowers.trait.burrowers")["kind"]).is_equal("primary")
	var ids := StandardTurn.pipeline(content).ids()
	assert_int(ids.find("burrowers.tunnels")).is_equal(ids.find("production.mining") + 1)
	var race := Race.new()
	race.primary_trait = "burrowers.trait.burrowers"
	assert_int(RaceMath.trait_param(race, content, "planet.max_pop_pct", 100)).is_equal(150)
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 5
	options.race = race
	var s := NewGame.create(content, options)
	var home := s.planet(s.player(0).homeworld)
	var earlier := home.surface.duplicate()
	var ctx := TurnContext.new(s, content, [])
	StandardTurn.pipeline(content).phase("burrowers.tunnels").run(ctx)
	for m in 3:
		assert_int(home.surface[m]).is_equal(earlier[m] + home.population / 100)


func test_supernova_flares_draw_from_their_own_stream() -> void:
	var content := _load(["supernova"]).registry
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 6
	var s := NewGame.create(content, options)
	var classic := s.rng.get_stream(RngStreams.CLASSIC)
	var classic_before := [classic.s1, classic.s2]
	var phase := StandardTurn.pipeline(content).phase("supernova.flares")
	var ctx := TurnContext.new(s, content, [])
	var flares := 0
	for year in 200:
		var radiation := []
		for pl in s.planets:
			radiation.append(pl.environment[2])
		phase.run(ctx)
		for pl in s.planets:
			if pl.environment[2] != radiation[pl.id]:
				flares += 1
	assert_int(flares).is_between(1, 30)
	# the game's own draws are untouched
	assert_array([classic.s1, classic.s2]).is_equal(classic_before)


func test_retro_text_changes_only_words() -> void:
	var retro := _load(["retro_text"]).registry
	var core := _core()
	assert_str(retro.display_name("hull.scout")).is_equal("Probe")
	assert_str(retro.ruleset_hash).is_equal(core.ruleset_hash)
	assert_array(Array(retro.gameplay_mods())).is_equal(Array(core.gameplay_mods()))


func test_the_validator_reports_a_bad_mod() -> void:
	var r := ModValidator.validate("res://tests/fixtures/mods/bad_script")
	assert_bool(r.ok()).is_false()
	var text := "\n".join(r.problems)
	assert_str(text).contains("bad.gd:10: uses clocks, OS or engine state")
