extends GdUnitTestSuite
## The tutorial (Tutorial, TutorialCoach): every step has its text, and doing what a step asks
## moves the coach on, from the welcome to the end.


func test_every_step_has_a_title_and_text() -> void:
	var content := GameSession.content
	for s: Array in Tutorial.STEPS:
		assert_str(content.string_for("tutorial.%s.title" % s[0])).is_not_equal(
			"tutorial.%s.title" % s[0]
		)
		assert_str(content.string_for("tutorial.%s.text" % s[0])).is_not_equal(
			"tutorial.%s.text" % s[0]
		)


func test_doing_each_step_moves_the_coach_on() -> void:
	GameSession.new_game(Tutorial.options())
	GameSession.tutorial = true
	var screen := GameScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var coaches := screen.find_children("*", "TutorialCoach", true, false)
	assert_int(coaches.size()).is_equal(1)
	var coach: TutorialCoach = coaches[0]
	assert_str(Tutorial.step_id(coach.step)).is_equal("welcome")
	coach._advance()
	assert_str(Tutorial.step_id(coach.step)).is_equal("select_home")
	var me := GameSession.view.me()
	coach._advance()
	assert_str(Tutorial.step_id(coach.step)).is_equal("queue")
	var items := [
		QueueItem.new("production_item.auto_factories", 10).to_dict(),
		QueueItem.new("production_item.auto_mines", 10).to_dict(),
	]
	var order := {"type": "production_queue", "planet": me.homeworld, "items": items}
	assert_str(GameSession.add_order(order)).is_empty()
	assert_str(Tutorial.step_id(coach.step)).is_equal("research")
	var research := {"type": "research", "percent": 20, "field": 2, "next": 7}
	assert_str(GameSession.add_order(research)).is_empty()
	assert_str(Tutorial.step_id(coach.step)).is_equal("scout")
	var home := GameSession.view.state.planet(me.homeworld)
	var target := _other_planet(home)
	var scout := _fleet_with(me, "hull.scout")
	assert_str(GameSession.add_order(_waypoint(scout, target, "none"))).is_empty()
	assert_str(Tutorial.step_id(coach.step)).is_equal("colonize")
	var settler := _fleet_with(me, "hull.colony_ship")
	assert_str(GameSession.add_order(_waypoint(settler, target, "colonize"))).is_empty()
	assert_str(Tutorial.step_id(coach.step)).is_equal("generate")
	assert_bool(GameSession.end_turn()).is_true()
	assert_str(Tutorial.step_id(coach.step)).is_equal("messages")
	coach._advance()
	assert_str(Tutorial.step_id(coach.step)).is_equal("colony")
	# a second planet of the player's
	target.owner = GameSession.player
	GameSession._refresh()
	assert_str(Tutorial.step_id(coach.step)).is_equal("done")
	coach._advance()
	await get_tree().process_frame
	assert_bool(GameSession.tutorial).is_false()
	assert_int(screen.find_children("*", "TutorialCoach", true, false).size()).is_equal(0)
	screen.queue_free()
	await get_tree().process_frame


func _fleet_with(me: Player, hull: String) -> Fleet:
	for f in GameSession.view.fleets():
		if not f.stacks.is_empty() and me.ship_design(f.stacks[0].design).hull == hull:
			return f
	return null


func _other_planet(home: Planet) -> Planet:
	for pl in GameSession.state.planets:
		if pl.id != home.id and pl.owner < 0:
			return pl
	return null


func _waypoint(f: Fleet, pl: Planet, task: String) -> Dictionary:
	return {
		"type": "waypoint_add",
		"owner": GameSession.player,
		"fleet": f.number,
		"index": 1,
		"waypoint":
		{
			"x": pl.x,
			"y": pl.y,
			"target": "planet",
			"target_owner": -1,
			"target_id": pl.id,
			"warp": 5,
			"task": task,
			"task_data": {},
		},
	}
