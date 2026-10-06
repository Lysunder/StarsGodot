class_name ReportTable
extends Control
## A report's table (D15, as the original draws it in `Report_DrawTable@10f8:0798` and
## `Report_DrawRow@10f8:24e2`): a row of raised column labels that stays put, then one row per
## item on the dialog grey with thin lines between the columns, and scroll bars. Text is the
## original's colours: the item under command in dark red, minerals in their colours, and warnings
## (too many people or mines, no fuel to get there) in red.

## A column label was clicked (it opens the column's menu).
signal header_clicked(column: String, at: Vector2)
## A button went down on a row's cell.
signal cell_pressed(row: Dictionary, column: String, button: int, at: Vector2)
## The button went up again (it closes a popup held open).
signal released

const LINE := Color("808080")
const SELECTED := Color("7f0000")
const WARNING := Color("ff0000")
const FULL := Color("007f00")
const POOR := Color("7f7f00")
## The original's report colours for the parts of a several-number cell: ironium, boranium,
## germanium, colonists.
const PART_COLORS := [Color("0000ff"), Color("007f00"), Color("ffff00"), Color("ffffff")]
## Characters per part of a several-number column.
const PART_CHARS := {"minerals": 5, "mining": 4, "concentration": 4, "cargo": 5}
const PAD := 4
const DOT := 4
const LABELS := {
	ReportView.PLANETS:
	{
		"name": "Planet Name",
		"starbase": "Starbase",
		"population": "Population",
		"cap": "Cap",
		"value": "Value",
		"production": "Production",
		"mines": "Mine",
		"factories": "Fact",
		"defenses": "Defense",
		"minerals": "Minerals",
		"mining": "Mining Rate",
		"concentration": "Min Conc",
		"resources": "Resources",
		"driver": "Driver Dest",
		"route": "Routing Dest",
	},
	ReportView.FLEETS:
	{
		"name": "Fleet Name",
		"id": "ID",
		"location": "Location",
		"destination": "Destination",
		"eta": "ETA",
		"task": "Task",
		"fuel": "Fuel",
		"cargo": "Cargo",
		"composition": "Composition",
		"cloak": "Cloak",
		"battle_plan": "Battle Plan",
		"mass": "Mass",
	},
	ReportView.OTHERS:
	{
		"name": "Fleet Name",
		"id": "ID",
		"location": "Location",
		"warp": "Warp",
		"mass": "Mass",
		"composition": "Composition",
		"ships": "# of Ships",
		"unarmed": "Unarmed",
		"scout": "Scout",
		"warship": "Warship",
		"bomber": "Bomber",
		"utility": "Utility",
	},
	ReportView.BATTLES:
	{
		"location": "Location",
		"starbase": "SB",
		"sides": "Sides",
		"units": "Units",
		"ours": "Ours",
		"theirs": "Theirs",
		"unarmed": "Unarmed",
		"scout": "Scout",
		"warship": "Warship",
		"bomber": "Bomber",
		"utility": "Utility",
		"our_dead": "Our Dead",
		"their_dead": "Their Dead",
		"ours_left": "Ours Left",
		"theirs_left": "Theirs Left",
	},
}
## The parts of the several-number columns, for the sort menu.
const PART_NAMES := ["Ironium", "Boranium", "Germanium", "Colonists"]

var report: String = ReportView.PLANETS
## The columns shown, in order.
var columns: Array[String] = []
var rows: Array[Dictionary] = []
## The planet id or fleet number whose name is shown in dark red (the one under command).
var highlight: int = -1

var _widths: Array[float] = []
var _vbar: VScrollBar
var _hbar: HScrollBar


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	_vbar = VScrollBar.new()
	_vbar.value_changed.connect(func(_v: float) -> void: queue_redraw())
	add_child(_vbar)
	_hbar = HScrollBar.new()
	_hbar.value_changed.connect(func(_v: float) -> void: queue_redraw())
	add_child(_hbar)
	resized.connect(_layout)


## Shows `p_rows` of `p_report` in `p_columns`.
func show_rows(p_report: String, p_columns: Array[String], p_rows: Array[Dictionary]) -> void:
	if p_report != report:
		_vbar.value = 0
		_hbar.value = 0
	report = p_report
	columns = p_columns
	rows = p_rows
	_measure()
	_layout()
	queue_redraw()


static func label(p_report: String, column: String) -> String:
	return LABELS[p_report].get(column, column)


func row_height() -> int:
	return int(get_theme_default_font().get_height(get_theme_default_font_size())) + 4


func header_height() -> int:
	return row_height() + 2


## The column at `x` (in the table's own coordinates), or "".
func column_at(x: float) -> String:
	var left := -_hbar.value
	for i in columns.size():
		if x >= left and x < left + _widths[i]:
			return columns[i]
		left += _widths[i]
	return ""


## The row at `y`, or -1 (the labels, or below the last row).
func row_at(y: float) -> int:
	if y < header_height():
		return -1
	var i := int((y - header_height() + _vbar.value) / row_height())
	return i if i < rows.size() else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var step := (
						row_height() * 3 * (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
					)
					_vbar.value += step
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if not mb.pressed:
					released.emit()
					accept_event()
					return
				var column := column_at(mb.position.x)
				if column == "":
					return
				if mb.position.y < header_height():
					header_clicked.emit(column, mb.global_position)
				else:
					var r := row_at(mb.position.y)
					if r >= 0:
						cell_pressed.emit(rows[r], column, mb.button_index, mb.global_position)
				accept_event()


func _layout() -> void:
	var bar := _vbar.get_combined_minimum_size().x
	var hbar := _hbar.get_combined_minimum_size().y
	_vbar.position = Vector2(size.x - bar, 0)
	_vbar.size = Vector2(bar, size.y - hbar)
	_hbar.position = Vector2(0, size.y - hbar)
	_hbar.size = Vector2(size.x - bar, hbar)
	var total := 0.0
	for w in _widths:
		total += w
	_hbar.max_value = total
	_hbar.page = size.x - bar
	_vbar.max_value = rows.size() * row_height()
	_vbar.page = size.y - hbar - header_height()


func _measure() -> void:
	var font := get_theme_default_font()
	var fsize := get_theme_default_font_size()
	var bold := ClassicTheme.bold_font(self)
	var digit := font.get_string_size("8", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	_widths.clear()
	for column in columns:
		var w := bold.get_string_size(label(report, column), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if PART_CHARS.has(column):
			var n: int = ReportView.PARTS[column]
			w = maxf(w, digit * (PART_CHARS[column] + 1) * n)
		else:
			for row in rows:
				var c := cell(column, row)
				w = maxf(
					w, _parts_width(c["left"], font, fsize) + _parts_width(c["right"], font, fsize)
				)
			if column == "name" and report == ReportView.PLANETS:
				w += DOT + PAD
		_widths.append(w + PAD * 3)


static func _parts_width(parts: Array, font: Font, fsize: int) -> float:
	var w := 0.0
	for p: Array in parts:
		w += font.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	return w


## What a cell shows: {left: [[text, colour]...], right: [...]} (text from the left and the right
## edges), or {parts: [[text, colour]...]} for a several-number column, each right-aligned in its
## own slot.
func cell(column: String, row: Dictionary) -> Dictionary:
	var black := ClassicTheme.TEXT
	var out := {"left": [], "right": []}
	if PART_CHARS.has(column) and row.has(column):
		var parts := []
		var values: Array = row[column]
		for i in values.size():
			parts.append([short_number(values[i]), PART_COLORS[i]])
		return {"left": [], "right": [], "parts": parts}
	match column:
		"name":
			var own := int(row.get("id", row.get("number", -2)))
			out["left"] = [[row["name"], SELECTED if own == highlight else black]]
		"population":
			var over: bool = row["population"] > row["max_population"]
			out["right"] = [[CommandPane.thousands(row["population"]), WARNING if over else black]]
		"cap":
			out["right"] = [["%d%%" % row["cap"], black]]
		"value":
			var v: int = row["value"]
			var parts := [["%d%%" % v, WARNING if v < 0 else (POOR if v <= 10 else black)]]
			var t: int = row["value_terraformed"]
			if t > v:
				parts.append([" (%d%%)" % t, POOR if t <= 10 else black])
			out["right"] = parts
		"production":
			var p: Dictionary = row["production"]
			if not p.is_empty():
				out["left"] = [[p["name"], black]]
				out["right"] = [[str(p["count"]), black]]
		"mines", "factories", "defenses":
			var n: int = row[column]
			var most: int = row["max_" + column]
			var colour := black
			if n > most:
				colour = WARNING
			elif n == most:
				colour = FULL
			out["right"] = [
				["--" if column == "defenses" and n == 0 else CommandPane.thousands(n), colour]
			]
		"resources":
			out["right"] = [["%d / %d" % [row["resources_available"], row["resources"]], black]]
		"id":
			out["right"] = [[str(row["number"] + 1), black]]
		"destination", "location", "driver", "route", "starbase", "battle_plan":
			var text: String = row.get(column, "")
			out["left"] = [[text if text != "" or column != "destination" else "--", black]]
		"eta":
			var years: int = row["eta"]
			var text := "%dy" % years if years >= 0 else "--"
			out["right"] = [[text, WARNING if row["short_of_fuel"] else black]]
		"task":
			var task: String = row["task"]
			out["left"] = [[SummaryPane._task_name(task) if task != "" else "", black]]
		"fuel":
			out["right"] = [[str(row["fuel"]), PART_COLORS[0] if row["short_of_fuel"] else black]]
		"composition":
			var c: Dictionary = row["composition"]
			out["left"] = [[c["name"], WARNING if c["damaged"] else black]]
			out["right"] = [[str(c["count"]) + ("+" if c["multi"] else " "), black]]
		"cloak":
			out["right"] = [["%d%%" % row["cloak"] if row["cloak"] > 0 else "--", black]]
		_:
			if row.has(column):
				out["right"] = [[short_number(int(row[column])), black]]
	return out


## The original's short numbers (`FormatShortNumber@1038:8f42`): as they are below 10,000, then
## rounded thousands with "k" (at most 999k), then millions with "M".
static func short_number(n: int) -> String:
	if n < 10000:
		return str(n)
	if n < 1000000:
		return "%dk" % mini((n + 500) / 1000, 999)
	return "%dM" % mini((n + 500000) / 1000000, 999)


func _draw() -> void:
	var font := get_theme_default_font()
	var fsize := get_theme_default_font_size()
	var bold := ClassicTheme.bold_font(self)
	var ascent := font.get_ascent(fsize)
	var rh := row_height()
	var hh := header_height()
	var bar := _vbar.size.x
	var view_w := size.x - bar
	var view_h := size.y - _hbar.size.y
	draw_rect(Rect2(0, 0, view_w, view_h), ClassicTheme.FACE)
	var first := int(_vbar.value / rh)
	var last := mini(rows.size(), first + int(view_h / rh) + 2)
	var left := -_hbar.value
	for ci in columns.size():
		var column := columns[ci]
		var w := _widths[ci]
		if left + w > 0 and left < view_w:
			for r in range(first, last):
				var y := hh + r * rh - _vbar.value
				if y + rh < hh:
					continue
				_draw_cell(Rect2(left, y, w, rh), column, rows[r], font, fsize, ascent)
			draw_line(Vector2(left + w - 1, hh), Vector2(left + w - 1, view_h), LINE)
		left += w
	# the labels, drawn last so rows scrolled up go under them
	left = -_hbar.value
	for ci in columns.size():
		var rect := Rect2(left, 0, _widths[ci], hh)
		_draw_bevel(rect)
		var text := label(report, columns[ci])
		var tw := bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var at := Vector2(rect.position.x + (rect.size.x - tw) / 2, (hh - rh) / 2.0 + 2 + ascent)
		draw_string(bold, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, ClassicTheme.TEXT)
		left += _widths[ci]
	if left < view_w:
		_draw_bevel(Rect2(left, 0, view_w - left, hh))


func _draw_bevel(rect: Rect2) -> void:
	draw_rect(rect, ClassicTheme.FACE)
	draw_line(rect.position, Vector2(rect.end.x - 1, rect.position.y), ClassicTheme.HIGHLIGHT)
	draw_line(rect.position, Vector2(rect.position.x, rect.end.y - 1), ClassicTheme.HIGHLIGHT)
	draw_line(Vector2(rect.position.x, rect.end.y - 1), rect.end - Vector2.ONE, ClassicTheme.SHADOW)
	draw_line(Vector2(rect.end.x - 1, rect.position.y), rect.end - Vector2.ONE, ClassicTheme.SHADOW)


func _draw_cell(
	rect: Rect2, column: String, row: Dictionary, font: Font, fsize: int, ascent: float
) -> void:
	var c := cell(column, row)
	var base := rect.position.y + 2 + ascent
	if c.has("parts"):
		var parts: Array = c["parts"]
		var slot := (rect.size.x - PAD * 3) / parts.size()
		for i in parts.size():
			var text: String = parts[i][0]
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			var x := rect.position.x + PAD + slot * (i + 1) - tw
			draw_string(
				font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, parts[i][1]
			)
		return
	var x := rect.position.x + PAD
	for p: Array in c["left"]:
		draw_string(font, Vector2(x, base), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, p[1])
		x += font.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var right := rect.end.x - PAD
	var right_parts: Array = c["right"]
	for i in range(right_parts.size() - 1, -1, -1):
		var p: Array = right_parts[i]
		right -= font.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(font, Vector2(right, base), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, p[1])
	if column == "name" and report == ReportView.PLANETS:
		_draw_dots(rect, row)


## The dots after a planet's name, top to bottom: its starbase (yellow: it can build ships; blue:
## it can't), a mass driver (purple), a stargate (green).
func _draw_dots(rect: Rect2, row: Dictionary) -> void:
	var third := (rect.size.y - 2) / 3.0
	var x := rect.end.x - PAD - DOT
	var marks := [
		[row["dock"], Color("ffff00")],
		[row["no_dock"], Color("0000ff")],
	]
	if row["dock"] or row["no_dock"]:
		var colour: Color = marks[0][1] if row["dock"] else marks[1][1]
		draw_rect(Rect2(x, rect.position.y + 1, DOT, third - 1), colour)
	if row["driver_dot"]:
		draw_rect(Rect2(x, rect.position.y + 1 + third, DOT, third - 1), Color("800080"))
	if row["gate"]:
		draw_rect(Rect2(x, rect.position.y + 1 + third * 2, DOT, third - 1), Color("00ff00"))
