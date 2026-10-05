class_name GalaxyMap
extends Control
## The galaxy map (M11 step 1): planets coloured by owner and sized by population, the player's
## fleets and the selected fleet's path. Wheel zooms, right or middle drag pans, a click selects
## (clicking again cycles through objects at that spot). For the selected fleet: Shift+click adds a
## waypoint after the selected one (at a planet, one of the player's other fleets, or in deep
## space); clicking a waypoint selects it and dragging moves it. While Shift is held over the map
## the cursor is a small crosshair.

signal selected(kind: String, id: int)
## A waypoint of the selected fleet was clicked or added.
signal waypoint_picked(index: int)

const UNIVERSE_MARGIN := 1000
const ZOOM_STEP := 1.15
const ZOOM_MIN := 0.2
const ZOOM_MAX := 8.0
const PLANET_RADIUS := 3.0
const PICK_PIXELS := 10.0
const DEFAULT_WARP := 6
const COLOR_BACKGROUND := Color(0.02, 0.02, 0.06)
const COLOR_UNOWNED := Color(0.55, 0.55, 0.6)
const COLOR_MINE := Color(0.3, 0.85, 0.35)
const COLOR_OTHER := Color(0.9, 0.3, 0.25)
const COLOR_FLEET := Color(0.45, 0.75, 1.0)
const COLOR_PATH := Color(0.45, 0.75, 1.0, 0.6)
const COLOR_SELECTED := Color(1.0, 0.9, 0.3)
const COLOR_SHORT := Color(1.0, 0.35, 0.3, 0.8)
## A press that moves less than this is a click, not a drag.
const DRAG_PIXELS := 4.0
## The Shift crosshair: arm length in pixels (the image is 2 × arm + 1 wide).
const CROSS_ARM := 7

var zoom: float = 1.0
var offset: Vector2 = Vector2.ZERO
var selection_kind: String = ""
var selection_id: int = -1
## The selected fleet's selected waypoint, or -1.
var waypoint: int = -1

var _dragging := false
var _last_pick: Array[Dictionary] = []
var _pick_index := 0
## The waypoint being dragged (-1: none), where the press started and where the mouse is.
var _drag_waypoint := -1
var _drag_from := Vector2.ZERO
var _drag_to := Vector2.ZERO


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	GameSession.changed.connect(queue_redraw)
	resized.connect(_fit)
	Input.set_custom_mouse_cursor(_crosshair(), Input.CURSOR_CROSS, Vector2(CROSS_ARM, CROSS_ARM))
	_fit.call_deferred()


## Shift over the map shows the crosshair (the cursor for adding waypoints), at once when the key
## goes down or up, not only on the next mouse move.
func _input(event: InputEvent) -> void:
	var shift := false
	if event is InputEventKey and event.keycode == KEY_SHIFT:
		shift = event.pressed
	elif event is InputEventWithModifiers:
		shift = event.shift_pressed
	else:
		return
	var shape := Control.CURSOR_CROSS if shift else Control.CURSOR_ARROW
	if shape == mouse_default_cursor_shape:
		return
	mouse_default_cursor_shape = shape
	if get_viewport().gui_get_hovered_control() == self:
		DisplayServer.cursor_set_shape(shape as DisplayServer.CursorShape)


## A small crosshair: white arms with a black outline, a gap in the middle.
static func _crosshair() -> ImageTexture:
	var side := CROSS_ARM * 2 + 1
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for pass_colour: Color in [Color.BLACK, Color.WHITE]:
		var pad := 1 if pass_colour == Color.BLACK else 0
		for i in side:
			if absi(i - CROSS_ARM) < 2:
				continue
			for d in range(-pad, pad + 1):
				img.set_pixel(i, clampi(CROSS_ARM + d, 0, side - 1), pass_colour)
				img.set_pixel(clampi(CROSS_ARM + d, 0, side - 1), i, pass_colour)
	return ImageTexture.create_from_image(img)


## Zooms and centres so the whole universe fits.
func _fit() -> void:
	if not GameSession.has_game() or size.x <= 0 or size.y <= 0:
		return
	var width := float(GameSession.view.universe_width())
	zoom = minf(size.x, size.y) / (width + 40.0)
	offset = size / 2.0 - Vector2(width, width) / 2.0 * zoom
	queue_redraw()


func to_screen(x: float, y: float) -> Vector2:
	return Vector2(x - UNIVERSE_MARGIN, y - UNIVERSE_MARGIN) * zoom + offset


func to_universe(p: Vector2) -> Vector2:
	return (p - offset) / zoom + Vector2(UNIVERSE_MARGIN, UNIVERSE_MARGIN)


func select(kind: String, id: int) -> void:
	if kind != selection_kind or id != selection_id:
		waypoint = -1
	selection_kind = kind
	selection_id = id
	selected.emit(kind, id)
	queue_redraw()


## Highlights a waypoint of the selected fleet (from the Command pane).
func set_waypoint(index: int) -> void:
	if index != waypoint:
		waypoint = index
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if not GameSession.has_game():
		return
	var view := GameSession.view
	var w := float(view.universe_width())
	draw_rect(
		Rect2(to_screen(UNIVERSE_MARGIN, UNIVERSE_MARGIN), Vector2(w, w) * zoom),
		Color(1, 1, 1, 0.08),
		false
	)
	for pl in view.planets():
		var colour := COLOR_UNOWNED
		if pl["owner"] >= 0:
			colour = COLOR_MINE if pl["mine"] else COLOR_OTHER
		var radius := PLANET_RADIUS + (2.0 if pl["population"] > 0 else 0.0)
		var at := to_screen(pl["x"], pl["y"])
		draw_circle(at, radius, colour)
		if pl["starbase"]:
			draw_arc(at, radius + 3.0, 0.0, TAU, 16, colour, 1.0)
		if selection_kind == "planet" and selection_id == pl["id"]:
			draw_arc(at, radius + 6.0, 0.0, TAU, 24, COLOR_SELECTED, 1.5)
		if zoom > 1.2:
			draw_string(
				get_theme_default_font(),
				at + Vector2(6, -6),
				pl["name"],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				10,
				Color(1, 1, 1, 0.6)
			)
	for f in view.fleets():
		var at := to_screen(f.x, f.y) + Vector2(5, 5)
		var tri := PackedVector2Array(
			[at + Vector2(0, -4), at + Vector2(4, 4), at + Vector2(-4, 4)]
		)
		draw_colored_polygon(tri, COLOR_FLEET)
		if selection_kind == "fleet" and selection_id == f.number:
			draw_arc(at, 7.0, 0.0, TAU, 16, COLOR_SELECTED, 1.5)
			_draw_path(f)


func _draw_path(f: Fleet) -> void:
	var rows: Array = GameSession.view.fleet_info(f.number).get("waypoints", [])
	var prev := to_screen(f.x, f.y)
	for i in range(1, f.waypoints.size()):
		var wp := f.waypoints[i]
		var at := to_screen(wp.x, wp.y)
		if i == _drag_waypoint:
			at = _drag_to
		var colour := COLOR_PATH
		if i < rows.size() and (rows[i]["short_of_fuel"] or rows[i]["cannot_move"]):
			colour = COLOR_SHORT
		draw_line(prev, at, colour, 1.5)
		draw_circle(at, 2.5, colour)
		if i == waypoint:
			draw_arc(at, 6.0, 0.0, TAU, 16, COLOR_SELECTED, 1.5)
		prev = at


func _gui_input(event: InputEvent) -> void:
	if not GameSession.has_game():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				if event.shift_pressed:
					_add_waypoint(event.position)
				else:
					_press(event.position)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = true
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = false
		elif event.button_index == MOUSE_BUTTON_LEFT and _drag_waypoint > 0:
			_release(event.position)
	elif event is InputEventMouseMotion and _dragging:
		offset += event.relative
		queue_redraw()
	elif event is InputEventMouseMotion and _drag_waypoint > 0:
		_drag_to = event.position
		queue_redraw()


func _zoom_at(at: Vector2, factor: float) -> void:
	var before := to_universe(at)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	offset += at - to_screen(before.x, before.y)
	queue_redraw()


## A click selects the nearest object; clicking the same spot again cycles through what is there.
func _pick(at: Vector2) -> void:
	var u := to_universe(at)
	var hits := GameSession.view.objects_at(u.x, u.y, PICK_PIXELS / zoom)
	if hits.is_empty():
		return
	if hits == _last_pick:
		_pick_index = (_pick_index + 1) % hits.size()
	else:
		_last_pick = hits
		_pick_index = 0
	var hit: Dictionary = hits[_pick_index]
	select(hit["kind"], hit["id"])


## A left press on one of the selected fleet's waypoints picks it (and may start a drag);
## anywhere else it selects what is there.
func _press(at: Vector2) -> void:
	var hit := _waypoint_at(at)
	if hit > 0:
		waypoint = hit
		_drag_waypoint = hit
		_drag_from = at
		_drag_to = at
		waypoint_picked.emit(hit)
		queue_redraw()
		return
	_pick(at)


## The end of a waypoint drag: a move of more than DRAG_PIXELS sends the waypoint to the planet,
## fleet or deep space under the mouse, keeping its warp and task.
func _release(at: Vector2) -> void:
	var index := _drag_waypoint
	_drag_waypoint = -1
	queue_redraw()
	if at.distance_to(_drag_from) <= DRAG_PIXELS:
		return
	var info := GameSession.view.fleet_info(selection_id)
	if info.is_empty() or index >= info["waypoints"].size():
		return
	var reason := (
		GameSession
		. add_order(
			{
				"type": "waypoint_change",
				"owner": GameSession.PLAYER,
				"fleet": selection_id,
				"index": index,
				"waypoint": CommandPane.waypoint_order(info["waypoints"][index], _target_at(at)),
			}
		)
	)
	if not reason.is_empty():
		push_warning(reason)
	waypoint_picked.emit(index)


## The selected fleet's waypoint (1 or later) under the mouse, or -1.
func _waypoint_at(at: Vector2) -> int:
	if selection_kind != "fleet":
		return -1
	var f := GameSession.view.state.fleet(GameSession.PLAYER, selection_id)
	if f == null:
		return -1
	for i in range(f.waypoints.size() - 1, 0, -1):
		if to_screen(f.waypoints[i].x, f.waypoints[i].y).distance_to(at) <= PICK_PIXELS * 0.6:
			return i
	return -1


## The waypoint target under the mouse: a planet, another of the player's fleets, or deep space.
func _target_at(at: Vector2) -> Dictionary:
	var u := to_universe(at)
	var out := {
		"x": int(round(u.x)),
		"y": int(round(u.y)),
		"target": "none",
		"target_owner": -1,
		"target_id": -1,
	}
	for hit in GameSession.view.objects_at(u.x, u.y, PICK_PIXELS / zoom):
		if hit["kind"] == "planet":
			var pl := GameSession.view.planet_info(hit["id"])
			out.merge({"x": pl["x"], "y": pl["y"], "target": "planet", "target_id": pl["id"]}, true)
			break
		if hit["kind"] == "fleet" and hit["id"] != selection_id:
			var f := GameSession.view.state.fleet(GameSession.PLAYER, hit["id"])
			(
				out
				. merge(
					{
						"x": f.x,
						"y": f.y,
						"target": "fleet",
						"target_owner": GameSession.PLAYER,
						"target_id": f.number,
					},
					true
				)
			)
			break
	return out


## Shift+click: a new waypoint for the selected fleet after its selected waypoint (or at the end),
## with the warp of the waypoint before it.
func _add_waypoint(at: Vector2) -> void:
	if selection_kind != "fleet":
		return
	var info := GameSession.view.fleet_info(selection_id)
	if info.is_empty():
		return
	var waypoints: Array = info["waypoints"]
	var index := waypoints.size()
	if waypoint >= 0 and waypoint < waypoints.size():
		index = waypoint + 1
	var wp := _target_at(at)
	wp.merge({"warp": DEFAULT_WARP, "task": "none", "task_data": {}})
	if index > 1 and waypoints[index - 1]["warp"] > 0:
		wp["warp"] = waypoints[index - 1]["warp"]
	var reason := (
		GameSession
		. add_order(
			{
				"type": "waypoint_add",
				"owner": GameSession.PLAYER,
				"fleet": selection_id,
				"index": index,
				"waypoint": wp,
			}
		)
	)
	if not reason.is_empty():
		push_warning(reason)
		return
	waypoint = index
	waypoint_picked.emit(index)
	queue_redraw()
