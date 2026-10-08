class_name SpacePhases
extends RefCounted
## Space object phases (spec S02 7, 8, 11, 14, 17).


## 7: minefields' "seen this turn" records start empty (S13).
class MinefieldsReset:
	extends Phase

	func _init() -> void:
		super("minefields.reset")

	func run(ctx: TurnContext) -> void:
		Minefields.reset_all(ctx.state)


## 8: packets in flight move a full year and hit their targets (S14); the Mystery Trader moves
## (S18, not built yet).
class MoveBeforeFleets:
	extends Phase

	func _init() -> void:
		super("space.move_before_fleets")

	func run(ctx: TurnContext) -> void:
		Packets.move_all(ctx.state, ctx.content, ctx.rng(), false)


## 11: minefields detonate and decay (S13), then packets and salvage decay (S14).
class DecayAndDetonate:
	extends Phase

	func _init() -> void:
		super("space.decay_and_detonate")

	func run(ctx: TurnContext) -> void:
		Minefields.decay_all(ctx.state, ctx.content)
		Packets.decay_all(ctx.state, ctx.content)


## 14: packets launched this year move half a year and may hit (S14), then wormholes shift (S12).
class MoveAfterProduction:
	extends Phase

	func _init() -> void:
		super("space.move_after_production")

	func run(ctx: TurnContext) -> void:
		Packets.move_all(ctx.state, ctx.content, ctx.rng(), true)
		Wormholes.shift_all(ctx.state, ctx.rng())


## 17: fleets and starbases with beam weapons sweep other players' minefields (S13).
class Sweep:
	extends Phase

	func _init() -> void:
		super("minefields.sweep")

	func run(ctx: TurnContext) -> void:
		Minefields.sweep_all(ctx.state, ctx.content)
