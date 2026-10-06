class_name RowList
extends ScrollContainer
## A list in the original's style (D15): a white sunken box of rows, each with text on the left and
## an optional value right-aligned, in a colour of its own, optionally in italics, and optionally
## with a coloured bar behind the text (a damaged ship's share). The selected row is navy with
## white text. Fleet Composition, Fleet Waypoints and the production queues use it.

signal row_selected(index: int)
signal row_activated(index: int)
## Any other key pressed while the list has focus (Delete for waypoints).
signal key_pressed(keycode: Key)

const PAD := 3
## How far italic text leans (FontVariation skew).
const ITALIC_SKEW := 0.2

## Each row: {left, right, colour, italic, bar (0..1), bar_colour}; only `left` is needed.
var rows: Array[Dictionary] = []
var selected: int = -1
## Optional drag and drop: `drag_payload(row) -> Variant` starts a drag from a row (null: none);
## `drop_check(data) -> bool` and `drop_take(data)` accept drops on the list.
var drag_payload := Callable()
var drop_check := Callable()
var drop_take := Callable()

var _canvas: _Rows


class _Rows:
	extends Control

	var owner_list: RowList

	func _draw() -> void:
		owner_list.draw_rows(self)

	func _gui_input(event: InputEvent) -> void:
		owner_list.rows_input(event)

	func _get_drag_data(at: Vector2) -> Variant:
		var i := int(at.y / owner_list.row_height())
		if not owner_list.drag_payload.is_valid() or i < 0 or i >= owner_list.rows.size():
			return null
		var data: Variant = owner_list.drag_payload.call(i)
		if data != null:
			var preview := Label.new()
			preview.text = owner_list.rows[i]["left"]
			set_drag_preview(preview)
		return data

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return owner_list.drop_check.is_valid() and owner_list.drop_check.call(data)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		owner_list.drop_take.call(data)


func _init(height: int = 96) -> void:
	custom_minimum_size = Vector2(0, height)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	theme_type_variation = "RowListBox"
	_canvas = _Rows.new()
	_canvas.owner_list = self
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.focus_mode = Control.FOCUS_CLICK
	add_child(_canvas)


## Replaces the rows (keeping the selection when it is still in range).
func set_rows(p_rows: Array[Dictionary], p_selected: int = -2) -> void:
	rows = p_rows
	if p_selected != -2:
		selected = p_selected
	if selected >= rows.size():
		selected = rows.size() - 1
	_canvas.custom_minimum_size = Vector2(0, rows.size() * row_height())
	_canvas.queue_redraw()


func select(index: int) -> void:
	selected = index
	_canvas.queue_redraw()
	if index >= 0 and index < rows.size():
		ensure_visible_row(index)


func ensure_visible_row(index: int) -> void:
	var top := index * row_height()
	if top < scroll_vertical:
		scroll_vertical = top
	elif top + row_height() > scroll_vertical + size.y:
		scroll_vertical = int(top + row_height() - size.y)


func row_height() -> int:
	return int(get_theme_default_font().get_height(get_theme_default_font_size())) + 2


func draw_rows(canvas: Control) -> void:
	var font := get_theme_default_font()
	var italic := FontVariation.new()
	italic.base_font = font
	italic.variation_transform = Transform2D(Vector2(1, ITALIC_SKEW), Vector2(0, 1), Vector2.ZERO)
	var font_size := get_theme_default_font_size()
	var h := row_height()
	var width := canvas.size.x
	for i in rows.size():
		var row: Dictionary = rows[i]
		var top := i * h
		var colour: Color = row.get("colour", ClassicTheme.TEXT)
		if i == selected:
			canvas.draw_rect(Rect2(0, top, width, h), ClassicTheme.NAVY)
			colour = ClassicTheme.TEXT_SELECTED
		elif row.get("bar", 0.0) > 0.0:
			var bar_width: float = width * clampf(row["bar"], 0.0, 1.0)
			canvas.draw_rect(Rect2(0, top, bar_width, h), row.get("bar_colour", Color.RED))
		var face: Font = italic if row.get("italic", false) else font
		var baseline := top + 1 + font.get_ascent(font_size)
		canvas.draw_string(
			face,
			Vector2(PAD, baseline),
			row["left"],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			colour
		)
		var right: String = row.get("right", "")
		if not right.is_empty():
			var w := face.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			canvas.draw_string(
				face,
				Vector2(width - PAD - w, baseline),
				right,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				colour
			)


func rows_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := int(event.position.y / row_height())
		if i >= 0 and i < rows.size():
			select(i)
			row_selected.emit(i)
			if event.double_click:
				row_activated.emit(i)
	elif event is InputEventKey and event.pressed and not rows.is_empty():
		var step := 0
		match event.keycode:
			KEY_UP:
				step = -1
			KEY_DOWN:
				step = 1
			KEY_ENTER, KEY_KP_ENTER:
				if selected >= 0:
					row_activated.emit(selected)
			_:
				key_pressed.emit(event.keycode)
		if step != 0:
			var to := clampi(selected + step, 0, rows.size() - 1)
			if to != selected:
				select(to)
				row_selected.emit(to)
			_canvas.accept_event()
