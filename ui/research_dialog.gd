class_name ResearchDialog
extends AcceptDialog
## Research (D15, the original's arrangement): the six fields as radio buttons with their levels on
## the left; on the right the field being researched (its next level, the resources still needed
## and an estimate of the years), the next field to research, the share of resources spent on
## research, and what the next level of the chosen field brings. Every change is a `research`
## order at once; Done closes.

const NEXT_SAME := 6
const NEXT_LOWEST := 7
const COLUMN_WIDTH := 260

var _fields: Array[CheckBox] = []
var _levels: Array[Label] = []
var _group := ButtonGroup.new()
var _next: OptionButton
var _percent: SpinBox
var _title: Label
var _needed: Label
var _time: Label
var _total: Label
var _budget: Label
var _benefits: RowList
var _loading := false


func _ready() -> void:
	title = "Research"
	ok_button_text = "Done"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(COLUMN_WIDTH - 60, 0)
	row.add_child(left)
	left.add_child(_label("Technology", true))
	var grid := GridContainer.new()
	grid.columns = 2
	left.add_child(grid)
	for i in 6:
		var radio := CheckBox.new()
		radio.button_group = _group
		radio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		radio.toggled.connect(
			func(on: bool) -> void:
				if on and not _loading:
					_send()
		)
		grid.add_child(radio)
		_fields.append(radio)
		var level := _label("", true)
		level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(level)
		_levels.append(level)
	left.add_child(_label("", false))
	left.add_child(_label("Resources", true))
	_total = _label("", false)
	left.add_child(_total)
	_budget = _label("", false)
	left.add_child(_budget)
	var percent_row := HBoxContainer.new()
	left.add_child(percent_row)
	percent_row.add_child(_label("Spend on research:", false))
	_percent = SpinBox.new()
	_percent.max_value = 100
	_percent.suffix = "%"
	_percent.value_changed.connect(
		func(_v: float) -> void:
			if not _loading:
				_send()
	)
	percent_row.add_child(_percent)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	row.add_child(right)
	_title = _label("", true)
	right.add_child(_title)
	_needed = _label("", false)
	right.add_child(_needed)
	_time = _label("", false)
	right.add_child(_time)
	right.add_child(_label("", false))
	right.add_child(_label("Next field to research:", true))
	_next = OptionButton.new()
	_next.item_selected.connect(
		func(_i: int) -> void:
			if not _loading:
				_send()
	)
	right.add_child(_next)
	right.add_child(_label("", false))
	right.add_child(_label("Expected research benefits:", true))
	_benefits = RowList.new(120)
	right.add_child(_benefits)


func _label(text: String, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	if bold:
		l.theme_type_variation = "BoldLabel"
	return l


func open() -> void:
	_show()
	popup_centered()


func _show() -> void:
	_loading = true
	var info := GameSession.view.research_info()
	var fields: Array = info["fields"]
	_next.clear()
	for i in fields.size():
		var f: Dictionary = fields[i]
		_fields[i].text = f["name"]
		_levels[i].text = str(f["level"])
		_fields[i].set_pressed_no_signal(i == info["field"])
		_next.add_item(f["name"])
	_next.add_item("Same field")
	_next.add_item("Lowest field")
	_next.select(info["next"])
	_percent.set_value_no_signal(info["percent"])
	var total := GameSession.view.total_resources()
	var budget: int = total * info["percent"] / 100
	_total.text = "Total resources: %s" % CommandPane.thousands(total)
	_budget.text = "For research next year: %s" % CommandPane.thousands(budget)
	var field: Dictionary = fields[info["field"]]
	_title.text = "Researching %s, level %d" % [field["name"], field["level"] + 1]
	var needed: int = maxi(field["cost"] - field["points"], 0)
	_needed.text = "Resources needed: %s" % CommandPane.thousands(needed)
	if budget <= 0:
		_time.text = "Estimated time: never"
	else:
		var years := ceili(float(needed) / budget)
		_time.text = "Estimated time: %d year%s" % [years, "" if years == 1 else "s"]
	var rows: Array[Dictionary] = []
	for name in field["benefits"]:
		rows.append({"left": name})
	if rows.is_empty():
		rows.append({"left": "(nothing new)", "colour": ClassicTheme.TEXT_DISABLED})
	_benefits.set_rows(rows, -1)
	_loading = false


func _send() -> void:
	var field := 0
	for i in _fields.size():
		if _fields[i].button_pressed:
			field = i
	var reason := GameSession.set_order(
		{"type": "research", "percent": int(_percent.value), "field": field, "next": _next.selected}
	)
	if not reason.is_empty():
		push_warning(reason)
	_show()
