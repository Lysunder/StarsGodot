class_name NewGameDialog
extends AcceptDialog
## New Game (D15, the original's arrangement): Difficulty Level and Universe Size as radio groups on
## the left, the race on the right with Customize Race and Advanced Game under it, and Begin
## Tutorial, OK and Cancel along the bottom. Advanced Game sets the density, the player positions,
## the game options, the seed and the computer players. The race list holds the presets and the
## player's own races (RaceStore); Customize Race opens the race wizard on the chosen one, and the
## finished race is saved and chosen. The difficulty level picks the computer players with the
## universe size (NewGame.pick_opponents) unless Advanced Game chooses the other players: computer
## players, each a personality (the game's own, the player's from the personality editor, or
## Random) and a level (or Random), and more human players for hotseat (S27), each with a race.
## The tutorial waits for M11 step 11.

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
	["computer_alliances", "Computer Players Form Alliances", true],
	["public_scores", "Public Player Scores", false],
	["galaxy_clumping", "Galaxy Clumping", true],
]

## Advanced Game's computer player list: the personality and level choices, and the rows.
const RANDOM_LEVEL := "Random"
const OPPONENT_LIST_SIZE := Vector2(300, 140)

var _size_group := ButtonGroup.new()
var _difficulty_group := ButtonGroup.new()
var _race: OptionButton
## The races the list offers, in its order: the presets, then the player's own.
var _races: Array[Race] = []
var _wizard: RaceWizard
var _advanced: AcceptDialog
var _density_group := ButtonGroup.new()
var _positions_group := ButtonGroup.new()
var _flags: Array[CheckBox] = []
var _seed: SpinBox
var _choose: CheckBox
var _opponent_list: ItemList
var _opponent_kind: OptionButton
var _opponent_level: OptionButton
var _opponent_buttons: Array[Button] = []
## What the personality choice offers, in its order: {ai, personality, name}.
var _kinds: Array[Dictionary] = []
## The chosen computer players, in the list's order: NewGame.Options.opponents entries.
var _opponents: Array[Dictionary] = []


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
	for i in DIFFICULTIES.size():
		_radio(difficulty, DIFFICULTIES[i], _difficulty_group, i == 1)
	var size_box := _group_box(left, "Universe Size")
	for i in SIZES.size():
		_radio(size_box, SIZES[i], _size_group, i == 1)
	var right := VBoxContainer.new()
	row.add_child(right)
	_race = OptionButton.new()
	right.add_child(_race)
	_fill_races("")
	_button(right, "Customize Race...", func() -> void: _wizard.open(_races[_race.selected]))
	_wizard = RaceWizard.new()
	_wizard.race_finished.connect(_on_race_finished)
	add_child(_wizard)
	_button(right, "Advanced Game...", _open_advanced)
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


## Fills the race list (presets, then the player's own races) and picks the player's race named
## `pick`, else the first.
func _fill_races(pick: String) -> void:
	var content := GameSession.content
	_race.clear()
	_races.clear()
	for id in RacePresets.ids(content):
		_races.append(RacePresets.make(content, id))
		_race.add_item(content.display_name(id))
	var selected := 0
	for r in RaceStore.races(content):
		if r.name == pick:
			selected = _races.size()
		_races.append(r)
		_race.add_item(r.name)
	_race.select(selected)


## The wizard's race: saved and chosen (a Random race is rolled when the game starts, so it is
## only chosen).
func _on_race_finished(race: Race) -> void:
	if race.random:
		_races[_race.selected] = race
		return
	RaceStore.save(race, GameSession.game_version)
	_fill_races(race.name)


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
			c.tooltip_text = "Comes with public scores (later)."
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
	_build_opponents(left)


func _build_opponents(parent: Control) -> void:
	_choose = CheckBox.new()
	_choose.text = "Choose the other players"
	_choose.tooltip_text = "Otherwise the difficulty level and universe size pick computer players."
	_choose.toggled.connect(func(_on: bool) -> void: _update_opponents())
	parent.add_child(_choose)
	var box := _group_box(parent, "Other Players")
	_opponent_list = ItemList.new()
	_opponent_list.custom_minimum_size = OPPONENT_LIST_SIZE
	box.add_child(_opponent_list)
	var row := HBoxContainer.new()
	box.add_child(row)
	_opponent_kind = OptionButton.new()
	_opponent_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_opponent_kind)
	_opponent_level = OptionButton.new()
	for n: String in DIFFICULTIES:
		_opponent_level.add_item(n)
	_opponent_level.add_item(RANDOM_LEVEL)
	_opponent_level.select(1)
	row.add_child(_opponent_level)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_opponent_buttons.append(_button(buttons, "Add", _on_add_opponent))
	_opponent_buttons.append(_button(buttons, "Remove", _on_remove_opponent))
	_update_opponents()


## Advanced Game, with the personality choice filled afresh (the player may have saved more).
func _open_advanced() -> void:
	_fill_kinds()
	_update_opponents()
	_advanced.popup_centered()


## The game's own personalities (not the inactive one), the player's, Random, then a human player
## (hotseat) for each race of the race list.
func _fill_kinds() -> void:
	var content := GameSession.content
	_kinds.clear()
	_opponent_kind.clear()
	var ids: Array = content.ids(ComputerPlayers.PERSONALITY)
	ids.sort_custom(
		func(a: String, b: String) -> bool:
			return (
				int(content.get_def(ComputerPlayers.PERSONALITY, a).get("order", 0))
				< int(content.get_def(ComputerPlayers.PERSONALITY, b).get("order", 0))
			)
	)
	for id: String in ids:
		var key := id.get_slice(".", 1)
		if key == ComputerPlayers.INACTIVE:
			continue
		_kinds.append({"ai": key, "personality": {}, "name": content.display_name(id)})
	for p: Dictionary in PersonalityStore.personalities():
		_kinds.append({"ai": NewGame.personality_key(p), "personality": p, "name": str(p["name"])})
	_kinds.append({"ai": NewGame.RANDOM, "personality": {}, "name": "Random"})
	for i in _races.size():
		_kinds.append(
			{"human": true, "race": _races[i], "name": "Human: " + _race.get_item_text(i)}
		)
	for k: Dictionary in _kinds:
		_opponent_kind.add_item(k["name"])


func _on_add_opponent() -> void:
	if _opponents.size() >= NewGame.MAX_PLAYERS - 1 or _kinds.is_empty():
		return
	var kind: Dictionary = _kinds[maxi(_opponent_kind.selected, 0)]
	if kind.get("human", false):
		var race := (kind["race"] as Race).copy() as Race
		_opponents.append({"human": true, "race": race, "name": kind["name"]})
		_update_opponents()
		return
	var level := _opponent_level.selected
	(
		_opponents
		. append(
			{
				"ai": kind["ai"],
				"level": -1 if level >= DIFFICULTIES.size() else level,
				"personality": (kind["personality"] as Dictionary).duplicate(true),
				"name": kind["name"],
			}
		)
	)
	_update_opponents()


func _on_remove_opponent() -> void:
	var picked := _opponent_list.get_selected_items()
	if picked.is_empty():
		return
	_opponents.remove_at(picked[0])
	_update_opponents()


func _update_opponents() -> void:
	_opponent_list.clear()
	for o: Dictionary in _opponents:
		if o.get("human", false):
			_opponent_list.add_item(o["name"])
			continue
		var level := int(o["level"])
		_opponent_list.add_item(
			"%s, %s" % [o["name"], RANDOM_LEVEL if level < 0 else DIFFICULTIES[level]]
		)
	var on := _choose.button_pressed
	for c: Control in [_opponent_kind, _opponent_level]:
		(c as OptionButton).disabled = not on
	for b in _opponent_buttons:
		b.disabled = not on
	_opponent_buttons[0].disabled = not on or _opponents.size() >= NewGame.MAX_PLAYERS - 1


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
	options.race = _races[_race.selected].copy() as Race
	options.seed = int(_seed.value)
	for i in FLAGS.size():
		if _flags[i].button_pressed:
			options.flags.append(FLAGS[i][0])
	if _choose.button_pressed:
		for o: Dictionary in _opponents:
			if o.get("human", false):
				options.opponents.append({"human": true, "race": o["race"]})
				continue
			options.opponents.append(
				{"ai": o["ai"], "level": o["level"], "personality": o["personality"]}
			)
	else:
		# the same seed fields the same computer players
		var rng := StarsRandom.from_game_seed(options.seed)
		options.opponents = NewGame.pick_opponents(options.size, _picked(_difficulty_group), rng)
	hide()
	game_chosen.emit(options)
