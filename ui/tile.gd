class_name Tile
extends VBoxContainer
## A Command pane tile (D15): a raised grey title bar with the tile's title centred in bold and a
## collapse button with an arrow, over a raised body. Dragging the title bar onto another tile
## moves the tile there. A tile's `key` (its kind, e.g. "fleet_cargo") lets the pane remember
## its place and whether it is collapsed while its title changes ("Fleet #2", "Orbiting Cherub").

## The title bar was clicked to collapse or expand the tile.
signal collapse_toggled(key: String, collapsed: bool)
## Another tile was dropped on this one: put tile `from_key` where this one is.
signal tile_dropped(from_key: String, to_key: String)

const BAR_HEIGHT := 20
const TOGGLE_SIZE := Vector2(18, 16)
const VALUE_GAP := 8

var key: String = ""
var body: VBoxContainer
var collapsed: bool = false

var _toggle: Button
var _grid: GridContainer


## The title bar: drags as its tile.
class TitleBar:
	extends PanelContainer

	var tile: Tile

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = tile.title_text()
		preview.theme_type_variation = "BoldLabel"
		set_drag_preview(preview)
		return {"tile": tile.key}


var _caption: Label


func _init(title: String, p_key: String = "") -> void:
	key = p_key if not p_key.is_empty() else title
	add_theme_constant_override("separation", 0)
	var bar := TitleBar.new()
	bar.tile = self
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.theme_type_variation = "TileBar"
	add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	_caption = Label.new()
	_caption.text = title
	_caption.theme_type_variation = "BoldLabel"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caption.clip_text = true
	row.add_child(_caption)
	_toggle = Button.new()
	_toggle.custom_minimum_size = TOGGLE_SIZE
	_toggle.icon = ClassicTheme.collapse_icon(false)
	_toggle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.pressed.connect(
		func() -> void:
			set_collapsed(not collapsed)
			collapse_toggled.emit(key, collapsed)
	)
	row.add_child(_toggle)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "TileBody"
	add_child(frame)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	frame.add_child(body)


func title_text() -> String:
	return _caption.text


func set_collapsed(p_collapsed: bool) -> void:
	collapsed = p_collapsed
	body.get_parent().visible = not collapsed
	_toggle.icon = ClassicTheme.collapse_icon(collapsed)


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("tile") and data["tile"] != key


func _drop_data(_at: Vector2, data: Variant) -> void:
	tile_dropped.emit(data["tile"], key)


## A label added to the body.
func line(text: String = "") -> Label:
	_grid = null
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)
	return l


## A row of the body's label / value table: the label in bold on the left (in `colour` if given),
## the value right-aligned. Consecutive fields share one table.
func field(label: String, value: String, colour: Color = Color()) -> Label:
	if _grid == null or _grid.get_parent() != body or body.get_child(-1) != _grid:
		_grid = GridContainer.new()
		_grid.columns = 2
		_grid.add_theme_constant_override("h_separation", VALUE_GAP)
		_grid.add_theme_constant_override("v_separation", 0)
		body.add_child(_grid)
	var name_label := Label.new()
	name_label.text = label
	name_label.theme_type_variation = "BoldLabel"
	if colour != Color():
		name_label.add_theme_color_override("font_color", colour)
	_grid.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(value_label)
	return value_label


## A labelled gauge row ("Fuel [=====]"), in the label / value table.
func gauge(label: String) -> Gauge:
	field(label, "")
	var spot := _grid.get_child(-1)
	var g := Gauge.new()
	_grid.remove_child(spot)
	spot.queue_free()
	_grid.add_child(g)
	return g


## A button added to `parent` (the body by default).
func button(text: String, action: Callable, parent: Control = null) -> Button:
	if parent == null:
		_grid = null
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	(parent if parent != null else body).add_child(b)
	return b


## A row of controls added to the body.
func row() -> HBoxContainer:
	_grid = null
	var r := HBoxContainer.new()
	body.add_child(r)
	return r
