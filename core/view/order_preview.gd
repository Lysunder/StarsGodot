class_name OrderPreview
extends RefCounted
## What the player's pending orders do (M11 UI): a copy of the state with the orders applied by
## the same OrderRules the turn generator uses, so the UI shows exactly what the next turn will
## start from. The real state is never changed.

var state: GameState
## One "player P order I: reason" line per rejected order.
var rejected: PackedStringArray = []


static func build(base: GameState, content: ContentRegistry, orders: OrderSet) -> OrderPreview:
	var out := OrderPreview.new()
	out.state = base.copy() as GameState
	var sets: Array[OrderSet] = [orders]
	out.rejected = OrderRules.apply_all(out.state, content, sets)
	return out
