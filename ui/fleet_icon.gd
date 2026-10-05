class_name FleetIcon
extends Control
## The picture in a Planet or Fleet tile (D15): a sunken black frame with a simple ship outline or
## planet drawn here. The original's ship and planet pictures come only from the local classic
## import mod (D13); until that exists every fleet and planet gets this placeholder.

const SIZE := Vector2(64, 64)
const HULL := Color(0.75, 0.78, 0.85)
const TRIM := Color(0.45, 0.75, 1.0)
const BACKGROUND := Color(0, 0, 0)
const PLANET_LIT := Color(0.55, 0.6, 0.8)
const PLANET_DARK := Color(0.12, 0.14, 0.25)
const PLANET_STEPS := 12

## Draw a planet instead of a ship.
var planet: bool = false


func _init(p_planet: bool = false) -> void:
	planet = p_planet
	custom_minimum_size = SIZE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, ClassicTheme.SHADOW, false, 1.0)
	draw_rect(r.grow(-1), BACKGROUND)
	draw_line(Vector2(size.x - 1, 0), size - Vector2(1, 1), ClassicTheme.HIGHLIGHT)
	draw_line(Vector2(0, size.y - 1), size - Vector2(1, 1), ClassicTheme.HIGHLIGHT)
	var c := size / 2.0
	var s := minf(size.x, size.y) / 64.0
	if planet:
		# a lit sphere: discs shrinking towards the light, dark to light
		for i in PLANET_STEPS:
			var f := float(i) / PLANET_STEPS
			var at := c + Vector2(-6, -6) * s * f
			draw_circle(at, 24.0 * s * (1.0 - 0.7 * f), PLANET_DARK.lerp(PLANET_LIT, f))
		return
	var body := PackedVector2Array(
		[
			c + Vector2(22, 0) * s,
			c + Vector2(-10, -9) * s,
			c + Vector2(-18, -6) * s,
			c + Vector2(-18, 6) * s,
			c + Vector2(-10, 9) * s,
		]
	)
	draw_colored_polygon(body, HULL)
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array(
			[
				c + Vector2(-4, 8 * side) * s,
				c + Vector2(-16, 20 * side) * s,
				c + Vector2(-20, 20 * side) * s,
				c + Vector2(-14, 7 * side) * s,
			]
		)
		draw_colored_polygon(wing, TRIM)
	draw_rect(Rect2(c + Vector2(-22, -4) * s, Vector2(4, 8) * s), TRIM)
