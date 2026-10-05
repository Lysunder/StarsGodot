class_name SummaryPane
extends PanelContainer
## The Selection Summary pane (D15): what the object selected in the scanner is like, for any
## planet or the player's fleets.

const ENVIRONMENT := ["Gravity", "Temperature", "Radiation"]
const MINERALS := ["Ironium", "Boranium", "Germanium"]

var kind: String = ""
var id: int = -1

var _text: Label


func _ready() -> void:
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_text)
	GameSession.changed.connect(refresh)


func show_object(p_kind: String, p_id: int) -> void:
	kind = p_kind
	id = p_id
	refresh()


func refresh() -> void:
	if not GameSession.has_game() or id < 0:
		_text.text = ""
		return
	_text.text = _planet() if kind == "planet" else _fleet()


func _planet() -> String:
	var info := GameSession.view.planet_info(id)
	var lines := PackedStringArray()
	var owner := "Uninhabited"
	if info["owner"] >= 0:
		owner = "Yours" if info["mine"] else "Player %d" % (info["owner"] + 1)
	lines.append("%s   %s" % [info["name"], owner])
	if not info["known"]:
		lines.append("No data.")
		return "\n".join(lines)
	lines.append(
		(
			"Value: %d%%   Population: %d of %d"
			% [info["habitability"], info["population"] * 100, info["max_population"] * 100]
		)
	)
	var env := PackedStringArray()
	for i in 3:
		env.append("%s %d" % [ENVIRONMENT[i], info["environment"][i]])
	lines.append("   ".join(env))
	var minerals := PackedStringArray()
	for i in 3:
		minerals.append(
			(
				"%s %d kT, concentration %d"
				% [MINERALS[i], info["surface"][i], info["concentration"][i]]
			)
		)
	lines.append("\n".join(minerals))
	return "\n".join(lines)


func _fleet() -> String:
	var info := GameSession.view.fleet_info(id)
	if info.is_empty():
		return ""
	var lines := PackedStringArray([info["name"]])
	for s: Dictionary in info["ships"]:
		lines.append("%d × %s" % [s["count"], s["name"]])
	lines.append("At (%d, %d)" % [info["x"], info["y"]])
	var waypoints: Array = info["waypoints"]
	if waypoints.size() > 1:
		lines.append(
			"Heading for %s, arriving in %d yr" % [waypoints[1]["label"], waypoints[1]["years"]]
		)
	return "\n".join(lines)
