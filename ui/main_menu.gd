class_name MainMenu
extends CenterContainer
## The start screen (D15): the game's name over New Game, Open Game, Open Turn File,
## Personalities, Settings and Exit. New Game opens the New Game window; Open Game loads the saved
## game; Open Turn File opens a play-by-email turn file from the host (S27); Mods chooses the mods
## the game loads; Import Classic Look reads the player's own copy of Stars! 2.6i (S26, D13);
## Personalities opens the computer player personality editor; Settings opens the interface
## settings.

signal start_game

const BUTTON_WIDTH := 200

var _status: Label
var _new_game: NewGameDialog
var _settings: SettingsDialog
var _help: HelpWindow
var _personalities: PersonalityEditor
var _turn_files: FileDialog
var _mods: ModManager
var _classic: FileDialog


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
	for spec: Array in [
		["New Game...", _on_new],
		["Tutorial", _on_tutorial],
		["Open Game", _on_load],
		["Open Turn File...", func() -> void: _turn_files.popup_centered_ratio(0.6)],
		["Mods...", func() -> void: _mods.open()],
		["Import Classic Look...", func() -> void: _classic.popup_centered_ratio(0.6)],
		["Personalities...", func() -> void: _personalities.open()],
		["Settings...", func() -> void: _settings.open()],
		["Help...", func() -> void: _help.open()],
		["Exit", _on_quit],
	]:
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
	_settings = SettingsDialog.new()
	add_child(_settings)
	_classic = FileDialog.new()
	_classic.title = "Your Stars! 2.6i Folder"
	_classic.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_classic.access = FileDialog.ACCESS_FILESYSTEM
	_classic.dir_selected.connect(_on_classic_folder)
	add_child(_classic)
	_mods = ModManager.new()
	_mods.mods_changed.connect(func() -> void: _status.text = GameSession.load_errors)
	add_child(_mods)
	_personalities = PersonalityEditor.new()
	add_child(_personalities)
	_help = HelpWindow.new()
	add_child(_help)
	_turn_files = FileDialog.new()
	_turn_files.title = "Open Turn File"
	_turn_files.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_turn_files.access = FileDialog.ACCESS_FILESYSTEM
	_turn_files.filters = PackedStringArray([tr("*.%s ; Turn files") % TurnFile.EXTENSION])
	_turn_files.file_selected.connect(_on_turn_file)
	add_child(_turn_files)
	_new_game = NewGameDialog.new()
	_new_game.game_chosen.connect(_on_game_chosen)
	add_child(_new_game)


func _on_new() -> void:
	_new_game.popup_centered()


func _on_game_chosen(options: NewGame.Options) -> void:
	GameSession.new_game(options)
	start_game.emit()


func _on_tutorial() -> void:
	GameSession.new_game(Tutorial.options())
	GameSession.tutorial = true
	start_game.emit()


func _on_load() -> void:
	var err := GameSession.load_game(GameSession.default_save_path())
	if err.is_empty():
		start_game.emit()
	else:
		_status.text = err


func _on_turn_file(path: String) -> void:
	var err := GameSession.open_turn_file(path)
	if err.is_empty():
		start_game.emit()
	else:
		_status.text = err


## Imports the classic look from the player's install folder and turns it on (S26).
func _on_classic_folder(dir: String) -> void:
	var r := ClassicImporter.run(dir, GameSession.content)
	if not r.ok():
		_status.text = "\n".join(r.errors)
		return
	var on := ModSettings.enabled()
	if not on.has(ClassicImporter.MOD_ID):
		on.append(ClassicImporter.MOD_ID)
	ModSettings.save(on, ModSettings.trusted())
	GameSession.reload_content()
	_status.text = tr("%s The classic look is on (Mods... turns it off).") % " ".join(r.lines)


func _on_quit() -> void:
	get_tree().quit()
