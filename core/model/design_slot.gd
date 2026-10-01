class_name DesignSlot
extends ModelObject
## What one hull slot of a design holds: a part content id ("" = empty) and how many.

var part: String = ""
var count: int = 0


func _init(p_part: String = "", p_count: int = 0) -> void:
	part = p_part
	count = p_count


func _schema() -> Array:
	return [
		["part", Kind.STRING],
		["count", Kind.INT],
	]
