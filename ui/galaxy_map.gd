class_name GalaxyMap
extends Control
## The galaxy map (M11 step 1): planets coloured by owner and sized by population, the player's
## fleets and the selected fleet's path. Wheel zooms, right or middle drag pans, a click selects
## (clicking again cycles through objects at that spot), Shift+click adds a waypoint for the
## selected fleet.

signal selected(kind: String, id: int)

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

var zoom: float = 1.0
var offset: Vector2 = Vector2.ZERO
var selection_kind: String = ""
var selection_id: int = -1

var _dragging := false
var _last_pick: Array[Dictionary] = []
var _pick_index := 0


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	GameSession.changed.connect(queue_redraw)
	resized.connect(_fit)
	_fit.call_deferred()


## Zooms and centres so the whole universe fits.
func _fit() -> void:
	if not GameSession.has_game() or size.x <= 0:
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
	selection_kind = kind
	selection_id = id
	selected.emit(kind, id)
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
	var prev := to_screen(f.x, f.y)
	for i in range(1, f.waypoints.size()):
		var wp := f.waypoints[i]
		var at := to_screen(wp.x, wp.y)
		draw_line(prev, at, COLOR_PATH, 1.5)
		draw_circle(at, 2.5, COLOR_PATH)
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
					_pick(event.position)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = true
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		offset += event.relative
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


## Shift+click: a waypoint for the selected fleet at the planet clicked, or in deep space.
func _add_waypoint(at: Vector2) -> void:
	if selection_kind != "fleet":
		return
	var info := GameSession.view.fleet_info(selection_id)
	if info.is_empty():
		return
	var u := to_universe(at)
	var wp := {
		"x": int(round(u.x)),
		"y": int(round(u.y)),
		"target": "none",
		"target_owner": -1,
		"target_id": -1,
		"warp": DEFAULT_WARP,
		"task": "none",
		"task_data": {},
	}
	var waypoints: Array = info["waypoints"]
	if waypoints.size() > 1 and waypoints[-1]["warp"] > 0:
		wp["warp"] = waypoints[-1]["warp"]
	for hit in GameSession.view.objects_at(u.x, u.y, PICK_PIXELS / zoom):
		if hit["kind"] == "planet":
			var pl := GameSession.view.planet_info(hit["id"])
			wp.merge({"x": pl["x"], "y": pl["y"], "target": "planet", "target_id": pl["id"]}, true)
			break
	var order := {
		"type": "waypoint_add",
		"owner": GameSession.PLAYER,
		"fleet": selection_id,
		"index": waypoints.size(),
		"waypoint": wp,
	}
	var reason := GameSession.add_order(order)
	if not reason.is_empty():
		push_warning(reason)
	selected.emit(selection_kind, selection_id)
