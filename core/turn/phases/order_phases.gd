class_name OrderPhases
extends RefCounted
## Order phases (spec S02 2).


## 2: every player's orders, players in index order (S11).
class Apply:
	extends Phase

	func _init() -> void:
		super("orders.apply")

	func run(ctx: TurnContext) -> void:
		ctx.rejected_orders = OrderRules.apply_all(ctx.state, ctx.content, ctx.orders)
