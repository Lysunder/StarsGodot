class_name HelpWindow
extends Window
## The help (M11 step 11): the topics on the left, the chosen one on the right (HelpText), links
## between topics, and Back to the topic before. The help key (F1 unless changed, KeyBindings) and
## Help > Help Topics open it; Escape closes it.

const SIZE := Vector2i(820, 560)
const LIST_WIDTH := 210

var topic: String = ""

var _list: ItemList
var _text: RichTextLabel
var _back: Button
var _topics: PackedStringArray = []
var _history: PackedStringArray = []


func _ready() -> void:
	title = "StarsGodot Help"
	size = SIZE
	visible = false
	wrap_controls = true
	close_requested.connect(hide)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_back = Button.new()
	_back.text = "Back"
	_back.pressed.connect(_go_back)
	bar.add_child(_back)
	var row := HSplitContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_list.item_selected.connect(func(i: int) -> void: show_topic(_topics[i]))
	row.add_child(_list)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.meta_clicked.connect(func(meta: Variant) -> void: show_topic(str(meta)))
	row.add_child(_text)
	# the text on a white field, like the list
	_text.add_theme_stylebox_override("normal", _list.get_theme_stylebox("panel"))


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		set_input_as_handled()


## Opens the help at `p_topic`, or where it was (the first topic the first time).
func open(p_topic: String = "") -> void:
	_topics = HelpText.topics(GameSession.content)
	_list.clear()
	for t in _topics:
		_list.add_item(HelpText.title(GameSession.content, t))
	var start := p_topic if not p_topic.is_empty() else topic
	if start.is_empty() or not _topics.has(start):
		start = _topics[0] if not _topics.is_empty() else ""
	_history.clear()
	topic = ""
	show_topic(start)
	popup_centered()


## Shows a topic, remembering the one before for Back.
func show_topic(p_topic: String) -> void:
	if p_topic == topic or not _topics.has(p_topic):
		return
	if not topic.is_empty():
		_history.append(topic)
	_show(p_topic)


func _go_back() -> void:
	if _history.is_empty():
		return
	var before := _history[_history.size() - 1]
	_history.remove_at(_history.size() - 1)
	_show(before)


func _show(p_topic: String) -> void:
	topic = p_topic
	var font_size := _text.get_theme_font_size("normal_font_size")
	var heading := int(font_size * HelpText.HEADING_SIZE * HelpText.HEADING_SIZE)
	_text.text = (
		(
			"[font_size=%d][b]%s[/b][/font_size]\n\n"
			% [heading, HelpText.title(GameSession.content, topic).replace("[", "[lb]")]
		)
		+ HelpText.bbcode(GameSession.content, topic, font_size)
	)
	_text.scroll_to_line(0)
	var at := _topics.find(topic)
	if at >= 0:
		_list.select(at)
	_back.disabled = _history.is_empty()
