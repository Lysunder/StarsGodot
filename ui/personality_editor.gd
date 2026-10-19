class_name PersonalityEditor
extends AcceptDialog
## Computer player personalities (S22 "The personality editor"; the original has none): the list
## on the left holds the game's own personalities (read only) and the player's (PersonalityStore);
## the right side shows the chosen one's name, brain, the original personality whose races it
## plays, and settings by group. Settings are edited
## for the personality as a whole, or with a difficulty chosen, as that level's overrides (a box
## per setting: unticked, the level takes the personality's value). New makes a personality for
## the baseline brain, Copy one from the chosen personality; Save and Delete work on the player's
## own. Brains that play the original's personalities have no settings.

signal personalities_changed

const ALL_LEVELS := "All levels"
const LEVEL_NAMES := ["Easy", "Standard", "Harder", "Expert"]
const GROUPS := ["research", "expansion", "economy", "military"]
const LIST_WIDTH := 180
const SETTINGS_SIZE := Vector2(460, 320)

var _list: ItemList
## The entries the list shows, in its order: {personality, own (the player's), id (content)}.
var _entries: Array[Dictionary] = []
## The personality being edited (a copy) and whether it is one of the player's.
var _current: Dictionary = {}
var _own := false
## The name it was saved under (renaming saves a new file and removes the old one).
var _saved_name := ""
var _name: LineEdit
var _brain: OptionButton
var _races: OptionButton
var _level: OptionButton
var _settings: VBoxContainer
var _status: Label
var _save: Button
var _delete: Button
## Per setting key: {spin, override (CheckBox or null)}.
var _rows := {}
var _filling := false


func _ready() -> void:
	title = "Computer Player Personalities"
	ok_button_text = "Close"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(LIST_WIDTH, SETTINGS_SIZE.y)
	_list.item_selected.connect(_on_selected)
	left.add_child(_list)
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	_button(buttons, "New", _on_new)
	_button(buttons, "Copy", _on_copy)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var grid := GridContainer.new()
	grid.columns = 2
	right.add_child(grid)
	grid.add_child(_label("Name:"))
	_name = LineEdit.new()
	_name.max_length = PersonalityFile.NAME_MAX
	_name.custom_minimum_size = Vector2(200, 0)
	_name.text_changed.connect(func(t: String) -> void: _current["name"] = t)
	grid.add_child(_name)
	grid.add_child(_label("Brain:"))
	_brain = OptionButton.new()
	for id: String in PersonalityFile.brains():
		_brain.add_item(_brain_name(id))
	_brain.item_selected.connect(_on_brain)
	grid.add_child(_brain)
	grid.add_child(_label("Races:"))
	_races = OptionButton.new()
	_races.tooltip_text = "The original personality whose race it plays at each level."
	for key: String in ComputerPlayers.RACES:
		_races.add_item(_content().display_name(ComputerPlayers.personality_id(key)))
	_races.item_selected.connect(
		func(i: int) -> void:
			if not _filling:
				_current["races_of"] = ComputerPlayers.RACES[i]
	)
	grid.add_child(_races)
	grid.add_child(_label("Settings for:"))
	_level = OptionButton.new()
	_level.add_item(ALL_LEVELS)
	for n: String in LEVEL_NAMES:
		_level.add_item(n)
	_level.item_selected.connect(func(_i: int) -> void: _fill_settings())
	grid.add_child(_level)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "SunkenField"
	frame.custom_minimum_size = SETTINGS_SIZE
	right.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	_settings = VBoxContainer.new()
	_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_settings)
	var bottom := HBoxContainer.new()
	right.add_child(bottom)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	_save = _button(bottom, "Save", _on_save)
	_delete = _button(bottom, "Delete", _on_delete)


## Shows the window with the list filled afresh (the first entry chosen).
func open() -> void:
	_refill("")
	popup_centered()


func _content() -> ContentRegistry:
	return GameSession.content


func _brain_name(id: String) -> String:
	var key := "ai_brain.%s.name" % id
	var text := _content().string_for(key) if _content() != null else key
	return id.capitalize() if text == key else text


func _refill(pick: String) -> void:
	_entries.clear()
	_list.clear()
	var content := _content()
	var ids: Array = content.ids(ComputerPlayers.PERSONALITY)
	ids.sort_custom(
		func(a: String, b: String) -> bool:
			return (
				int(content.get_def(ComputerPlayers.PERSONALITY, a).get("order", 0))
				< int(content.get_def(ComputerPlayers.PERSONALITY, b).get("order", 0))
			)
	)
	for id: String in ids:
		if id == ComputerPlayers.personality_id(ComputerPlayers.INACTIVE):
			continue
		var p := PersonalityFile.from_content(content, id)
		_entries.append({"personality": p, "own": false, "id": id})
		_list.add_item(tr("%s (built in)") % p["name"])
	var selected := 0
	for p: Dictionary in PersonalityStore.personalities():
		if p["name"] == pick:
			selected = _entries.size()
		_entries.append({"personality": p, "own": true, "id": ""})
		_list.add_item(str(p["name"]))
	if not _entries.is_empty():
		_list.select(selected)
		_on_selected(selected)


func _on_selected(index: int) -> void:
	var entry: Dictionary = _entries[index]
	_show(entry["personality"], entry["own"])


func _show(p: Dictionary, own: bool) -> void:
	_current = p.duplicate(true)
	_own = own
	_saved_name = str(p["name"]) if own else ""
	_filling = true
	_name.text = str(_current["name"])
	_name.editable = own
	_brain.select(maxi(PersonalityFile.brains().find(_current["brain"]), 0))
	_brain.disabled = not own
	_select_races()
	_races.disabled = not own
	_filling = false
	_save.disabled = not own
	_delete.disabled = not own
	_status.text = "" if own else "The game's own personalities can't be changed: Copy makes one."
	_fill_settings()


func _on_brain(index: int) -> void:
	if _filling:
		return
	# another brain has other settings: start from its defaults
	var label_text := str(_current.get("name", ""))
	_current = PersonalityFile.make(label_text, PersonalityFile.brains()[index])
	_filling = true
	_select_races()
	_filling = false
	_fill_settings()


func _select_races() -> void:
	var key := str(
		_current.get("races_of", ComputerPlayers.default_races(str(_current.get("brain", ""))))
	)
	_races.select(maxi(ComputerPlayers.RACES.find(key), 0))


## The settings of the current brain, by group, for the level chosen (or all levels).
func _fill_settings() -> void:
	for child in _settings.get_children():
		child.queue_free()
	_rows.clear()
	var level := _level.selected - 1
	var declared := AiBrains.settings(str(_current.get("brain", "")))
	if declared.is_empty():
		var l := _label(
			(
				"This brain plays the original's %s; it has no settings."
				% _brain_name(str(_current.get("brain", "")))
			)
		)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(SETTINGS_SIZE.x - 20, 0)
		_settings.add_child(l)
		return
	for group: String in GROUPS:
		var in_group := declared.filter(func(s: Dictionary) -> bool: return s["group"] == group)
		if in_group.is_empty():
			continue
		var heading := _label(_content().display_name("ai_setting_group." + group))
		heading.theme_type_variation = "BoldLabel"
		_settings.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 3 if level >= 0 else 2
		_settings.add_child(grid)
		for s: Dictionary in in_group:
			_add_row(grid, s, level)


func _add_row(grid: GridContainer, s: Dictionary, level: int) -> void:
	var key: String = s["key"]
	var override: CheckBox = null
	if level >= 0:
		override = CheckBox.new()
		override.tooltip_text = "Set for this level"
		override.button_pressed = _level_map(level).has(key)
		override.disabled = not _own
		grid.add_child(override)
	var label_text := _label(_content().string_for("ai_setting.%s.name" % key))
	label_text.tooltip_text = _content().string_for("ai_setting.%s.description" % key)
	label_text.mouse_filter = Control.MOUSE_FILTER_PASS
	label_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label_text)
	var spin := SpinBox.new()
	spin.min_value = s["min"]
	spin.max_value = s["max"]
	spin.step = 1
	spin.value = PersonalityFile.value(_current, level, key)
	spin.editable = _own and (override == null or override.button_pressed)
	spin.tooltip_text = tr("%d to %d (default %d)") % [s["min"], s["max"], s["default"]]
	grid.add_child(spin)
	_rows[key] = {"spin": spin, "override": override}
	spin.value_changed.connect(func(v: float) -> void: _set_value(key, level, int(v)))
	if override != null:
		override.toggled.connect(func(on: bool) -> void: _set_override(key, level, on))


func _level_map(level: int) -> Dictionary:
	var levels: Array = _current["levels"]
	while levels.size() <= level:
		levels.append({})
	return levels[level]


func _set_value(key: String, level: int, v: int) -> void:
	if level < 0:
		_current["params"][key] = v
	else:
		_level_map(level)[key] = v


func _set_override(key: String, level: int, on: bool) -> void:
	var row: Dictionary = _rows[key]
	var spin: SpinBox = row["spin"]
	if on:
		_level_map(level)[key] = int(spin.value)
	else:
		_level_map(level).erase(key)
		spin.set_value_no_signal(PersonalityFile.value(_current, -1, key))
	spin.editable = on


func _unique_name(base: String) -> String:
	var taken := {}
	for e: Dictionary in _entries:
		taken[str(e["personality"]["name"])] = true
	var label_text := base.left(PersonalityFile.NAME_MAX)
	var n := 2
	while taken.has(label_text):
		var tail := " %d" % n
		label_text = base.left(PersonalityFile.NAME_MAX - tail.length()) + tail
		n += 1
	return label_text


func _on_new() -> void:
	_show(PersonalityFile.make(_unique_name("New personality"), AiBrains.BASELINE), true)
	_saved_name = ""
	_status.text = "Not saved yet."


func _on_copy() -> void:
	var p := _current.duplicate(true)
	p["name"] = _unique_name(tr("Copy of %s") % str(_current.get("name", "")))
	_show(p, true)
	_saved_name = ""
	_status.text = "Not saved yet."


func _on_save() -> void:
	var problems := PersonalityFile.check(_current)
	if not problems.is_empty():
		_status.text = problems[0]
		return
	var label_text := str(_current["name"]).strip_edges()
	_current["name"] = label_text
	for e: Dictionary in _entries:
		if (
			str(e["personality"]["name"]) == label_text
			and (not e["own"] or label_text != _saved_name)
		):
			_status.text = tr("Another personality is called %s.") % label_text
			return
	if PersonalityStore.save(_current).is_empty():
		_status.text = "The personality could not be saved."
		return
	if _saved_name != "" and _saved_name != label_text:
		PersonalityStore.delete(_saved_name)
	_refill(label_text)
	_status.text = "Saved."
	personalities_changed.emit()


func _on_delete() -> void:
	if _saved_name != "":
		PersonalityStore.delete(_saved_name)
	_refill("")
	personalities_changed.emit()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(70, 0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
