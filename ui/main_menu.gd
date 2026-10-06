class_name MainMenu
extends CenterContainer
## The start screen (D15): the game's name over New Game, Open Game and Exit. New Game opens the
## New Game window; Open Game loads the saved game.

signal start_game

const BUTTON_WIDTH := 200

var _status: Label
var _new_game: NewGameDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "TileBody"
	add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)
	var title := Label.new()
	title.text = "StarsGodot"
	title.theme_type_variation = "BoldLabel"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for spec: Array in [["New Game...", _on_new], ["Open Game", _on_load], ["Exit", _on_quit]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
		b.pressed.connect(spec[1])
		box.add_child(b)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	box.add_child(_status)
	if not GameSession.load_errors.is_empty():
		_status.text = GameSession.load_errors
	_new_game = NewGameDialog.new()
	_new_game.game_chosen.connect(_on_game_chosen)
	add_child(_new_game)


func _on_new() -> void:
	_new_game.popup_centered()


func _on_game_chosen(options: NewGame.Options) -> void:
	GameSession.new_game(options)
	start_game.emit()


func _on_load() -> void:
	var err := GameSession.load_game(GameSession.default_save_path())
	if err.is_empty():
		start_game.emit()
	else:
		_status.text = err


func _on_quit() -> void:
	get_tree().quit()
