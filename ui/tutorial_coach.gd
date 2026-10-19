class_name TutorialCoach
extends PanelContainer
## The tutorial's panel over the scanner (Tutorial): the step's title and text, the step count,
## Next for steps that wait for the player to read, and Hide. It checks the step's condition
## whenever the game changes, and moves on by itself.

signal finished

const WIDTH := 340

var step: int = 0
var start_turn: int = 0

var _title: Label
var _count: Label
var _text: RichTextLabel
var _next: Button


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	add_child(box)
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_title = Label.new()
	_title.theme_type_variation = "BoldLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)
	_count = Label.new()
	bar.add_child(_count)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(WIDTH, 0)
	box.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	var hide_button := Button.new()
	hide_button.text = "Hide Tutorial"
	hide_button.pressed.connect(_finish)
	buttons.add_child(hide_button)
	_next = Button.new()
	_next.text = "Next"
	_next.pressed.connect(_advance)
	buttons.add_child(_next)
	GameSession.changed.connect(check)
	start_turn = GameSession.state.turn if GameSession.has_game() else 0
	_show()


## Moves on while the step's condition holds.
func check() -> void:
	if not GameSession.has_game() or not is_inside_tree():
		return
	var moved := false
	while (
		step < Tutorial.STEPS.size()
		and Tutorial.done(step, GameSession.view, GameSession.orders, start_turn)
	):
		step += 1
		moved = true
	if moved:
		_show()


func _advance() -> void:
	if step >= Tutorial.STEPS.size() - 1:
		_finish()
		return
	step += 1
	_show()
	check()


func _finish() -> void:
	finished.emit()
	queue_free()


func _show() -> void:
	var id := Tutorial.step_id(step)
	var content := GameSession.content
	_title.text = content.string_for("tutorial.%s.title" % id)
	_count.text = tr("%d of %d") % [step + 1, Tutorial.STEPS.size()]
	var font_size := _text.get_theme_font_size("normal_font_size")
	_text.text = HelpText.markup(content, content.string_for("tutorial.%s.text" % id), font_size)
	_next.visible = Tutorial.needs_next(step)
	_next.text = "Finish" if step == Tutorial.STEPS.size() - 1 else "Next"
	reset_size()
