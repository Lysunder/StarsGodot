class_name SpacePhases
extends RefCounted
## Space object phases (spec S02 8, 14).


## 14: wormholes shift (S12); packets launched this year move and hit (S14, not built yet).
class MoveAfterProduction:
	extends Phase

	func _init() -> void:
		super("space.move_after_production")

	func run(ctx: TurnContext) -> void:
		Wormholes.shift_all(ctx.state, ctx.rng())
