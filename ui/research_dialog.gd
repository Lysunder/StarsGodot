class_name ResearchDialog
extends AcceptDialog
## Research settings (M11 step 6): the field being researched, the next field, the share of
## resources spent on research, and each field's level and cost. Sends a `research` order.

const NEXT_SAME := 6
const NEXT_LOWEST := 7

var _field: OptionButton
var _next: OptionButton
var _percent: SpinBox
var _levels: Label


func _ready() -> void:
	title = "Research"
	var box := VBoxContainer.new()
	add_child(box)
	_levels = Label.new()
	box.add_child(_levels)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	grid.add_child(_label("Research"))
	_field = OptionButton.new()
	grid.add_child(_field)
	grid.add_child(_label("Next"))
	_next = OptionButton.new()
	grid.add_child(_next)
	grid.add_child(_label("Resources spent (%)"))
	_percent = SpinBox.new()
	_percent.max_value = 100
	grid.add_child(_percent)
	confirmed.connect(_on_confirmed)


func open() -> void:
	var info := GameSession.view.research_info()
	_field.clear()
	_next.clear()
	var lines := PackedStringArray()
	for f: Dictionary in info["fields"]:
		_field.add_item(f["name"])
		_next.add_item(f["name"])
		lines.append(
			"%s: level %d (%d of %d points)" % [f["name"], f["level"], f["points"], f["cost"]]
		)
	_next.add_item("Same field")
	_next.add_item("Lowest field")
	_levels.text = "\n".join(lines)
	_field.select(info["field"])
	_next.select(info["next"])
	_percent.value = info["percent"]
	popup_centered()


func _on_confirmed() -> void:
	var reason := (
		GameSession
		. set_order(
			{
				"type": "research",
				"percent": int(_percent.value),
				"field": _field.selected,
				"next": _next.selected,
			}
		)
	)
	if not reason.is_empty():
		push_warning(reason)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
