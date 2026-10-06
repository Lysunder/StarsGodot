class_name MergeDialog
extends ConfirmationDialog
## Merge Fleets (D15, the original's layout): "Select the fleets to merge" over a list of the
## player's other fleets at the same place, any number selected, with OK, Cancel, Select All and
## Unselect All in a column on the right. OK sends one `fleet_merge` order (S11).

signal merge_chosen(fleets: Array[int])

const LIST_SIZE := Vector2(220, 200)

var _list: ItemList
var _numbers: Array[int] = []


func _ready() -> void:
	title = "Merge Fleets"
	ok_button_text = "OK"
	var row := HBoxContainer.new()
	add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	var label := Label.new()
	label.text = "Select the fleets to merge:"
	left.add_child(label)
	_list = ItemList.new()
	_list.select_mode = ItemList.SELECT_TOGGLE
	_list.custom_minimum_size = LIST_SIZE
	left.add_child(_list)
	var column := VBoxContainer.new()
	row.add_child(column)
	column.add_child(Control.new())
	for spec: Array in [["Select All", true], ["Unselect All", false]]:
		var b := Button.new()
		b.text = spec[0]
		var on: bool = spec[1]
		b.pressed.connect(
			func() -> void:
				for i in _list.item_count:
					if on:
						_list.select(i, false)
					else:
						_list.deselect(i)
		)
		column.add_child(b)
	confirmed.connect(_on_ok)


## Opens the window for the fleets `numbers` (with their names).
func open(numbers: Array[int], names: PackedStringArray) -> void:
	_numbers = numbers
	_list.clear()
	for name in names:
		_list.add_item(name)
	popup_centered()


func _on_ok() -> void:
	var chosen: Array[int] = []
	for i in _list.get_selected_items():
		chosen.append(_numbers[i])
	if not chosen.is_empty():
		merge_chosen.emit(chosen)
