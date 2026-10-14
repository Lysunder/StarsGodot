class_name BattleViewer
extends AcceptDialog
## The battle viewer (M11 step 8; D15, the original's `VCRDLG@10e0:084e` arrangement): the board
## on the left; on the right the step and round, the playback speed, what the current step's
## token did, and the selected token's state; below the board the buttons to go to the start,
## back one step, play or pause, on one step and to the end. Shift makes a step 10, Ctrl 100.
## Each step selects the token that acts; clicking a square selects its next token, a right
## click lists them all, and holding the mouse on the selection shows the token's design.

const SPEED_MAX := 5
const PANEL_WIDTH := 300
const LOST := Color(0.6, 0, 0)

var replay: BattleReplay
## The selected token (-1 none) and square (BattleReplay.GONE none).
var selected: int = -1
var selected_square: int = BattleReplay.GONE

var _board: BattleBoard
var _position: Label
var _speed_label: Label
var _action: RichTextLabel
var _selection: RichTextLabel
var _buttons: Array[Button] = []
var _timer: Timer
var _speed: int = 3
var _square_menu: PopupMenu
var _popup: HoldPopup


func _ready() -> void:
	title = "Battle Viewer"
	ok_button_text = "Done"
	var column := VBoxContainer.new()
	add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	_board = BattleBoard.new()
	_board.square_clicked.connect(_on_square_clicked)
	row.add_child(_board)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	row.add_child(panel)
	_position = Label.new()
	panel.add_child(_position)
	var speed := HBoxContainer.new()
	panel.add_child(speed)
	speed.add_child(_small_button("<", func() -> void: _set_speed(_speed - 1)))
	_speed_label = Label.new()
	speed.add_child(_speed_label)
	speed.add_child(_small_button(">", func() -> void: _set_speed(_speed + 1)))
	_action = _text()
	panel.add_child(_action)
	panel.add_child(HSeparator.new())
	_selection = _text()
	_selection.mouse_filter = Control.MOUSE_FILTER_STOP
	_selection.gui_input.connect(_on_selection_input)
	panel.add_child(_selection)
	var controls := HBoxContainer.new()
	column.add_child(controls)
	for label: String in ["|<<", "<", ">/||", ">", ">>|"]:
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(44, 0)
		b.pressed.connect(_on_control.bind(_buttons.size()))
		controls.add_child(b)
		_buttons.append(b)
	_timer = Timer.new()
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_square_menu = PopupMenu.new()
	_square_menu.id_pressed.connect(_select)
	add_child(_square_menu)
	_popup = HoldPopup.new()
	add_child(_popup)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if not visible:
		_timer.stop()


func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _text() -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	t.add_theme_color_override("default_color", ClassicTheme.TEXT)
	return t


## Opens the battle with this id at its start.
func open(id: int) -> void:
	var b := BattleReplay.find(GameSession.view, id)
	if b.is_empty():
		return
	replay = BattleReplay.new(GameSession.view, b)
	_board.replay = replay
	selected = -1
	selected_square = BattleReplay.GONE
	_set_speed(_speed)
	_show()
	popup_centered()


func _seek(to: int) -> void:
	replay.seek(to)
	var e := replay.event()
	if not e.is_empty():
		selected = int(e["token"])
		selected_square = int(e["square"])
	_show()


func _on_control(index: int) -> void:
	var playing := not _timer.is_stopped()
	_timer.stop()
	var by := 1
	if Input.is_key_pressed(KEY_CTRL):
		by = 100
	elif Input.is_key_pressed(KEY_SHIFT):
		by = 10
	match index:
		0:
			_seek(-1)
		1:
			_seek(replay.step - by)
		2:
			if not playing and replay.step < replay.last:
				_timer.start(_interval())
		3:
			_seek(replay.step + by)
		4:
			_seek(replay.last)
	_update_buttons()


func _on_tick() -> void:
	if replay.step >= replay.last:
		_timer.stop()
		_update_buttons()
		return
	_seek(replay.step + 1)
	_timer.start(_interval())


## Seconds between steps while playing: faster at higher speeds.
func _interval() -> float:
	return (570 - 120 * (_speed - 1)) / 1000.0


func _set_speed(s: int) -> void:
	_speed = clampi(s, 1, SPEED_MAX)
	_speed_label.text = "Playback speed: %d" % _speed
	if not _timer.is_stopped():
		_timer.start(_interval())


func _update_buttons() -> void:
	_buttons[0].disabled = replay.step < 0
	_buttons[1].disabled = replay.step < 0
	_buttons[3].disabled = replay.step >= replay.last
	_buttons[4].disabled = replay.step >= replay.last
	_buttons[2].disabled = replay.step >= replay.last and _timer.is_stopped()


func _on_square_clicked(square: int, button: int, at: Vector2) -> void:
	var here := replay.tokens_at(square)
	if button == MOUSE_BUTTON_RIGHT:
		if here.is_empty():
			return
		_square_menu.clear()
		for i in here:
			_square_menu.add_item(_token_name(i, true), i)
		_square_menu.position = Vector2i(at)
		_square_menu.reset_size()
		_square_menu.popup()
		return
	# the next token on the square after the selected one, round to the first
	var next := -1
	if not here.is_empty():
		next = here[0]
		if square == selected_square and here.has(selected):
			next = here[(here.find(selected) + 1) % here.size()]
	selected = next
	selected_square = square
	_show()


func _select(token: int) -> void:
	selected = token
	selected_square = int(replay.tokens[token]["square"])
	_show()


func _on_selection_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not mb.pressed:
		_popup.close()
	elif selected >= 0 and replay.design(selected) != null:
		var starbase := int(replay.battle["tokens"][selected]["kind"]) == BattleReplay.KIND_STARBASE
		_popup.open(SummaryPane.design_view(replay.design(selected), starbase), mb.global_position)


## "Design" or "Design × n", with the owner first when `owner` is set.
func _token_name(i: int, owner: bool) -> String:
	var rec: Dictionary = replay.battle["tokens"][i]
	var d := replay.design(i)
	var text := d.name if d != null else "?"
	var count := int(replay.tokens[i]["count"])
	if count > 1:
		text += " × %d" % count
	if owner:
		text = "%s: %s" % [_player(int(rec["owner"])), text]
	return text


func _player(p: int) -> String:
	return GameSession.view.state.player(p).race.plural_name


static func _square_text(square: int) -> String:
	return "(%d, %d)" % [square & 15, square >> 4]


func _show() -> void:
	_board.selected_square = selected_square
	_board.queue_redraw()
	var rounds := replay.last_round + 1
	_position.text = (
		"Step %d of %d    Round %d of %d"
		% [replay.step + 1, replay.last + 1, replay.current_round() + 1, rounds]
	)
	_action.text = _action_text()
	_selection.text = _selection_text()
	_update_buttons()


func _action_text() -> String:
	var a := replay.action()
	if a.is_empty():
		return "The battle is about to begin."
	var lines: Array[String] = []
	var token: int = a["token"]
	var rec: Dictionary = replay.battle["tokens"][token]
	lines.append(_player(int(rec["owner"])))
	lines.append("[b]%s[/b]" % _token_name(token, false))
	if a["target"] < 0:
		if a["square"] == BattleReplay.GONE:
			lines.append("leaves the battle.")
		else:
			lines.append("moves to %s." % _square_text(a["square"]))
		return "\n".join(lines)
	var target: int = a["target"]
	lines.append("fires on " + _player(int(replay.battle["tokens"][target]["owner"])))
	var name := _token_name(target, false)
	lines.append("[color=#%s]%s[/color]" % [LOST.to_html(false), name] if a["killed"] > 0 else name)
	lines.append("at %s:" % _square_text(a["target_square"]))
	if a["shield_damage"] > 0:
		lines.append("%d damage to shields" % a["shield_damage"])
	if a["armor_damage"] > 0:
		lines.append("%d damage to armor" % a["armor_damage"])
	if a["no_damage"]:
		lines.append("no damage.")
	if a["killed"] > 0:
		lines.append("%d ship%s destroyed." % [a["killed"], "" if a["killed"] == 1 else "s"])
	return "\n".join(lines)


func _selection_text() -> String:
	if selected_square == BattleReplay.GONE:
		return ""
	var lines: Array[String] = ["Selected square: " + _square_text(selected_square)]
	if selected < 0:
		return "\n".join(lines)
	var s := replay.status(selected)
	lines.append(_player(s["owner"]))
	var name: String = _token_name(selected, false)
	var e := replay.event()
	var lost := 0
	if not e.is_empty():
		for h: Dictionary in e["hits"]:
			if int(h["target"]) == selected:
				lost += int(h["killed"])
	if lost > 0:
		name += " (−%d)" % lost
	lines.append("[b]%s[/b]" % name)
	if not s["alive"]:
		lines.append("Destroyed")
		return "\n".join(lines)
	if s["gone"]:
		lines.append("Has left the battle")
		return "\n".join(lines)
	lines.append(
		"Initiative: %d    Moves a round: %s" % [s["initiative"], _moves(s["movement_quarters"])]
	)
	var damage := "none"
	if s["damaged"] > 0:
		damage = (
			"%d%%" % s["damage_pct"]
			if s["starbase"]
			else "%d at %d%%" % [s["damaged"], s["damage_pct"]]
		)
	lines.append("Armor: %d    Damage: %s" % [s["armor"], damage])
	lines.append("Shields: %s" % (str(s["shields"]) if s["shields"] > 0 else "none"))
	if s["jamming"] > 0:
		lines.append("Torpedo jamming: %d%%" % s["jamming"])
	if not s["starbase"]:
		var tactic: String = BattlePlansDialog.TACTICS[mini(s["tactic"], 5)]
		if s["tactic"] == 0:
			tactic += " in %d moves" % s["countdown"]
		lines.append("Tactic: " + tactic)
	lines.append("Primary target: " + BattlePlansDialog.TARGETS[mini(s["primary_target"], 7)])
	lines.append("Secondary target: " + BattlePlansDialog.TARGETS[mini(s["secondary_target"], 7)])
	return "\n".join(lines)


## Moves a round from quarters: "1¼", "½", "--" for a starbase.
static func _moves(quarters: int) -> String:
	if quarters < 0:
		return "--"
	var whole := quarters / 4
	var part: String = ["", "¼", "½", "¾"][quarters % 4]
	if whole == 0:
		return part if part != "" else "0"
	return str(whole) + part
