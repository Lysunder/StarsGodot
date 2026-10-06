class_name SplitDialog
extends ConfirmationDialog
## Split Fleet (D15): one row per ship design with how many stay and how many go to the new
## fleet, and arrow buttons that move one ship (Shift: ten, Ctrl: all) between the two. OK sends a
## `fleet_split` and a `fleet_move_ships` order (S11).

signal split_chosen(ships: Array)

const STEP_SHIFT := 10

var _grid: GridContainer
## Per row: {design, total, moved, label_keep, label_new}.
var _rows: Array[Dictionary] = []


func _ready() -> void:
	title = "Split Fleet"
	ok_button_text = "OK"
	var box := VBoxContainer.new()
	add_child(box)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 8)
	box.add_child(_grid)
	confirmed.connect(_on_ok)


## Opens the window for a fleet's ships: [{design, name, count}].
func open(fleet_name: String, ships: Array) -> void:
	for child in _grid.get_children():
		child.queue_free()
	_rows.clear()
	for heading in ["", fleet_name, "", "", "New fleet"]:
		var l := Label.new()
		l.text = heading
		l.theme_type_variation = "BoldLabel"
		_grid.add_child(l)
	for s: Dictionary in ships:
		var row := {"design": s["design"], "total": s["count"], "moved": 0}
		var name := Label.new()
		name.text = s["name"]
		_grid.add_child(name)
		var keep := Label.new()
		keep.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(keep)
		row["label_keep"] = keep
		for spec: Array in [["<", -1], [">", 1]]:
			var b := Button.new()
			b.text = spec[0]
			var direction: int = spec[1]
			b.pressed.connect(func() -> void: _move(row, direction))
			_grid.add_child(b)
		var moved := Label.new()
		_grid.add_child(moved)
		row["label_new"] = moved
		_rows.append(row)
		_show(row)
	popup_centered()
	reset_size()


func _move(row: Dictionary, direction: int) -> void:
	var step := 1
	if Input.is_key_pressed(KEY_CTRL):
		step = row["total"]
	elif Input.is_key_pressed(KEY_SHIFT):
		step = STEP_SHIFT
	row["moved"] = clampi(row["moved"] + direction * step, 0, row["total"])
	_show(row)


func _show(row: Dictionary) -> void:
	(row["label_keep"] as Label).text = str(row["total"] - row["moved"])
	(row["label_new"] as Label).text = str(row["moved"])


func _on_ok() -> void:
	var ships := []
	var left := 0
	for row in _rows:
		left += row["total"] - row["moved"]
		if row["moved"] > 0:
			ships.append({"design": row["design"], "count": row["moved"]})
	if not ships.is_empty() and left > 0:
		split_chosen.emit(ships)
