class_name MainMenu
extends CenterContainer
## The main menu (M11): a new single-player game (universe size, density, player positions,
## race preset, seed), loading the saved game, quitting.

signal start_game

const DENSITIES := ["sparse", "normal", "dense", "packed"]
const POSITIONS := ["close", "moderate", "farther", "distant"]

var _size: OptionButton
var _density: OptionButton
var _positions: OptionButton
var _race: OptionButton
var _seed: SpinBox
var _status: Label
var _race_ids: Array[String] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	add_child(box)
	var title := Label.new()
	title.text = "StarsGodot"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_size = _option(grid, "Universe size", NewGame.SIZES, 1)
	_density = _option(grid, "Density", DENSITIES, 1)
	_positions = _option(grid, "Player positions", POSITIONS, 1)
	_race_ids = RacePresets.ids(GameSession.content)
	var names: Array = []
	for id in _race_ids:
		names.append(GameSession.content.display_name(id))
	_race = _option(grid, "Race", names, 0)
	grid.add_child(_label("Seed"))
	_seed = SpinBox.new()
	_seed.max_value = 1 << 30
	_seed.value = randi() % 100000
	grid.add_child(_seed)
	for spec: Array in [["New game", _on_new], ["Load saved game", _on_load], ["Quit", _on_quit]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		box.add_child(b)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	if not GameSession.load_errors.is_empty():
		_status.text = GameSession.load_errors


func _option(grid: GridContainer, text: String, items: Array, selected: int) -> OptionButton:
	grid.add_child(_label(text))
	var o := OptionButton.new()
	for item: Variant in items:
		o.add_item(str(item).capitalize())
	o.select(selected)
	grid.add_child(o)
	return o


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _on_new() -> void:
	var options := NewGame.Options.new()
	options.size = _size.selected
	options.density = DENSITIES[_density.selected]
	options.positions = POSITIONS[_positions.selected]
	options.race = RacePresets.make(GameSession.content, _race_ids[_race.selected])
	options.seed = int(_seed.value)
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
