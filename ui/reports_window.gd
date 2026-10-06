class_name ReportsWindow
extends Window
## The report window (D15; the original's `REPORTDLG@10f8:0000`): one window showing one report at
## a time, titled "Planet Summary Report -- 5 Planets" and so on. F3 opens the Planet report, and
## each press after goes on to the Fleet, Others' Fleets and Battle reports, then closes it; Escape
## closes it.
##
## Clicking a column label opens its menu: sort by it (forward or reverse; by each mineral in a
## column of several), hide it, or show a hidden column. The sort before becomes the second level.
## Clicking a row puts its planet or fleet under command; some cells do more: a planet's
## Production opens the Production dialog, its Starbase shows the design while the button is held;
## a fleet's Composition shows its ships while held, its Fuel and Cargo open the cargo transfer.

signal goto(kind: String, id: int)
signal production_requested(planet: int)
signal cargo_requested(fleet: int)

const TITLES := {
	ReportView.PLANETS: ["Planet Summary Report", "Planet"],
	ReportView.FLEETS: ["Fleet Summary Report", "Fleet"],
	ReportView.OTHERS: ["Others' Fleets Summary Report", "Fleet"],
	ReportView.BATTLES: ["Battle Summary Report", "Battle"],
}
const START_SIZE := Vector2i(900, 360)

var report: String = ReportView.PLANETS
var table: ReportTable

var _menu: PopupMenu
## What each menu item does: {kind: "sort" | "hide" | "show", column, sub, forward}.
var _menu_actions: Array[Dictionary] = []
var _popup: HoldPopup


func _init() -> void:
	visible = false
	wrap_controls = false
	transient = true
	exclusive = false
	size = START_SIZE
	min_size = Vector2i(320, 160)
	close_requested.connect(hide)
	window_input.connect(_on_window_input)
	var back := Panel.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	table = ReportTable.new()
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table.header_clicked.connect(_on_header_clicked)
	table.cell_pressed.connect(_on_cell_pressed)
	table.released.connect(func() -> void: _popup.close())
	add_child(table)
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu_item)
	add_child(_menu)
	_popup = HoldPopup.new()
	table.add_child(_popup)


func _ready() -> void:
	GameSession.changed.connect(refresh)


## Shows `p_report`.
func open(p_report: String) -> void:
	report = p_report
	refresh()
	if not visible:
		popup_centered()
	grab_focus()


## F3: the Planet report when closed, else the next report; after the Battle report, closes.
func cycle() -> void:
	if not visible:
		open(ReportView.PLANETS)
		return
	var next := ReportView.REPORTS.find(report) + 1
	if next >= ReportView.REPORTS.size():
		hide()
	else:
		open(ReportView.REPORTS[next])


## The object under command, shown in dark red.
func set_highlight(kind: String, id: int) -> void:
	var wanted := "planet" if report == ReportView.PLANETS else "fleet"
	table.highlight = id if kind == wanted else -1
	table.queue_redraw()


func refresh() -> void:
	if not GameSession.has_game():
		return
	var s := ReportSettings.of(report)
	var columns: Array[String] = []
	for c: String in ReportView.COLUMNS[report]:
		if not (s["hidden"] as Array).has(c):
			columns.append(c)
	var rows := ReportView.sorted(
		ReportView.rows(GameSession.view, report), report, s["primary"], s["secondary"]
	)
	table.show_rows(report, columns, rows)
	var t: Array = TITLES[report]
	title = "%s -- %d %s%s" % [t[0], rows.size(), t[1], "" if rows.size() == 1 else "s"]


func _on_window_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			hide()
			set_input_as_handled()
		KEY_F3:
			cycle()
			set_input_as_handled()


func _on_header_clicked(column: String, at: Vector2) -> void:
	_menu.clear()
	_menu_actions.clear()
	var name := ReportTable.label(report, column)
	if ReportView.PARTS.has(column):
		for i in ReportView.PARTS[column]:
			var part: String = ReportTable.PART_NAMES[i]
			_add(
				"Sort by %s (%s)" % [name, part],
				{"kind": "sort", "column": column, "sub": i, "forward": true}
			)
			_add(
				"Reverse Sort by %s (%s)" % [name, part],
				{"kind": "sort", "column": column, "sub": i, "forward": false}
			)
	else:
		_add("Sort by " + name, {"kind": "sort", "column": column, "sub": 0, "forward": true})
		_add(
			"Reverse Sort by " + name,
			{"kind": "sort", "column": column, "sub": 0, "forward": false}
		)
	var s := ReportSettings.of(report)
	var hidden: Array = s["hidden"]
	if table.columns.size() > 1:
		_menu.add_separator()
		_add("Hide the %s column" % name, {"kind": "hide", "column": column})
	if not hidden.is_empty():
		_menu.add_separator()
		for c: String in ReportView.COLUMNS[report]:
			if hidden.has(c):
				_add(
					"Show the %s column" % ReportTable.label(report, c),
					{"kind": "show", "column": c}
				)
	_menu.position = Vector2i(at) + position
	_menu.reset_size()
	_menu.popup()


func _add(text: String, action: Dictionary) -> void:
	_menu.add_item(text, _menu_actions.size())
	_menu_actions.append(action)


func _on_menu_item(item: int) -> void:
	var action := _menu_actions[item]
	var s := ReportSettings.of(report)
	match action["kind"]:
		"sort":
			action.erase("kind")
			ReportSettings.sort_by(report, action)
		"hide":
			(s["hidden"] as Array).append(action["column"])
			ReportSettings.save(report, s)
		"show":
			(s["hidden"] as Array).erase(action["column"])
			ReportSettings.save(report, s)
	refresh()


func _on_cell_pressed(row: Dictionary, column: String, button: int, at: Vector2) -> void:
	if report == ReportView.PLANETS:
		var id: int = row["id"]
		if column == "starbase" and row["starbase"] != "":
			var pl := GameSession.view.state.planet(id)
			var design := GameSession.view.me().starbase_design(pl.starbase.design)
			_hold(SummaryPane.design_view(design, true), at)
			return
		if button != MOUSE_BUTTON_LEFT:
			return
		goto.emit("planet", id)
		if column == "production":
			production_requested.emit(id)
	elif report == ReportView.FLEETS:
		var number: int = row["number"]
		if column == "composition":
			_hold(SummaryPane.ships_view(GameSession.view.fleet_info(number)), at)
			return
		if button != MOUSE_BUTTON_LEFT:
			return
		goto.emit("fleet", number)
		if column == "fuel" or column == "cargo":
			cargo_requested.emit(number)


func _hold(content: Control, at: Vector2) -> void:
	if content != null:
		_popup.open(content, at)
