class_name WarpGauge
extends Gauge
## The Fleet Waypoints tile's warp factor (D15): a red gauge reading "Warp 9" ("Stopped" at 0)
## that the player drags to set the speed, like the original's (`DrawFleetSpeed@1048:2ab0`).

## The value while the mouse drags it.
signal value_dragged(value: int)
## The value when the mouse is let go (or after a click).
signal value_set(value: int)

const MAX_WARP := 10
const FILL := Color("ff0000")

var value: int = 0
var _dragging := false


func _init() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HSIZE


func set_value(v: int) -> void:
	value = clampi(v, 0, MAX_WARP)
	show_values([[value, FILL]], MAX_WARP, "Stopped" if value == 0 else "Warp %d" % value)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_to(event.position.x)
		elif _dragging:
			_dragging = false
			value_set.emit(value)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to(event.position.x)
		accept_event()


## The warp under x: the gauge is split into MAX_WARP equal steps, rounding to the nearest.
func _drag_to(x: float) -> void:
	var inner := maxf(size.x - 2.0, 1.0)
	var v := clampi(roundi((x - 1.0) / inner * MAX_WARP), 0, MAX_WARP)
	if v != value:
		set_value(v)
		value_dragged.emit(v)
