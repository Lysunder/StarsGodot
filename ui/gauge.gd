class_name Gauge
extends Control
## A gauge bar (D15): a black frame, coloured segments filled from the left in proportion to
## `maximum`, white where empty, and a caption centred over it in bold ("377 of 1200kT"). Used for
## fuel, cargo and (later) warp. A caption that doesn't fit is left out.

const HEIGHT := 16
const FRAME := Color.BLACK
const EMPTY := Color.WHITE
const CAPTION := Color.BLACK

## [[amount, colour], ...] drawn left to right.
var segments: Array = []
var maximum: int = 0
var caption: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Sets what the gauge shows and redraws it.
func show_values(p_segments: Array, p_maximum: int, p_caption: String) -> void:
	segments = p_segments
	maximum = p_maximum
	caption = p_caption
	queue_redraw()


## A single-colour gauge: "value of maximum<unit>".
func show_amount(value: int, p_maximum: int, colour: Color, unit: String) -> void:
	show_values([[value, colour]], p_maximum, "%d of %d%s" % [value, p_maximum, unit])


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, FRAME, false, 1.0)
	var inner := r.grow(-1)
	var x := inner.position.x
	if maximum > 0:
		var total := 0
		for seg: Array in segments:
			total += int(seg[0])
			var right := inner.position.x + inner.size.x * minf(float(total) / maximum, 1.0)
			if right > x:
				draw_rect(Rect2(x, inner.position.y, right - x, inner.size.y), seg[1])
				x = right
	if x < inner.end.x:
		draw_rect(Rect2(x, inner.position.y, inner.end.x - x, inner.size.y), EMPTY)
	var font := ClassicTheme.bold_font(self)
	var font_size := get_theme_default_font_size()
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if caption.is_empty() or width > inner.size.x - 2:
		return
	var baseline := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(
		font,
		Vector2((size.x - width) / 2.0, baseline),
		caption,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		CAPTION
	)
