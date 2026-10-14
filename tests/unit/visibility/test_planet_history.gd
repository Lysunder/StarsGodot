extends GdUnitTestSuite
## S15 "Planet history": what a player keeps of each planet from its sightings. (The rules were
## checked against the original's history files of an 80-turn, 6-player harness game: every
## record of players 1-5 matches.)

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


## tiny3ai turn 1: three players, each with a homeworld.
func _state() -> GameState:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/golden/tiny3ai/t001.json")
	var result := SaveFile.decode(text, _content)
	assert_bool(result.ok()).override_failure_message("\n".join(result.errors)).is_true()
	var s := result.state
	s.views.clear()
	for p in s.players:
		s.views.append({"planets": {}})
		p.knowledge = {}
	return s


func _seen(s: GameState, p: int, planet: int, level: int) -> void:
	s.views[p]["planets"] = {str(planet): level}
	PlanetHistory.note(s, p)


func _record(s: GameState, p: int, planet: int) -> Dictionary:
	return s.player(p).knowledge["planets"].get(str(planet), {})


func test_own_planets_are_recorded_scanned() -> void:
	var s := _state()
	PlanetHistory.note_all(s)
	var home := s.planet(s.player(0).homeworld)
	var r := _record(s, 0, home.id)
	assert_int(r["detail"]).is_equal(PlanetHistory.SCANNED)
	assert_int(r["owner"]).is_equal(0)
	assert_bool(r["homeworld"]).is_true()
	assert_int(r["turn"]).is_equal(s.turn)
	assert_array(r["environment"]).is_equal(Array(home.environment))
	assert_int(r["population_estimate"]).is_equal(home.population_estimate)
	assert_int(r["starbase_design"]).is_equal(home.starbase.design)
	# planets never seen have no record
	assert_int(s.player(0).knowledge["planets"].size()).is_equal(1)


func test_a_glimpse_keeps_the_scanned_values() -> void:
	var s := _state()
	var other := s.planet(s.player(1).homeworld)
	_seen(s, 0, other.id, 3)
	var scanned := _record(s, 0, other.id)
	assert_int(scanned["population_estimate"]).is_equal(other.population_estimate)
	# later: the planet changes, and is only glimpsed (a fleet without scanners in orbit)
	s.turn += 5
	other.environment[0] += 1
	other.population_estimate += 7
	_seen(s, 0, other.id, 1)
	var r := _record(s, 0, other.id)
	assert_int(r["turn"]).is_equal(s.turn)
	assert_int(r["detail"]).is_equal(PlanetHistory.SCANNED)
	assert_int(r["environment"][0]).is_equal(other.environment[0] - 1)
	assert_int(r["population_estimate"]).is_equal(other.population_estimate - 7)
	# scanned again: the values follow
	_seen(s, 0, other.id, 3)
	assert_int(_record(s, 0, other.id)["population_estimate"]).is_equal(other.population_estimate)


func test_a_glimpse_alone_has_no_values() -> void:
	var s := _state()
	var other := s.planet(s.player(2).homeworld)
	_seen(s, 0, other.id, 1)
	var r := _record(s, 0, other.id)
	assert_int(r["detail"]).is_equal(1)
	assert_int(r["owner"]).is_equal(2)
	assert_int(r["starbase_design"]).is_equal(other.starbase.design)
	assert_bool(r.has("environment")).is_false()


func test_hidden_starbase_and_unowned_estimates() -> void:
	var s := _state()
	var other := s.planet(s.player(1).homeworld)
	_seen(s, 0, other.id, PlanetHistory.STARBASE_HIDDEN)
	var r := _record(s, 0, other.id)
	assert_int(r["detail"]).is_equal(PlanetHistory.SCANNED)
	assert_int(r["starbase_design"]).is_equal(-1)
	# the planet empties: an unowned sighting keeps the last estimates
	var before: int = r["population_estimate"]
	other.owner = -1
	other.starbase = null
	other.population_estimate = 0
	_seen(s, 0, other.id, 3)
	r = _record(s, 0, other.id)
	assert_int(r["owner"]).is_equal(-1)
	assert_int(r["population_estimate"]).is_equal(before)
