class_name ScoreGraph
extends Control
## The score report's history graph (D15; the original's `Score_DrawHistoryGraph@10f8:1a0e`
## arrangement): one figure over the years, a line per player whose records the viewer has (its
## own drawn thicker), on a sunken white plot with the years along the bottom and the values up
## the side, and the players' names in their colours below. Clicking it lists the figures to pick.

## The figure picked from the click menu.
signal field_picked(field: String)

const PLAYER_COLORS := [
	Color("0000c0"),
	Color("c00000"),
	Color("008000"),
	Color("a000a0"),
	Color("c08000"),
	Color("008080"),
	Color("606060"),
	Color("ff4080"),
	Color("4080ff"),
	Color("80c000"),
	Color("804000"),
	Color("000060"),
	Color("600000"),
	Color("006040"),
	Color("8060ff"),
	Color("ff8040"),
]
const PLOT := Color(1, 1, 1)
const GRID := Color(0.85, 0.85, 0.85)
const MARGIN_LEFT := 56.0
const MARGIN := 10.0
const LEGEND_ROW := 18.0
const TITLE_GAP := 10.0
## Year steps for the marks along the bottom; the smallest giving at most YEAR_MARKS marks.
const YEAR_STEPS := [1, 2, 5, 10, 20, 50, 100]
const YEAR_MARKS := 8
## Value steps for the side scale, smallest first; above the last, multiples of it.
const STEPS := [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000]
const LABELS := {
	"planets": "Planets",
	"starbases": "Starbases",
	"unarmed": "Unarmed Ships",
	"escorts": "Escort Ships",
	"capitals": "Capital Ships",
	"tech": "Tech Levels",
	"resources": "Resources",
	"score": "Score",
	"rank": "Rank",
}

var field: String = "score"
## [{player, points: [Vector2i(year, value)]}] (ScoreView.series).
var lines: Array[Dictionary] = []
## The viewer's player (drawn thicker) and every player's name.
var me: int = 0
var names: Array[String] = []

var _menu: PopupMenu


func _init() -> void:
	custom_minimum_size = Vector2(520, 320)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(func(id: int) -> void: field_picked.emit(ScoreView.GRAPH_FIELDS[id]))
	add_child(_menu)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	_menu.clear()
	for i in ScoreView.GRAPH_FIELDS.size():
		var f: String = ScoreView.GRAPH_FIELDS[i]
		_menu.add_radio_check_item(LABELS[f], i)
		_menu.set_item_checked(i, f == field)
	_menu.position = Vector2i(mb.global_position)
	_menu.reset_size()
	_menu.popup()
	accept_event()


static func color(p: int) -> Color:
	return PLAYER_COLORS[p % PLAYER_COLORS.size()]


## The side scale's top: the smallest step multiple of 5 steps at or above `most`.
static func scale_top(most: int) -> int:
	for s: int in STEPS:
		if s * 5 >= most:
			return s * 5
	var big: int = STEPS[-1] * 5
	return ceili(float(most) / big) * big


func _plot_rect() -> Rect2:
	var legend := ceili(lines.size() / 4.0) * LEGEND_ROW
	var font := get_theme_default_font()
	var fsize := get_theme_default_font_size()
	var text_h := font.get_height(fsize)
	return Rect2(
		MARGIN_LEFT,
		MARGIN + text_h + TITLE_GAP,
		size.x - MARGIN_LEFT - MARGIN,
		size.y - 2 * MARGIN - 2 * text_h - TITLE_GAP - legend - 8
	)


func _draw() -> void:
	var font := get_theme_default_font()
	var fsize := get_theme_default_font_size()
	var text := ClassicTheme.TEXT
	draw_string(
		font,
		Vector2(MARGIN_LEFT, MARGIN + font.get_ascent(fsize)),
		LABELS[field] + " by Year",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fsize,
		text
	)
	var r := _plot_rect()
	draw_rect(r, PLOT)
	draw_rect(r.grow(1), ClassicTheme.SHADOW, false, 1.0)
	var first := 0
	var last := 0
	var most := 1
	for line: Dictionary in lines:
		for pt: Vector2i in line["points"]:
			first = pt.x if first == 0 else mini(first, pt.x)
			last = maxi(last, pt.x)
			most = maxi(most, pt.y)
	if lines.is_empty():
		draw_string(
			font,
			r.position + Vector2(8, 8 + font.get_ascent(fsize)),
			"No history yet.",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fsize,
			text
		)
		return
	var span := maxi(last - first, 1)
	var top := scale_top(most)
	# five steps up the side
	for i in range(0, 6):
		var y := r.end.y - r.size.y * i / 5.0
		if i > 0 and i < 5:
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), GRID)
		var label := str(top * i / 5)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(
			font,
			Vector2(r.position.x - 6 - w, y + font.get_ascent(fsize) / 2.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fsize,
			text
		)
	var base := r.end.y + 4 + font.get_ascent(fsize)
	var step: int = YEAR_STEPS[-1]
	for s: int in YEAR_STEPS:
		if span / s < YEAR_MARKS:
			step = s
			break
	var year := ceili(float(first) / step) * step
	while year <= last:
		var x := r.position.x + r.size.x * (year - first) / span
		draw_line(Vector2(x, r.end.y), Vector2(x, r.end.y - 4), ClassicTheme.SHADOW)
		var label := str(year)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		x = clampf(x - w / 2.0, r.position.x - w / 2.0, r.end.x - w)
		draw_string(font, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, text)
		year += step
	for line: Dictionary in lines:
		var pts := PackedVector2Array()
		for pt: Vector2i in line["points"]:
			pts.append(
				Vector2(
					r.position.x + r.size.x * (pt.x - first) / span, r.end.y - r.size.y * pt.y / top
				)
			)
		var width := 3.0 if int(line["player"]) == me else 1.5
		if pts.size() == 1:
			draw_circle(pts[0], width + 1, color(line["player"]))
		else:
			draw_polyline(pts, color(line["player"]), width)
	# the legend: four names a row
	var column := (size.x - 2 * MARGIN) / 4.0
	for i in lines.size():
		var p: int = lines[i]["player"]
		var at := Vector2(MARGIN + column * (i % 4), base + LEGEND_ROW + 4 + LEGEND_ROW * (i / 4))
		draw_rect(Rect2(at + Vector2(0, -10), Vector2(12, 4)), color(p))
		var label_text := names[p] if p < names.size() else str(p)
		draw_string(
			font,
			at + Vector2(16, 0),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			column - 20,
			fsize,
			color(p)
		)
