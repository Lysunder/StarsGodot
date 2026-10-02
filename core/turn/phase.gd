class_name Phase
extends RefCounted
## One step of turn generation (spec S02), identified by its id. Subclasses override run().

var id: String = ""


func _init(p_id: String = "") -> void:
	id = p_id


func run(_ctx: TurnContext) -> void:
	pass
