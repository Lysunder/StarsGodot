class_name FleetIcon
extends Control
## The picture in a Planet or Fleet tile (D15): a sunken black frame with a simple ship outline or
## planet drawn here, or the picture a mod turned on supplies for `art_id` (ArtRegistry: the
## original's pictures come only from the local classic import, D13).

const SIZE := Vector2(64, 64)
const HULL := Color(0.75, 0.78, 0.85)
const TRIM := Color(0.45, 0.75, 1.0)
const BACKGROUND := Color(0, 0, 0)
const PLANET_LIT := Color(0.55, 0.6, 0.8)
const PLANET_DARK := Color(0.12, 0.14, 0.25)
const PLANET_STEPS := 12

## Draw a planet instead of a ship.
var planet: bool = false
## A map object (MapObjects.OBJECT_KINDS) to draw our own symbol for when there is no picture,
## in `tint`; "" for a ship or planet.
var object_kind := ""
var tint := Color.WHITE
## The picture to show when a mod supplies it (ArtRegistry.ship_id, planet_id); "" for none.
var art_id := "":
	set(value):
		art_id = value
		queue_redraw()


func _init(p_planet: bool = false, p_art_id := "") -> void:
	planet = p_planet
	art_id = p_art_id
	custom_minimum_size = SIZE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, ClassicTheme.SHADOW, false, 1.0)
	draw_rect(r.grow(-1), BACKGROUND)
	draw_line(Vector2(size.x - 1, 0), size - Vector2(1, 1), ClassicTheme.HIGHLIGHT)
	draw_line(Vector2(0, size.y - 1), size - Vector2(1, 1), ClassicTheme.HIGHLIGHT)
	var art := ArtRegistry.texture(art_id)
	if art != null:
		draw_texture_rect(art, r.grow(-1), false)
		return
	var c := size / 2.0
	var s := minf(size.x, size.y) / 64.0
	if not object_kind.is_empty():
		_draw_object_symbol(c, s)
		return
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


## Our own symbols for map objects, as the map draws them, larger.
func _draw_object_symbol(c: Vector2, s: float) -> void:
	match object_kind:
		"minefield":
			draw_circle(c, 24.0 * s, Color(tint, 0.3))
			draw_arc(c, 24.0 * s, 0.0, TAU, 48, tint, 2.0)
		"wormhole":
			draw_arc(c, 18.0 * s, 0.0, TAU, 32, tint, 5.0 * s)
		"packet":
			draw_rect(Rect2(c - Vector2(10, 10) * s, Vector2(20, 20) * s), tint)
		_:
			var d := 18.0 * s
			draw_colored_polygon(
				PackedVector2Array(
					[c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]
				),
				tint
			)
