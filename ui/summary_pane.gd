class_name SummaryPane
extends PanelContainer
## The Selection Summary pane (D15): a raised title bar "<name> Summary", then for a planet its
## value, how current the report is and its population over the environment and mineral graphs,
## and for a fleet its picture beside ship count, fuel and cargo gauges, mass, next waypoint, task
## and warp. Holding the left button on the fleet's picture shows its ships, the right button its
## main design; the popup goes when the button is let go.

const ROW_GAP := 2

var kind: String = ""
var id: int = -1

var _title: Label
var _planet_box: VBoxContainer
var _value: Label
var _report: Label
var _population: Label
var _environment: EnvironmentGraph
var _minerals: MineralGraph
var _fleet_box: HBoxContainer
var _fleet_fields: GridContainer
var _fuel: Gauge
var _cargo: Gauge
var _popup: HoldPopup


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_GAP)
	add_child(box)
	var bar := PanelContainer.new()
	bar.theme_type_variation = "TileBar"
	box.add_child(bar)
	_title = Label.new()
	_title.theme_type_variation = "BoldLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_title)
	_planet_box = VBoxContainer.new()
	box.add_child(_planet_box)
	var line := HBoxContainer.new()
	_planet_box.add_child(line)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(left)
	_value = _bold(left)
	_report = _bold(left)
	_population = _bold(line)
	_environment = EnvironmentGraph.new()
	_planet_box.add_child(_environment)
	_minerals = MineralGraph.new()
	_planet_box.add_child(_minerals)
	_fleet_box = HBoxContainer.new()
	box.add_child(_fleet_box)
	var icon := FleetIcon.new()
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.gui_input.connect(_on_icon_input)
	_fleet_box.add_child(icon)
	_popup = HoldPopup.new()
	add_child(_popup)
	_fleet_fields = GridContainer.new()
	_fleet_fields.columns = 2
	_fleet_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fleet_box.add_child(_fleet_fields)
	GameSession.changed.connect(refresh)
	refresh()


func _bold(parent: Control) -> Label:
	var l := Label.new()
	l.theme_type_variation = "BoldLabel"
	parent.add_child(l)
	return l


func show_object(p_kind: String, p_id: int) -> void:
	kind = p_kind
	id = p_id
	refresh()


func refresh() -> void:
	_planet_box.visible = false
	_fleet_box.visible = false
	if not GameSession.has_game() or id < 0:
		_title.text = ""
		return
	if kind == "planet":
		_show_planet()
	else:
		_show_fleet()


func _show_planet() -> void:
	var info := GameSession.view.planet_info(id)
	_title.text = "%s Summary" % info["name"]
	_planet_box.visible = true
	if not info["known"]:
		_value.text = "No information."
		_report.text = ""
		_population.text = ""
		_environment.show_planet({})
		_minerals.show_planet({})
		return
	_value.text = "Value: %d%%" % info["habitability"]
	_report.text = "Report is current"
	_population.text = (
		"Population: %s" % CommandPane.thousands(info["population"] * 100)
		if info["population"] > 0
		else ""
	)
	_environment.show_planet(info)
	_minerals.show_planet(info)


func _show_fleet() -> void:
	var info := GameSession.view.fleet_info(id)
	if info.is_empty():
		_title.text = ""
		return
	_title.text = "%s Summary" % info["name"]
	_fleet_box.visible = true
	for child in _fleet_fields.get_children():
		child.queue_free()
	var count := 0
	for s: Dictionary in info["ships"]:
		count += s["count"]
	_field("Ship Count:", str(count))
	_fuel = Gauge.new()
	_cargo = Gauge.new()
	_field("Fuel:", "", _fuel)
	_field("Cargo:", "", _cargo)
	CommandPane.fill_gauges(info, _fuel, _cargo)
	_field("Mass:", "%skT" % CommandPane.thousands(info["mass"]))
	var waypoints: Array = info["waypoints"]
	if waypoints.size() > 1:
		var next: Dictionary = waypoints[1]
		_field("WP:", next["label"])
		_field("Task:", _task_name(next["task"]))
		_field("Warp:", str(next["warp"]))
	else:
		_field("Task:", _task_name(waypoints[0]["task"]) if not waypoints.is_empty() else "None")


## While a button is held on the fleet's picture: the left shows the ships in the fleet, the right
## the fleet's main design (as the original's summary does); letting go closes it.
func _on_icon_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or kind != "fleet":
		return
	var button: int = event.button_index
	if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
		return
	if not event.pressed:
		_popup.close()
		return
	var content := _ships_view() if button == MOUSE_BUTTON_LEFT else _design_view()
	if content != null:
		_popup.open(content, get_global_mouse_position())
	accept_event()


## The fleet's ships: each design with how many.
func _ships_view() -> Control:
	var info := GameSession.view.fleet_info(id)
	if info.is_empty():
		return null
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = info["name"]
	title.theme_type_variation = "BoldLabel"
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)
	for s: Dictionary in info["ships"]:
		var name := Label.new()
		name.text = s["name"]
		grid.add_child(name)
		var count := Label.new()
		count.text = str(s["count"])
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(count)
	return box


## The fleet's main design: its hull picture with the parts in place, and its totals.
func _design_view() -> Control:
	var view := GameSession.view
	var fleet := view.state.fleet(GameSession.PLAYER, id)
	if fleet == null:
		return null
	var slot: int = FleetOrders.main_design(fleet, view.me(), GameSession.content)[0]
	var design := view.me().ship_design(slot)
	if design == null:
		return null
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "%s (%s)" % [design.name, GameSession.content.display_name(design.hull)]
	title.theme_type_variation = "BoldLabel"
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var schematic := HullSchematic.new()
	schematic.show_design(design, false)
	schematic.fit_to_hull()
	schematic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(schematic)
	var stats := view.designer.design_stats(design, false)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	row.add_child(grid)
	var cost: Array = stats["cost"]
	var rows := [
		["Ironium", "%dkT" % cost[0], ClassicTheme.CARGO_COLORS[0]],
		["Boranium", "%dkT" % cost[1], ClassicTheme.CARGO_COLORS[1]],
		["Germanium", "%dkT" % cost[2], ClassicTheme.CARGO_COLORS[2]],
		["Resources", str(cost[3]), Color()],
		["Mass", "%skT" % CommandPane.thousands(stats["mass"]), Color()],
		["Max Fuel", "%smg" % CommandPane.thousands(stats["fuel"]), Color()],
		["Armor", "%sdp" % CommandPane.thousands(stats["armor"]), Color()],
		["Shields", "%sdp" % CommandPane.thousands(stats["shields"]), Color()],
		["Cargo", "%skT" % CommandPane.thousands(stats["cargo"]), Color()],
	]
	for entry: Array in rows:
		var name := Label.new()
		name.text = entry[0]
		name.theme_type_variation = "BoldLabel"
		if entry[2] != Color():
			name.add_theme_color_override("font_color", entry[2])
		grid.add_child(name)
		var value := Label.new()
		value.text = entry[1]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
	return box


func _field(label: String, value: String, control: Control = null) -> void:
	var l := Label.new()
	l.text = label
	l.theme_type_variation = "BoldLabel"
	_fleet_fields.add_child(l)
	if control == null:
		control = Label.new()
		(control as Label).text = value
		(control as Label).theme_type_variation = "BoldLabel"
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fleet_fields.add_child(control)


static func _task_name(task: String) -> String:
	for t: Array in CommandPane.TASKS:
		if t[0] == task:
			return "None" if task == "none" else t[1]
	return task
