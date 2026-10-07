class_name SpacePhases
extends RefCounted
## Space object phases (spec S02 8, 14).


## 7: minefields' "seen this turn" records start empty (S13).
class MinefieldsReset:
	extends Phase

	func _init() -> void:
		super("minefields.reset")

	func run(ctx: TurnContext) -> void:
		Minefields.reset_all(ctx.state)


## 11: minefields decay (S13); salvage and packets decay (S14, not built yet).
class DecayAndDetonate:
	extends Phase

	func _init() -> void:
		super("space.decay_and_detonate")

	func run(ctx: TurnContext) -> void:
		Minefields.decay_all(ctx.state, ctx.content)


## 14: wormholes shift (S12); packets launched this year move and hit (S14, not built yet).
class MoveAfterProduction:
	extends Phase

	func _init() -> void:
		super("space.move_after_production")

	func run(ctx: TurnContext) -> void:
		Wormholes.shift_all(ctx.state, ctx.rng())
