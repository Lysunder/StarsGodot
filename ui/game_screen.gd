class_name GameScreen
extends VBoxContainer
## The game screen (D15): the menu bar (File, View, Turn, Commands, Report, Help, in the original's
## order), then four resizable panes: Command (top left), Scanner (top right, with its toolbar
## above and status bar below), Messages (bottom left; it shows the year), Selection Summary
## (bottom right). Clicking an object selects it for the summary; the player's own planets and
## fleets also come under command. F9 generates the turn. A player whose race has been wiped out
## is told so once (the original says nothing unless the game has a winner, S20) and may keep
## generating turns to watch the game play out. In a hotseat game (S27) a cover hides the game
## between players until the next one begins their turn.

signal quit_requested

const LEFT_WIDTH := 400
const SUMMARY_HEIGHT := 200
const MESSAGES_HEIGHT := 150
const MENU_SAVE := 0
const MENU_MAIN := 1
const MENU_QUIT := 2
const MENU_RESEARCH := 10
const MENU_DESIGN := 11
const MENU_PLANS := 12
const MENU_RELATIONS := 13
const MENU_END_TURN := 20
const MENU_ABOUT := 40
## Report menu items are this plus the index in ReportView.REPORTS.
const MENU_REPORT := 50
const MENU_SCORE := 60
const MENU_SETTINGS := 30

var _map: GalaxyMap
var _command: CommandPane
var _summary: SummaryPane
var _messages: MessagesPane
var _status: ScannerStatus
var _research: ResearchDialog
var _designer: ShipDesigner
var _plans: BattlePlansDialog
var _relations: RelationsDialog
var _reports: ReportsWindow
var _battle_viewer: BattleViewer
var _score: ScoreWindow
var _about: AcceptDialog
var _settings: SettingsDialog
var _eliminated: AcceptDialog
## The hotseat hand-off cover, its text, and the human players already wiped out when the year
## was generated (to name those lost since).
var _handoff: Control
var _handoff_text: Label
var _lost := {}
## The menu items with a key binding: [menu, item id, KeyBindings action].
var _keyed: Array[Array] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", 2)
	_build_menu()
	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var left := VSplitContainer.new()
	left.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	columns.add_child(left)
	var command_scroll := ScrollContainer.new()
	command_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	command_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(command_scroll)
	_command = CommandPane.new()
	_command.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command.goto.connect(_on_goto)
	command_scroll.add_child(_command)
	_messages = MessagesPane.new()
	_messages.custom_minimum_size = Vector2(0, MESSAGES_HEIGHT)
	_messages.goto_target.connect(_on_message_goto)
	left.add_child(_messages)
	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var scanner := VBoxContainer.new()
	scanner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scanner.add_theme_constant_override("separation", 0)
	right.add_child(scanner)
	var toolbar := ScannerToolbar.new()
	scanner.add_child(toolbar)
	_map = GalaxyMap.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.selected.connect(_on_selected)
	_map.waypoint_picked.connect(_command.select_waypoint)
	_map.hovered.connect(_on_hovered)
	_command.waypoint_selected.connect(_map.set_waypoint)
	_command.pick_planet_requested.connect(_map.pick_planet)
	toolbar.view_chosen.connect(_map.set_view)
	toolbar.names_toggled.connect(_map.set_show_names)
	toolbar.zoom_requested.connect(_map.zoom_by)
	scanner.add_child(_map)
	_status = ScannerStatus.new()
	scanner.add_child(_status)
	_summary = SummaryPane.new()
	_summary.custom_minimum_size = Vector2(0, SUMMARY_HEIGHT)
	right.add_child(_summary)
	_research = ResearchDialog.new()
	add_child(_research)
	_designer = ShipDesigner.new()
	add_child(_designer)
	_plans = BattlePlansDialog.new()
	add_child(_plans)
	_relations = RelationsDialog.new()
	add_child(_relations)
	_reports = ReportsWindow.new()
	_reports.goto.connect(_on_goto)
	_reports.production_requested.connect(_command.open_production)
	_reports.cargo_requested.connect(
		func(number: int) -> void: _command.open_cargo(GameSession.view.fleet_info(number))
	)
	add_child(_reports)
	_battle_viewer = BattleViewer.new()
	add_child(_battle_viewer)
	_reports.battle_requested.connect(_battle_viewer.open)
	_score = ScoreWindow.new()
	add_child(_score)
	_about = AcceptDialog.new()
	_about.title = "About StarsGodot"
	_about.dialog_text = (
		"StarsGodot\nA reimplementation of the game rules of Stars! 2.6i in Godot.\n"
		+ "Version %s" % GameSession.game_version
	)
	add_child(_about)
	_settings = SettingsDialog.new()
	add_child(_settings)
	_eliminated = AcceptDialog.new()
	_eliminated.title = "Defeat"
	_eliminated.dialog_text = (
		"Your race has been wiped out: no planets and no ships are left.\n"
		+ "You can keep generating turns to watch the rest of the game."
	)
	add_child(_eliminated)
	var home := GameSession.view.me().homeworld
	if home >= 0:
		_map.select("planet", home)
	_build_handoff()
	GameSession.player_changed.connect(_on_player_changed)
	_lost = _lost_players()
	if GameSession.is_hotseat():
		_show_handoff()
	else:
		_tell_if_eliminated.call_deferred()


## A cover over the whole screen naming the player whose turn it is, with a button to begin.
func _build_handoff() -> void:
	_handoff = PanelContainer.new()
	# top level: out of the screen's layout, over everything (the theme still applies)
	_handoff.top_level = true
	_handoff.z_index = 100
	_handoff.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_handoff.mouse_filter = Control.MOUSE_FILTER_STOP
	# solid whatever the theme: nothing of the last player's game shows through
	var face := StyleBoxFlat.new()
	face.bg_color = ClassicTheme.FACE
	_handoff.add_theme_stylebox_override("panel", face)
	add_child(_handoff)
	var center := CenterContainer.new()
	_handoff.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	_handoff_text = Label.new()
	_handoff_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_handoff_text)
	var begin := Button.new()
	begin.text = "Begin Turn"
	begin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	begin.pressed.connect(_begin_turn)
	box.add_child(begin)
	_handoff.hide()


func _build_menu() -> void:
	var menu := MenuBar.new()
	add_child(menu)
	var file := PopupMenu.new()
	file.name = "File"
	_keyed_item(file, "Save", MENU_SAVE, "save")
	file.add_item("Close (Main Menu)", MENU_MAIN)
	file.add_separator()
	file.add_item("Exit", MENU_QUIT)
	file.id_pressed.connect(_on_menu)
	menu.add_child(file)
	var view := PopupMenu.new()
	view.name = "View"
	view.add_item("Settings...", MENU_SETTINGS)
	view.id_pressed.connect(_on_menu)
	menu.add_child(view)
	var turn := PopupMenu.new()
	turn.name = "Turn"
	_keyed_item(turn, "Generate", MENU_END_TURN, "generate")
	turn.id_pressed.connect(_on_menu)
	menu.add_child(turn)
	var commands := PopupMenu.new()
	commands.name = "Commands"
	_keyed_item(commands, "Ship Design...", MENU_DESIGN, "ship_design")
	_keyed_item(commands, "Research...", MENU_RESEARCH, "research")
	_keyed_item(commands, "Battle Plans...", MENU_PLANS, "battle_plans")
	_keyed_item(commands, "Player Relations...", MENU_RELATIONS, "relations")
	commands.id_pressed.connect(_on_menu)
	menu.add_child(commands)
	var report := PopupMenu.new()
	report.name = "Report"
	_keyed_item(report, "Planets...", MENU_REPORT, "reports")
	report.add_item("Fleets...", MENU_REPORT + 1)
	report.add_item("Others' Fleets...", MENU_REPORT + 2)
	report.add_item("Battles...", MENU_REPORT + 3)
	report.add_separator()
	_keyed_item(report, "Score...", MENU_SCORE, "score")
	report.id_pressed.connect(_on_menu)
	menu.add_child(report)
	var help := PopupMenu.new()
	help.name = "Help"
	help.add_item("About StarsGodot...", MENU_ABOUT)
	help.id_pressed.connect(_on_menu)
	menu.add_child(help)
	_apply_keys()
	# Settings rebuild the theme when anything changes, the keys and colours included
	get_tree().root.theme_changed.connect(_on_settings_changed)


func _keyed_item(menu: PopupMenu, text: String, id: int, action: String) -> void:
	menu.add_item(text, id)
	_keyed.append([menu, id, action])


## New settings: the keys, and the panes drawn again in the palette's colours.
func _on_settings_changed() -> void:
	_apply_keys()
	if _command.kind != "" and _command.id >= 0:
		_command.command(_command.kind, _command.id)
	_summary.refresh()


## The menu items' keys from KeyBindings.
func _apply_keys() -> void:
	for k: Array in _keyed:
		var menu: PopupMenu = k[0]
		menu.set_item_accelerator(menu.get_item_index(k[1]), KeyBindings.key(k[2]))


func _on_selected(kind: String, id: int) -> void:
	_summary.show_object(kind, id)
	_reports.set_highlight(kind, id)
	var own := kind == "fleet"
	if kind == "planet":
		own = GameSession.view.planet_info(id)["mine"]
	if own:
		_command.command(kind, id)


func _on_goto(kind: String, id: int) -> void:
	_map.select(kind, id)


## A message's Goto (S21): a planet or one of the player's fleets in the scanner, research in the
## Research window, hulls in the ship designer, a battle in the battle viewer (and its planet in
## the scanner), the score report.
func _on_message_goto(goto: Dictionary) -> void:
	if goto.has("score"):
		_score.open()
	elif goto.has("battle"):
		var b := BattleReplay.find(GameSession.view, goto["battle"])
		if int(b.get("planet", -1)) >= 0:
			_map.select("planet", b["planet"])
		_battle_viewer.open(goto["battle"])
	elif goto.has("planet"):
		_map.select("planet", goto["planet"])
	elif goto.has("fleet") and goto.get("owner", -1) == GameSession.player:
		if GameSession.view.state.fleet(GameSession.player, goto["fleet"]) != null:
			_map.select("fleet", goto["fleet"])
	elif goto.has("research"):
		_research.open()
	elif goto.has("hulls"):
		_designer.open()
		_designer._set_mode(ShipDesigner.MODE_HULLS)


## The status bar: what is under the mouse and how far it is from the selected object.
func _on_hovered(x: int, y: int, hit: Dictionary) -> void:
	var from := {}
	if _map.selection_kind == "planet" and _map.selection_id >= 0:
		from = GameSession.view.planet_info(_map.selection_id)
	elif _map.selection_kind == "fleet":
		from = GameSession.view.fleet_info(_map.selection_id)
	_status.show_at(x, y, hit, from)


func _on_menu(menu_id: int) -> void:
	match menu_id:
		MENU_SAVE:
			var err := GameSession.save_game(GameSession.default_save_path())
			_messages.add("Game saved." if err == OK else "Saving failed (%s)." % error_string(err))
		MENU_MAIN:
			quit_requested.emit()
		MENU_QUIT:
			get_tree().quit()
		MENU_RESEARCH:
			_research.open()
		MENU_DESIGN:
			_designer.open()
		MENU_PLANS:
			_plans.open()
		MENU_RELATIONS:
			_relations.open()
		MENU_END_TURN:
			_on_end_turn()
		MENU_ABOUT:
			_about.popup_centered()
		MENU_SETTINGS:
			_settings.open()
		MENU_REPORT:
			# F3: the Planet report, then each report in turn, then closed; the menu item itself
			# opens the Planet report
			if KeyBindings.held("reports"):
				_reports.cycle()
			else:
				_reports.open(ReportView.PLANETS)
		MENU_SCORE:
			_score.open()
		MENU_REPORT + 1, MENU_REPORT + 2, MENU_REPORT + 3:
			_reports.open(ReportView.REPORTS[menu_id - MENU_REPORT])


func _on_end_turn() -> void:
	var was_eliminated := GameSession.view.me().eliminated
	var hotseat := GameSession.is_hotseat()
	if not GameSession.end_turn():
		return
	if hotseat:
		# the next player's hand-off (player_changed) or, the same player first again, this one
		if not _handoff.visible:
			_show_handoff()
		return
	_new_year()
	if not was_eliminated:
		_tell_if_eliminated()


## The year's start for the player at the controls: the messages, the orders refused, the map
## selection kept.
func _new_year() -> void:
	_messages.new_year()
	for line in GameSession.my_rejections():
		_messages.add("Order rejected: " + line)
	_map.select(_map.selection_kind, _map.selection_id)


func _on_player_changed() -> void:
	_show_handoff()


func _show_handoff() -> void:
	var me := GameSession.view.me()
	var lines := PackedStringArray()
	lines.append("Year %d" % GameSession.view.year())
	for p: int in _lost_players():
		if not _lost.has(p):
			lines.append(
				"The %s have been wiped out." % GameSession.state.player(p).race.display_plural()
			)
	_lost = _lost_players()
	lines.append("")
	lines.append("%s (player %d): your turn." % [me.race.display_plural(), me.index + 1])
	lines.append("Everyone else, look away.")
	_handoff_text.text = "\n".join(lines)
	_handoff.show()


## The game of the player now at the controls, from their homeworld (or first planet).
func _begin_turn() -> void:
	_handoff.hide()
	var home := GameSession.view.me().homeworld
	if home < 0 or not GameSession.view.planet_info(home)["mine"]:
		home = -1
		for pl in GameSession.state.planets:
			if pl.owner == GameSession.player:
				home = pl.id
				break
	if home >= 0:
		_map.select("planet", home)
	_new_year()


## The human players wiped out so far.
func _lost_players() -> Dictionary:
	var out := {}
	if GameSession.state == null:
		return out
	for p in GameSession.state.players:
		if p.is_human() and p.eliminated:
			out[p.index] = true
	return out


## The one-time notice that the player's race is gone (on the turn it happens, or when a game
## already lost is opened).
func _tell_if_eliminated() -> void:
	if GameSession.view.me().eliminated:
		_eliminated.popup_centered()
