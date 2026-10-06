class_name SummaryPane
extends PanelContainer
## The Selection Summary pane (D15): a raised title bar "<name> Summary", then for a planet its
## value, how current the report is and its population over the environment and mineral graphs,
## and for a fleet its picture beside ship count, fuel and cargo gauges, mass, next waypoint, task
## and warp.

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
	_fleet_box.add_child(FleetIcon.new())
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
