class_name ClassicBrain
extends AiPlayer
## A brain playing one of the original's personalities (spec S22 "The classic world"): it builds
## the player's classic world from its view, lets the personality play on it, and gives the
## orders the personality gave, ending with the working memory for the next turn.

## The personality played (ClassicWorld.ROBOTOIDS ...).
var personality := ""


func _init(p_personality: String) -> void:
	personality = p_personality


func play(ctx: AiContext) -> void:
	var w := ClassicWorld.build(ctx.view.state, ctx.content, ctx.view.player, ctx.rng, personality)
	match personality:
		ClassicWorld.ROBOTOIDS:
			ClassicRobotoids.play(w)
		ClassicWorld.TURINDRONES:
			ClassicTurindrones.play(w)
	var memory := w.memory_order()
	if not memory.is_empty():
		w.order(memory)
	for o: Dictionary in w.orders.orders:
		ctx.order(o)
