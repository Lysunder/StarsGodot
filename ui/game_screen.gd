class_name GameScreen
extends VBoxContainer
## The game screen (D15): the menu bar (File, View, Turn, Commands, Report, Help, in the original's
## order), then four resizable panes: Command (top left), Scanner (top right, with its toolbar
## above and status bar below), Messages (bottom left; it shows the year), Selection Summary
## (bottom right). Clicking an object selects it for the summary; the player's own planets and
## fleets also come under command. F9 generates the turn.

signal quit_requested

const LEFT_WIDTH := 400
const SUMMARY_HEIGHT := 200
const MESSAGES_HEIGHT := 150
const MENU_SAVE := 0
const MENU_MAIN := 1
const MENU_QUIT := 2
const MENU_RESEARCH := 10
const MENU_DESIGN := 11
const MENU_END_TURN := 20
const MENU_ABOUT := 40
## View > Font items are this plus the index in ClassicTheme.FONTS.
const MENU_FONT := 30

var _map: GalaxyMap
var _command: CommandPane
var _summary: SummaryPane
var _messages: MessagesPane
var _status: ScannerStatus
var _research: ResearchDialog
var _designer: ShipDesigner
var _about: AcceptDialog


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
	_messages.goto.connect(_on_goto)
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
	_about = AcceptDialog.new()
	_about.title = "About StarsGodot"
	_about.dialog_text = (
		"StarsGodot\nA reimplementation of the game rules of Stars! 2.6i in Godot.\n"
		+ "Version %s" % GameSession.game_version
	)
	add_child(_about)
	_messages.add("Year %d." % GameSession.view.year())
	var home := GameSession.view.me().homeworld
	if home >= 0:
		_messages.add(
			"Your home planet is %s." % GameSession.view.planet_info(home)["name"], "planet", home
		)
		_map.select("planet", home)


func _build_menu() -> void:
	var menu := MenuBar.new()
	add_child(menu)
	var file := PopupMenu.new()
	file.name = "File"
	file.add_item("Save", MENU_SAVE, KEY_MASK_CTRL | KEY_S)
	file.add_item("Close (Main Menu)", MENU_MAIN)
	file.add_separator()
	file.add_item("Exit", MENU_QUIT)
	file.id_pressed.connect(_on_menu)
	menu.add_child(file)
	var view := PopupMenu.new()
	view.name = "View"
	var current := ClassicTheme.saved_font()
	for i in ClassicTheme.FONTS.size():
		view.add_radio_check_item("Font: " + ClassicTheme.FONTS[i]["name"], MENU_FONT + i)
		view.set_item_checked(i, i == current)
	view.id_pressed.connect(_on_font.bind(view))
	menu.add_child(view)
	var turn := PopupMenu.new()
	turn.name = "Turn"
	turn.add_item("Generate", MENU_END_TURN, KEY_F9)
	turn.id_pressed.connect(_on_menu)
	menu.add_child(turn)
	var commands := PopupMenu.new()
	commands.name = "Commands"
	commands.add_item("Ship Design...", MENU_DESIGN, KEY_F4)
	commands.add_item("Research...", MENU_RESEARCH, KEY_F5)
	commands.id_pressed.connect(_on_menu)
	menu.add_child(commands)
	var report := PopupMenu.new()
	report.name = "Report"
	report.add_item("(reports come later)")
	report.set_item_disabled(0, true)
	menu.add_child(report)
	var help := PopupMenu.new()
	help.name = "Help"
	help.add_item("About StarsGodot...", MENU_ABOUT)
	help.id_pressed.connect(_on_menu)
	menu.add_child(help)


func _on_selected(kind: String, id: int) -> void:
	_summary.show_object(kind, id)
	var own := kind == "fleet"
	if kind == "planet":
		own = GameSession.view.planet_info(id)["mine"]
	if own:
		_command.command(kind, id)


func _on_goto(kind: String, id: int) -> void:
	_map.select(kind, id)


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
		MENU_END_TURN:
			_on_end_turn()
		MENU_ABOUT:
			_about.popup_centered()


func _on_font(menu_id: int, view: PopupMenu) -> void:
	var index := menu_id - MENU_FONT
	for i in view.item_count:
		view.set_item_checked(i, i == index)
	ClassicTheme.save_font(index)
	get_tree().root.theme = ClassicTheme.build(index)


func _on_end_turn() -> void:
	var rejected := GameSession.end_turn()
	_messages.clear()
	_messages.add("Year %d." % GameSession.view.year())
	for line in rejected:
		_messages.add("Order rejected: " + line)
	_map.select(_map.selection_kind, _map.selection_id)
