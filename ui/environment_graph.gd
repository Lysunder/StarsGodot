class_name EnvironmentGraph
extends Control
## The Selection Summary's environment graph (D15): for gravity, temperature and radiation, a
## black bar with the player's habitable range as a coloured band, the planet's current value as
## a ringed cross, its original value as a small cross, a line to the best value terraforming
## could reach, and the current value in the original's units on the right.

const LABELS := ["Gravity", "Temperature", "Radiation"]
const BANDS := [Color("0000c0"), Color("c00000"), Color("00a000")]
const BAR := Color.BLACK
const MARK := Color.WHITE
const LABEL_WIDTH := 100
const VALUE_WIDTH := 60
const ROW := 16

## planet_info of the planet shown, or {}.
var info: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(0, ROW * 3 + 2)
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
	var width := size.x - LABEL_WIDTH - VALUE_WIDTH
	for axis in 3:
		var top := axis * ROW + 1.0
		var baseline := top + (ROW + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
		var label_w := (
			font.get_string_size(LABELS[axis], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
		draw_string(
			font,
			Vector2(left - 6 - label_w, baseline),
			LABELS[axis],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			ClassicTheme.TEXT
		)
		var bar := Rect2(left, top, width, ROW - 2)
		draw_rect(bar, BAR)
		var low: int = info["hab_low"][axis]
		var high: int = info["hab_high"][axis]
		if low < 0:
			draw_rect(bar, BANDS[axis].darkened(0.4))
		else:
			draw_rect(Rect2(_x(bar, low), top, _x(bar, high) - _x(bar, low), ROW - 2), BANDS[axis])
		var mid := top + (ROW - 2) / 2.0
		var now := _x(bar, info["environment"][axis])
		var best := _x(bar, info["terraform_best"][axis])
		if absf(best - now) > 1.0:
			draw_line(Vector2(now, mid), Vector2(best, mid), MARK, 1.0)
		var original := _x(bar, info["environment_original"][axis])
		draw_line(Vector2(original - 3, mid), Vector2(original + 3, mid), MARK, 1.0)
		draw_line(Vector2(original, mid - 3), Vector2(original, mid + 3), MARK, 1.0)
		draw_arc(Vector2(now, mid), 4.5, 0.0, TAU, 16, MARK, 1.0)
		draw_line(Vector2(now - 6, mid), Vector2(now + 6, mid), MARK, 1.0)
		draw_line(Vector2(now, mid - 6), Vector2(now, mid + 6), MARK, 1.0)
		draw_string(
			plain,
			Vector2(left + width + 6, baseline),
			EnvironmentUnits.format(axis, info["environment"][axis]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			ClassicTheme.TEXT
		)


func _x(bar: Rect2, value: int) -> float:
	return bar.position.x + bar.size.x * clampf(value / 100.0, 0.0, 1.0)
