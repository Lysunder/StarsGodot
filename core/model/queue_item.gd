class_name QueueItem
extends ModelObject
## One entry of a planet's production queue (spec S09): a standard item (content id of a
## `production_item`) or a design (ship or starbase slot), how many, and the progress of the
## first unit in percent of its cost.

## Content id of a production item; "" for a design.
var item: String = ""
## Design slot for a design item; -1 for a standard item.
var design: int = -1
var starbase: bool = false
var count: int = 0
## 0..100: percent of one unit's cost already paid.
var progress: int = 0


func _init(p_item: String = "", p_count: int = 0) -> void:
	item = p_item
	count = p_count


static func of_design(slot: int, is_starbase: bool, p_count: int) -> QueueItem:
	var q := QueueItem.new("", p_count)
	q.design = slot
	q.starbase = is_starbase
	return q


func is_design() -> bool:
	return item.is_empty()


func _schema() -> Array:
	return [
		["item", Kind.STRING],
		["design", Kind.INT],
		["starbase", Kind.BOOL],
		["count", Kind.INT],
		["progress", Kind.INT],
	]
