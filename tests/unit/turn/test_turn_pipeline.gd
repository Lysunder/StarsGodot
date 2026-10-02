extends GdUnitTestSuite
## The turn pipeline (spec S02; MODDING §7).


class Counter:
	extends Phase

	var log: Array

	func _init(p_id: String, p_log: Array) -> void:
		super(p_id)
		log = p_log

	func run(_ctx: TurnContext) -> void:
		log.append(id)


func test_standard_ids_follow_s02() -> void:
	assert_array(StandardTurn.pipeline().ids()).is_equal(PackedStringArray(StandardTurn.PHASE_IDS))


func test_insert_replace_disable() -> void:
	var log := []
	var p := TurnPipeline.new()
	p.add(Counter.new("a", log))
	p.add(Counter.new("c", log))
	p.insert_before("c", Counter.new("b", log))
	p.insert_after("c", Counter.new("d", log))
	p.replace("a", Counter.new("a2", log))
	p.disable("d")
	assert_array(p.ids()).is_equal(PackedStringArray(["a2", "b", "c", "d"]))
	p.run(TurnContext.new(GameState.new(), null))
	assert_array(log).is_equal(["a2", "b", "c"])
