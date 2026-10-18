extends GdUnitTestSuite
## S27 "Play by email": turn files hold only what their player knows and refuse damage; order
## submissions are checked against the game, player and year; the host turns the year when every
## human's orders are in; a 3-player game runs 20 years through files alone.

const DIR := "user://test_pbem"
const NAME := "duel"

var _content: ContentRegistry


func before() -> void:
	var r := ModLoader.new().load_mods(FolderModSource.discover("res://content"), [])
	assert_bool(r.ok()).override_failure_message(r.error_text()).is_true()
	_content = r.registry


func before_test() -> void:
	_clear(DIR)


func after() -> void:
	_clear(DIR)


static func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _options(humans: int) -> NewGame.Options:
	var options := NewGame.Options.new()
	options.size = 0
	options.seed = 4321
	options.race = RacePresets.make(_content, "race_preset.default")
	var presets := ["race_preset.warrior", "race_preset.traveler"]
	for i in humans - 1:
		options.opponents.append({"human": true, "race": RacePresets.make(_content, presets[i])})
	options.opponents.append({"ai": "rototills", "level": 1, "personality": {}})
	return options


func test_a_turn_file_holds_only_what_its_player_knows() -> void:
	var host := NewGame.create(_content, _options(2))
	for t in 3:
		var given: Array[OrderSet] = [OrderSet.new(0, host.turn), OrderSet.new(1, host.turn)]
		StandardTurn.generate(host, _content, ComputerPlayers.add_orders(host, _content, given))
	var loaded := TurnFile.decode(TurnFile.encode(host, 0, "id", "t"), _content)
	assert_bool(loaded.ok()).override_failure_message("\n".join(loaded.errors)).is_true()
	var s := loaded.state
	assert_array(Array(StateValidator.validate(s, _content))).is_empty()
	assert_int(loaded.player).is_equal(0)
	# the player's own things are whole
	assert_object(s.player(0).race).is_equal(host.player(0).race)
	assert_dict(s.player(0).knowledge).is_equal(host.player(0).knowledge)
	# of the others only what anyone may know
	var other := s.player(1)
	assert_str(other.race.name).is_equal(host.player(1).race.name)
	assert_str(other.race.primary_trait).is_equal(Race.new().primary_trait)
	assert_dict(other.knowledge).is_empty()
	assert_int(other.research_percent).is_equal(0)
	assert_int(other.homeworld).is_equal(-1)
	assert_array(s.messages[1]).is_empty()
	# other players' fleets only when seen this year; unknown planets blank
	var seen: Dictionary = host.views[0].get("fleets", {})
	for f in s.fleets:
		assert_bool(f.owner == 0 or seen.has("%d/%d" % [f.owner, f.number])).is_true()
	var home := s.planet(host.player(1).homeworld)
	if not host.player(0).knowledge.get(PlanetHistory.KEY, {}).has(str(home.id)):
		assert_int(home.owner).is_equal(-1)
		assert_int(home.population).is_equal(0)
	# nothing to foresee the year with
	assert_dict(s.rng.to_dict()).is_equal(RngStreams.new(0).to_dict())


func test_a_damaged_turn_file_is_refused() -> void:
	var host := NewGame.create(_content, _options(2))
	var text := TurnFile.encode(host, 1, "id", "t")
	var at := text.find('"turn":0')
	assert_int(at).is_greater(0)
	var damaged := text.substr(0, at) + '"turn":1' + text.substr(at + 8)
	var loaded := TurnFile.decode(damaged, _content)
	assert_bool(loaded.ok()).is_false()
	assert_str(loaded.errors[0]).contains("damaged")


func test_the_host_waits_for_every_human() -> void:
	var r := PbemHost.create(DIR, NAME, _options(2), _content, "t")
	assert_bool(r.ok()).override_failure_message("\n".join(r.errors)).is_true()
	assert_bool(FileAccess.file_exists(DIR.path_join("duel-p1.turn"))).is_true()
	assert_bool(FileAccess.file_exists(DIR.path_join("duel-p2.turn"))).is_true()
	assert_bool(PbemHost.create(DIR, NAME, _options(2), _content, "t").ok()).is_false()
	assert_array(PbemHost.status(DIR, _content).waiting).is_equal([0, 1])
	# player 1 plays from their turn file and sends orders back
	var t1 := TurnFile.read(DIR.path_join("duel-p1.turn"), _content)
	var orders := OrderSet.new(t1.player, t1.state.turn)
	orders.add({"type": "research", "percent": 33, "field": 0, "next": Player.NEXT_FIELD_LOWEST})
	OrderSubmission.write(DIR.path_join("duel-p1.orders"), orders, t1.game_id, "t")
	r = PbemHost.generate(DIR, _content, "t")
	assert_bool(r.generated).is_false()
	assert_array(r.waiting).is_equal([1])
	# orders for another game are refused
	var wrong := OrderSet.new(1, 0)
	OrderSubmission.write(DIR.path_join("duel-p2.orders"), wrong, "another", "t")
	r = PbemHost.status(DIR, _content)
	assert_array(r.waiting).is_equal([1])
	assert_str("\n".join(r.lines)).contains("another game")
	OrderSubmission.write(DIR.path_join("duel-p2.orders"), wrong, t1.game_id, "t")
	r = PbemHost.generate(DIR, _content, "t")
	assert_bool(r.generated).override_failure_message("\n".join(r.lines + r.errors)).is_true()
	# the year came with player 1's orders; the orders used are put away
	var game := SaveStore.read(DIR.path_join(PbemHost.GAME_FILE), _content).state
	assert_int(game.turn).is_equal(1)
	assert_int(game.player(0).research_percent).is_equal(33)
	assert_bool(FileAccess.file_exists(DIR.path_join("done/0/duel-p1.orders"))).is_true()
	assert_bool(FileAccess.file_exists(DIR.path_join("duel-p1.orders"))).is_false()
	assert_int(TurnFile.read(DIR.path_join("duel-p2.turn"), _content).state.turn).is_equal(1)
	# with force, the missing orders are none
	assert_bool(PbemHost.generate(DIR, _content, "t", true).generated).is_true()


## M13 "done when", on one machine: three humans and a computer player, 20 years, nothing passing
## between the players and the host but turn files and order files.
func test_three_players_twenty_years_by_files() -> void:
	assert_bool(PbemHost.create(DIR, NAME, _options(3), _content, "t").ok()).is_true()
	for year in 20:
		for p in 3:
			var turn := DIR.path_join("duel-p%d.turn" % (p + 1))
			var t := TurnFile.read(turn, _content)
			assert_bool(t.ok()).override_failure_message("\n".join(t.errors)).is_true()
			assert_int(t.state.turn).is_equal(year)
			var orders := OrderSet.new(p, t.state.turn)
			var percent := 10 + p * 5 + year % 3
			orders.add(
				{
					"type": "research",
					"percent": percent,
					"field": 0,
					"next": Player.NEXT_FIELD_LOWEST
				}
			)
			var path := turn.get_basename() + "." + OrderSubmission.EXTENSION
			OrderSubmission.write(path, orders, t.game_id, "t")
		var r := PbemHost.generate(DIR, _content, "t")
		assert_bool(r.generated).override_failure_message("\n".join(r.lines + r.errors)).is_true()
		var refused := Array(r.lines).filter(func(l: String) -> bool: return l.begins_with("Ref"))
		assert_array(refused).is_empty()
	var game := SaveStore.read(DIR.path_join(PbemHost.GAME_FILE), _content).state
	assert_int(game.turn).is_equal(20)
	assert_int(game.player(2).research_percent).is_equal(20 + 19 % 3)
