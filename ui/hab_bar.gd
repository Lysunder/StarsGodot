class_name HabBar
extends Control
## One habitability bar of the race wizard (D15): black, with the race's range on this axis as a
## coloured band and its middle marked, or "Immune" across it. Pressing or dragging on it moves
## the range's middle there (`dragged`, 0..100).

signal dragged(at: int)

var axis: int = 0
var race: Race
var editable: bool = true
var _dragging: bool = false


func _init(p_axis: int = 0) -> void:
	axis = p_axis
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if not editable or race == null or race.is_immune(axis):
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		if mb.pressed:
			dragged.emit(_at(mb.position.x))
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		dragged.emit(_at((event as InputEventMouseMotion).position.x))
		accept_event()


func _at(x: float) -> int:
	return clampi(roundi((x - 1) / maxf(size.x - 2, 1) * 100), 0, 100)


func _x(value: int) -> float:
	return 1 + (size.x - 2) * value / 100.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), EnvironmentGraph.BAR)
	if race == null:
		return
	if race.is_immune(axis):
		var font := get_theme_default_font()
		var fsize := get_theme_default_font_size()
		var w := font.get_string_size("Immune", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), Palette.axis(axis))
		draw_string(
			font,
			Vector2((size.x - w) / 2, (size.y + font.get_ascent(fsize)) / 2 - 2),
			"Immune",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fsize,
			EnvironmentGraph.MARK
		)
		return
	var low := _x(race.hab_low[axis])
	var high := _x(race.hab_high[axis])
	draw_rect(Rect2(low, 3, high - low, size.y - 6), Palette.axis(axis))
	var mid := _x(race.hab_center[axis])
	draw_line(Vector2(mid, 2), Vector2(mid, size.y - 2), EnvironmentGraph.MARK, 2.0)
