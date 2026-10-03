class_name OrderSet
extends RefCounted
## One player's orders for one turn (spec S11): a list of orders, each a Dictionary with a
## "type" and that type's fields, applied in list order. Order types are defined by OrderRules.

var player: int = 0
## The turn (year - 2400) the orders were given in; they apply when that turn is generated.
var turn: int = 0
var orders: Array[Dictionary] = []


func _init(p_player: int = 0, p_turn: int = 0) -> void:
	player = p_player
	turn = p_turn


func add(order: Dictionary) -> void:
	orders.append(order)


func to_dict() -> Dictionary:
	return {"player": player, "turn": turn, "orders": orders.duplicate(true)}
