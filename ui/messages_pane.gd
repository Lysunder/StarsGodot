class_name MessagesPane
extends PanelContainer
## The Messages pane (D15): a raised title bar with the filter box and "Year: 2400*  Messages:
## 1 of 3" (* while there are unsaved changes), the message in large text, and Prev, Goto and Next
## in a column on the right (Shift+Prev / Shift+Next jump to the first / last). There is no turn
## message system yet (S21): the messages are the notes the UI makes (the new year, orders the
## host rejected), some with an object to go to.

signal goto(kind: String, id: int)

const TEXT_SIZE := 16
const BUTTON_WIDTH := 64

## Each: {text, kind, id}; kind "" when there is nothing to go to.
var messages: Array[Dictionary] = []
var current: int = 0

var _header: Label
var _filter: CheckBox
var _text: Label
var _prev: Button
var _goto: Button
var _next: Button


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var bar := PanelContainer.new()
	bar.theme_type_variation = "TileBar"
	box.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar.add_child(bar_row)
	_filter = CheckBox.new()
	_filter.disabled = true
	_filter.tooltip_text = "Message filters come with the turn messages."
	bar_row.add_child(_filter)
	_header = Label.new()
	_header.theme_type_variation = "BoldLabel"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(_header)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "TileBody"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(frame)
	_text = Label.new()
	_text.theme_type_variation = "BoldLabel"
	_text.add_theme_font_size_override("font_size", TEXT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	frame.add_child(_text)
	var column := VBoxContainer.new()
	row.add_child(column)
	_prev = _button(column, "Prev", func() -> void: _step(-1))
	_goto = _button(column, "Goto", _on_goto)
	_next = _button(column, "Next", func() -> void: _step(1))
	GameSession.changed.connect(_show)
	_show()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func clear() -> void:
	messages.clear()
	current = 0
	_show()


## Adds a message; `kind` and `id` name the object Goto shows ("planet", "fleet").
func add(text: String, kind: String = "", id: int = -1) -> void:
	messages.append({"text": text, "kind": kind, "id": id})
	_show()


func _step(direction: int) -> void:
	if messages.is_empty():
		return
	if Input.is_key_pressed(KEY_SHIFT):
		current = 0 if direction < 0 else messages.size() - 1
	else:
		current = clampi(current + direction, 0, messages.size() - 1)
	_show()


func _on_goto() -> void:
	if current < messages.size() and messages[current]["kind"] != "":
		goto.emit(messages[current]["kind"], messages[current]["id"])


func _show() -> void:
	if _header == null:
		return
	var year := ""
	if GameSession.has_game():
		year = "Year: %d%s" % [GameSession.view.year(), "*" if GameSession.dirty else ""]
	var count := messages.size()
	current = clampi(current, 0, maxi(count - 1, 0))
	_header.text = "%s   Messages: %d of %d" % [year, current + 1 if count > 0 else 0, count]
	_text.text = messages[current]["text"] if count > 0 else ""
	_prev.disabled = current <= 0
	_next.disabled = current >= count - 1
	_goto.disabled = count == 0 or messages[current]["kind"] == ""
