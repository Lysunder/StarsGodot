class_name Tile
extends VBoxContainer
## A collapsible tile of the Command pane (D15): a navy title bar with the tile's name and a
## collapse button, and a body the tile fills.

var body: VBoxContainer

var _toggle: Button


func _init(title: String) -> void:
	add_theme_constant_override("separation", 0)
	var bar := PanelContainer.new()
	var navy := StyleBoxFlat.new()
	navy.bg_color = ClassicTheme.NAVY
	navy.content_margin_left = 4
	navy.content_margin_right = 2
	bar.add_theme_stylebox_override("panel", navy)
	add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var caption := Label.new()
	caption.text = title
	caption.add_theme_color_override("font_color", ClassicTheme.TEXT_SELECTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	_toggle = Button.new()
	_toggle.text = "–"
	_toggle.custom_minimum_size = Vector2(18, 16)
	_toggle.pressed.connect(func() -> void: set_collapsed(body.visible))
	row.add_child(_toggle)
	var frame := PanelContainer.new()
	add_child(frame)
	body = VBoxContainer.new()
	frame.add_child(body)


func set_collapsed(collapsed: bool) -> void:
	body.get_parent().visible = not collapsed
	body.visible = not collapsed
	_toggle.text = "+" if collapsed else "–"


## A label added to the body.
func line(text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)
	return l


## A button added to `parent` (the body by default).
func button(text: String, action: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	(parent if parent != null else body).add_child(b)
	return b


## A row of controls added to the body.
func row() -> HBoxContainer:
	var r := HBoxContainer.new()
	body.add_child(r)
	return r
