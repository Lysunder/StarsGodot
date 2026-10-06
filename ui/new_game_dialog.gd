class_name NewGameDialog
extends AcceptDialog
## New Game (D15, the original's arrangement): Difficulty Level and Universe Size as radio groups on
## the left, the race on the right with Customize Race and Advanced Game under it, and Begin
## Tutorial, OK and Cancel along the bottom. Advanced Game sets the density, the player positions,
## the game options and the seed. Difficulty, race customizing and the tutorial wait for the AI,
## the race wizard and the tutorial (M12, M11 steps 9 and 11).

signal game_chosen(options: NewGame.Options)

const DIFFICULTIES := ["Easy", "Standard", "Harder", "Expert"]
const SIZES := ["Tiny", "Small", "Medium", "Large", "Huge"]
const DENSITIES := ["sparse", "normal", "dense", "packed"]
const POSITIONS := ["close", "moderate", "farther", "distant"]
## [settings flag, label, built yet]
const FLAGS := [
	["max_minerals", "Beginner: Maximum Minerals", true],
	["slow_tech", "Slower Tech Advances", true],
	["accelerated_start", "Accelerated BBS Play", true],
	["no_random_events", "No Random Events", true],
	["computer_alliances", "Computer Players Form Alliances", false],
	["public_scores", "Public Player Scores", false],
	["galaxy_clumping", "Galaxy Clumping", true],
]

var _size_group := ButtonGroup.new()
var _race: OptionButton
var _race_ids: Array[String] = []
var _advanced: AcceptDialog
var _density_group := ButtonGroup.new()
var _positions_group := ButtonGroup.new()
var _flags: Array[CheckBox] = []
var _seed: SpinBox


func _ready() -> void:
	title = "New Game"
	get_ok_button().hide()
	var box := VBoxContainer.new()
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	var difficulty := _group_box(left, "Difficulty Level")
	var difficulty_group := ButtonGroup.new()
	for i in DIFFICULTIES.size():
		var r := _radio(difficulty, DIFFICULTIES[i], difficulty_group, i == 1)
		r.disabled = true
		r.tooltip_text = "Computer players come with the AI."
	var size_box := _group_box(left, "Universe Size")
	for i in SIZES.size():
		_radio(size_box, SIZES[i], _size_group, i == 1)
	var right := VBoxContainer.new()
	row.add_child(right)
	_race = OptionButton.new()
	_race_ids = RacePresets.ids(GameSession.content)
	for id in _race_ids:
		_race.add_item(GameSession.content.display_name(id))
	right.add_child(_race)
	var customize := _button(right, "Customize Race...", func() -> void: pass)
	customize.disabled = true
	customize.tooltip_text = "The race wizard comes later."
	_button(right, "Advanced Game...", func() -> void: _advanced.popup_centered())
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	var tutorial := _button(bottom, "Begin Tutorial", func() -> void: pass)
	tutorial.disabled = true
	tutorial.tooltip_text = "The tutorial comes later."
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	_button(bottom, "OK", _on_ok)
	_button(bottom, "Cancel", hide)
	_build_advanced()


func _build_advanced() -> void:
	_advanced = AcceptDialog.new()
	_advanced.title = "Advanced Game"
	_advanced.ok_button_text = "OK"
	add_child(_advanced)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_advanced.add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	var density := _group_box(left, "Density")
	for i in DENSITIES.size():
		_radio(density, DENSITIES[i].capitalize(), _density_group, i == 1)
	var right := VBoxContainer.new()
	row.add_child(right)
	var positions := _group_box(right, "Player Positions")
	for i in POSITIONS.size():
		_radio(positions, POSITIONS[i].capitalize(), _positions_group, i == 1)
	for spec: Array in FLAGS:
		var c := CheckBox.new()
		c.text = spec[1]
		c.disabled = not spec[2]
		if not spec[2]:
			c.tooltip_text = "Comes with computer players and scores."
		right.add_child(c)
		_flags.append(c)
	var seed_row := HBoxContainer.new()
	right.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Universe seed:"
	seed_row.add_child(seed_label)
	_seed = SpinBox.new()
	_seed.max_value = 1 << 30
	_seed.value = randi() % 100000
	seed_row.add_child(_seed)


func _group_box(parent: Control, heading: String) -> VBoxContainer:
	var label := Label.new()
	label.text = heading
	label.theme_type_variation = "BoldLabel"
	parent.add_child(label)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "SunkenField"
	parent.add_child(frame)
	var inner := VBoxContainer.new()
	frame.add_child(inner)
	return inner


func _radio(parent: Control, text: String, group: ButtonGroup, on: bool) -> CheckBox:
	var r := CheckBox.new()
	r.text = text
	r.button_group = group
	r.button_pressed = on
	parent.add_child(r)
	return r


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(80, 0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


static func _picked(group: ButtonGroup) -> int:
	return group.get_buttons().find(group.get_pressed_button())


func _on_ok() -> void:
	var options := NewGame.Options.new()
	options.size = _picked(_size_group)
	options.density = DENSITIES[_picked(_density_group)]
	options.positions = POSITIONS[_picked(_positions_group)]
	options.race = RacePresets.make(GameSession.content, _race_ids[_race.selected])
	options.seed = int(_seed.value)
	for i in FLAGS.size():
		if _flags[i].button_pressed:
			options.flags.append(FLAGS[i][0])
	hide()
	game_chosen.emit(options)
