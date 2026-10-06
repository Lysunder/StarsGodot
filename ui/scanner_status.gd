class_name ScannerStatus
extends PanelContainer
## The status bar under the Scanner (D15): the object under the mouse (its id, X and Y, its
## name) in sunken boxes, and how far the mouse is from the selected object.

const ID_WIDTH := 70
const XY_WIDTH := 70

var _id: Label
var _x: Label
var _y: Label
var _name: Label
var _distance: Label


func _ready() -> void:
	theme_type_variation = "TileBody"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	_id = _field(row, ID_WIDTH)
	_x = _field(row, XY_WIDTH)
	_y = _field(row, XY_WIDTH)
	_name = _field(row, 0)
	_name.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_distance = _field(box, 0)


func _field(parent: Control, width: int) -> Label:
	var frame := PanelContainer.new()
	frame.theme_type_variation = "SunkenField"
	frame.custom_minimum_size = Vector2(width, 0)
	parent.add_child(frame)
	var l := Label.new()
	l.theme_type_variation = "BoldLabel"
	frame.add_child(l)
	return l


## Shows the mouse position and the object there; `from` is the selected object's
## {name, x, y} (or {}) for the distance line.
func show_at(x: int, y: int, hit: Dictionary, from: Dictionary) -> void:
	_x.text = "X: %d" % x
	_y.text = "Y: %d" % y
	_id.text = ""
	_name.text = ""
	if not hit.is_empty():
		if hit["kind"] == "planet":
			var info := GameSession.view.planet_info(hit["id"])
			_id.text = "ID #%d" % (hit["id"] + 1)
			_name.text = info["name"]
			_x.text = "X: %d" % info["x"]
			_y.text = "Y: %d" % info["y"]
		else:
			var f := GameSession.view.fleet_info(hit["id"])
			_id.text = "ID #%d" % (hit["id"] + 1)
			_name.text = f.get("name", "")
	_distance.text = ""
	if not from.is_empty():
		var d := Vector2(x - from["x"], y - from["y"]).length()
		_distance.text = "%.2f light years from %s" % [d, from["name"]]
