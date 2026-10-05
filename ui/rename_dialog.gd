class_name RenameDialog
extends ConfirmationDialog
## A small OK / Cancel window with one text field (D15): it opens with the current name in the
## field, all of it selected, so typing replaces it at once. Enter is OK, Escape is Cancel.

signal name_entered(text: String)

const FIELD_WIDTH := 260

var _field: LineEdit


func _ready() -> void:
	ok_button_text = "OK"
	var box := VBoxContainer.new()
	add_child(box)
	_field = LineEdit.new()
	_field.custom_minimum_size = Vector2(FIELD_WIDTH, 0)
	box.add_child(_field)
	register_text_enter(_field)
	confirmed.connect(func() -> void: name_entered.emit(_field.text.strip_edges()))


## Opens the window titled `p_title` with `current` in the field, selected.
func open(p_title: String, current: String, max_length: int = 0) -> void:
	title = p_title
	_field.max_length = max_length
	_field.text = current
	popup_centered(Vector2i.ZERO)
	reset_size()
	_field.grab_focus()
	_field.select_all()
	_field.caret_column = current.length()
