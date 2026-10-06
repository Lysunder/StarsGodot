class_name MineralGraph
extends Control
## The Selection Summary's mineral graph (D15): per mineral, a black bar with the surface amount
## as a light bar (and next year's mining as a darker piece after it) on a kT scale, and the
## mineral concentration as a diamond (the bar's width is concentration 100; a + past the end
## means more). The scale is marked in 500 kT steps below.

const LABELS := ["Ironium", "Boranium", "Germanium"]
const SURFACE := Color("c0c0c0")
const MINED := Color("808080")
const DIAMOND := Color("a0a0a0")
const BAR := Color.BLACK
const GRID := Color("404040")
const LABEL_WIDTH := 100
const RIGHT_PAD := 60
const ROW := 16
const STEP := 500
const MIN_SCALE := 2500

var info: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(0, ROW * 4 + 2)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func show_planet(p_info: Dictionary) -> void:
	info = p_info
	queue_redraw()


func _draw() -> void:
	if info.is_empty() or not info.get("known", false):
		return
	var font := ClassicTheme.bold_font(self)
	var plain := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var left := float(LABEL_WIDTH)
	var width := size.x - LABEL_WIDTH - RIGHT_PAD
	var mined: Array = info.get("mined_next_year", [0, 0, 0])
	var biggest := MIN_SCALE
	for m in 3:
		biggest = maxi(biggest, info["surface"][m] + mined[m])
	var scale := ceili(float(biggest) / STEP) * STEP
	var area := Rect2(left, 1, width, ROW * 3 - 2)
	draw_rect(area, BAR)
	for kt in range(STEP, scale, STEP):
		var gx := left + width * kt / scale
		draw_line(Vector2(gx, area.position.y), Vector2(gx, area.end.y), GRID, 1.0)
	for m in 3:
		var top := m * ROW + 1.0
		var baseline := top + (ROW + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
		var label_w := font.get_string_size(LABELS[m], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			Vector2(left - 6 - label_w, baseline),
			LABELS[m],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			ClassicTheme.CARGO_COLORS[m]
		)
		var surface: int = info["surface"][m]
		var w_surface := width * float(surface) / scale
		draw_rect(Rect2(left, top + 2, w_surface, ROW - 6), SURFACE)
		var w_mined := width * float(mined[m]) / scale
		if w_mined > 0.0:
			draw_rect(Rect2(left + w_surface, top + 2, w_mined, ROW - 6), MINED)
		var conc: int = info["concentration"][m]
		var cx := left + width * minf(conc / 100.0, 1.0)
		var cy := top + (ROW - 2) / 2.0
		var d := PackedVector2Array(
			[Vector2(cx, cy - 5), Vector2(cx + 5, cy), Vector2(cx, cy + 5), Vector2(cx - 5, cy)]
		)
		draw_colored_polygon(d, DIAMOND)
		if conc > 100:
			draw_string(
				font,
				Vector2(left + width + 4, baseline),
				"+",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				ClassicTheme.TEXT
			)
	var scale_y := ROW * 3 + font.get_ascent(font_size)
	draw_string(
		plain,
		Vector2(left - 24, scale_y),
		"kT",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		ClassicTheme.TEXT
	)
	for kt in range(0, scale + 1, STEP):
		var text := str(kt)
		var tw := plain.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var gx := left + width * kt / scale - tw / 2.0
		draw_string(
			plain,
			Vector2(gx, scale_y),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			ClassicTheme.TEXT
		)
