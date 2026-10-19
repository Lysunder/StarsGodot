class_name BattleBoard
extends Control
## The battle viewer's board (D15): the 10 × 10 battle squares in a sunken black frame. Each square
## shows its tokens' picture (the design's small picture with its owner's tiny logo when a mod
## supplies them, else a ship outline or a ring for a starbase in the owner's colour),
## the ships in the first token, and "+n" for further tokens; the selected square has a frame.
## A shot draws a line from the firing token to each square it hit (beams solid, torpedoes
## dashed), and a square where ships died gets a burst.

## A square was clicked (`button` is the mouse button).
signal square_clicked(square: int, button: int, at: Vector2)

const CELL := 44
const GAP := 1
const BACKGROUND := Color(0, 0, 0)
const GRID := Color(0.22, 0.22, 0.28)
const SELECTED := Color(1.0, 0.9, 0.3)
const BEAM := Color(1.0, 0.95, 0.5)
const TORPEDO := Color(1.0, 0.6, 0.2)
const BURST := Color(1.0, 0.45, 0.2)
const COUNT := Color(1, 1, 1)
const TORPEDO_HIT := 4
## A token's picture from a mod (ArtRegistry, the small ship pictures), in pixels.
const PICTURE := 32.0

var replay: BattleReplay
## The square framed as selected (BattleReplay.GONE for none).
var selected_square: int = BattleReplay.GONE


func _init() -> void:
	var side := BattleReplay.BOARD * CELL + 2
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_STOP


## The top-left corner of a square.
func square_origin(square: int) -> Vector2:
	return Vector2(1 + (square & 15) * CELL, 1 + (square >> 4) * CELL)


func square_center(square: int) -> Vector2:
	return square_origin(square) + Vector2(CELL, CELL) / 2.0


func square_at(p: Vector2) -> int:
	var x := int((p.x - 1) / CELL)
	var y := int((p.y - 1) / CELL)
	if p.x < 1 or p.y < 1 or x >= BattleReplay.BOARD or y >= BattleReplay.BOARD:
		return BattleReplay.GONE
	return x + 16 * y


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	var square := square_at(mb.position)
	if square != BattleReplay.GONE:
		square_clicked.emit(square, mb.button_index, mb.global_position)
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, ClassicTheme.SHADOW, false, 1.0)
	draw_rect(r.grow(-1), BACKGROUND)
	draw_line(Vector2(size.x - 1, 0), size - Vector2(1, 1), ClassicTheme.HIGHLIGHT)
	draw_line(Vector2(0, size.y - 1), size - Vector2(1, 1), ClassicTheme.HIGHLIGHT)
	for i in range(1, BattleReplay.BOARD):
		draw_line(Vector2(1 + i * CELL, 1), Vector2(1 + i * CELL, size.y - 1), GRID)
		draw_line(Vector2(1, 1 + i * CELL), Vector2(size.x - 1, 1 + i * CELL), GRID)
	if replay == null:
		return
	for y in BattleReplay.BOARD:
		for x in BattleReplay.BOARD:
			_draw_square(x + 16 * y)
	if selected_square != BattleReplay.GONE:
		var o := square_origin(selected_square)
		draw_rect(Rect2(o + Vector2(1, 1), Vector2(CELL - 2, CELL - 2)), SELECTED, false, 2.0)
	_draw_shot()


func _draw_square(square: int) -> void:
	var here := replay.tokens_at(square)
	if here.is_empty():
		return
	var first := here[0]
	var rec: Dictionary = replay.battle["tokens"][first]
	var colour := Palette.color(
		Palette.MINE if int(rec["owner"]) == replay.view.player else Palette.OTHER
	)
	var c := square_center(square) + Vector2(0, -4)
	var s := CELL / 64.0
	var art := ArtRegistry.texture(
		ArtRegistry.ship_id(replay.design(first), replay.view.content, true)
	)
	if art != null:
		# the design's small picture, with its owner's tiny logo in the corner (as the original)
		var pic := Rect2(c - Vector2(PICTURE, PICTURE) / 2.0, Vector2(PICTURE, PICTURE))
		draw_texture_rect(art, pic, false)
		var owner_race := replay.view.state.player(int(rec["owner"])).race
		var logo := ArtRegistry.texture(ArtRegistry.logo_id(owner_race, ".tiny"))
		if logo != null:
			draw_texture_rect(logo, Rect2(pic.position, logo.get_size()), false)
	elif int(rec["kind"]) == BattleReplay.KIND_STARBASE:
		draw_arc(c, 13.0 * s * 1.4, 0, TAU, 24, colour, 3.0)
		draw_circle(c, 4.0 * s * 1.4, colour)
	else:
		# facing the board's middle, like ships closing in
		var dir := 1.0 if (square & 15) < BattleReplay.BOARD / 2 else -1.0
		var body := PackedVector2Array(
			[
				c + Vector2(20 * dir, 0) * s,
				c + Vector2(-12 * dir, -12) * s,
				c + Vector2(-6 * dir, 0) * s,
				c + Vector2(-12 * dir, 12) * s,
			]
		)
		draw_colored_polygon(body, colour)
	var font := get_theme_default_font()
	var fsize := maxi(get_theme_default_font_size() - 2, 8)
	var o := square_origin(square)
	var count := str(int(replay.tokens[first]["count"]))
	draw_string(font, o + Vector2(3, CELL - 4), count, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, COUNT)
	if here.size() > 1:
		var more := "+%d" % (here.size() - 1)
		var w := font.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(
			font,
			o + Vector2(CELL - 3 - w, CELL - 4),
			more,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fsize,
			COUNT
		)


func _draw_shot() -> void:
	var e := replay.event()
	if e.is_empty() or (e["hits"] as Array).is_empty():
		return
	var from := square_center(int(e["square"]))
	var killed := {}
	for h: Dictionary in e["hits"]:
		var target := int(h["target"])
		var to := square_center(int(replay.tokens[target]["square"]))
		if int(h["kind"]) & TORPEDO_HIT:
			draw_dashed_line(from, to, TORPEDO, 2.0, 4.0)
		else:
			draw_line(from, to, BEAM, 2.0)
		if int(h["killed"]) > 0:
			killed[to] = true
	for at: Vector2 in killed:
		for k in 8:
			var a := TAU * k / 8.0
			draw_line(at + Vector2.from_angle(a) * 5, at + Vector2.from_angle(a) * 14, BURST, 2.0)
