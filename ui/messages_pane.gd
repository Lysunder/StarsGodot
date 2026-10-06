class_name MessagesPane
extends PanelContainer
## The Messages pane (D15): a raised title bar with the filter box and "Year: 2400*  Messages:
## 1 of 3" (* while there are unsaved changes), the message in large text, and Prev, Goto and Next
## in a column on the right (Shift+Prev / Shift+Next jump to the first / last). It shows the
## player's turn messages (S21, from the game state, in our wording) and then the notes the UI
## adds (a save, orders the host rejected).

## Goto: what the current message is about ({"planet": id}, {"fleet": n, "owner": p},
## {"research": true}, {"hulls": true}, {"item": id}).
signal goto_target(goto: Dictionary)

const TEXT_SIZE := 16
const BUTTON_WIDTH := 64

var current: int = 0

## The UI's own notes, after the turn messages: {text, goto}.
var _notes: Array[Dictionary] = []
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
	_filter.tooltip_text = "Message filters come later."
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
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
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


## A new year: back to the first message, the UI's notes dropped.
func new_year() -> void:
	_notes.clear()
	current = 0
	_show()


## Adds a note of the UI's own after the turn messages; `goto` as for messages.
func add(text: String, goto: Dictionary = {}) -> void:
	_notes.append({"text": text, "goto": goto})
	_show()


## Every message shown: the turn messages, then the notes.
func messages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if GameSession.has_game():
		var view := GameSession.view
		var lists: Array = view.state.messages
		if view.player < lists.size():
			for m: Dictionary in lists[view.player]:
				(
					out
					. append(
						{
							"text": MessageText.format(view, view.player, m),
							"goto": m.get("goto", {}),
						}
					)
				)
	out.append_array(_notes)
	return out


func _step(direction: int) -> void:
	var count := messages().size()
	if count == 0:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		current = 0 if direction < 0 else count - 1
	else:
		current = clampi(current + direction, 0, count - 1)
	_show()


func _on_goto() -> void:
	var list := messages()
	if current < list.size() and not (list[current]["goto"] as Dictionary).is_empty():
		goto_target.emit(list[current]["goto"])


func _show() -> void:
	if _header == null:
		return
	var list := messages()
	var year := ""
	if GameSession.has_game():
		year = "Year: %d%s" % [GameSession.view.year(), "*" if GameSession.dirty else ""]
	var count := list.size()
	current = clampi(current, 0, maxi(count - 1, 0))
	_header.text = "%s   Messages: %d of %d" % [year, current + 1 if count > 0 else 0, count]
	_text.text = list[current]["text"] if count > 0 else ""
	_prev.disabled = current <= 0
	_next.disabled = current >= count - 1
	_goto.disabled = count == 0 or (list[current]["goto"] as Dictionary).is_empty()
