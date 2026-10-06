class_name MessagesPane
extends PanelContainer
## The Messages pane (D15): a raised title bar with the filter box and "Year: 2400*  Messages:
## 1 of 3" (* while there are unsaved changes), the message in large text, and Prev, Goto and Next
## in a column on the right (Shift+Prev / Shift+Next jump to the first / last). It shows the
## player's turn messages (S21, from the game state, in our wording) and then the notes the UI
## adds (a save, orders the host rejected).
##
## Filters (S21 "Filters"): the box at the left of the title bar shows whether the current
## message's type is shown (a blue check) or filtered out (a red X); clicking it changes that for
## the type (and the types filtered with it) for the rest of the game. Prev and Next skip filtered
## messages. While any of this year's messages is filtered, a magnifying glass at the right of the
## title bar switches between hiding them (a minus) and showing them too (a plus).

## Goto: what the current message is about ({"planet": id}, {"fleet": n, "owner": p},
## {"research": true}, {"hulls": true}, {"item": id}).
signal goto_target(goto: Dictionary)

const TEXT_SIZE := 16
const BUTTON_WIDTH := 64
const ICON_SIZE := Vector2(18, 18)
const CHECK_COLOR := Color("0000ff")
const CROSS_COLOR := Color("ff0000")
const GLASS_COLOR := Color("000000")
const WATERMARK_COLOR := Color("ffffff")
const WATERMARK := "FILTERED"
const WATERMARK_SIZE := 40
const SEE_FILTERED := " Click the magnifying glass to see them."
const FILTERED_TEXT := "Messages of this kind are now filtered out." + SEE_FILTERED
const ALL_FILTERED_TEXT := "All of this year's messages are filtered out." + SEE_FILTERED

## Index of the message shown; -1 when every message is filtered out.
var current: int = 0
## Filtered messages are shown too (the magnifying glass with a plus).
var show_all: bool = false

## The UI's own notes, after the turn messages: {text, goto}.
var _notes: Array[Dictionary] = []
## messages() as of the last refresh.
var _list: Array[Dictionary] = []
var _header: Label
var _filter: Button
var _glass: Button
var _watermark: Control
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
	_filter = _icon_button(bar_row, _draw_filter, _toggle_filter)
	_header = Label.new()
	_header.theme_type_variation = "BoldLabel"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(_header)
	_glass = _icon_button(bar_row, _draw_glass, toggle_show_all)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "TileBody"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.clip_contents = true
	row.add_child(frame)
	_watermark = Control.new()
	_watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_watermark.draw.connect(_draw_watermark)
	frame.add_child(_watermark)
	_text = Label.new()
	_text.theme_type_variation = "BoldLabel"
	_text.add_theme_font_size_override("font_size", TEXT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# long text is clipped rather than making the pane taller
	_text.clip_text = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_text)
	var column := VBoxContainer.new()
	row.add_child(column)
	_prev = _button(column, "Prev", func() -> void: _step(-1))
	_goto = _button(column, "Goto", _on_goto)
	_next = _button(column, "Next", func() -> void: _step(1))
	GameSession.changed.connect(_show)
	_list = messages()
	current = _first()
	_show()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _icon_button(parent: Control, painter: Callable, action: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = ICON_SIZE
	b.draw.connect(painter.bind(b))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## A new year: the first message that is not filtered out, the UI's notes dropped.
func new_year() -> void:
	_notes.clear()
	show_all = false
	_list = messages()
	current = _first()
	_show()


## Adds a note of the UI's own after the turn messages; `goto` as for messages.
func add(text: String, goto: Dictionary = {}) -> void:
	_notes.append({"text": text, "goto": goto, "type": ""})
	_list = messages()
	if current < 0:
		current = _list.size() - 1
	_show()


## Every message, filtered or not: the turn messages ({text, goto, type}), then the notes (type "").
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
							"type": m["type"],
						}
					)
				)
	out.append_array(_notes)
	return out


## The message types filtered out.
func filters() -> Array[String]:
	if not GameSession.has_game():
		return []
	return GameSession.view.state.player(GameSession.view.player).message_filters


## Whether message `index` is of a type filtered out (notes never are).
func is_filtered(index: int) -> bool:
	return index >= 0 and index < _list.size() and filters().has(_list[index]["type"])


## Switches between hiding and also showing the filtered messages. Turning it on goes to the next
## filtered message; turning it off leaves a filtered message for the next one that is not.
func toggle_show_all() -> void:
	show_all = not show_all
	if current < 0 or is_filtered(current) != show_all:
		var to := _next_index(current, true)
		if to < 0:
			to = _prev_index(current, true)
		current = to
	_show()


## Filters out the current message's type (with the types filtered with it), or shows it again.
## The message stays on screen.
func _toggle_filter() -> void:
	if current < 0 or current >= _list.size() or _list[current]["type"] == "":
		return
	var type: String = _list[current]["type"]
	var group := _group_of(type)
	var now := filters().duplicate()
	var filtering := not now.has(type)
	for t in group:
		now.erase(t)
		if filtering:
			now.append(t)
	now.sort()
	GameSession.set_order({"type": "message_filters", "filtered": now})


## `type` and the types filtered with it (the same `filter_group`).
func _group_of(type: String) -> Array[String]:
	var content := GameSession.content
	var group: String = content.get_def("message", type).get("filter_group", "")
	var out: Array[String] = [type]
	if group.is_empty():
		return out
	for id in content.ids("message"):
		if id != type and content.get_def("message", id).get("filter_group", "") == group:
			out.append(id)
	return out


## The first message to show this year: the first one not filtered out, or -1.
func _first() -> int:
	return _next_index(-1, false)


## The next message after `from`: any while showing all (unless `matching`), otherwise the next
## whose filtered state is `show_all`; -1 when there is none.
func _next_index(from: int, matching: bool) -> int:
	for i in range(from + 1, _list.size()):
		if (show_all and not matching) or is_filtered(i) == show_all:
			return i
	return -1


func _prev_index(from: int, matching: bool) -> int:
	if from < 0:
		return -1
	for i in range(from - 1, -1, -1):
		if (show_all and not matching) or is_filtered(i) == show_all:
			return i
	return -1


func _step(direction: int) -> void:
	var to := current
	if Input.is_key_pressed(KEY_SHIFT):
		var step := _next_index(-1, false) if direction < 0 else _last()
		to = step if step >= 0 else to
	else:
		var step := _next_index(current, false) if direction > 0 else _prev_index(current, false)
		to = step if step >= 0 else to
	current = to
	_show()


func _last() -> int:
	var last := -1
	var i := _next_index(-1, false)
	while i >= 0:
		last = i
		i = _next_index(i, false)
	return last


func _on_goto() -> void:
	if current >= 0 and current < _list.size() and not _goto.disabled:
		goto_target.emit(_list[current]["goto"])


## Whether any of this year's messages is filtered (the magnifying glass is shown).
func _any_filtered() -> bool:
	for i in _list.size():
		if is_filtered(i):
			return true
	return false


func _show() -> void:
	if _header == null:
		return
	_list = messages()
	var list := _list
	var count := list.size()
	current = clampi(current, -1, count - 1)
	if current < 0 and count > 0:
		current = _first()
	var year := ""
	if GameSession.has_game():
		year = "Year: %d%s   " % [GameSession.view.year(), "*" if GameSession.dirty else ""]
	if count == 0:
		_header.text = year + "Messages: (none)"
	else:
		_header.text = year + "Messages: %d of %d" % [current + 1, count]
	if not _any_filtered():
		show_all = false
	var filtered := is_filtered(current)
	if current < 0:
		_text.text = ALL_FILTERED_TEXT if count > 0 else ""
	elif filtered and not show_all:
		_text.text = FILTERED_TEXT
	else:
		_text.text = list[current]["text"]
	_filter.visible = current >= 0 and list[current]["type"] != ""
	_filter.tooltip_text = (
		"Messages of this kind are filtered out. Click to show them again."
		if filtered
		else "Click to filter out messages of this kind."
	)
	_glass.visible = _any_filtered()
	_glass.tooltip_text = (
		"Showing the filtered messages too. Click to hide them."
		if show_all
		else "Click to show the filtered messages too."
	)
	_prev.disabled = _prev_index(current, false) < 0
	_next.disabled = _next_index(current, false) < 0
	_goto.disabled = (
		current < 0
		or (filtered and not show_all)
		or (list[current]["goto"] as Dictionary).is_empty()
	)
	_filter.queue_redraw()
	_glass.queue_redraw()
	_watermark.queue_redraw()


## The filter box: a blue check (shown) or a red X (filtered out).
func _draw_filter(b: Button) -> void:
	var r := Rect2(Vector2.ZERO, b.size).grow(-4)
	if is_filtered(current):
		b.draw_line(r.position, r.end, CROSS_COLOR, 2.0)
		b.draw_line(
			Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), CROSS_COLOR, 2.0
		)
	else:
		var points := PackedVector2Array(
			[
				r.position + Vector2(0, r.size.y * 0.55),
				r.position + Vector2(r.size.x * 0.4, r.size.y),
				r.position + Vector2(r.size.x, 0),
			]
		)
		b.draw_polyline(points, CHECK_COLOR, 2.0)


## The magnifying glass: a minus while filtered messages are hidden, a plus while shown.
func _draw_glass(b: Button) -> void:
	var radius := b.size.y * 0.28
	var centre := Vector2(radius + 3, radius + 3)
	b.draw_arc(centre, radius, 0, TAU, 24, GLASS_COLOR, 1.5)
	var handle := centre + Vector2(radius, radius) * 0.7
	b.draw_line(handle, Vector2(b.size.x - 2, b.size.y - 2), GLASS_COLOR, 2.5)
	var arm := radius * 0.55
	b.draw_line(centre - Vector2(arm, 0), centre + Vector2(arm, 0), GLASS_COLOR, 1.5)
	if show_all:
		b.draw_line(centre - Vector2(0, arm), centre + Vector2(0, arm), GLASS_COLOR, 1.5)


## "FILTERED" across the message area, behind the text, while a filtered message (or none) shows.
func _draw_watermark() -> void:
	var count := _list.size()
	if count == 0 or (current >= 0 and not (is_filtered(current) and show_all)):
		return
	var font := get_theme_default_font()
	var area := _watermark.size
	var width := font.get_string_size(WATERMARK, HORIZONTAL_ALIGNMENT_LEFT, -1, WATERMARK_SIZE).x
	_watermark.draw_set_transform(area / 2, -atan2(area.y, area.x))
	_watermark.draw_string(
		font,
		Vector2(-width / 2, WATERMARK_SIZE / 3.0),
		WATERMARK,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		WATERMARK_SIZE,
		WATERMARK_COLOR
	)
	_watermark.draw_set_transform(Vector2.ZERO)
